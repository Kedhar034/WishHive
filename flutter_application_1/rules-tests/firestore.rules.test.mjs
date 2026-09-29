// Firestore security rules regression suite for WishHive.
//
//   cd flutter_application_1/rules-tests
//   npm install        (once)
//   npm test
//
// Tests run against ../firestore.rules in the local Firestore emulator.
// Nothing touches the real project.

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  getDocs,
  query,
  collectionGroup,
  where,
} from 'firebase/firestore';

const ALICE = 'alice';
const BOB = 'bob';
const CAROL = 'carol';

let testEnv;

// Contexts
const asAlice = () => testEnv.authenticatedContext(ALICE).firestore();
const asBob = () => testEnv.authenticatedContext(BOB).firestore();
const asCarol = () => testEnv.authenticatedContext(CAROL).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

// Paths
const userDoc = (db, uid) => doc(db, 'users', uid);
const hiveDoc = (db, uid, hiveId) => doc(db, 'users', uid, 'hives', hiveId);
const wishDoc = (db, uid, wishId) => doc(db, 'users', uid, 'wishes', wishId);

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-wishhive',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// Seed a consistent world before every test:
//   alice owns hive "h1" (bob is an editor, carol is not) and wish "w1" in it.
beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await setDoc(userDoc(db, ALICE), {
      email: 'alice@example.com',
      displayName: 'Alice',
      username: 'alice',
      photoUrl: null,
      friends: [{ uid: BOB, displayName: 'Bob', email: 'bob@example.com' }],
      friendRequestsSent: [],
      friendRequestsReceived: [],
      mutedFriends: [],
      hiddenHiveIds: [],
    });

    await setDoc(userDoc(db, BOB), {
      email: 'bob@example.com',
      displayName: 'Bob',
      username: 'bob',
      friends: [],
      friendRequestsSent: [],
      friendRequestsReceived: [],
      mutedFriends: [],
      hiddenHiveIds: [],
    });

    await setDoc(userDoc(db, CAROL), {
      email: 'carol@example.com',
      displayName: 'Carol',
      username: 'carol',
      friends: [],
      friendRequestsSent: [],
      friendRequestsReceived: [],
      mutedFriends: [],
      hiddenHiveIds: [],
    });

    await setDoc(hiveDoc(db, ALICE, 'h1'), {
      id: 'h1',
      title: 'Birthday',
      privacy: 'specific',
      allowedViewerIds: [BOB],
      allowedEditorIds: [BOB],
      itemCount: 1,
      totalCost: 500,
      ownerId: ALICE,
      ownerDisplayName: 'Alice',
    });

    await setDoc(wishDoc(db, ALICE, 'w1'), {
      name: 'Headphones',
      hiveId: 'h1',
      cost: 500,
      quantity: 1,
      fulfilledBy: '',
      fulfilledByName: '',
      ownerSeen: true,
      addedByUid: '',
      addedByName: '',
      isNote: false,
    });

    // Contributed by Bob into Alice's hive.
    await setDoc(wishDoc(db, ALICE, 'w_bob'), {
      name: 'Gift from Bob',
      hiveId: 'h1',
      cost: 200,
      quantity: 1,
      fulfilledBy: '',
      fulfilledByName: '',
      ownerSeen: true,
      addedByUid: BOB,
      addedByName: 'Bob',
      isNote: false,
    });

    // ── new schema, as the mirror functions would produce it ──
    await setDoc(doc(db, 'users', ALICE, 'public', 'profile'), {
      displayName: 'Alice',
      username: 'alice',
      photoUrl: null,
      friendCount: 1,
    });
    await setDoc(doc(db, 'users', ALICE, 'friends', BOB), { since: new Date() });
    await setDoc(doc(db, 'users', BOB, 'friends', ALICE), { since: new Date() });
    await setDoc(doc(db, 'users', ALICE, 'settings', 'prefs'), {
      mutedFriends: [],
      hiddenHiveIds: [],
    });
    await setDoc(doc(db, 'usernames', 'alice'), { uid: ALICE });

    await setDoc(doc(db, 'hives', 'th1'), {
      ownerId: ALICE,
      title: 'Birthday',
      privacy: 'specific',
      viewerIds: [BOB],
      editorIds: [BOB],
      audienceIds: [ALICE, BOB],
      isPublic: false,
      itemCount: 1,
      totalCost: 500,
    });
    await setDoc(doc(db, 'hives', 'th1', 'wishes', 'tw1'), {
      name: 'Headphones',
      cost: 500,
      quantity: 1,
      fulfilledBy: '',
      ownerSeen: true,
      addedByUid: '',
      hiveOwnerId: ALICE,
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('anonymous access is closed', () => {
  it('cannot read a user document', async () => {
    await assertFails(getDoc(userDoc(asAnon(), ALICE)));
  });

  it('cannot read a hive', async () => {
    await assertFails(getDoc(hiveDoc(asAnon(), ALICE, 'h1')));
  });

  it('cannot read a wish', async () => {
    await assertFails(getDoc(wishDoc(asAnon(), ALICE, 'w1')));
  });

  it('cannot write a user document', async () => {
    await assertFails(setDoc(userDoc(asAnon(), ALICE), { displayName: 'Hacked' }));
  });

  it('cannot create a hive', async () => {
    await assertFails(setDoc(hiveDoc(asAnon(), ALICE, 'h9'), { title: 'x' }));
  });

  it('cannot delete a hive', async () => {
    await assertFails(deleteDoc(hiveDoc(asAnon(), ALICE, 'h1')));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('user documents', () => {
  it('owner can read their own document', async () => {
    await assertSucceeds(getDoc(userDoc(asAlice(), ALICE)));
  });

  it('owner can update their own profile fields', async () => {
    await assertSucceeds(
      updateDoc(userDoc(asAlice(), ALICE), { displayName: 'Alice B', photoUrl: 'x.jpg' }),
    );
  });

  it('owner can delete their own document', async () => {
    await assertSucceeds(deleteDoc(userDoc(asAlice(), ALICE)));
  });

  it('another user CANNOT change email', async () => {
    await assertFails(updateDoc(userDoc(asBob(), ALICE), { email: 'attacker@evil.com' }));
  });

  it('another user CANNOT change username', async () => {
    await assertFails(updateDoc(userDoc(asBob(), ALICE), { username: 'stolen' }));
  });

  it('another user CANNOT change photoUrl', async () => {
    await assertFails(updateDoc(userDoc(asBob(), ALICE), { photoUrl: 'evil.jpg' }));
  });

  it('another user CANNOT delete the document', async () => {
    await assertFails(deleteDoc(userDoc(asBob(), ALICE)));
  });

  it('another user CANNOT mix a social field with a profile field', async () => {
    await assertFails(
      updateDoc(userDoc(asBob(), ALICE), {
        friendRequestsReceived: [BOB],
        email: 'attacker@evil.com',
      }),
    );
  });

  // Required by sendFriendRequest / acceptFriendRequest / rejectFriendRequest.
  it('another user CAN append to friendRequestsReceived (sendFriendRequest)', async () => {
    await assertSucceeds(
      updateDoc(userDoc(asCarol(), ALICE), { friendRequestsReceived: [CAROL] }),
    );
  });

  it('another user CAN update friendRequestsSent (rejectFriendRequest)', async () => {
    await assertSucceeds(updateDoc(userDoc(asBob(), ALICE), { friendRequestsSent: [] }));
  });

  it('another user CAN update friends (acceptFriendRequest / profile sync)', async () => {
    await assertSucceeds(
      updateDoc(userDoc(asBob(), ALICE), {
        friends: [{ uid: BOB, displayName: 'Bob', email: 'bob@example.com' }],
      }),
    );
  });

  it('a user cannot create a document under someone else\'s uid', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'users', 'newbie'));
    });
    await assertFails(setDoc(userDoc(asBob(), 'newbie'), { email: 'x@y.com' }));
  });

  // CLOSED: search and profile lookups moved to users/{uid}/public/profile.
  it('an unrelated user CANNOT read another user document', async () => {
    await assertFails(getDoc(userDoc(asCarol(), ALICE)));
  });

  it('a friend CAN still read it (needed by accept / remove friend)', async () => {
    await assertSucceeds(getDoc(userDoc(asBob(), ALICE)));
  });

  it('nobody can enumerate the users collection', async () => {
    await assertFails(getDocs(collection(asBob(), 'users')));
  });

  it('a pending requester CAN read the recipient document', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', ALICE, 'friendRequests', CAROL), {
        sentAt: new Date(),
      });
    });
    await assertSucceeds(getDoc(userDoc(asCarol(), ALICE)));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('hives', () => {
  it('owner can create a hive in their own collection', async () => {
    await assertSucceeds(
      setDoc(hiveDoc(asAlice(), ALICE, 'h2'), { title: 'New', privacy: 'private' }),
    );
  });

  it('owner can update their own hive freely', async () => {
    await assertSucceeds(updateDoc(hiveDoc(asAlice(), ALICE, 'h1'), { title: 'Renamed' }));
  });

  it('owner can delete their own hive', async () => {
    await assertSucceeds(deleteDoc(hiveDoc(asAlice(), ALICE, 'h1')));
  });

  it('another user CANNOT create a hive in the owner\'s collection', async () => {
    await assertFails(
      setDoc(hiveDoc(asBob(), ALICE, 'h3'), { title: 'Intruder', privacy: 'private' }),
    );
  });

  it('another user CANNOT delete the owner\'s hive', async () => {
    await assertFails(deleteDoc(hiveDoc(asBob(), ALICE, 'h1')));
  });

  it('an editor CAN bump itemCount and totalCost (addWishToFriendsHive)', async () => {
    await assertSucceeds(
      updateDoc(hiveDoc(asBob(), ALICE, 'h1'), { itemCount: 2, totalCost: 900 }),
    );
  });

  it('an editor CANNOT rename the hive', async () => {
    await assertFails(updateDoc(hiveDoc(asBob(), ALICE, 'h1'), { title: 'Hijacked' }));
  });

  it('an editor CANNOT grant themselves more access', async () => {
    await assertFails(
      updateDoc(hiveDoc(asBob(), ALICE, 'h1'), { allowedEditorIds: [BOB, CAROL] }),
    );
  });

  it('a non-editor CANNOT bump the counters', async () => {
    await assertFails(
      updateDoc(hiveDoc(asCarol(), ALICE, 'h1'), { itemCount: 99, totalCost: 0 }),
    );
  });

  // Legacy nested hives are still readable by any signed-in user; the feed no
  // longer reads them, but friends' wish lists do until writes move too.
  it('LEGACY PATH: signed-in users can still read nested hives', async () => {
    await assertSucceeds(getDoc(hiveDoc(asCarol(), ALICE, 'h1')));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('wishes', () => {
  it('owner can create a wish in their own collection', async () => {
    await assertSucceeds(
      setDoc(wishDoc(asAlice(), ALICE, 'w2'), { name: 'Book', hiveId: 'h1', cost: 100 }),
    );
  });

  it('owner can update any field on their own wish', async () => {
    await assertSucceeds(
      updateDoc(wishDoc(asAlice(), ALICE, 'w1'), { name: 'Better headphones', cost: 800 }),
    );
  });

  it('owner can delete their own wish', async () => {
    await assertSucceeds(deleteDoc(wishDoc(asAlice(), ALICE, 'w1')));
  });

  // The editor role is now enforced server-side. Previously this was a Dart
  // getter that only decided whether to draw a button.
  it('an EDITOR of the hive CAN add a wish to the owner\'s collection', async () => {
    await assertSucceeds(
      setDoc(wishDoc(asBob(), ALICE, 'w3'), {
        name: 'Gift from Bob',
        hiveId: 'h1',
        cost: 200,
        addedByUid: BOB,
      }),
    );
  });

  it('a NON-EDITOR CANNOT add a wish to the owner\'s collection', async () => {
    await assertFails(
      setDoc(wishDoc(asCarol(), ALICE, 'w4'), {
        name: 'Spam',
        hiveId: 'h1',
        cost: 0,
        addedByUid: CAROL,
      }),
    );
  });

  it('a non-editor cannot add a wish pointing at a hive that does not exist', async () => {
    await assertFails(
      setDoc(wishDoc(asCarol(), ALICE, 'w5'), { name: 'Ghost', hiveId: 'nope', cost: 0 }),
    );
  });

  it('another user CAN claim a wish (fulfilledBy / fulfilledByName / ownerSeen)', async () => {
    await assertSucceeds(
      updateDoc(wishDoc(asCarol(), ALICE, 'w1'), {
        fulfilledBy: CAROL,
        fulfilledByName: 'Carol',
        ownerSeen: false,
      }),
    );
  });

  it('another user CANNOT change a wish name', async () => {
    await assertFails(updateDoc(wishDoc(asCarol(), ALICE, 'w1'), { name: 'Vandalised' }));
  });

  it('another user CANNOT change a wish price', async () => {
    await assertFails(updateDoc(wishDoc(asCarol(), ALICE, 'w1'), { cost: 1 }));
  });

  it('another user CANNOT smuggle a name change alongside a claim', async () => {
    await assertFails(
      updateDoc(wishDoc(asCarol(), ALICE, 'w1'), { fulfilledBy: CAROL, name: 'Vandalised' }),
    );
  });

  it('another user CANNOT delete a wish they did not contribute', async () => {
    await assertFails(deleteDoc(wishDoc(asBob(), ALICE, 'w1')));
  });

  it('a contributor CAN delete the wish they added', async () => {
    await assertSucceeds(deleteDoc(wishDoc(asBob(), ALICE, 'w_bob')));
  });

  it('a contributor CAN edit the wish they added', async () => {
    await assertSucceeds(
      updateDoc(wishDoc(asBob(), ALICE, 'w_bob'), { name: 'Better gift', cost: 350 }),
    );
  });

  it('the owner can still delete a contributed wish', async () => {
    await assertSucceeds(deleteDoc(wishDoc(asAlice(), ALICE, 'w_bob')));
  });

  it('an unrelated user cannot delete a contributed wish', async () => {
    await assertFails(deleteDoc(wishDoc(asCarol(), ALICE, 'w_bob')));
  });

  it('an unrelated user cannot edit a contributed wish', async () => {
    await assertFails(updateDoc(wishDoc(asCarol(), ALICE, 'w_bob'), { cost: 1 }));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('app query paths still work', () => {
  it('owner can list their own hives', async () => {
    await assertSucceeds(getDocs(collection(asAlice(), 'users', ALICE, 'hives')));
  });

  it('a friend can run the feed query against another user\'s hives', async () => {
    const q = query(
      collection(asBob(), 'users', ALICE, 'hives'),
      where('privacy', '==', 'specific'),
      where('allowedViewerIds', 'array-contains', BOB),
    );
    await assertSucceeds(getDocs(q));
  });

  it('a user can run the wishes-by-hive query', async () => {
    const q = query(
      collection(asBob(), 'users', ALICE, 'wishes'),
      where('hiveId', '==', 'h1'),
    );
    await assertSucceeds(getDocs(q));
  });

  // searchUsers moved off the users collection onto public profiles, which is
  // what stops a search returning everyone's email address.
  it('searchUsers can no longer query the users collection', async () => {
    const q = query(collection(asBob(), 'users'), where('username', '==', 'alice'));
    await assertFails(getDocs(q));
  });

  it('searchUsers can query public profiles by username prefix', async () => {
    const q = query(
      collectionGroup(asBob(), 'public'),
      where('username', '>=', 'al'),
      where('username', '<', 'al'),
    );
    await assertSucceeds(getDocs(q));
  });

  it('searchUsers can resolve an exact username to a uid', async () => {
    await assertSucceeds(getDoc(doc(asBob(), 'usernames', 'alice')));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
describe('NEW: public profiles', () => {
  it('any signed-in user can read a public profile', async () => {
    await assertSucceeds(getDoc(doc(asCarol(), 'users', ALICE, 'public', 'profile')));
  });

  it('anonymous cannot read a public profile', async () => {
    await assertFails(getDoc(doc(asAnon(), 'users', ALICE, 'public', 'profile')));
  });

  it('owner can write their own public profile', async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), 'users', ALICE, 'public', 'profile'), { displayName: 'Alice B' }),
    );
  });

  it('another user cannot write someone else\'s public profile', async () => {
    await assertFails(
      setDoc(doc(asBob(), 'users', ALICE, 'public', 'profile'), { displayName: 'Hacked' }),
    );
  });
});

describe('NEW: friend edges', () => {
  it('owner can read their own friend edges', async () => {
    await assertSucceeds(getDocs(collection(asAlice(), 'users', ALICE, 'friends')));
  });

  it('another user cannot read someone else\'s friend list', async () => {
    await assertFails(getDocs(collection(asCarol(), 'users', ALICE, 'friends')));
  });

  it('nobody can write a friend edge directly, not even the owner', async () => {
    await assertFails(setDoc(doc(asAlice(), 'users', ALICE, 'friends', CAROL), { since: new Date() }));
  });

  it('an attacker cannot forge a friendship into someone else', async () => {
    await assertFails(setDoc(doc(asCarol(), 'users', ALICE, 'friends', CAROL), { since: new Date() }));
  });
});

describe('NEW: friend requests (the DoS fix)', () => {
  it('a sender can create a request named after themselves', async () => {
    await assertSucceeds(
      setDoc(doc(asCarol(), 'users', ALICE, 'friendRequests', CAROL), {
        sentAt: new Date(),
        fromName: 'Carol',
      }),
    );
  });

  it('a sender CANNOT create a request under another uid', async () => {
    await assertFails(
      setDoc(doc(asCarol(), 'users', ALICE, 'friendRequests', 'spam-1'), {
        sentAt: new Date(),
        fromName: 'x',
      }),
    );
  });

  it('a sender CANNOT stuff extra fields into a request', async () => {
    await assertFails(
      setDoc(doc(asCarol(), 'users', ALICE, 'friendRequests', CAROL), {
        sentAt: new Date(),
        fromName: 'Carol',
        payload: 'x'.repeat(5000),
      }),
    );
  });

  it('the recipient can delete a request', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', ALICE, 'friendRequests', CAROL), { sentAt: new Date() });
    });
    await assertSucceeds(deleteDoc(doc(asAlice(), 'users', ALICE, 'friendRequests', CAROL)));
  });

  it('the sender can cancel their own request', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', ALICE, 'friendRequests', CAROL), { sentAt: new Date() });
    });
    await assertSucceeds(deleteDoc(doc(asCarol(), 'users', ALICE, 'friendRequests', CAROL)));
  });

  it('an unrelated user cannot delete someone else\'s request', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', ALICE, 'friendRequests', CAROL), { sentAt: new Date() });
    });
    await assertFails(deleteDoc(doc(asBob(), 'users', ALICE, 'friendRequests', CAROL)));
  });

  it('a request cannot be read by anyone but the recipient', async () => {
    await assertFails(getDoc(doc(asBob(), 'users', ALICE, 'friendRequests', CAROL)));
  });
});

