import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { getFirestore, Timestamp, DocumentData } from "firebase-admin/firestore";
import { parseHttpUrl, isWishHiveLink, productKey } from "./urls";

const ZYTE_API_KEY = defineSecret("ZYTE_API_KEY");

// Prices move daily; a title or a photo does not.
const PRICE_FRESH_MS = 24 * 60 * 60 * 1000;
const DETAILS_FRESH_MS = 30 * 24 * 60 * 60 * 1000;

// A page Zyte found no product on (a blog, a video) is not paid for again by
// the next person who taps the chip on the same link.
const NOT_FOUND_MS = 7 * 24 * 60 * 60 * 1000;

// Zyte is the only part of this that costs money. Cache hits never count.
const USER_DAILY_LIMIT = 30;
const GLOBAL_DAILY_LIMIT = 1000;

interface ProductInfo {
  title?: string;
  price?: number;
  currency?: string;
  images: string[];
  brand?: string;
  rating?: number;
  ratingCount?: number;
  description?: string;
}

const db = () => getFirestore();

/**
 * Product details for a link, from the shared cache or, when asked, from Zyte.
 *
 * mode "cache" is free and silent: the app calls it on every pasted link.
 * mode "fetch" is the user tapping "Get price & photos", and may spend money.
 */
export const resolveProduct = onCall(
  { secrets: [ZYTE_API_KEY], timeoutSeconds: 60, memory: "256MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const parsed = parseHttpUrl(request.data?.url);
    if (!parsed) throw new HttpsError("invalid-argument", "A product link is required.");
    if (isWishHiveLink(parsed)) return { status: "hive-link" };

    const mode = request.data?.mode === "fetch" ? "fetch" : "cache";
    const { canonical, key } = await productKey(parsed);
    const canonicalUrl = canonical.toString();
    const ref = db().doc(`productCache/${key}`);

    // The same document also holds the product's affiliate link, so an entry
    // can exist without product details.
    const snap = await ref.get();
    const entry = snap.exists ? snap.data() : undefined;
    const cached = entry?.product ? entry : undefined;
    const age = cached ? Date.now() - toMillis(cached.fetchedAt) : Infinity;

    if (cached && age < PRICE_FRESH_MS) return found(cached, "cache", canonicalUrl);
    if (mode === "cache") {
      return cached && age < DETAILS_FRESH_MS
        ? found(cached, "cache", canonicalUrl)
        : { status: "miss", canonicalUrl };
    }

    if (!cached && Date.now() - toMillis(entry?.notFoundAt) < NOT_FOUND_MS) {
      return { status: "not-found", canonicalUrl };
    }

    await consumeQuota(uid);

    const fresh = await extractWithZyte(canonical);
    if (!fresh) {
      if (cached) return found(cached, "cache", canonicalUrl);
      await ref.set({ url: canonicalUrl, notFoundAt: Timestamp.now() }, { merge: true });
      return { status: "not-found", canonicalUrl };
    }

    const product = mergeOver(fresh, cached?.product as ProductInfo | undefined);
    const fetchedAt = Timestamp.now();
    await ref.set({ url: canonicalUrl, product, fetchedAt }, { merge: true });
    return found({ product, fetchedAt }, "zyte", canonicalUrl);
  }
);

function found(entry: DocumentData, source: "cache" | "zyte", canonicalUrl: string) {
  return {
    status: "found",
    source,
    canonicalUrl,
    fetchedAt: toMillis(entry.fetchedAt),
    product: entry.product as ProductInfo,
  };
}

const toMillis = (value: unknown) =>
  value instanceof Timestamp ? value.toMillis() : 0;

function mergeOver(fresh: ProductInfo, old?: ProductInfo): ProductInfo {
  if (!old) return fresh;
  return stripUndefined({
    title: fresh.title ?? old.title,
    price: fresh.price ?? old.price,
    currency: fresh.currency ?? old.currency,
    images: fresh.images.length ? fresh.images : old.images ?? [],
    brand: fresh.brand ?? old.brand,
    rating: fresh.rating ?? old.rating,
    ratingCount: fresh.ratingCount ?? old.ratingCount,
    description: fresh.description ?? old.description,
  });
}

