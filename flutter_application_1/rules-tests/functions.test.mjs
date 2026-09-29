// Cloud Functions integration suite for WishHive.
//
//   cd flutter_application_1/rules-tests
//   npm install            (once)
//   npm run test:functions
//
// Boots the Firestore AND Functions emulators, writes real documents with the
// Admin SDK, and asserts the derived documents the triggers are supposed to
// produce. Nothing touches the real project.

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

let app;
let db;

// Each test gets its own uids and hive ids, so no cleanup is needed between
// tests. Deleting user documents would fire the onUserDocDeleted cascade and
// starve the emulator.
let n = 0;
let ALICE, BOB, CAROL, H1, W1;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Triggers are eventual — poll until the expectation holds or we give up.
async function waitFor(check, label, timeoutMs = 25000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const r = await check();
      if (r) return r;
    } catch {
      // keep polling
    }
    await sleep(250);
  }
  throw new Error(`timed out waiting for: ${label}`);
}

before(async () => {
  app = initializeApp({ projectId: 'demo-wishhive' });
  db = getFirestore(app);
});

after(async () => {
  await deleteApp(app);
});

beforeEach(() => {
  n++;
  ALICE = `alice${n}`;
  BOB = `bob${n}`;
  CAROL = `carol${n}`;
  H1 = `h${n}`;
  W1 = `w${n}`;
});