describe('unfriend works under the deployed rules', () => {
  it('a user can remove their own card from the other person\'s friends array', async () => {
    await assertSucceeds(updateDoc(userDoc(asBob(), ALICE), { friends: [] }));
  });

  it('a user can clear their own side of the friendship', async () => {
    await assertSucceeds(updateDoc(userDoc(asAlice(), ALICE), {
      friends: [],
      mutedFriends: [],
      friendRequestsSent: [],
      friendRequestsReceived: [],
    }));
  });

  it('a user can drop pending requests on the other person', async () => {
    await assertSucceeds(updateDoc(userDoc(asBob(), ALICE), {
      friendRequestsSent: [],
      friendRequestsReceived: [],
    }));
  });

  it('the owner can strip a friend from their hive access lists', async () => {
    await assertSucceeds(updateDoc(hiveDoc(asAlice(), ALICE, 'h1'), {
      viewerIds: [],
      editorIds: [],
      allowedViewerIds: [],
      allowedEditorIds: [],
    }));
  });

  it('unfriending CANNOT be used to touch the other person\'s hives', async () => {
    await assertFails(updateDoc(hiveDoc(asBob(), ALICE, 'h1'), {
      allowedViewerIds: [],
    }));
  });

  // A no-op write (setting a field to the value it already holds) produces an
  // empty affectedKeys() and is correctly allowed, so assert a real change.
  it('unfriending CANNOT be used to alter the other person\'s mutes', async () => {
    await assertFails(
      updateDoc(userDoc(asBob(), ALICE), { mutedFriends: ['injected'] }),
    );
  });

  it('unfriending CANNOT be used to alter the other person\'s hidden hives', async () => {
    await assertFails(
      updateDoc(userDoc(asBob(), ALICE), { hiddenHiveIds: ['injected'] }),
    );
  });
});

