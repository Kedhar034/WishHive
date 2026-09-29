import { setGlobalOptions } from "firebase-functions/v2";
import {
  onDocumentWritten,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { getAuth } from "firebase-admin/auth";

initializeApp();
const db = getFirestore();

setGlobalOptions({ region: "asia-south1", maxInstances: 10 });

const chunk = <T>(arr: T[], size: number): T[][] => {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
};

const sameSet = (a: string[], b: string[]) =>
  a.length === b.length && a.every((x) => b.includes(x));

// ─── Migration: old user document → new subcollections ───────────────────────
// Runs for writes from EVERY client version, including v1.0.3, so no user is
// stranded on the old schema. Only writes to subcollections, so it cannot
// retrigger itself.

export const mirrorUserDoc = onDocumentWritten("users/{uid}", async (event) => {
  const uid = event.params.uid;
  const after = event.data?.after.data();
  if (!after) return;

  const rawFriends: unknown[] = after.friends ?? [];
  const friendUids = rawFriends
    .map((f) => (typeof f === "string" ? f : (f as { uid?: string })?.uid))
    .filter((v): v is string => !!v);

  const existing = await db.collection(`users/${uid}/friends`).get();
  const existingUids = existing.docs.map((d) => d.id);

  const writes: { ref: FirebaseFirestore.DocumentReference; op: "set" | "delete"; data?: object }[] = [];

  for (const fid of friendUids) {
    if (!existingUids.includes(fid)) {
      writes.push({
        ref: db.doc(`users/${uid}/friends/${fid}`),
        op: "set",
        data: { since: FieldValue.serverTimestamp() },
      });
    }
  }
  for (const fid of existingUids) {
    if (!friendUids.includes(fid)) {
      writes.push({ ref: db.doc(`users/${uid}/friends/${fid}`), op: "delete" });
    }
  }

  for (const fromUid of (after.friendRequestsReceived ?? []) as string[]) {
    writes.push({
      ref: db.doc(`users/${uid}/friendRequests/${fromUid}`),
      op: "set",
      data: { sentAt: FieldValue.serverTimestamp() },
    });
  }

  // Outbound mirror. The sender cannot read the recipient's inbox, so the
  // "Sent" state in the UI needs its own owner-readable copy.
  for (const toUid of (after.friendRequestsSent ?? []) as string[]) {
    writes.push({
      ref: db.doc(`users/${uid}/sentRequests/${toUid}`),
      op: "set",
      data: { sentAt: FieldValue.serverTimestamp() },
    });
  }

  // Public profile carries no email — that stays in the private parent document.
  writes.push({
    ref: db.doc(`users/${uid}/public/profile`),
    op: "set",
    data: {
      displayName: after.displayName ?? "User",
      username: after.username ?? null,
      photoUrl: after.photoUrl ?? null,
      friendCount: friendUids.length,
      updatedAt: FieldValue.serverTimestamp(),
    },
  });

  writes.push({
    ref: db.doc(`users/${uid}/settings/prefs`),
    op: "set",
    data: {
      mutedFriends: after.mutedFriends ?? [],
      hiddenHiveIds: after.hiddenHiveIds ?? [],
      updatedAt: FieldValue.serverTimestamp(),
    },
  });

  if (after.username) {
    writes.push({
      ref: db.doc(`usernames/${String(after.username).toLowerCase()}`),
      op: "set",
      data: { uid },
    });
  }

  for (const group of chunk(writes, 450)) {
    const batch = db.batch();
    for (const w of group) {
      if (w.op === "delete") batch.delete(w.ref);
      else batch.set(w.ref, w.data!, { merge: true });
    }
    await batch.commit();
  }
});

// ─── Migration: nested hive → top-level hives/{hiveId} ───────────────────────

export const mirrorHive = onDocumentWritten(
  "users/{uid}/hives/{hiveId}",
  async (event) => {
    const { uid, hiveId } = event.params;
    const after = event.data?.after.data();
    const target = db.doc(`hives/${hiveId}`);

    if (!after) {
      await target.delete().catch(() => undefined);
      return;
    }

    // audienceIds is deliberately omitted — onHiveWrite owns it.
    await target.set(
      {
        ownerId: uid,
        ownerDisplayName: after.ownerDisplayName ?? "",
        title: after.title ?? "Untitled",
        imageUrl: after.imageUrl ?? "",
        note: after.note ?? "",
        privacy: after.privacy ?? "private",
        viewerIds: after.viewerIds ?? after.allowedViewerIds ?? [],
        editorIds: after.editorIds ?? after.allowedEditorIds ?? [],
        itemCount: after.itemCount ?? 0,
        totalCost: after.totalCost ?? 0,
        createdAt: after.createdAt ?? FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
);

// ─── Migration: nested wish → hives/{hiveId}/wishes/{wishId} ─────────────────

export const mirrorWish = onDocumentWritten(
  "users/{uid}/wishes/{wishId}",
  async (event) => {
    const { uid, wishId } = event.params;
    const after = event.data?.after.data();
    const before = event.data?.before.data();

    const hiveId = (after ?? before)?.hiveId;
    if (!hiveId) return;

    const target = db.doc(`hives/${hiveId}/wishes/${wishId}`);

    if (!after) {
      await target.delete().catch(() => undefined);
      return;
    }
    // hiveOwnerId scopes the collection-group query behind the unseen badge.
    await target.set({ ...after, hiveOwnerId: uid }, { merge: true });
  }
);

// ─── Access: resolve privacy into audienceIds ────────────────────────────────
// The client sends what the user WANTS (privacy + viewerIds).
// This decides what that actually MEANS. Rules then read audienceIds.

export const onHiveWrite = onDocumentWritten("hives/{hiveId}", async (event) => {
  const after = event.data?.after.data();
  if (!after) return;

  const ownerId: string = after.ownerId ?? "";
  if (!ownerId) return;

  const privacy: string = after.privacy ?? "private";
  const viewers: string[] = after.viewerIds ?? after.allowedViewerIds ?? [];

  // viewerIds is an explicit grant and is ALWAYS additive, whatever the privacy
  // mode. Previously the friends branch ignored it, so redeeming a share link
  // on a friends-only hive added the person to viewerIds and then immediately
  // recomputed them straight back out — they were told access was granted and
  // still could not open the hive.
  let audience: string[];
  switch (privacy) {
    case "friends": {
      // Security rules cannot enumerate a collection, which is exactly why
      // friends-only privacy cannot be enforced without this function.
      const snap = await db.collection(`users/${ownerId}/friends`).get();
      audience = [ownerId, ...snap.docs.map((d) => d.id), ...viewers];
      break;
    }
    case "public":
      audience = [];
      break;
    default: // private and specific
      audience = [ownerId, ...viewers];
  }
  audience = [...new Set(audience)];

  const current: string[] = after.audienceIds ?? [];
  const isPublic = privacy === "public";
  if (sameSet(current, audience) && after.isPublic === isPublic) return;

  await event.data!.after.ref.update({ audienceIds: audience, isPublic });
});

// ─── Access: a friendship change updates every friends-privacy hive ──────────
// This is what makes unfriending actually revoke access.

export const onFriendshipChanged = onDocumentWritten(
  "users/{uid}/friends/{friendId}",
  async (event) => {
    const uid = event.params.uid;

    const snap = await db.collection(`users/${uid}/friends`).get();
    const audience = [uid, ...snap.docs.map((d) => d.id)];

    // friendCount was previously derived from the legacy friends array. Once
    // clients write edges directly that array stops changing, so the count has
    // to be maintained here instead.
    await db
      .doc(`users/${uid}/public/profile`)
      .set({ friendCount: snap.size }, { merge: true });

    const hives = await db
      .collection("hives")
      .where("ownerId", "==", uid)
      .where("privacy", "==", "friends")
      .get();
    if (hives.empty) return;

    for (const group of chunk(hives.docs, 450)) {
      const batch = db.batch();
      for (const h of group) {
        if (sameSet(h.data().audienceIds ?? [], audience)) continue;
        batch.update(h.ref, { audienceIds: audience });
      }
      await batch.commit();
    }
  }
);

// ─── Aggregates: itemCount and totalCost, computed not incremented ───────────

export const onWishWrite = onDocumentWritten(
  "hives/{hiveId}/wishes/{wishId}",
  async (event) => {
    const hiveId = event.params.hiveId;

    const wishes = await db.collection(`hives/${hiveId}/wishes`).get();
    let itemCount = 0;
    let totalCost = 0;
    // Matches the client: totalCost sums `cost` and ignores `quantity`.
    // Changing this to cost * quantity would shift every existing hive total
    // the moment these functions deploy.
    for (const w of wishes.docs) {
      const d = w.data();
      itemCount += 1;
      totalCost += Number(d.cost) || 0;
    }

    const hiveSnap = await db.doc(`hives/${hiveId}`).get();
    if (!hiveSnap.exists) return;
    const cur = hiveSnap.data()!;
    if (cur.itemCount === itemCount && cur.totalCost === totalCost) return;

    const batch = db.batch();
    batch.update(hiveSnap.ref, { itemCount, totalCost });
    // Keep the nested copy correct so v1.0.3 clients show the right totals too.
    if (cur.ownerId) {
      batch.set(
        db.doc(`users/${cur.ownerId}/hives/${hiveId}`),
        { itemCount, totalCost },
        { merge: true }
      );
    }
    await batch.commit();
  }
);

// ─── Cleanup: deleting a hive removes its wishes and its Storage objects ─────

export const onHiveDelete = onDocumentDeleted(
  "hives/{hiveId}",
  async (event) => {
    const hiveId = event.params.hiveId;
    const data = event.data?.data();

    const wishes = await db.collection(`hives/${hiveId}/wishes`).get();
    const imagePaths: string[] = [];

    for (const group of chunk(wishes.docs, 450)) {
      const batch = db.batch();
      for (const w of group) {
        const url = w.data().imageUrl as string | undefined;
        if (url?.startsWith("https://")) imagePaths.push(url);
        batch.delete(w.ref);
      }
      await batch.commit();
    }

    const ownerId = data?.ownerId;
    if (ownerId) {
      await db.doc(`users/${ownerId}/hives/${hiveId}`).delete().catch(() => undefined);
      const owned = await db
        .collection(`users/${ownerId}/wishes`)
        .where("hiveId", "==", hiveId)
        .get();
      for (const group of chunk(owned.docs, 450)) {
        const batch = db.batch();
        for (const w of group) batch.delete(w.ref);
        await batch.commit();
      }
    }

    const bucket = getStorage().bucket();
    for (const url of imagePaths) {
      const match = decodeURIComponent(url).match(/\/o\/(.+?)\?/);
      if (match?.[1]) await bucket.file(match[1]).delete().catch(() => undefined);
    }
  }
);

// ─── Cleanup: a deleted hive should not linger in anyone's hidden list ───────

export const onHiveDeleteCleanHidden = onDocumentDeleted(
  "hives/{hiveId}",
  async (event) => {
    const hiveId = event.params.hiveId;
    const holders = await db
      .collectionGroup("settings")
      .where("hiddenHiveIds", "array-contains", hiveId)
      .get();
    if (holders.empty) return;

    for (const group of chunk(holders.docs, 450)) {
      const batch = db.batch();
      for (const d of group) {
        batch.update(d.ref, { hiddenHiveIds: FieldValue.arrayRemove(hiveId) });
      }
      await batch.commit();
    }
  }
);

// ─── Callable: accept a friend request ───────────────────────────────────────
// Writing both sides of a friendship crosses an ownership boundary, which no
// security rule can permit safely. Dual-writes the legacy arrays so clients
// still on v1.0.3 continue to see their friends.

export const acceptFriendRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

  const requesterUid = request.data?.requesterUid as string | undefined;
  if (!requesterUid) throw new HttpsError("invalid-argument", "requesterUid is required.");
  if (requesterUid === uid) throw new HttpsError("invalid-argument", "Cannot befriend yourself.");

  const meRef = db.doc(`users/${uid}`);
  const themRef = db.doc(`users/${requesterUid}`);
  const [meSnap, themSnap] = await db.getAll(meRef, themRef);
  if (!meSnap.exists || !themSnap.exists) {
    throw new HttpsError("not-found", "User not found.");
  }

  const pending =
    (meSnap.data()?.friendRequestsReceived ?? []).includes(requesterUid) ||
    (await db.doc(`users/${uid}/friendRequests/${requesterUid}`).get()).exists;
  if (!pending) throw new HttpsError("failed-precondition", "No pending request.");

  const me = meSnap.data()!;
  const them = themSnap.data()!;
  const meCard = {
    uid,
    displayName: me.displayName ?? "User",
    photoUrl: me.photoUrl ?? null,
    email: me.email ?? "",
  };
  const themCard = {
    uid: requesterUid,
    displayName: them.displayName ?? "User",
    photoUrl: them.photoUrl ?? null,
    email: them.email ?? "",
  };

  const batch = db.batch();

  batch.set(db.doc(`users/${uid}/friends/${requesterUid}`), {
    since: FieldValue.serverTimestamp(),
  });
  batch.set(db.doc(`users/${requesterUid}/friends/${uid}`), {
    since: FieldValue.serverTimestamp(),
  });
  batch.delete(db.doc(`users/${uid}/friendRequests/${requesterUid}`));

  batch.update(meRef, {
    friends: FieldValue.arrayUnion(themCard),
    friendRequestsReceived: FieldValue.arrayRemove(requesterUid),
  });
  batch.update(themRef, {
    friends: FieldValue.arrayUnion(meCard),
    friendRequestsSent: FieldValue.arrayRemove(uid),
  });

  await batch.commit();
  return { ok: true };
});

// ─── Callable: remove a friend ───────────────────────────────────────────────

export const removeFriend = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

  const friendUid = request.data?.friendUid as string | undefined;
  if (!friendUid) throw new HttpsError("invalid-argument", "friendUid is required.");

  const meRef = db.doc(`users/${uid}`);
  const themRef = db.doc(`users/${friendUid}`);
  const [meSnap, themSnap] = await db.getAll(meRef, themRef);

  const batch = db.batch();
  batch.delete(db.doc(`users/${uid}/friends/${friendUid}`));
  batch.delete(db.doc(`users/${friendUid}/friends/${uid}`));

  const strip = (
    snap: FirebaseFirestore.DocumentSnapshot,
    ref: FirebaseFirestore.DocumentReference,
    otherUid: string
  ) => {
    if (!snap.exists) return;
    const friends: unknown[] = snap.data()?.friends ?? [];
    const kept = friends.filter(
      (f) => (typeof f === "string" ? f : (f as { uid?: string })?.uid) !== otherUid
    );
    batch.update(ref, { friends: kept });
  };
  strip(meSnap, meRef, friendUid);
  strip(themSnap, themRef, uid);

  await batch.commit();
  return { ok: true };
});

