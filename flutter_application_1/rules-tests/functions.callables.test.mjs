// Callable functions and destructive cascades.
// Split from functions.test.mjs because these exercise the HTTPS endpoints and
// the delete paths, which are the highest-risk code in the project.
//
//   npm run test:functions

import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

let app;
let db;

let n = 1000;
let ALICE, BOB, H1, W1;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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

// The functions emulator accepts an unsigned token locally, so we can act as a
// specific uid without standing up the Auth emulator.
function fakeToken(uid) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return [
    b64({ alg: 'none', typ: 'JWT' }),
    b64({
      sub: uid,
      user_id: uid,
      uid,
      aud: 'demo-wishhive',
      iss: 'https://securetoken.google.com/demo-wishhive',
      iat: now,
      exp: now + 3600,
      auth_time: now,
      firebase: { sign_in_provider: 'custom', identities: {} },
    }),
    '',
  ].join('.');
}

async function callFn(name, uid, data) {
  const headers = { 'Content-Type': 'application/json' };
  if (uid) headers.Authorization = `Bearer ${fakeToken(uid)}`;
  const res = await fetch(
    `http://127.0.0.1:5001/demo-wishhive/asia-south1/${name}`,
    { method: 'POST', headers, body: JSON.stringify({ data }) },
  );
  const json = await res.json();
  if (json.error) {
    const e = new Error(json.error.message ?? JSON.stringify(json.error));
    e.status = json.error.status;
    throw e;
  }
  return json.result;
}

before(async () => {
  app = initializeApp({ projectId: 'demo-wishhive' }, 'callables');
  db = getFirestore(app);
});

after(async () => {
  await deleteApp(app);
});

beforeEach(() => {
  n++;
  ALICE = `ca${n}`;
  BOB = `cb${n}`;
  H1 = `ch${n}`;
  W1 = `cw${n}`;
});