describe('NEW: outbound sent-requests mirror', () => {
  it('owner can read and create their own sent-request markers', async () => {
    await assertSucceeds(
      setDoc(doc(asBob(), 'users', BOB, 'sentRequests', ALICE), { sentAt: new Date() }),
    );
    await assertSucceeds(getDocs(collection(asBob(), 'users', BOB, 'sentRequests')));
  });

  it('owner can delete a sent-request marker when cancelling', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', BOB, 'sentRequests', ALICE), { sentAt: new Date() });
    });
    await assertSucceeds(deleteDoc(doc(asBob(), 'users', BOB, 'sentRequests', ALICE)));
  });

  it('nobody else can read or write someone\'s sent requests', async () => {
    await assertFails(getDocs(collection(asCarol(), 'users', BOB, 'sentRequests')));
    await assertFails(
      setDoc(doc(asCarol(), 'users', BOB, 'sentRequests', CAROL), { sentAt: new Date() }),
    );
  });
});

describe('NEW: settings are private', () => {
  it('owner can read and write their settings', async () => {
    await assertSucceeds(getDoc(doc(asAlice(), 'users', ALICE, 'settings', 'prefs')));
    await assertSucceeds(
      setDoc(doc(asAlice(), 'users', ALICE, 'settings', 'prefs'), { mutedFriends: [BOB] }),
    );
  });

  it('nobody else can read settings', async () => {
    await assertFails(getDoc(doc(asBob(), 'users', ALICE, 'settings', 'prefs')));
  });
});

