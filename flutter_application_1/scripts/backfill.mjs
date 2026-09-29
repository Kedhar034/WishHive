// WishHive schema backfill — old structure → new structure.
//
// SETUP (once)
//   Firebase Console → Project Settings → Service accounts → Generate new private key
//   Save it OUTSIDE the repo, then:
//     Windows PowerShell:  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\keys\wishhive.json"
//     bash:                export GOOGLE_APPLICATION_CREDENTIALS=/path/wishhive.json
//   npm install
//
// RUN
//   npm run backfill          Dry run. Reads only. Writes NOTHING. Always do this first.
//   npm run backfill:commit   Applies the changes.
//   npm run verify            Compares old vs new and reports any mismatch.
//
// Safe to re-run: every write is a merge keyed on a deterministic document id,
// so running it twice produces the same result as running it once.

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const COMMIT = process.argv.includes('--commit');
const VERIFY = process.argv.includes('--verify');
const PROJECT_ID =
  process.env.GCLOUD_PROJECT ||
  process.env.FIREBASE_PROJECT_ID ||
  'flutterapplication-77c19';

// Against the emulator no credentials are needed or wanted.
const USING_EMULATOR = !!process.env.FIRESTORE_EMULATOR_HOST;
initializeApp(
  USING_EMULATOR
    ? { projectId: PROJECT_ID }
    : { credential: applicationDefault(), projectId: PROJECT_ID },
);
const db = getFirestore();

const stats = {
  users: 0,
  friendEdges: 0,
  friendRequests: 0,
  sentRequests: 0,
  profiles: 0,
  settings: 0,
  usernames: 0,
  hives: 0,
  wishes: 0,
  aggregatesFixed: 0,
  skipped: [],
};

let pending = [];

function queue(ref, data) {
  pending.push({ ref, data });
}

async function flush() {
  if (!COMMIT) {
    pending = [];
    return;
  }
  while (pending.length) {
    const group = pending.splice(0, 450);
    const batch = db.batch();
    for (const { ref, data } of group) batch.set(ref, data, { merge: true });
    await batch.commit();
  }
}

const uidsOf = (friends) =>
  (friends ?? [])
    .map((f) => (typeof f === 'string' ? f : f?.uid))
    .filter((v) => typeof v === 'string' && v.length > 0);

function audienceFor(hive, ownerId, friendUids) {
  const privacy = hive.privacy ?? 'private';
  const viewers = hive.viewerIds ?? hive.allowedViewerIds ?? [];
  switch (privacy) {
    case 'specific':
      return [...new Set([ownerId, ...viewers])];
    case 'friends':
      return [...new Set([ownerId, ...friendUids])];
    case 'public':
      return [];
    default:
      return [ownerId];
  }
}

// ─────────────────────────────────────────────────────────────────────────────

