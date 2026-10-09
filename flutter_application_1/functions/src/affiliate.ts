import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import {
  getFirestore,
  FieldPath,
  FieldValue,
  Timestamp,
  DocumentReference,
  DocumentData,
} from "firebase-admin/firestore";
import { parseHttpUrl, isWishHiveLink, productKey } from "./urls";

const CUELINKS_API_KEY = defineSecret("CUELINKS_API_KEY");

type AffiliateStatus = "ok" | "unsupported" | "error" | "skipped";

const AFFILIATE_FIELDS = [
  "affiliateLink",
  "affiliateFor",
  "affiliateStatus",
  "affiliateCheckedAt",
] as const;

const RETRY_AFTER_MS = 6 * 24 * 60 * 60 * 1000;

// A converted link for a product is reused by every wish of that product.
const AFFILIATE_REUSE_MS = 30 * 24 * 60 * 60 * 1000;

const db = () => getFirestore();

/**
 * Converts a wish's product link into a Cuelinks affiliate link.
 *
 * Runs on the owner's copy only; mirrorWish carries the result to the hive
 * copy. `link` is never touched, so the original always remains to fall back
 * on, and `affiliateFor` records which link was converted so the write below
 * does not trigger another conversion.
 */
export const convertWishLink = onDocumentWritten(
  { document: "users/{uid}/wishes/{wishId}", secrets: [CUELINKS_API_KEY] },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const data = after.data()!;
    const link = typeof data.link === "string" ? data.link.trim() : "";

    if (!link || data.isNote === true) {
      if (AFFILIATE_FIELDS.some((f) => f in data)) {
        await after.ref.update(
          Object.fromEntries(AFFILIATE_FIELDS.map((f) => [f, FieldValue.delete()]))
        );
      }
      return;
    }
    if (data.affiliateFor === link) return;

    await convertAndStore(after.ref, link);
  }
);

/**
 * Weekly. Retries links that failed or whose store was not yet approved, so a
 * campaign approved later starts earning on wishes saved before it. Also walks
 * wishes created before this feature existed, once, until it reaches the end.
 */
export const retryAffiliateLinks = onSchedule(
  {
    schedule: "every monday 03:30",
    timeZone: "Asia/Kolkata",
    secrets: [CUELINKS_API_KEY],
    timeoutSeconds: 540,
  },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - RETRY_AFTER_MS);
    const stale = await db()
      .collectionGroup("wishes")
      .where("affiliateStatus", "in", ["unsupported", "error"])
      .where("affiliateCheckedAt", "<", cutoff)
      .limit(400)
      .get();

    let retried = 0;
    for (const doc of stale.docs) {
      if (!isOwnerCopy(doc.ref)) continue;
      const link = String(doc.data().link ?? "").trim();
      if (!link) continue;
      await convertAndStore(doc.ref, link, { fresh: true });
      retried++;
    }

    const backfilled = await backfillPass();
    logger.info("Affiliate retry finished", { retried, backfilled });
  }
);

// users/{uid}/wishes/{id} is the copy the app writes. hives/{id}/wishes/{id}
// is the mirror, and converting it too would call Cuelinks twice per wish.
const isOwnerCopy = (ref: DocumentReference) =>
  ref.parent.parent?.parent.id === "users";