describe('NEW: username uniqueness', () => {
  it('a free name can be claimed', async () => {
    await assertSucceeds(setDoc(doc(asBob(), 'usernames', 'bobby'), { uid: BOB }));
  });

  it('a name cannot be claimed on behalf of someone else', async () => {
    await assertFails(setDoc(doc(asBob(), 'usernames', 'impostor'), { uid: ALICE }));
  });

  it('an already-claimed name cannot be taken over', async () => {
    await assertFails(setDoc(doc(asBob(), 'usernames', 'alice'), { uid: BOB }));
  });

  it('a user can release their own name', async () => {
    await assertSucceeds(deleteDoc(doc(asAlice(), 'usernames', 'alice')));
  });

  it('a user cannot release someone else\'s name', async () => {
    await assertFails(deleteDoc(doc(asBob(), 'usernames', 'alice')));
  });
});

describe('NEW: top-level hives use audienceIds', () => {
  it('a user in audienceIds can read the hive', async () => {
    await assertSucceeds(getDoc(doc(asBob(), 'hives', 'th1')));
  });

  it('a user NOT in audienceIds CANNOT read the hive', async () => {
    await assertFails(getDoc(doc(asCarol(), 'hives', 'th1')));
  });

  it('anonymous cannot read the hive', async () => {
    await assertFails(getDoc(doc(asAnon(), 'hives', 'th1')));
  });

  it('REVOCATION: removing a uid from audienceIds removes read access', async () => {
    await assertSucceeds(getDoc(doc(asBob(), 'hives', 'th1')));
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'hives', 'th1'), { audienceIds: [ALICE] });
    });
    await assertFails(getDoc(doc(asBob(), 'hives', 'th1')));
  });

  it('owner can create a hive without audienceIds', async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), 'hives', 'th2'), { ownerId: ALICE, title: 'New', privacy: 'private' }),
    );
  });

  it('a client CANNOT set audienceIds on create', async () => {
    await assertFails(
      setDoc(doc(asBob(), 'hives', 'th3'), {
        ownerId: BOB,
        title: 'Sneaky',
        privacy: 'private',
        audienceIds: [BOB, ALICE, CAROL],
      }),
    );
  });

  it('a client CANNOT change audienceIds on update', async () => {
    await assertFails(updateDoc(doc(asAlice(), 'hives', 'th1'), { audienceIds: [ALICE, CAROL] }));
  });

  it('a client CANNOT change isPublic', async () => {
    await assertFails(updateDoc(doc(asAlice(), 'hives', 'th1'), { isPublic: true }));
  });

  it('owner CAN change privacy and viewerIds', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'hives', 'th1'), { privacy: 'friends', viewerIds: [] }),
    );
  });

  it('a viewer cannot rename the hive', async () => {
    await assertFails(updateDoc(doc(asBob(), 'hives', 'th1'), { title: 'Hijacked' }));
  });

  it('a non-owner cannot delete the hive', async () => {
    await assertFails(deleteDoc(doc(asBob(), 'hives', 'th1')));
  });

  it('owner can run the new single-query feed', async () => {
    const q = query(collection(asBob(), 'hives'), where('audienceIds', 'array-contains', BOB));
    await assertSucceeds(getDocs(q));
  });
});

