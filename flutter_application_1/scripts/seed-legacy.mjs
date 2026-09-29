// Seeds old-schema data into the Firestore emulator so the backfill can be
// rehearsed against realistic input before it ever runs on production.
//
//   npm run rehearse

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('Refusing to seed: FIRESTORE_EMULATOR_HOST is not set.');
  process.exit(1);
}

initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-wishhive' });
const db = getFirestore();

const card = (uid, name) => ({
  uid,
  displayName: name,
  photoUrl: `${uid}.jpg`,
  email: `${uid}@example.com`,
});

const users = [
  { uid: 'u_alice', name: 'Alice', username: 'alice' },
  { uid: 'u_bob', name: 'Bob', username: 'bob' },
  { uid: 'u_carol', name: 'Carol', username: 'carol' },
  { uid: 'u_dave', name: 'Dave', username: 'dave' },
];

const now = Timestamp.now();

await db.doc('users/u_alice').set({
  email: 'u_alice@example.com',
  displayName: 'Alice',
  username: 'alice',
  photoUrl: 'u_alice.jpg',
  friends: [card('u_bob', 'Bob'), card('u_carol', 'Carol')],
  friendRequestsSent: ['u_dave'],
  friendRequestsReceived: [],
  mutedFriends: ['u_carol'],
  hiddenHiveIds: ['h_bob_1'],
});

await db.doc('users/u_bob').set({
  email: 'u_bob@example.com',
  displayName: 'Bob',
  username: 'bob',
  photoUrl: 'u_bob.jpg',
  friends: [card('u_alice', 'Alice')],
  friendRequestsSent: [],
  friendRequestsReceived: [],
  mutedFriends: [],
  hiddenHiveIds: [],
});

await db.doc('users/u_carol').set({
  email: 'u_carol@example.com',
  displayName: 'Carol',
  username: 'carol',
  friends: [card('u_alice', 'Alice')],
  friendRequestsSent: [],
  friendRequestsReceived: [],
  mutedFriends: [],
  hiddenHiveIds: [],
});

// Legacy string-only friend entries, and no username at all.
await db.doc('users/u_dave').set({
  email: 'u_dave@example.com',
  displayName: 'Dave',
  friends: ['u_alice'],
  friendRequestsReceived: ['u_alice'],
});

// Alice: one hive per privacy mode.
await db.doc('users/u_alice/hives/h_priv').set({
  id: 'h_priv', title: 'Private list', privacy: 'private',
  allowedViewerIds: [], allowedEditorIds: [],
  itemCount: 99, totalCost: 99999,          // deliberately drifted
  createdAt: now, ownerId: 'u_alice', ownerDisplayName: 'Alice',
});

await db.doc('users/u_alice/hives/h_friends').set({
  id: 'h_friends', title: 'Friends list', privacy: 'friends',
  allowedViewerIds: [], allowedEditorIds: [],
  itemCount: 0, totalCost: 0,
  createdAt: now, ownerId: 'u_alice', ownerDisplayName: 'Alice',
});

await db.doc('users/u_alice/hives/h_specific').set({
  id: 'h_specific', title: 'Specific list', privacy: 'specific',
  allowedViewerIds: ['u_bob'], allowedEditorIds: ['u_bob'],
  itemCount: 0, totalCost: 0,
  createdAt: now, ownerId: 'u_alice', ownerDisplayName: 'Alice',
});

await db.doc('users/u_bob/hives/h_bob_1').set({
  id: 'h_bob_1', title: "Bob's list", privacy: 'friends',
  allowedViewerIds: [], allowedEditorIds: [],
  itemCount: 0, totalCost: 0,
  createdAt: now, ownerId: 'u_bob', ownerDisplayName: 'Bob',
});

const wish = (name, hiveId, cost, quantity = 1, extra = {}) => ({
  name, subtitle: '', imageUrl: '', hiveId, date: null, quantity, note: '',
  link: '', cost, createdAt: now, fulfilledBy: '', fulfilledByName: '',
  ownerSeen: true, addedByUid: '', addedByName: '', isNote: false, ...extra,
});

await db.doc('users/u_alice/wishes/w1').set(wish('Headphones', 'h_priv', 500, 2));
await db.doc('users/u_alice/wishes/w2').set(wish('Book', 'h_priv', 300));
await db.doc('users/u_alice/wishes/w3').set(
  wish('Camera', 'h_specific', 25000, 1, {
    fulfilledBy: 'u_bob', fulfilledByName: 'Bob', ownerSeen: false,
    addedByUid: 'u_bob', addedByName: 'Bob',
  }),
);
// Orphan: points at a hive that no longer exists.
await db.doc('users/u_alice/wishes/w_orphan').set(wish('Ghost', 'h_deleted', 10));
// Malformed: no hiveId at all.
await db.doc('users/u_alice/wishes/w_nohive').set({ name: 'Broken', cost: 5 });

await db.doc('users/u_bob/wishes/wb1').set(wish('Shoes', 'h_bob_1', 2000));

console.log(`Seeded ${users.length} users, 4 hives, 6 wishes (incl. 2 deliberately broken).`);
process.exit(0);