async function consumeQuota(uid: string) {
  const day = new Date().toISOString().slice(0, 10);
  const userRef = db().doc(`productUsage/${uid}`);
  const globalRef = db().doc("productUsage/_global");

  await db().runTransaction(async (tx) => {
    const [user, all] = await Promise.all([tx.get(userRef), tx.get(globalRef)]);
    const used = (snap: DocumentData | undefined) =>
      snap?.day === day ? Number(snap.count) || 0 : 0;
    const userCount = used(user.data());
    const globalCount = used(all.data());

    if (globalCount >= GLOBAL_DAILY_LIMIT) {
      logger.warn("Global product lookup cap reached", { day, globalCount });
      throw new HttpsError("resource-exhausted", "Busy right now. Please try again tomorrow.", {
        scope: "global",
      });
    }
    if (userCount >= USER_DAILY_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        "You've reached today's limit for fetching details. Try again tomorrow.",
        { scope: "user" }
      );
    }
    tx.set(userRef, { day, count: userCount + 1 });
    tx.set(globalRef, { day, count: globalCount + 1 });
  });
}

/**
 * Plain HTTP first because it is several times cheaper. The rendered browser
 * pass only runs when the plain one came back with neither price nor photo.
 */
async function extractWithZyte(url: URL): Promise<ProductInfo | null> {
  const plain = await zyteExtract(url, "httpResponseBody", 18000);
  if (plain && (plain.price !== undefined || plain.images.length)) return plain;
  const rendered = await zyteExtract(url, "browserHtml", 25000);
  return rendered ?? plain;
}

async function zyteExtract(
  url: URL,
  extractFrom: "httpResponseBody" | "browserHtml",
  timeoutMs: number
): Promise<ProductInfo | null> {
  try {
    const res = await fetch("https://api.zyte.com/v1/extract", {
      method: "POST",
      headers: {
        Authorization: `Basic ${Buffer.from(`${ZYTE_API_KEY.value()}:`).toString("base64")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        url: url.toString(),
        product: true,
        productOptions: { extractFrom },
      }),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!res.ok) {
      logger.warn("Zyte request failed", {
        url: url.toString(),
        extractFrom,
        status: res.status,
        body: (await res.text()).slice(0, 500),
      });
      return null;
    }
    const body = (await res.json()) as { product?: Record<string, unknown> };
    return fromZyte(body.product);
  } catch (e) {
    logger.warn("Zyte request error", { url: url.toString(), extractFrom, error: String(e) });
    return null;
  }
}

function fromZyte(p: Record<string, any> | undefined): ProductInfo | null {
  if (!p) return null;
  // Zyte scores how sure it is that the page is a product at all.
  const probability = Number(p.metadata?.probability);
  if (!Number.isNaN(probability) && probability < 0.5) return null;

  const images: string[] = [];
  for (const candidate of [p.mainImage?.url, ...(p.images ?? []).map((i: any) => i?.url)]) {
    if (typeof candidate === "string" && candidate.startsWith("https://") && !images.includes(candidate)) {
      images.push(candidate);
    }
  }

  const price = parseFloat(String(p.price ?? ""));
  const info: ProductInfo = {
    title: str(p.name),
    price: Number.isFinite(price) && price > 0 ? price : undefined,
    currency: str(p.currency),
    images: images.slice(0, 8),
    brand: str(p.brand?.name),
    rating: num(p.aggregateRating?.ratingValue),
    ratingCount: num(p.aggregateRating?.reviewCount),
    description: str(p.description)?.slice(0, 600),
  };
  const useful = info.title || info.price !== undefined || info.images.length;
  return useful ? stripUndefined(info) : null;
}

const str = (v: unknown) =>
  typeof v === "string" && v.trim() ? v.trim() : undefined;

const num = (v: unknown) => {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? ""));
  return Number.isFinite(n) ? n : undefined;
};

// Firestore rejects undefined values.
function stripUndefined<T extends object>(obj: T): T {
  return Object.fromEntries(
    Object.entries(obj).filter(([, v]) => v !== undefined)
  ) as T;
}