describe('NEW: share links', () => {
  it('the owner can set shareId and linkShareEnabled', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'hives', 'th1'), {
        shareId: 'k3f9x2mq',
        linkShareEnabled: true,
      }),
    );
  });

  it('the owner can disable the link', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'hives', 'th1'), { linkShareEnabled: false }),
    );
  });

  it('a viewer CANNOT create a share link on someone else\'s hive', async () => {
    await assertFails(
      updateDoc(doc(asBob(), 'hives', 'th1'), {
        shareId: 'hijacked',
        linkShareEnabled: true,
      }),
    );
  });

  it('an unrelated user CANNOT enable sharing', async () => {
    await assertFails(
      updateDoc(doc(asCarol(), 'hives', 'th1'), { linkShareEnabled: true }),
    );
  });

  // Redeeming widens audienceIds, and only the Cloud Function may do that.
  it('a redeemer CANNOT add themselves to audienceIds directly', async () => {
    await assertFails(
      updateDoc(doc(asCarol(), 'hives', 'th1'), { audienceIds: [ALICE, CAROL] }),
    );
  });

  it('a redeemer CANNOT add themselves to viewerIds directly', async () => {
    await assertFails(
      updateDoc(doc(asCarol(), 'hives', 'th1'), { viewerIds: [BOB, CAROL] }),
    );
  });
});