// ─── Share landing page ──────────────────────────────────────────────────────
// Served at /h/<shareId> via a Hosting rewrite. Link previews (WhatsApp,
// Telegram, iMessage) do not run JavaScript, so the Open Graph tags have to be
// in the HTML as it leaves the server. Returns metadata only — never wishes.

const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=com.wishhive.app";

const escapeHtml = (s: string) =>
  String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");

function landingHtml(opts: {
  title: string;
  description: string;
  image: string;
  url: string;
}) {
  const t = escapeHtml(opts.title);
  const d = escapeHtml(opts.description);
  const img = escapeHtml(opts.image);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${t} · WishHive</title>
<meta property="og:type" content="website">
<meta property="og:site_name" content="WishHive">
<meta property="og:title" content="${t}">
<meta property="og:description" content="${d}">
${img ? `<meta property="og:image" content="${img}">` : ""}
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${t}">
<meta name="twitter:description" content="${d}">
${img ? `<meta name="twitter:image" content="${img}">` : ""}
<style>
:root{color-scheme:light dark}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
padding:24px;background:#faf7f0;color:#1d1b16;
font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
.card{width:100%;max-width:380px;background:#fff;border-radius:18px;overflow:hidden;
box-shadow:0 2px 4px rgba(0,0,0,.05),0 12px 32px rgba(0,0,0,.09)}
.hero{aspect-ratio:16/10;background:#e8e2d4 center/cover no-repeat;display:block}
.body{padding:20px}
h1{margin:0 0 6px;font-size:21px;line-height:1.25}
.meta{margin:0 0 18px;color:#6b6659;font-size:14px}
.btn{display:block;padding:14px;border-radius:12px;background:#c77a14;color:#fff;
text-align:center;text-decoration:none;font-weight:600}
.hint{margin:14px 0 0;font-size:13px;color:#8a8478;text-align:center}
@media(prefers-color-scheme:dark){
body{background:#14161b;color:#e8eaee}
.card{background:#1c1f26;box-shadow:none}
.hero{background-color:#242832}
.meta{color:#aeb5c2}.hint{color:#7c8494}}
</style>
</head>
<body>
<div class="card">
  ${img ? `<span class="hero" style="background-image:url('${img}')"></span>` : `<span class="hero"></span>`}
  <div class="body">
    <h1>${t}</h1>
    <p class="meta">${d}</p>
    <a class="btn" href="${PLAY_STORE_URL}">Get WishHive</a>
    <p class="hint">Already have the app? Open this link on your phone.</p>
  </div>
</div>
</body>
</html>`;
}

export const hiveLandingPage = onRequest(
  { region: "asia-south1", cors: true },
  async (req, res) => {
    const shareId = (req.path || "").split("/").filter(Boolean).pop() ?? "";

    res.set("Cache-Control", "public, max-age=300, s-maxage=600");

    if (!shareId) {
      res.status(404).send(
        landingHtml({
          title: "Link not found",
          description: "This WishHive link is not valid.",
          image: "",
          url: "",
        })
      );
      return;
    }

    const found = await db
      .collection("hives")
      .where("shareId", "==", shareId)
      .limit(1)
      .get();

    if (found.empty) {
      res.status(404).send(
        landingHtml({
          title: "Link not found",
          description: "This WishHive link is no longer active.",
          image: "",
          url: "",
        })
      );
      return;
    }

    const hive = found.docs[0].data();
    const owner = hive.ownerDisplayName ? ` · shared by ${hive.ownerDisplayName}` : "";
    const count = Number(hive.itemCount) || 0;
    const items = count === 1 ? "1 item" : `${count} items`;
    const image = String(hive.imageUrl ?? "").startsWith("http")
      ? String(hive.imageUrl)
      : "";

    res.status(200).send(
      landingHtml({
        title: hive.title ?? "A WishHive list",
        description: `${items}${owner}`,
        image,
        url: req.url,
      })
    );
  }
);

// ─── Callable: redeem a share link ───────────────────────────────────────────
// A link is a grant. Redeeming adds the caller to that ONE hive's viewerIds;
// onHiveWrite then widens audienceIds and the normal rules take over from
// there — no separate access path exists.

export const redeemShareLink = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

  const shareId = request.data?.shareId as string | undefined;
  if (!shareId) throw new HttpsError("invalid-argument", "shareId is required.");

  const found = await db
    .collection("hives")
    .where("shareId", "==", shareId)
    .limit(1)
    .get();
  if (found.empty) return { status: "invalid" };

  const doc = found.docs[0];
  const hive = doc.data();

  if (hive.ownerId === uid) return { status: "already", hiveId: doc.id };
  if ((hive.audienceIds ?? []).includes(uid)) {
    return { status: "already", hiveId: doc.id };
  }
  // Still return the owner so the app can offer a friend request instead.
  if (hive.linkShareEnabled !== true) {
    return { status: "disabled", hiveId: doc.id, ownerId: hive.ownerId };
  }

  const viewers: string[] = hive.viewerIds ?? hive.allowedViewerIds ?? [];
  const next = [...new Set([...viewers, uid])];

  // The privacy mode is left alone — viewerIds is additive in every mode.
  await doc.ref.update({ viewerIds: next, allowedViewerIds: next });

  // Keep the legacy nested copy in step for clients still on v1.0.3.
  if (hive.ownerId) {
    await db
      .doc(`users/${hive.ownerId}/hives/${doc.id}`)
      .update({ viewerIds: next, allowedViewerIds: next })
      .catch(() => undefined);
  }

  return { status: "granted", hiveId: doc.id, ownerId: hive.ownerId };
});

// ─── Callable: delete my account ─────────────────────────────────────────────
// Google Play requires an in-app deletion route. Deleting the user document
// triggers onUserDocDeleted, which cascades everything else.

export const deleteAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

  const snap = await db.doc(`users/${uid}`).get();
  if (!snap.exists) return { ok: true };

  // Detach from other people's friend lists before the cascade runs, so nobody
  // is left holding a card for an account that no longer exists.
  const friends = await db.collection(`users/${uid}/friends`).get();
  for (const group of chunk(friends.docs, 200)) {
    await Promise.all(
      group.map(async (f) => {
        const otherRef = db.doc(`users/${f.id}`);
        const other = await otherRef.get();
        if (!other.exists) return;
        const kept = (other.data()?.friends ?? []).filter(
          (x: unknown) =>
            (typeof x === "string" ? x : (x as { uid?: string })?.uid) !== uid
        );
        await otherRef.update({ friends: kept });
        await db.doc(`users/${f.id}/friends/${uid}`).delete().catch(() => undefined);
      })
    );
  }

  await db.doc(`users/${uid}`).delete();
  await getAuth().deleteUser(uid).catch(() => undefined);
  return { ok: true };
});

// ─── Account deletion cascade ────────────────────────────────────────────────

export const onUserDocDeleted = onDocumentDeleted("users/{uid}", async (event) => {
  const uid = event.params.uid;
  const data = event.data?.data();

  // Capture the friend ids BEFORE the subcollection is deleted, so the
  // reciprocal edges can be removed by direct path. The previous version read
  // every friend edge in the entire database with a collectionGroup query and
  // filtered client-side.
  const myFriends = (await db.collection(`users/${uid}/friends`).get()).docs.map(
    (d) => d.id
  );

  const hives = await db.collection("hives").where("ownerId", "==", uid).get();
  for (const h of hives.docs) await h.ref.delete();

  for (const sub of ["friends", "friendRequests", "sentRequests", "blocked", "hives", "wishes"]) {
    const docs = await db.collection(`users/${uid}/${sub}`).get();
    for (const group of chunk(docs.docs, 450)) {
      const batch = db.batch();
      for (const d of group) batch.delete(d.ref);
      await batch.commit();
    }
  }

  await db.doc(`users/${uid}/public/profile`).delete().catch(() => undefined);
  await db.doc(`users/${uid}/settings/prefs`).delete().catch(() => undefined);

  if (data?.username) {
    const nameRef = db.doc(`usernames/${String(data.username).toLowerCase()}`);
    const snap = await nameRef.get();
    if (snap.exists && snap.data()?.uid === uid) await nameRef.delete();
  }

  for (const group of chunk(myFriends, 450)) {
    const batch = db.batch();
    for (const fid of group) batch.delete(db.doc(`users/${fid}/friends/${uid}`));
    await batch.commit();
  }
});

// ─── Username claim guard ────────────────────────────────────────────────────
// Releases claims a user no longer holds. Driven by the profile rather than by
// the claim document: two concurrent claim triggers would each see the other as
// stale and could delete the name the user actually wants.

export const releaseStaleUsernames = onDocumentWritten(
  "users/{uid}/public/profile",
  async (event) => {
    const uid = event.params.uid;
    const current = (event.data?.after.data()?.username as string | undefined)
      ?.toLowerCase();
    if (!current) return;

    const claims = await db.collection("usernames").where("uid", "==", uid).get();
    const stale = claims.docs.filter((d) => d.id !== current);
    if (!stale.length) return;

    const batch = db.batch();
    for (const d of stale) batch.delete(d.ref);
    await batch.commit();
  }
);
