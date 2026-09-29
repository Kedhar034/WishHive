// Seeds demo hives and wishes onto ONE account so every UI state can be tested.
//
//   npm run seed:test            Dry run — shows what it would write.
//   npm run seed:test:commit     Writes it.
//   npm run seed:test:clean      Removes everything this script created.
//
// Safety: refuses to run unless it finds exactly one user matching BOTH the
// email and the username below, and only ever writes under that user's own
// hives/ and wishes/ subcollections. Document ids are deterministic, so
// re-running replaces rather than duplicates.

import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const TARGET_EMAIL = 'test123@gmail.com';
const TARGET_USERNAME = 'testing123';

const COMMIT = process.argv.includes('--commit');
const CLEAN = process.argv.includes('--clean');
const PROJECT_ID =
  process.env.GCLOUD_PROJECT ||
  process.env.FIREBASE_PROJECT_ID ||
  'flutterapplication-77c19';

const USING_EMULATOR = !!process.env.FIRESTORE_EMULATOR_HOST;
initializeApp(
  USING_EMULATOR
    ? { projectId: PROJECT_ID }
    : { credential: applicationDefault(), projectId: PROJECT_ID },
);
const db = getFirestore();

const daysAgo = (n) =>
  Timestamp.fromDate(new Date(Date.now() - n * 24 * 60 * 60 * 1000));

// Local asset paths — Firebase Storage is not provisioned yet, so network
// image URLs would render as broken.
const IMG = {
  gift: 'assets/categories/Gift.jpeg',
  tech: 'assets/categories/Tec.jpeg',
  book: 'assets/categories/Book.jpeg',
  travel: 'assets/categories/Trave.jpeg',
  gaming: 'assets/categories/Gamin.jpeg',
  fitness: 'assets/categories/Fitnes.jpeg',
  shopping: 'assets/categories/shoppin.jpeg',
  food: 'assets/categories/Foo.jpeg',
  party: 'assets/categories/Part.jpeg',
};