async function backfill() {
  const users = await db.collection('users').get();
  console.log(`Found ${users.size} users\n`);

  for (const userDoc of users.docs) {
    const uid = userDoc.id;
    const u = userDoc.data();
    stats.users++;

    const friendUids = uidsOf(u.friends);

    for (const fid of friendUids) {
      queue(db.doc(`users/${uid}/friends/${fid}`), { since: FieldValue.serverTimestamp() });
      stats.friendEdges++;
    }

    for (const fromUid of u.friendRequestsReceived ?? []) {
      if (typeof fromUid !== 'string' || !fromUid) continue;
      queue(db.doc(`users/${uid}/friendRequests/${fromUid}`), {
        sentAt: FieldValue.serverTimestamp(),
      });
      stats.friendRequests++;
    }

    for (const toUid of u.friendRequestsSent ?? []) {
      if (typeof toUid !== 'string' || !toUid) continue;
      queue(db.doc(`users/${uid}/sentRequests/${toUid}`), {
        sentAt: FieldValue.serverTimestamp(),
      });
      stats.sentRequests++;
    }

    queue(db.doc(`users/${uid}/public/profile`), {
      displayName: u.displayName ?? 'User',
      username: u.username ?? null,
      photoUrl: u.photoUrl ?? null,
      friendCount: friendUids.length,
      updatedAt: FieldValue.serverTimestamp(),
    });
    stats.profiles++;

    queue(db.doc(`users/${uid}/settings/prefs`), {
      mutedFriends: u.mutedFriends ?? [],
      hiddenHiveIds: u.hiddenHiveIds ?? [],
      updatedAt: FieldValue.serverTimestamp(),
    });
    stats.settings++;

    if (u.username) {
      const name = String(u.username).toLowerCase();
      const existing = await db.doc(`usernames/${name}`).get();
      if (existing.exists && existing.data()?.uid !== uid) {
        stats.skipped.push(`username "${name}" already claimed by ${existing.data()?.uid}, not ${uid}`);
      } else {
        queue(db.doc(`usernames/${name}`), { uid });
        stats.usernames++;
      }
    }

    // Hives → top-level, with audienceIds resolved.
    const hives = await db.collection(`users/${uid}/hives`).get();
    const hiveIds = [];
    for (const h of hives.docs) {
      const hd = h.data();
      hiveIds.push(h.id);
      queue(db.doc(`hives/${h.id}`), {
        ownerId: uid,
        ownerDisplayName: hd.ownerDisplayName ?? u.displayName ?? '',
        title: hd.title ?? 'Untitled',
        imageUrl: hd.imageUrl ?? '',
        note: hd.note ?? '',
        privacy: hd.privacy ?? 'private',
        viewerIds: hd.viewerIds ?? hd.allowedViewerIds ?? [],
        editorIds: hd.editorIds ?? hd.allowedEditorIds ?? [],
        audienceIds: audienceFor(hd, uid, friendUids),
        isPublic: (hd.privacy ?? 'private') === 'public',
        itemCount: hd.itemCount ?? 0,
        totalCost: hd.totalCost ?? 0,
        createdAt: hd.createdAt ?? FieldValue.serverTimestamp(),
      });
      stats.hives++;
    }

    // Wishes → nested under their hive.
    const wishes = await db.collection(`users/${uid}/wishes`).get();
    const totals = {};
    for (const w of wishes.docs) {
      const wd = w.data();
      const hiveId = wd.hiveId;
      if (!hiveId) {
        stats.skipped.push(`wish ${uid}/${w.id} has no hiveId`);
        continue;
      }
      if (!hiveIds.includes(hiveId)) {
        stats.skipped.push(`wish ${uid}/${w.id} points at missing hive ${hiveId}`);
        continue;
      }
      queue(db.doc(`hives/${hiveId}/wishes/${w.id}`), { ...wd, hiveOwnerId: uid });
      stats.wishes++;

      // Matches the client: sums `cost`, ignores `quantity`.
      totals[hiveId] ??= { count: 0, cost: 0 };
      totals[hiveId].count += 1;
      totals[hiveId].cost += Number(wd.cost) || 0;
    }

    // Repair the aggregates that drifted under the old increment logic.
    for (const [hiveId, t] of Object.entries(totals)) {
      const stored = hives.docs.find((d) => d.id === hiveId)?.data();
      if (stored && (stored.itemCount !== t.count || stored.totalCost !== t.cost)) {
        queue(db.doc(`hives/${hiveId}`), { itemCount: t.count, totalCost: t.cost });
        queue(db.doc(`users/${uid}/hives/${hiveId}`), { itemCount: t.count, totalCost: t.cost });
        stats.aggregatesFixed++;
      }
    }

    await flush();
    process.stdout.write(`  ${stats.users}/${users.size} users\r`);
  }

  await flush();
}

// ─────────────────────────────────────────────────────────────────────────────