describe('NEW: wishes inherit hive access', () => {
  it('a user in audienceIds can read a wish', async () => {
    await assertSucceeds(getDoc(doc(asBob(), 'hives', 'th1', 'wishes', 'tw1')));
  });

  it('a user NOT in audienceIds CANNOT read a wish', async () => {
    await assertFails(getDoc(doc(asCarol(), 'hives', 'th1', 'wishes', 'tw1')));
  });

  it('an editor can add a wish', async () => {
    await assertSucceeds(
      setDoc(doc(asBob(), 'hives', 'th1', 'wishes', 'tw2'), { name: 'Gift', cost: 10, addedByUid: BOB }),
    );
  });

  it('a non-editor CANNOT add a wish', async () => {
    await assertFails(
      setDoc(doc(asCarol(), 'hives', 'th1', 'wishes', 'tw3'), { name: 'Spam', cost: 0 }),
    );
  });

  it('a viewer can claim a wish', async () => {
    await assertSucceeds(
      updateDoc(doc(asBob(), 'hives', 'th1', 'wishes', 'tw1'), {
        fulfilledBy: BOB,
        fulfilledByName: 'Bob',
        ownerSeen: false,
      }),
    );
  });

  it('a viewer CANNOT change a wish price', async () => {
    await assertFails(updateDoc(doc(asBob(), 'hives', 'th1', 'wishes', 'tw1'), { cost: 1 }));
  });

  it('the owner can change anything', async () => {
    await assertSucceeds(
      updateDoc(doc(asAlice(), 'hives', 'th1', 'wishes', 'tw1'), { name: 'Better', cost: 900 }),
    );
  });
});