// ─────────────────────────────────────────────────────────────────────────────
describe('mirrorUserDoc', () => {
  it('creates friend edges, profile, settings and username claim', async () => {
    await db.doc(`users/${ALICE}`).set({
      email: 'alice@example.com',
      displayName: 'Alice',
      username: ALICE,
      photoUrl: 'a.jpg',
      friends: [{ uid: BOB, displayName: 'Bob', email: 'bob@example.com' }],
      friendRequestsReceived: [CAROL],
      mutedFriends: [BOB],
      hiddenHiveIds: [`hidden${n}`],
    });

    const edge = await waitFor(
      async () => (await db.doc(`users/${ALICE}/friends/${BOB}`).get()).exists,
      'friend edge alice→bob',
    );
    assert.ok(edge);

    const profile = await waitFor(
      async () => {
        const s = await db.doc(`users/${ALICE}/public/profile`).get();
        return s.exists ? s.data() : null;
      },
      'public profile',
    );
    assert.equal(profile.displayName, 'Alice');
    assert.equal(profile.username, ALICE);
    assert.equal(profile.friendCount, 1);
    assert.equal(profile.email, undefined, 'email must NOT leak into the public profile');

    const settings = await waitFor(
      async () => {
        const s = await db.doc(`users/${ALICE}/settings/prefs`).get();
        return s.exists ? s.data() : null;
      },
      'settings',
    );
    assert.deepEqual(settings.mutedFriends, [BOB]);
    assert.deepEqual(settings.hiddenHiveIds, [`hidden${n}`]);

    const req = await waitFor(
      async () => (await db.doc(`users/${ALICE}/friendRequests/${CAROL}`).get()).exists,
      'inbound friend request',
    );
    assert.ok(req);

    const name = await waitFor(
      async () => {
        const s = await db.doc(`usernames/${ALICE}`).get();
        return s.exists ? s.data() : null;
      },
      'username claim',
    );
    assert.equal(name.uid, ALICE);
  });

  it('mirrors friendRequestsSent so the Sent state survives', async () => {
    await db.doc(`users/${ALICE}`).set({
      displayName: 'Alice',
      friends: [],
      friendRequestsSent: [BOB, CAROL],
    });

    const sent = await waitFor(async () => {
      const s = await db.collection(`users/${ALICE}/sentRequests`).get();
      return s.size === 2 ? s : null;
    }, 'outbound sent-request mirror');

    assert.deepEqual(sent.docs.map((d) => d.id).sort(), [BOB, CAROL].sort());
  });

  it('removes the edge when a friend is dropped from the array', async () => {
    await db.doc(`users/${ALICE}`).set({
      displayName: 'Alice',
      friends: [{ uid: BOB, displayName: 'Bob', email: '' }],
    });
    await waitFor(
      async () => (await db.doc(`users/${ALICE}/friends/${BOB}`).get()).exists,
      'edge created',
    );

    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', friends: [] });
    const gone = await waitFor(
      async () => !(await db.doc(`users/${ALICE}/friends/${BOB}`).get()).exists,
      'edge removed',
    );
    assert.ok(gone);
  });

  it('tolerates legacy string-only friend entries', async () => {
    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', friends: [BOB] });
    const edge = await waitFor(
      async () => (await db.doc(`users/${ALICE}/friends/${BOB}`).get()).exists,
      'edge from legacy string entry',
    );
    assert.ok(edge);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('mirrorHive and onHiveWrite', () => {
  it('mirrors a nested hive to the top level', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({
      title: 'Birthday',
      privacy: 'private',
      itemCount: 0,
      totalCost: 0,
    });

    const top = await waitFor(async () => {
      const s = await db.doc(`hives/${H1}`).get();
      return s.exists ? s.data() : null;
    }, 'top-level hive');

    assert.equal(top.ownerId, ALICE);
    assert.equal(top.title, 'Birthday');
  });

  it('private hive resolves audienceIds to the owner only', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'Secret', privacy: 'private' });
    const aud = await waitFor(async () => {
      const s = await db.doc(`hives/${H1}`).get();
      const a = s.data()?.audienceIds;
      return a?.length ? a : null;
    }, 'audienceIds for private');
    assert.deepEqual(aud, [ALICE]);
  });

  it('specific hive resolves audienceIds to owner plus viewers', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({
      title: 'Shared',
      privacy: 'specific',
      allowedViewerIds: [BOB, CAROL],
      allowedEditorIds: [BOB],
    });
    const aud = await waitFor(async () => {
      const s = await db.doc(`hives/${H1}`).get();
      const a = s.data()?.audienceIds;
      return a?.length >= 3 ? a : null;
    }, 'audienceIds for specific');
    assert.deepEqual([...aud].sort(), [ALICE, BOB, CAROL].sort());
  });

  it('friends hive resolves audienceIds from the friend edges', async () => {
    await db.doc(`users/${ALICE}/friends/${BOB}`).set({ since: new Date() });
    await db.doc(`users/${ALICE}/friends/${CAROL}`).set({ since: new Date() });
    await sleep(500);

    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'Friends only', privacy: 'friends' });

    const aud = await waitFor(async () => {
      const s = await db.doc(`hives/${H1}`).get();
      const a = s.data()?.audienceIds;
      return a?.length >= 3 ? a : null;
    }, 'audienceIds for friends');
    assert.deepEqual([...aud].sort(), [ALICE, BOB, CAROL].sort());
  });

  it('REVOCATION: dropping a viewer removes them from audienceIds', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({
      title: 'Shared',
      privacy: 'specific',
      allowedViewerIds: [BOB, CAROL],
    });
    await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a?.includes(CAROL) ? a : null;
    }, 'carol granted');

    await db.doc(`users/${ALICE}/hives/${H1}`).set(
      { allowedViewerIds: [BOB], viewerIds: [BOB] },
      { merge: true },
    );

    const aud = await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a && !a.includes(CAROL) ? a : null;
    }, 'carol revoked');
    assert.ok(!aud.includes(CAROL));
    assert.ok(aud.includes(BOB));
  });

  it('deleting the nested hive deletes the mirrored one', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'Temp', privacy: 'private' });
    await waitFor(async () => (await db.doc(`hives/${H1}`).get()).exists, 'mirrored');

    await db.doc(`users/${ALICE}/hives/${H1}`).delete();
    const gone = await waitFor(
      async () => !(await db.doc(`hives/${H1}`).get()).exists,
      'mirror deleted',
    );
    assert.ok(gone);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('onFriendshipChanged', () => {
  it('adding a friend widens every friends-privacy hive', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'Friends', privacy: 'friends' });
    await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a?.length === 1 ? a : null;
    }, 'initial audience');

    await db.doc(`users/${ALICE}/friends/${BOB}`).set({ since: new Date() });

    const aud = await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a?.includes(BOB) ? a : null;
    }, 'bob added to audience');
    assert.ok(aud.includes(BOB));
  });

  it('UNFRIEND: removing a friend revokes their access', async () => {
    await db.doc(`users/${ALICE}/friends/${BOB}`).set({ since: new Date() });
    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'Friends', privacy: 'friends' });
    await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a?.includes(BOB) ? a : null;
    }, 'bob has access');

    await db.doc(`users/${ALICE}/friends/${BOB}`).delete();

    const aud = await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a && !a.includes(BOB) ? a : null;
    }, 'bob revoked');
    assert.deepEqual(aud, [ALICE]);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('mirrorWish and onWishWrite', () => {
  it('mirrors a wish under its hive and computes the aggregates', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({
      title: 'Gifts',
      privacy: 'private',
      itemCount: 99,
      totalCost: 99999,
    });
    await waitFor(async () => (await db.doc(`hives/${H1}`).get()).exists, 'hive mirrored');

    await db.doc(`users/${ALICE}/wishes/${W1}`).set({
      name: 'Headphones',
      hiveId: H1,
      cost: 500,
      quantity: 2,
    });

    const mirrored = await waitFor(async () => {
      const s = await db.doc(`hives/${H1}/wishes/${W1}`).get();
      return s.exists ? s.data() : null;
    }, 'wish mirrored');
    assert.equal(mirrored.name, 'Headphones');

    const hive = await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.itemCount === 1 ? d : null;
    }, 'aggregates recomputed');

    assert.equal(hive.itemCount, 1);
    // totalCost deliberately sums `cost` and ignores `quantity`, matching the
    // Flutter client. Using cost * quantity here would shift every existing
    // hive total the moment these functions deploy.
    assert.equal(hive.totalCost, 500, 'cost only, quantity ignored');
  });

  it('corrects drifted aggregates rather than incrementing them', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'X', privacy: 'private' });
    await waitFor(async () => (await db.doc(`hives/${H1}`).get()).exists, 'hive mirrored');

    await db.doc(`users/${ALICE}/wishes/${W1}`).set({ name: 'A', hiveId: H1, cost: 100, quantity: 1 });
    await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.totalCost === 100 ? d : null;
    }, 'first total');

    // A price edit — the exact case the old increment logic never handled.
    await db.doc(`users/${ALICE}/wishes/${W1}`).set(
      { name: 'A', hiveId: H1, cost: 250, quantity: 1 },
      { merge: true },
    );

    const hive = await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.totalCost === 250 ? d : null;
    }, 'total corrected after price edit');
    assert.equal(hive.totalCost, 250);
    assert.equal(hive.itemCount, 1);
  });

  it('deleting a wish lowers the aggregates', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'X', privacy: 'private' });
    await db.doc(`users/${ALICE}/wishes/${W1}`).set({ name: 'A', hiveId: H1, cost: 100, quantity: 1 });
    await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.itemCount === 1 ? d : null;
    }, 'counted');

    await db.doc(`users/${ALICE}/wishes/${W1}`).delete();

    const hive = await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.itemCount === 0 ? d : null;
    }, 'uncounted');
    assert.equal(hive.itemCount, 0);
    assert.equal(hive.totalCost, 0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('onHiveDelete', () => {
  it('removes the hive wishes when the hive goes', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'X', privacy: 'private' });
    await db.doc(`users/${ALICE}/wishes/${W1}`).set({ name: 'A', hiveId: H1, cost: 10, quantity: 1 });
    await waitFor(async () => (await db.doc(`hives/${H1}/wishes/${W1}`).get()).exists, 'wish mirrored');

    await db.doc(`hives/${H1}`).delete();

    const gone = await waitFor(
      async () => !(await db.doc(`hives/${H1}/wishes/${W1}`).get()).exists,
      'nested wishes deleted',
    );
    assert.ok(gone);
  });
});