const HIVES = [
  {
    id: 'seed_birthday',
    title: 'Birthday Wishlist',
    note: 'Turning 26 next month',
    imageUrl: IMG.party,
    privacy: 'friends',
    createdAt: daysAgo(2),
    wishes: [
      { id: 'w_head', name: 'Sony WH-1000XM5', subtitle: 'Noise cancelling', cost: 26990, quantity: 1, imageUrl: IMG.tech, link: 'https://www.flipkart.com', note: 'Midnight blue if possible' },
      { id: 'w_watch', name: 'Casio vintage watch', cost: 3495, quantity: 1, imageUrl: IMG.shopping },
      { id: 'w_cake', name: 'Chocolate truffle cake', cost: 1200, quantity: 1, imageUrl: IMG.food, note: 'Eggless please' },
      { id: 'w_note1', name: 'Anything handmade works too', isNote: true, cost: 0, quantity: 1 },
    ],
  },
  {
    id: 'seed_home',
    title: 'Home Essentials',
    note: 'Moving into the new flat',
    imageUrl: IMG.shopping,
    privacy: 'friends',
    createdAt: daysAgo(6),
    wishes: [
      { id: 'w_mixer', name: 'Preethi mixer grinder', cost: 4899, quantity: 1, imageUrl: IMG.shopping },
      { id: 'w_iron', name: 'Philips steam iron', cost: 2199, quantity: 1, imageUrl: IMG.shopping, fulfilledBy: 'SEED_FRIEND', fulfilledByName: 'A Friend', ownerSeen: false },
      { id: 'w_towel', name: 'Bath towel set', cost: 1499, quantity: 2, imageUrl: IMG.shopping },
      { id: 'w_lamp', name: 'Study lamp', cost: 899, quantity: 1, imageUrl: IMG.tech },
    ],
  },
  {
    id: 'seed_gaming',
    title: 'Gaming Setup',
    note: 'Saving up slowly',
    imageUrl: IMG.gaming,
    privacy: 'specific',
    createdAt: daysAgo(11),
    wishes: [
      { id: 'w_ps5', name: 'PlayStation 5 Slim', cost: 54990, quantity: 1, imageUrl: IMG.gaming, link: 'https://www.amazon.in' },
      { id: 'w_pad', name: 'Extra DualSense controller', cost: 5990, quantity: 2, imageUrl: IMG.gaming },
      { id: 'w_chair', name: 'Gaming chair', cost: 12999, quantity: 1, imageUrl: IMG.gaming, fulfilledBy: 'SEED_FRIEND', fulfilledByName: 'A Friend', ownerSeen: true },
    ],
  },
  {
    id: 'seed_books',
    title: 'Books to Read',
    note: '',
    imageUrl: IMG.book,
    privacy: 'private',
    createdAt: daysAgo(18),
    wishes: [
      { id: 'w_b1', name: 'Sapiens', subtitle: 'Yuval Noah Harari', cost: 499, quantity: 1, imageUrl: IMG.book },
      { id: 'w_b2', name: 'The Pragmatic Programmer', cost: 3200, quantity: 1, imageUrl: IMG.book },
      { id: 'w_b3', name: 'Atomic Habits', cost: 399, quantity: 1, imageUrl: IMG.book, note: 'Paperback is fine' },
      { id: 'w_b4', name: 'Shoe Dog', cost: 450, quantity: 1, imageUrl: IMG.book },
      { id: 'w_b5', name: 'Deep Work', cost: 425, quantity: 1, imageUrl: IMG.book },
    ],
  },
  {
    id: 'seed_travel',
    title: 'Goa Trip Fund',
    note: 'December, hopefully',
    imageUrl: IMG.travel,
    privacy: 'friends',
    createdAt: daysAgo(25),
    wishes: [
      { id: 'w_t1', name: 'Flight tickets', cost: 8500, quantity: 2, imageUrl: IMG.travel },
      { id: 'w_t2', name: 'Beach stay, 3 nights', cost: 15000, quantity: 1, imageUrl: IMG.travel },
      { id: 'w_t3', name: 'Snorkelling', cost: 2500, quantity: 2, imageUrl: IMG.travel },
    ],
  },
  {
    // Deliberately empty, to exercise the zero-wishes state.
    id: 'seed_empty',
    title: 'Diwali Gifts',
    note: 'Nothing added yet',
    imageUrl: IMG.gift,
    privacy: 'private',
    createdAt: daysAgo(1),
    wishes: [],
  },
];

async function findTarget() {
  // Explicit override: --uid <id>. Use when email and username point at
  // different accounts.
  const uidFlag = process.argv.indexOf('--uid');
  if (uidFlag !== -1 && process.argv[uidFlag + 1]) {
    const uid = process.argv[uidFlag + 1];
    const snap = await db.doc(`users/${uid}`).get();
    if (!snap.exists) throw new Error(`No user document at users/${uid}`);
    const data = snap.data() ?? {};
    console.log(`Target: ${uid}  (explicit --uid)`);
    console.log(`  email:    ${data.email ?? '(none)'}`);
    console.log(`  username: ${data.username ?? '(none)'}`);
    console.log(`  display:  ${data.displayName ?? '(none)'}\n`);
    return uid;
  }

  const byEmail = await db
    .collection('users')
    .where('email', '==', TARGET_EMAIL)
    .get();
  const byUsername = await db
    .collection('users')
    .where('username', '==', TARGET_USERNAME)
    .get();

  const ids = new Set([
    ...byEmail.docs.map((d) => d.id),
    ...byUsername.docs.map((d) => d.id),
  ]);

  if (ids.size === 0) {
    throw new Error(
      `No account found for ${TARGET_EMAIL} / @${TARGET_USERNAME}.\n` +
        '  Sign up in the app with that email and username first, then re-run.',
    );
  }
  if (ids.size > 1) {
    throw new Error(
      `Ambiguous: ${ids.size} accounts match. Refusing to touch any of them.\n` +
        `  ${[...ids].join('\n  ')}`,
    );
  }

  const uid = [...ids][0];
  const snap = await db.doc(`users/${uid}`).get();
  const data = snap.data() ?? {};
  console.log(`Target: ${uid}`);
  console.log(`  email:    ${data.email ?? '(none)'}`);
  console.log(`  username: ${data.username ?? '(none)'}`);
  console.log(`  display:  ${data.displayName ?? '(none)'}\n`);
  return uid;
}