async function backfillPass(): Promise<number> {
  const stateRef = db().doc("system/affiliateBackfill");
  const state = (await stateRef.get()).data();
  if (state?.done === true) return 0;

  let query = db()
    .collectionGroup("wishes")
    .orderBy(FieldPath.documentId())
    .limit(300);
  if (typeof state?.cursor === "string") query = query.startAfter(state.cursor);

  const page = await query.get();
  let converted = 0;
  for (const doc of page.docs) {
    if (!isOwnerCopy(doc.ref)) continue;
    const data = doc.data();
    const link = String(data.link ?? "").trim();
    if (!link || data.isNote === true || "affiliateFor" in data) continue;
    await convertAndStore(doc.ref, link);
    converted++;
  }

  const last = page.docs[page.docs.length - 1];
  await stateRef.set({
    cursor: last ? last.ref.path : state?.cursor ?? null,
    done: page.size < 300,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return converted;
}

async function convertAndStore(
  ref: DocumentReference,
  link: string,
  opts: { fresh?: boolean } = {}
) {
  const { affiliateLink, status } = await convert(link, opts.fresh === true);
  await ref.update({
    affiliateLink,
    affiliateFor: link,
    affiliateStatus: status,
    affiliateCheckedAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Keyed by the same cleaned product URL as the product details, so a product
 * many people wish for is converted once. Only successes are reused; a store
 * that was not approved is asked again next time, since approval can come.
 */
async function convert(
  link: string,
  fresh: boolean
): Promise<{ affiliateLink: string | null; status: AffiliateStatus }> {
  const parsed = parseHttpUrl(link);
  if (!parsed || isWishHiveLink(parsed)) return { affiliateLink: null, status: "skipped" };

  const { canonical, key } = await productKey(parsed);
  const target = canonical.toString();
  const cacheRef = db().doc(`productCache/${key}`);

  if (!fresh) {
    const cached = (await cacheRef.get()).data()?.affiliate;
    const checkedAt = cached?.checkedAt instanceof Timestamp ? cached.checkedAt.toMillis() : 0;
    if (typeof cached?.link === "string" && Date.now() - checkedAt < AFFILIATE_REUSE_MS) {
      return { affiliateLink: cached.link, status: "ok" };
    }
  }

  try {
    const res = await callCuelinks(target);
    if (res.status === 401 || res.status === 403) {
      logger.error("Cuelinks rejected the API key", { status: res.status });
      return { affiliateLink: null, status: "error" };
    }
    if (res.status >= 500) return { affiliateLink: null, status: "error" };

    const body = await res.json().catch(() => null);
    const affiliateLink = res.ok ? findAffiliateUrl(body, target) : null;
    if (!affiliateLink) {
      logger.info("Cuelinks did not convert", { target, status: res.status, body });
      return { affiliateLink: null, status: "unsupported" };
    }
    await cacheRef.set(
      { url: target, affiliate: { link: affiliateLink, checkedAt: Timestamp.now() } },
      { merge: true }
    );
    return { affiliateLink, status: "ok" };
  } catch (e) {
    logger.warn("Cuelinks request failed", { target, error: String(e) });
    return { affiliateLink: null, status: "error" };
  }
}

// Cuelinks documents `Token token="..."`; the bare form is tried once if that
// is refused, and whichever works is remembered for this instance.
let authStyle: "quoted" | "bare" = "quoted";

async function callCuelinks(url: string): Promise<Response> {
  const api = new URL("https://www.cuelinks.com/api/v2/links.json");
  api.searchParams.set("url", url);
  api.searchParams.set("subid", "wishhive-app");

  const send = (style: "quoted" | "bare") => {
    const key = CUELINKS_API_KEY.value();
    return fetch(api, {
      headers: {
        Authorization: style === "quoted" ? `Token token="${key}"` : `Token ${key}`,
        Accept: "application/json",
      },
      signal: AbortSignal.timeout(10000),
    });
  };

  const first = await send(authStyle);
  if (first.status !== 401) return first;
  const other = authStyle === "quoted" ? "bare" : "quoted";
  const second = await send(other);
  if (second.status !== 401) authStyle = other;
  return second;
}

const AFFILIATE_HOST = /(^|\.)(linksredirect\.com|cuelinks\.com|clnk\.in|cuel\.ink)$/i;

/**
 * The response field holding the converted link is looked for by name first,
 * then by host anywhere in the body, so a renamed field does not silently
 * stop every conversion.
 */
function findAffiliateUrl(body: unknown, original: string): string | null {
  const byName: string[] = [];
  const byHost: string[] = [];

  const visit = (node: unknown, key: string, depth: number) => {
    if (depth > 5 || node == null) return;
    if (typeof node === "string") {
      const url = parseHttpUrl(node);
      if (!url || node === original) return;
      if (/affiliate|short|shorten/i.test(key)) byName.push(node);
      else if (AFFILIATE_HOST.test(url.hostname)) byHost.push(node);
      return;
    }
    if (Array.isArray(node)) node.forEach((v) => visit(v, key, depth + 1));
    else if (typeof node === "object") {
      for (const [k, v] of Object.entries(node as DocumentData)) visit(v, k, depth + 1);
    }
  };
  visit(body, "", 0);
  return byName[0] ?? byHost[0] ?? null;
}