// ─────────────────────────────────────────────────────────────────────────────
describe('acceptFriendRequest (callable)', () => {
  it('creates both edges, clears the request, keeps legacy arrays in sync', async () => {
    await db.doc(`users/${ALICE}`).set({
      displayName: 'Alice',
      email: 'a@x.com',
      friends: [],
      friendRequestsReceived: [BOB],
    });
    await db.doc(`users/${BOB}`).set({
      displayName: 'Bob',
      email: 'b@x.com',
      friends: [],
      friendRequestsSent: [ALICE],
    });
    await waitFor(
      async () => (await db.doc(`users/${ALICE}/friendRequests/${BOB}`).get()).exists,
      'request mirrored',
    );

    await callFn('acceptFriendRequest', ALICE, { requesterUid: BOB });

    assert.ok((await db.doc(`users/${ALICE}/friends/${BOB}`).get()).exists, 'alice to bob edge');
    assert.ok((await db.doc(`users/${BOB}/friends/${ALICE}`).get()).exists, 'bob to alice edge');
    assert.ok(
      !(await db.doc(`users/${ALICE}/friendRequests/${BOB}`).get()).exists,
      'request cleared',
    );

    const alice = (await db.doc(`users/${ALICE}`).get()).data();
    const bob = (await db.doc(`users/${BOB}`).get()).data();
    assert.equal(alice.friends.length, 1, 'legacy array kept current for v1.0.3 clients');
    assert.equal(bob.friends.length, 1);
    assert.ok(!alice.friendRequestsReceived.includes(BOB));
    assert.ok(!bob.friendRequestsSent.includes(ALICE));
  });

  it('refuses when there is no pending request', async () => {
    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', friends: [] });
    await db.doc(`users/${BOB}`).set({ displayName: 'Bob', friends: [] });
    await sleep(1500);
    await assert.rejects(() => callFn('acceptFriendRequest', ALICE, { requesterUid: BOB }));
  });

  it('refuses an unauthenticated caller', async () => {
    await assert.rejects(() => callFn('acceptFriendRequest', null, { requesterUid: BOB }));
  });

  it('refuses befriending yourself', async () => {
    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', friends: [] });
    await assert.rejects(() => callFn('acceptFriendRequest', ALICE, { requesterUid: ALICE }));
  });

  it('refuses a missing requesterUid', async () => {
    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', friends: [] });
    await assert.rejects(() => callFn('acceptFriendRequest', ALICE, {}));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('removeFriend (callable)', () => {
  it('removes both edges and strips both legacy arrays', async () => {
    await db.doc(`users/${ALICE}`).set({
      displayName: 'Alice',
      friends: [{ uid: BOB, displayName: 'Bob', email: '' }],
    });
    await db.doc(`users/${BOB}`).set({
      displayName: 'Bob',
      friends: [{ uid: ALICE, displayName: 'Alice', email: '' }],
    });
    await waitFor(
      async () => (await db.doc(`users/${ALICE}/friends/${BOB}`).get()).exists,
      'edges mirrored',
    );

    await callFn('removeFriend', ALICE, { friendUid: BOB });

    assert.ok(!(await db.doc(`users/${ALICE}/friends/${BOB}`).get()).exists);
    assert.ok(!(await db.doc(`users/${BOB}/friends/${ALICE}`).get()).exists);
    assert.equal((await db.doc(`users/${ALICE}`).get()).data().friends.length, 0);
    assert.equal((await db.doc(`users/${BOB}`).get()).data().friends.length, 0);
  });

  it('refuses an unauthenticated caller', async () => {
    await assert.rejects(() => callFn('removeFriend', null, { friendUid: BOB }));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('friendCount stays current after the flip', () => {
  it('tracks edges being added and removed', async () => {
    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', friends: [] });
    await waitFor(
      async () => (await db.doc(`users/${ALICE}/public/profile`).get()).exists,
      'profile created',
    );

    await db.doc(`users/${ALICE}/friends/${BOB}`).set({ since: new Date() });
    const up = await waitFor(async () => {
      const d = (await db.doc(`users/${ALICE}/public/profile`).get()).data();
      return d?.friendCount === 1 ? d : null;
    }, 'friendCount rises to 1');
    assert.equal(up.friendCount, 1);

    await db.doc(`users/${ALICE}/friends/${BOB}`).delete();
    const down = await waitFor(async () => {
      const d = (await db.doc(`users/${ALICE}/public/profile`).get()).data();
      return d?.friendCount === 0 ? d : null;
    }, 'friendCount falls to 0');
    assert.equal(down.friendCount, 0);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('releaseStaleUsernames', () => {
  it('releases the old name on rename and keeps the new one', async () => {
    const oldName = `old${n}`;
    const newName = `new${n}`;

    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', username: oldName, friends: [] });
    await waitFor(
      async () => (await db.doc(`usernames/${oldName}`).get()).exists,
      'old name claimed',
    );

    await db.doc(`users/${ALICE}`).set(
      { displayName: 'Alice', username: newName, friends: [] },
      { merge: true },
    );

    await waitFor(
      async () => !(await db.doc(`usernames/${oldName}`).get()).exists,
      'old name released',
    );
    assert.ok(
      (await db.doc(`usernames/${newName}`).get()).exists,
      'new name kept — a rename must never leave the user with no claim',
    );
  });

  it('never touches a name belonging to someone else', async () => {
    const theirs = `theirs${n}`;
    await db.doc(`usernames/${theirs}`).set({ uid: BOB });
    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', username: `mine${n}`, friends: [] });
    await waitFor(
      async () => (await db.doc(`usernames/mine${n}`).get()).exists,
      'own name claimed',
    );
    await sleep(2500);
    assert.ok((await db.doc(`usernames/${theirs}`).get()).exists, 'other claim survives');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('onHiveDeleteCleanHidden', () => {
  it('removes the deleted hive from every hidden list', async () => {
    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'X', privacy: 'private' });
    await waitFor(async () => (await db.doc(`hives/${H1}`).get()).exists, 'hive mirrored');

    await db.doc(`users/${BOB}/settings/prefs`).set({
      mutedFriends: [],
      hiddenHiveIds: [H1, 'keep-me'],
    });
    await sleep(500);

    await db.doc(`hives/${H1}`).delete();

    const cleaned = await waitFor(async () => {
      const d = (await db.doc(`users/${BOB}/settings/prefs`).get()).data();
      return d && !d.hiddenHiveIds.includes(H1) ? d : null;
    }, 'hidden id removed');
    assert.deepEqual(cleaned.hiddenHiveIds, ['keep-me'], 'unrelated ids untouched');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('onUserDocDeleted', () => {
  it('cascades hives, edges, profile, settings and the username claim', async () => {
    await db.doc(`users/${ALICE}`).set({
      displayName: 'Alice',
      username: ALICE,
      friends: [{ uid: BOB, displayName: 'Bob', email: '' }],
    });
    await db.doc(`users/${ALICE}/hives/${H1}`).set({ title: 'Mine', privacy: 'private' });
    await db.doc(`users/${ALICE}/wishes/${W1}`).set({
      name: 'A',
      hiveId: H1,
      cost: 1,
      quantity: 1,
    });

    await waitFor(async () => (await db.doc(`hives/${H1}`).get()).exists, 'hive mirrored');
    await waitFor(async () => (await db.doc(`usernames/${ALICE}`).get()).exists, 'name claimed');
    await waitFor(
      async () => (await db.doc(`users/${ALICE}/public/profile`).get()).exists,
      'profile created',
    );

    await db.doc(`users/${ALICE}`).delete();

    await waitFor(async () => !(await db.doc(`hives/${H1}`).get()).exists, 'hives gone');
    await waitFor(
      async () => (await db.collection(`users/${ALICE}/friends`).get()).empty,
      'edges gone',
    );
    await waitFor(
      async () => !(await db.doc(`users/${ALICE}/public/profile`).get()).exists,
      'profile gone',
    );
    await waitFor(
      async () => !(await db.doc(`users/${ALICE}/settings/prefs`).get()).exists,
      'settings gone',
    );
    await waitFor(
      async () => !(await db.doc(`usernames/${ALICE}`).get()).exists,
      'username released',
    );
  });

  it('leaves another account untouched', async () => {
    await db.doc(`usernames/${BOB}`).set({ uid: BOB });
    await db.doc(`users/${BOB}`).set({ displayName: 'Bob', username: BOB, friends: [] });
    await db.doc(`users/${BOB}/hives/keep${n}`).set({ title: 'Keep', privacy: 'private' });
    await db.doc(`users/${ALICE}`).set({ displayName: 'Alice', username: ALICE, friends: [] });

    await waitFor(async () => (await db.doc(`usernames/${ALICE}`).get()).exists, 'alice claimed');
    await waitFor(async () => (await db.doc(`hives/keep${n}`).get()).exists, 'bob hive mirrored');

    await db.doc(`users/${ALICE}`).delete();
    await sleep(4000);

    assert.ok((await db.doc(`usernames/${BOB}`).get()).exists, "bob's name survives");
    assert.ok((await db.doc(`hives/keep${n}`).get()).exists, "bob's hive survives");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('redeemShareLink (callable)', () => {
  const makeHive = async (owner, shareId, extra = {}) => {
    await db.doc(`users/${owner}/hives/${H1}`).set({
      title: 'Shared list',
      privacy: 'private',
      shareId,
      linkShareEnabled: true,
      ...extra,
    });
    await waitFor(async () => (await db.doc(`hives/${H1}`).get()).exists, 'hive mirrored');
    // mirrorHive does not copy the share fields, so set them on the top-level doc.
    await db.doc(`hives/${H1}`).set(
      { shareId, linkShareEnabled: extra.linkShareEnabled ?? true },
      { merge: true },
    );
    await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.shareId === shareId ? d : null;
    }, 'share fields set');
  };

  it('grants access to a signed-in redeemer and widens audienceIds', async () => {
    const shareId = `tok${n}`;
    await makeHive(ALICE, shareId);

    const res = await callFn('redeemShareLink', BOB, { shareId });
    assert.equal(res.status, 'granted');
    assert.equal(res.hiveId, H1);

    const aud = await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a?.includes(BOB) ? a : null;
    }, 'bob in audience');
    assert.ok(aud.includes(BOB));
    assert.ok(aud.includes(ALICE));
  });

  it('reports already for someone who can see it', async () => {
    const shareId = `tok${n}`;
    await makeHive(ALICE, shareId);
    const first = await callFn('redeemShareLink', BOB, { shareId });
    assert.equal(first.status, 'granted');
    await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a?.includes(BOB) ? a : null;
    }, 'audience widened');

    const second = await callFn('redeemShareLink', BOB, { shareId });
    assert.equal(second.status, 'already');
  });

  it('reports already for the owner', async () => {
    const shareId = `tok${n}`;
    await makeHive(ALICE, shareId);
    const res = await callFn('redeemShareLink', ALICE, { shareId });
    assert.equal(res.status, 'already');
  });

  it('refuses when the owner has disabled the link', async () => {
    const shareId = `tok${n}`;
    await makeHive(ALICE, shareId);
    await db.doc(`hives/${H1}`).set({ linkShareEnabled: false }, { merge: true });
    await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.linkShareEnabled === false ? d : null;
    }, 'link disabled');

    const res = await callFn('redeemShareLink', BOB, { shareId });
    assert.equal(res.status, 'disabled');

    const aud = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds ?? [];
    assert.ok(!aud.includes(BOB), 'must not be granted access');
  });

  it('reports invalid for an unknown token', async () => {
    const res = await callFn('redeemShareLink', BOB, { shareId: `nope${n}` });
    assert.equal(res.status, 'invalid');
  });

  it('refuses an unauthenticated caller', async () => {
    await assert.rejects(() => callFn('redeemShareLink', null, { shareId: 'x' }));
  });

  it('refuses a missing shareId', async () => {
    await assert.rejects(() => callFn('redeemShareLink', BOB, {}));
  });

  it('grants only the shared hive, not the owner\'s other hives', async () => {
    const shareId = `tok${n}`;
    await makeHive(ALICE, shareId);
    const otherId = `other${n}`;
    await db.doc(`users/${ALICE}/hives/${otherId}`).set({
      title: 'Not shared',
      privacy: 'private',
    });
    await waitFor(async () => {
      const a = (await db.doc(`hives/${otherId}`).get()).data()?.audienceIds;
      return a?.length ? a : null;
    }, 'other hive resolved');

    await callFn('redeemShareLink', BOB, { shareId });
    await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a?.includes(BOB) ? a : null;
    }, 'shared hive widened');

    const otherAud = (await db.doc(`hives/${otherId}`).get()).data()?.audienceIds ?? [];
    assert.ok(!otherAud.includes(BOB), 'must not leak the other hive');
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// viewerIds must be additive in EVERY privacy mode. The friends branch used to
// ignore it, so redeeming a link on a friends-only hive reported success and
// then recomputed the new viewer straight back out again.
describe('viewerIds is additive in every privacy mode', () => {
  it('a redeemed link grants access to a FRIENDS-privacy hive', async () => {
    const shareId = `fr${n}`;
    // Alice has one existing friend, and Carol is a stranger.
    await db.doc(`users/${ALICE}/friends/${BOB}`).set({ since: new Date() });
    await db.doc(`users/${ALICE}/hives/${H1}`).set({
      title: 'Friends only',
      privacy: 'friends',
    });
    await waitFor(async () => (await db.doc(`hives/${H1}`).get()).exists, 'mirrored');
    await db.doc(`hives/${H1}`).set(
      { shareId, linkShareEnabled: true },
      { merge: true },
    );
    await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a?.includes(BOB) ? a : null;
    }, 'friend in audience');

    const carol = `cz${n}`;
    const res = await callFn('redeemShareLink', carol, { shareId });
    assert.equal(res.status, 'granted');

    const aud = await waitFor(async () => {
      const a = (await db.doc(`hives/${H1}`).get()).data()?.audienceIds;
      return a?.includes(carol) ? a : null;
    }, 'redeemer stays in the audience');

    assert.ok(aud.includes(carol), 'link redeemer must keep access');
    assert.ok(aud.includes(BOB), 'existing friends must keep access');
    assert.ok(aud.includes(ALICE), 'owner must keep access');
  });

  it('privacy mode is not changed by redeeming', async () => {
    const shareId = `pv${n}`;
    await db.doc(`users/${ALICE}/hives/${H1}`).set({
      title: 'Private list',
      privacy: 'private',
    });
    await waitFor(async () => (await db.doc(`hives/${H1}`).get()).exists, 'mirrored');
    await db.doc(`hives/${H1}`).set(
      { shareId, linkShareEnabled: true },
      { merge: true },
    );
    await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.shareId === shareId ? d : null;
    }, 'share fields set');

    await callFn('redeemShareLink', BOB, { shareId });

    const hive = await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.audienceIds?.includes(BOB) ? d : null;
    }, 'bob granted');

    assert.equal(hive.privacy, 'private', 'privacy must be left alone');
    assert.ok(hive.audienceIds.includes(BOB));
  });

  it('a disabled link still reports the owner so the app can offer a request', async () => {
    const shareId = `dz${n}`;
    await db.doc(`users/${ALICE}/hives/${H1}`).set({
      title: 'Closed',
      privacy: 'friends',
    });
    await waitFor(async () => (await db.doc(`hives/${H1}`).get()).exists, 'mirrored');
    await db.doc(`hives/${H1}`).set(
      { shareId, linkShareEnabled: false },
      { merge: true },
    );
    await waitFor(async () => {
      const d = (await db.doc(`hives/${H1}`).get()).data();
      return d?.shareId === shareId ? d : null;
    }, 'share fields set');

    const stranger = `sx${n}`;
    const res = await callFn('redeemShareLink', stranger, { shareId });
    assert.equal(res.status, 'disabled');
    assert.equal(res.ownerId, ALICE, 'owner needed for the friend-request offer');
  });
});