describe('NEW: blocking', () => {
  it('owner can block, list and unblock', async () => {
    await assertSucceeds(
      setDoc(doc(asAlice(), 'users', ALICE, 'blocked', CAROL), { blockedAt: new Date() }),
    );
    await assertSucceeds(getDocs(collection(asAlice(), 'users', ALICE, 'blocked')));
    await assertSucceeds(deleteDoc(doc(asAlice(), 'users', ALICE, 'blocked', CAROL)));
  });

  it('the blocked user cannot see they were blocked', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', ALICE, 'blocked', CAROL), { blockedAt: new Date() });
    });
    await assertFails(getDoc(doc(asCarol(), 'users', ALICE, 'blocked', CAROL)));
    await assertFails(getDocs(collection(asCarol(), 'users', ALICE, 'blocked')));
  });

  it('nobody can write into someone else\'s block list', async () => {
    await assertFails(
      setDoc(doc(asCarol(), 'users', ALICE, 'blocked', BOB), { blockedAt: new Date() }),
    );
  });

  it('a user cannot block themselves', async () => {
    await assertFails(
      setDoc(doc(asAlice(), 'users', ALICE, 'blocked', ALICE), { blockedAt: new Date() }),
    );
  });
});

describe('NEW: reporting', () => {
  const report = (reporter) => ({
    reporterUid: reporter,
    targetType: 'hive',
    targetId: 'th1',
    targetOwnerUid: ALICE,
    reason: 'spam',
    details: 'unwanted content',
    createdAt: new Date(),
  });

  it('a signed-in user can file a report', async () => {
    await assertSucceeds(setDoc(doc(asBob(), 'reports', 'r1'), report(BOB)));
  });

  it('a report cannot be filed on behalf of someone else', async () => {
    await assertFails(setDoc(doc(asBob(), 'reports', 'r2'), report(CAROL)));
  });

  it('reports are not readable by users', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reports', 'r3'), report(BOB));
    });
    await assertFails(getDoc(doc(asBob(), 'reports', 'r3')));
    await assertFails(getDoc(doc(asAlice(), 'reports', 'r3')));
  });

  it('a report cannot be edited or withdrawn once filed', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'reports', 'r4'), report(BOB));
    });
    await assertFails(updateDoc(doc(asBob(), 'reports', 'r4'), { reason: 'changed' }));
    await assertFails(deleteDoc(doc(asBob(), 'reports', 'r4')));
  });

  it('oversized details are rejected', async () => {
    await assertFails(
      setDoc(doc(asBob(), 'reports', 'r5'), { ...report(BOB), details: 'x'.repeat(1001) }),
    );
  });

  it('unknown fields are rejected', async () => {
    await assertFails(
      setDoc(doc(asBob(), 'reports', 'r6'), { ...report(BOB), isAdmin: true }),
    );
  });

  it('anonymous cannot file a report', async () => {
    await assertFails(setDoc(doc(asAnon(), 'reports', 'r7'), report(BOB)));
  });
});