async function clean(uid) {
  let removed = 0;
  for (const hive of HIVES) {
    const wishes = await db
      .collection(`users/${uid}/wishes`)
      .where('hiveId', '==', hive.id)
      .get();
    for (const w of wishes.docs) {
      if (COMMIT) await w.ref.delete();
      removed++;
    }
    const h = await db.doc(`users/${uid}/hives/${hive.id}`).get();
    if (h.exists) {
      if (COMMIT) await h.ref.delete();
      removed++;
    }
    if (COMMIT) await db.doc(`hives/${hive.id}`).delete().catch(() => undefined);
  }
  console.log(`${COMMIT ? 'Deleted' : 'Would delete'} ${removed} seeded document(s).`);
}

async function seed(uid) {
  const userSnap = await db.doc(`users/${uid}`).get();
  const displayName = userSnap.data()?.displayName ?? 'Test User';

  let hiveCount = 0;
  let wishCount = 0;

  for (const hive of HIVES) {
    // totalCost sums `cost` and ignores `quantity`, matching the app.
    const totalCost = hive.wishes.reduce((sum, w) => sum + (w.cost || 0), 0);
    const itemCount = hive.wishes.length;

    const hiveDoc = {
      id: hive.id,
      title: hive.title,
      imageUrl: hive.imageUrl,
      note: hive.note,
      privacy: hive.privacy,
      viewerIds: [],
      editorIds: [],
      allowedViewerIds: [],
      allowedEditorIds: [],
      isPublic: false,
      itemCount,
      totalCost,
      createdAt: hive.createdAt,
      ownerId: uid,
      ownerDisplayName: displayName,
    };

    console.log(
      `  ${hive.title.padEnd(22)} ${hive.privacy.padEnd(9)} ` +
        `${String(itemCount).padStart(2)} items  ₹${totalCost}`,
    );

    if (COMMIT) {
      await db.doc(`users/${uid}/hives/${hive.id}`).set(hiveDoc, { merge: true });
    }
    hiveCount++;

    for (const w of hive.wishes) {
      const wishDoc = {
        name: w.name,
        subtitle: w.subtitle ?? '',
        imageUrl: w.imageUrl ?? '',
        hiveId: hive.id,
        date: null,
        quantity: w.quantity ?? 1,
        note: w.note ?? '',
        link: w.link ?? '',
        cost: w.cost ?? 0,
        createdAt: hive.createdAt,
        fulfilledBy: w.fulfilledBy === 'SEED_FRIEND' ? uid : (w.fulfilledBy ?? ''),
        fulfilledByName: w.fulfilledByName ?? '',
        ownerSeen: w.ownerSeen ?? true,
        addedByUid: '',
        addedByName: '',
        isNote: w.isNote ?? false,
      };
      if (COMMIT) {
        await db.doc(`users/${uid}/wishes/${w.id}`).set(wishDoc, { merge: true });
      }
      wishCount++;
    }
  }

  console.log(
    `\n${COMMIT ? 'Wrote' : 'Would write'} ${hiveCount} hives and ${wishCount} wishes.`,
  );
}

console.log(`Project: ${PROJECT_ID}${USING_EMULATOR ? '  (EMULATOR)' : ''}`);
console.log(
  `Mode:    ${CLEAN ? 'CLEAN' : 'SEED'} ${COMMIT ? '(writing)' : '(DRY RUN — no writes)'}\n`,
);

try {
  const uid = await findTarget();
  if (CLEAN) {
    await clean(uid);
  } else {
    await seed(uid);
  }
  if (!COMMIT) console.log('\nDry run — nothing was written. Add --commit to apply.');
  process.exit(0);
} catch (err) {
  console.error('\nFAILED:', err.message ?? err);
  process.exit(1);
}