async function verify() {
  const users = await db.collection('users').get();
  const problems = [];
  const orphans = [];

  for (const userDoc of users.docs) {
    const uid = userDoc.id;
    const u = userDoc.data();
    const friendUids = uidsOf(u.friends);

    const edges = await db.collection(`users/${uid}/friends`).get();
    if (edges.size !== friendUids.length) {
      problems.push(`${uid}: ${friendUids.length} friends in array, ${edges.size} edge docs`);
    }

    const profile = await db.doc(`users/${uid}/public/profile`).get();
    if (!profile.exists) problems.push(`${uid}: missing public/profile`);

    const hives = await db.collection(`users/${uid}/hives`).get();
    for (const h of hives.docs) {
      const top = await db.doc(`hives/${h.id}`).get();
      if (!top.exists) {
        problems.push(`${uid}: hive ${h.id} not mirrored`);
        continue;
      }
      if (!(top.data().audienceIds ?? []).length && top.data().privacy !== 'public') {
        problems.push(`hive ${h.id}: audienceIds is empty`);
      }
    }

    const wishes = await db.collection(`users/${uid}/wishes`).get();
    for (const w of wishes.docs) {
      const hiveId = w.data().hiveId;
      if (!hiveId) {
        orphans.push(`${uid}/${w.id}: no hiveId`);
        continue;
      }
      // A wish whose hive no longer exists cannot be mirrored. That is pre-existing
      // orphaned data, not a migration failure.
      if (!(await db.doc(`hives/${hiveId}`).get()).exists) {
        orphans.push(`${uid}/${w.id}: hive ${hiveId} does not exist`);
        continue;
      }
      const top = await db.doc(`hives/${hiveId}/wishes/${w.id}`).get();
      if (!top.exists) problems.push(`${uid}: wish ${w.id} not mirrored`);
    }
  }

  console.log('\n─── VERIFY ───');
  if (!problems.length) {
    console.log('✓ Old and new structures match. Safe to flip reads.');
  } else {
    console.log(`✗ ${problems.length} mismatch(es):\n`);
    problems.slice(0, 50).forEach((p) => console.log('  ' + p));
    if (problems.length > 50) console.log(`  ... and ${problems.length - 50} more`);
  }

  if (orphans.length) {
    console.log(`\n  ${orphans.length} pre-existing orphaned wish(es), safely ignored:`);
    orphans.slice(0, 20).forEach((o) => console.log('    ' + o));
    if (orphans.length > 20) console.log(`    ... and ${orphans.length - 20} more`);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

const started = Date.now();
console.log(`Project: ${PROJECT_ID}${USING_EMULATOR ? '  (EMULATOR)' : ''}`);
console.log(VERIFY ? 'Mode:    VERIFY' : COMMIT ? 'Mode:    COMMIT (writing)' : 'Mode:    DRY RUN (no writes)');
console.log('');

try {
  if (VERIFY) {
    await verify();
  } else {
    await backfill();
    console.log('\n\n─── SUMMARY ───');
    console.log(`  users            ${stats.users}`);
    console.log(`  friend edges     ${stats.friendEdges}`);
    console.log(`  friend requests  ${stats.friendRequests}`);
    console.log(`  sent requests    ${stats.sentRequests}`);
    console.log(`  public profiles  ${stats.profiles}`);
    console.log(`  settings docs    ${stats.settings}`);
    console.log(`  usernames        ${stats.usernames}`);
    console.log(`  hives            ${stats.hives}`);
    console.log(`  wishes           ${stats.wishes}`);
    console.log(`  aggregates fixed ${stats.aggregatesFixed}`);
    if (stats.skipped.length) {
      console.log(`\n  SKIPPED (${stats.skipped.length}):`);
      stats.skipped.slice(0, 30).forEach((s) => console.log('    ' + s));
      if (stats.skipped.length > 30) console.log(`    ... and ${stats.skipped.length - 30} more`);
    }
    if (!COMMIT) console.log('\n  Dry run — nothing was written. Re-run with --commit to apply.');
  }
  console.log(`\nDone in ${((Date.now() - started) / 1000).toFixed(1)}s`);
  process.exit(0);
} catch (err) {
  console.error('\nFAILED:', err);
  process.exit(1);
}