describe('NEW: collection-group queries are scoped', () => {
  it('owner can query their own wishes across all hives', async () => {
    const q = query(
      collectionGroup(asAlice(), 'wishes'),
      where('hiveOwnerId', '==', ALICE),
      where('ownerSeen', '==', false),
    );
    await assertSucceeds(getDocs(q));
  });

  it('a user CANNOT query another owner\'s wishes', async () => {
    const q = query(
      collectionGroup(asBob(), 'wishes'),
      where('hiveOwnerId', '==', ALICE),
      where('ownerSeen', '==', false),
    );
    await assertFails(getDocs(q));
  });

  it('an unscoped collection-group wish query is rejected', async () => {
    await assertFails(getDocs(collectionGroup(asBob(), 'wishes')));
  });

  it('public profiles can be searched by username prefix', async () => {
    const q = query(
      collectionGroup(asBob(), 'public'),
      where('username', '>=', 'al'),
      where('username', '<', 'al'),
    );
    await assertSucceeds(getDocs(q));
  });

  it('anonymous cannot run the public profile search', async () => {
    await assertFails(getDocs(collectionGroup(asAnon(), 'public')));
  });
});

describe('unknown collections are denied', () => {
  it('cannot write to an arbitrary top-level collection', async () => {
    await assertFails(setDoc(doc(asBob(), 'malware', 'x'), { a: 1 }));
  });

  it('cannot read an arbitrary top-level collection', async () => {
    await assertFails(getDoc(doc(asBob(), 'malware', 'x')));
  });

  it('cannot write to an unknown subcollection under a user', async () => {
    await assertFails(setDoc(doc(asBob(), 'users', ALICE, 'secrets', 'x'), { a: 1 }));
  });
});
