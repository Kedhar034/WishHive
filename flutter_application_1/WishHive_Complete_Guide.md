# WishHive — Complete Dart/Flutter Learning Guide & Documentation

> **A comprehensive reference for learning Dart & Flutter through a real-world app.**
> Built by Kedhareesh | February 2026

---

## Table of Contents

1. [Part 1: Dart Language Fundamentals](#part-1-dart-language-fundamentals)
2. [Part 2: Flutter Widget System](#part-2-flutter-widget-system)
3. [Part 3: State Management (Riverpod)](#part-3-state-management-riverpod)
4. [Part 4: Firebase Integration](#part-4-firebase-integration)
5. [Part 5: Animations & Transitions](#part-5-animations--transitions)
6. [Part 6: App Architecture](#part-6-app-architecture)
7. [Part 7: Complete App Documentation](#part-7-complete-app-documentation)
8. [Part 8: Future Improvements](#part-8-future-improvements)

---

# Part 1: Dart Language Fundamentals

## 1.1 Variables & Data Types

Dart is **strongly typed** but supports type inference with `var`, `final`, and `const`.

```dart
// From app_constants.dart
static const String appName = 'WishHive';    // Compile-time constant
static const String appTagline = 'Your new mind is here.';

// From home_page.dart
int _currentNavIndex = 0;         // Mutable variable
bool _isHandlingShare = false;    // Boolean type
```

**Key Concepts:**
- `const` = Compile-time constant. Value is known at build time.
- `final` = Runtime constant. Value is set once and never changes.
- `var` = Type inferred. Dart figures out the type automatically.
- `late` = Initialized later (used when you can't set a value in the declaration).

```dart
// From product_detail_page.dart — 'late' example
late StreamSubscription _intentDataStreamSubscription;
```

---

## 1.2 Null Safety

Dart uses **sound null safety** — variables cannot be `null` unless you explicitly allow it with `?`.

```dart
// From user_model.dart
final String? username;       // Can be null (note the ?)
final String? photoUrl;        // Can be null
final String displayName;      // Cannot be null

// Null-aware operators in practice:
final String name = data['name'] as String? ?? 'No Name';
//                                         ^?  nullable cast
//                                              ^^ if null, use default

// Null-aware access
final requestCount = user?.friendRequestsReceived.length ?? 0;
//                       ^? if user is null, don't crash, return null
//                                                         ^^ then default to 0
```

**All null-aware operators we used:**
| Operator | Meaning | Example |
|----------|---------|---------|
| `?` | Nullable type | `String? name` |
| `??` | If null, use default | `name ?? 'Unknown'` |
| `?.` | Null-safe access | `user?.email` |
| `!` | Force unwrap (dangerous) | `widget.heroTag!` |
| `??=` | Assign if null | `name ??= 'Default'` |

---

## 1.3 Classes & Object-Oriented Programming

### Basic Class Structure

```dart
// From wish_model.dart
class WishModel {
  final String id;          // Instance field (immutable)
  final String name;
  final double cost;

  // Named constructor with required and optional params
  WishModel({
    required this.id,       // 'required' makes it mandatory
    required this.name,
    this.cost = 0.0,        // Default value
  });
}
```

### Factory Constructors

A factory constructor doesn't always create a new instance — it can return cached instances or different subtypes.

```dart
// From hive_model.dart
factory HiveModel.fromFirestore(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>? ?? {};
  return HiveModel(
    id: doc.id,
    title: data['title'] as String? ?? 'Untitled',
    itemCount: (data['itemCount'] as num?)?.toInt() ?? 0,
    totalCost: (data['totalCost'] as num?)?.toDouble() ?? 0.0,
    createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
  );
}
```

**Why factory?** It lets you:
- Parse data from a Map (Firestore document) into a Dart object
- Add validation/transformation logic before creating the object
- Return different types based on input

### The `copyWith` Pattern

Since our models use `final` fields (immutable), we can't modify them directly. `copyWith` creates a **new object** with some fields changed.

```dart
// From wish_model.dart
WishModel copyWith({
  String? id,
  String? name,
  double? cost,
}) {
  return WishModel(
    id: id ?? this.id,          // Use new value OR keep old one
    name: name ?? this.name,
    cost: cost ?? this.cost,
  );
}

// Usage:
final updatedWish = existingWish.copyWith(name: 'New Name');
// Creates a NEW object with 'name' changed, everything else stays the same
```

### Serialization (toFirestore / fromFirestore)

Converting between Dart objects ←→ Firestore documents:

```dart
// Dart Object → Firestore Map
Map<String, dynamic> toFirestore() {
  return {
    'name': name,
    'cost': cost,
    'createdAt': FieldValue.serverTimestamp(), // Special Firestore value
  };
}

// Firestore Document → Dart Object
factory WishModel.fromFirestore(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>? ?? {};
  return WishModel(
    id: doc.id,
    name: data['name'] as String? ?? 'No Name',
  );
}
```

---

## 1.4 Enums

Enums represent a fixed set of constants.

```dart
// From hive_model.dart
enum HivePrivacy { public, private, friends, specific }

// Usage in parsing:
static HivePrivacy _parsePrivacy(String? value) {
  switch (value) {
    case 'public': return HivePrivacy.public;
    case 'friends': return HivePrivacy.friends;
    case 'specific': return HivePrivacy.specific;
    default: return HivePrivacy.private;
  }
}

// Saving to Firestore:
'privacy': privacy.name,  // .name gives the string 'public', 'private', etc.
```

---

## 1.5 Collections (List, Map, Set)

```dart
// List — Ordered collection
static const List<String> defaultImages = [
  'assets/images/c5.jpeg',
  'assets/images/c10.jpeg',
];

// Map — Key-value pairs (used everywhere for Firestore)
Map<String, dynamic> toFirestore() {
  return {'title': title, 'cost': cost};
}

// Set — Unordered collection of UNIQUE items
// From providers.dart — used for tracking hidden hives
class TemporarilyHiddenHivesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};    // Empty set

  void add(String id) {
    state = {...state, id};     // Spread operator + new item → new Set
  }

  void remove(String id) {
    state = state.difference({id});  // Set difference
  }
}
```

**Key List operations we used:**
```dart
allHives.where((h) => !hidden.contains(h.id)).toList();  // Filter
friends.map((f) => f.toMap()).toList();                     // Transform
friendsData.firstWhere((f) => f.uid == id, orElse: ...);  // Find first match
List<String>.from(data['friends'] ?? []);                   // Safe copy
```

---

## 1.6 Async Programming (Future, async/await, Streams)

### Futures & async/await

A `Future` represents a value that will be available *in the future* (like fetching data from a server).

```dart
// From firestore_service.dart
Future<void> toggleWishFulfillment({
  required String hiveId, 
  required String wishId,
}) async {                          // 'async' marks it as asynchronous
  final docRef = _wishesCollection(hiveId).doc(wishId);
  
  await _firestore.runTransaction((transaction) async {
    //  ^await pauses until the transaction completes
    final snapshot = await transaction.get(docRef);
    // ...process data...
  });
}
```

### Streams

A `Stream` delivers data over time (like a live feed of changes).

```dart
// From providers.dart — real-time Firestore listener
final hiveListProvider = StreamProvider.autoDispose((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream<QuerySnapshot>.empty();
  
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('hives')
      .orderBy('createdAt', descending: true)
      .snapshots();    // Returns a Stream — auto-updates on changes!
});
```

### try/catch/finally

Error handling for async operations:

```dart
// From upload_service.dart
try {
  final downloadUrl = await ImageStorageService.uploadImage(file, userId);
  await FirebaseFirestore.instance
      .collection('wishes')
      .doc(task.wishId)
      .update({'imageUrl': downloadUrl});
} catch (e) {
  debugPrint('Upload failed: $e');
  // Retry logic here...
} finally {
  _isUploading = false;     // Always runs, even if error occurred
  _processQueue();          // Continue with next item
}
```

---

## 1.7 Generics

Generics let you write code that works with **any type**.

```dart
// Generic provider that returns List<WishModel>
final wishesByHiveProvider = StreamProvider.autoDispose
    .family<List<WishModel>, ({String hiveId, String ownerId})>(
  (ref, args) {
    // ...
  },
);
//      ^ Return type: List<WishModel>
//                      ^ Parameter type: a Record

// Generic function
Future<void> toggleWishFulfillment({ ... })
//     ^ Returns Future<void> — a Future that completes with no value
```

---

## 1.8 Spread Operator & Collection If/For

```dart
// Spread operator (...) copies all items from one collection into another
state = [...state, newTask];       // Add item to list immutably
state = {...state, id};            // Add item to set immutably

// Collection If (conditionally include items in a list)
Column(
  children: [
    Text('Always shown'),
    if (_isOwner) ...[             // Only include these if owner
      const SizedBox(height: 6),
      Text('Add a wish!'),
    ],
  ],
)
```

---

## 1.9 Arrow Functions & Lambdas

Short syntax for single-expression functions:

```dart
// Arrow function (single expression)
bool get _isOwner => widget.ownerId.isEmpty || widget.ownerId == uid;

// Lambda (anonymous function)
hives.where((h) => !hidden.contains(h.id)).toList();
//           ^ parameter    ^ body (single expression)

// Named function equivalent:
bool filterHive(HiveModel h) {
  return !hidden.contains(h.id);
}
hives.where(filterHive).toList();
```

---

## 1.10 String Interpolation

```dart
// Simple variable
Text('$items items')                    // → "5 items"

// Expression
Text('₹${price.toStringAsFixed(2)}')   // → "₹499.99"

// Complex expressions
'wish_image_${widget.wish.id}'          // → "wish_image_abc123"
```

---

# Part 2: Flutter Widget System

## 2.1 StatelessWidget vs StatefulWidget vs ConsumerWidget

### StatelessWidget — No internal state, just builds UI

```dart
// From hive_card.dart
class HiveCard extends StatelessWidget {
  final String title;
  final int items;

  const HiveCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Text(title);  // Rebuilt only when parent passes new data
  }
}
```

### StatefulWidget — Has internal mutable state

```dart
// From product_detail_page.dart — _WishTile
class _WishTile extends StatefulWidget {
  final WishModel wish;

  const _WishTile({required this.wish});

  @override
  State<_WishTile> createState() => _WishTileState();
}

class _WishTileState extends State<_WishTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, ...);
  }

  @override
  void dispose() {
    _controller.dispose();  // Clean up resources!
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _controller, child: ...);
  }
}
```

### ConsumerWidget / ConsumerStatefulWidget — Riverpod integration

```dart
// ConsumerWidget (stateless + Riverpod)
class AuthWrapper extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    // ref.watch = Listen for changes and rebuild
  }
}

// ConsumerStatefulWidget (stateful + Riverpod)
class HomePage extends ConsumerStatefulWidget {
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(uidProvider);  // Use ref from ConsumerState
  }
}
```

---

## 2.2 Widget Lifecycle

```
initState()       → Called ONCE when widget is created
didUpdateWidget() → Called when parent rebuilds with new data
build()           → Called every time the widget needs to paint
dispose()         → Called ONCE when widget is removed forever
```

```dart
// From _WishTileState
@override
void initState() {
  super.initState();
  _controller = AnimationController(vsync: this, duration: Duration(milliseconds: 400));
  if (widget.wish.fulfilledBy.isNotEmpty) {
    _controller.value = 1.0;  // Set initial state without animation
  }
}

@override
void didUpdateWidget(covariant _WishTile oldWidget) {
  super.didUpdateWidget(oldWidget);
  final isFulfilled = widget.wish.fulfilledBy.isNotEmpty;
  final wasFulfilled = oldWidget.wish.fulfilledBy.isNotEmpty;

  if (isFulfilled && !wasFulfilled) {
    _controller.forward(from: 0.0);  // Trigger animation!
  } else if (!isFulfilled && wasFulfilled) {
    _controller.reset();
  }
}
```

---

## 2.3 Layout Widgets

### Column, Row, Expanded, Spacer

```dart
Row(
  children: [
    Image.asset('logo.png', width: 40),
    const SizedBox(width: 12),          // Fixed spacing
    Text('WishHive'),
    const Spacer(),                      // Takes up remaining space
    IconButton(icon: Icon(Icons.sort)),
  ],
)
```

### CustomScrollView & Slivers

Slivers are scrollable pieces that compose together inside a `CustomScrollView`:

```dart
// From product_detail_page.dart
CustomScrollView(
  physics: const BouncingScrollPhysics(),  // iOS-style bounce
  slivers: [
    SliverAppBar(               // Collapsible header with image
      expandedHeight: 240,
      pinned: true,             // Title stays visible at top
      stretch: true,            // Stretch effect on overscroll
      flexibleSpace: FlexibleSpaceBar(
        background: Hero(
          tag: heroTag,
          child: _buildHeaderImage(),
        ),
        stretchModes: const [StretchMode.zoomBackground],
      ),
    ),
    SliverToBoxAdapter(         // Single non-scrollable widget
      child: Text('Wishes'),
    ),
    SliverList.separated(       // Scrollable list of wish tiles
      itemCount: wishes.length,
      itemBuilder: (context, index) => _WishTile(wish: wishes[index]),
    ),
    const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
  ],
)
```

### IndexedStack

Shows only one child at a time but keeps all children alive in memory (preserves state):

```dart
// From home_page.dart — Bottom navigation
IndexedStack(
  index: _currentNavIndex,    // Which page to show
  children: [
    _buildHomeContent(...),   // index 0
    const ContactsPage(),     // index 1
    const MarketplacePage(),  // index 2
    const SettingsPage(),     // index 3
  ],
)
```

---

## 2.4 Navigation

### Basic Push/Pop

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const HiddenHivesPage()),
);

Navigator.pop(context);  // Go back
```

### Custom Page Transitions

```dart
// From home_page.dart — Fast transition for hive opening
Navigator.push(
  context,
  PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) =>
        ProductDetailPage(hiveId: hive.id, heroTag: heroTag),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return child;  // No transition effect — instant page swap
    },
  ),
);
```

---

## 2.5 Theming

The entire app's visual identity is defined in one place:

```dart
// From app_theme.dart
class AppTheme {
  // Brand colors
  static const Color primaryAmber = Color(0xFFF5A623);
  static const Color backgroundLight = Color(0xFFFFFDF7);

  // Complete theme
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: primaryAmber),
      scaffoldBackgroundColor: backgroundLight,
      textTheme: GoogleFonts.interTextTheme(),   // Custom fonts
      
      // Every widget type can be themed globally:
      appBarTheme: AppBarTheme(...),
      cardTheme: CardThemeData(...),
      elevatedButtonTheme: ElevatedButtonThemeData(...),
      inputDecorationTheme: InputDecorationTheme(...),
      snackBarTheme: SnackBarThemeData(...),
    );
  }
}
```

**Applied in main.dart:**
```dart
MaterialApp(
  theme: AppTheme.lightTheme,  // One line applies everything
)
```

---

# Part 3: State Management (Riverpod)

## 3.1 What is Riverpod?

Riverpod is a state management library that lets you create **providers** (data sources) and **watch** them from widgets. When the data changes, widgets automatically rebuild.

## 3.2 Provider Types We Used

### Provider — Simple read-only value

```dart
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

// Usage: ref.read(firestoreServiceProvider).createWish(...)
```

### StreamProvider — Real-time data from a Stream

```dart
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).idTokenChanges();
});

// Usage in widget:
final authState = ref.watch(authStateProvider);
authState.when(
  data: (user) => ...,     // Got data!
  loading: () => ...,      // Still loading
  error: (e, _) => ...,    // Error occurred
);
```

### FutureProvider — One-time async data

```dart
final friendFeedProvider = FutureProvider.autoDispose<List<HiveModel>>((ref) async {
  final user = ref.watch(currentUserStreamProvider).value;
  if (user == null || user.friends.isEmpty) return [];
  return ref.read(firestoreServiceProvider).getFriendsFeed(user.friends);
});
```

### NotifierProvider — Complex state with methods

```dart
// The Notifier class — contains state + methods
class TemporarilyHiddenHivesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};  // Initial state

  void add(String id) {
    state = {...state, id};    // Must create NEW set (immutable update)
  }

  void remove(String id) {
    state = state.difference({id});
  }
}

// The provider that exposes the notifier
final temporarilyHiddenHivesProvider = 
    NotifierProvider<TemporarilyHiddenHivesNotifier, Set<String>>(
      TemporarilyHiddenHivesNotifier.new
    );

// Usage:
ref.watch(temporarilyHiddenHivesProvider);                    // Read state
ref.read(temporarilyHiddenHivesProvider.notifier).add(id);    // Call method
```

### Family Provider — Parameterized provider

```dart
// Provider that takes parameters
final wishesByHiveProvider = StreamProvider.autoDispose
    .family<List<WishModel>, ({String hiveId, String ownerId})>(
  (ref, args) {
    return ref.read(firestoreServiceProvider)
        .wishesStream(args.ownerId, args.hiveId);
  },
);

// Usage with arguments:
ref.watch(wishesByHiveProvider((hiveId: 'abc', ownerId: 'xyz')));
```

## 3.3 ref.watch vs ref.read

```dart
// ref.watch — Rebuilds widget when value changes (use in build())
final uid = ref.watch(uidProvider);

// ref.read — One-time read, no rebuilds (use in callbacks)
onPressed: () {
  ref.read(firestoreServiceProvider).deleteWish(id);
}

// ref.invalidate — Force provider to refetch
ref.invalidate(friendFeedProvider);
```

---

# Part 4: Firebase Integration

## 4.1 Firebase Auth

```dart
// Google Sign-In flow (from login logic)
final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
final GoogleSignInAuthentication? googleAuth = await googleUser?.authentication;
final credential = GoogleAuthProvider.credential(
  accessToken: googleAuth?.accessToken,
  idToken: googleAuth?.idToken,
);
await FirebaseAuth.instance.signInWithCredential(credential);
```

## 4.2 Cloud Firestore (Database)

### Data Structure
```
users/
  {userId}/
    ├── displayName, email, username, friends[], hiddenHiveIds[]
    └── hives/
          {hiveId}/
            ├── title, imageUrl, privacy, itemCount, totalCost
            └── wishes/
                  {wishId}/
                    ├── name, cost, link, fulfilledBy, imageUrl
```

### CRUD Operations

```dart
// CREATE
await _firestore.collection('users').doc(uid)
    .collection('hives').add(hive.toFirestore());

// READ (one-time)
final doc = await _firestore.collection('users').doc(uid).get();

// READ (real-time stream)
Stream<List<WishModel>> wishesStream(String ownerId, String hiveId) {
  return _wishesCollection(ownerId).snapshots().map(
    (snap) => snap.docs.map((d) => WishModel.fromFirestore(d)).toList(),
  );
}

// UPDATE
await docRef.update({'fulfilledBy': userId});

// DELETE
await docRef.delete();
```

### Transactions

Transactions ensure atomic operations (all-or-nothing):

```dart
await _firestore.runTransaction((transaction) async {
  final snapshot = await transaction.get(docRef);
  final currentData = snapshot.data() as Map<String, dynamic>;
  
  if (currentData['fulfilledBy'] == '') {
    transaction.update(docRef, {'fulfilledBy': userId});
  } else {
    transaction.update(docRef, {'fulfilledBy': ''});
  }
});
```

## 4.3 Firebase Storage

```dart
// From image_storage_service.dart
static Future<String> uploadImage(File file, String userId) async {
  final ref = FirebaseStorage.instance
      .ref()
      .child('user_images/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg');
  
  await ref.putFile(file);
  return await ref.getDownloadURL();  // Returns the public URL
}
```

---

# Part 5: Animations & Transitions

## 5.1 Hero Animation

The Hero widget makes an element **fly** between two screens:

```dart
// SOURCE screen (HiveCard)
Hero(
  tag: 'hive-${hive.id}',     // Must match on both screens!
  child: ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: CachedNetworkImage(imageUrl: hive.imageUrl),
  ),
)

// DESTINATION screen (ProductDetailPage)
Hero(
  tag: widget.heroTag ?? 'hive-${widget.hiveId}',  // Same tag!
  child: _buildHeaderImage(),
)
```

**How it works:** Flutter finds matching `Hero` tags and animates the widget between the two positions.

## 5.2 AnimationController & ScaleTransition

Used for the "popping" animation when a wish is fulfilled:

```dart
_controller = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 400),
  lowerBound: 0.8,   // Minimum scale (80%)
  upperBound: 1.0,    // Maximum scale (100%)
);

_scaleAnimation = CurvedAnimation(
  parent: _controller,
  curve: Curves.elasticOut,  // Bouncy overshoot effect
);

// In build():
ScaleTransition(
  scale: _scaleAnimation,
  child: Container(...),    // The checkbox that pops
)
```

## 5.3 AnimatedContainer

Automatically animates changes to its properties:

```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  width: 26, height: 26,
  decoration: BoxDecoration(
    color: isCompleted ? Colors.green : Colors.transparent,
    // When isCompleted changes, color animates smoothly!
  ),
)
```

---

# Part 6: App Architecture

## 6.1 Folder Structure

```
lib/
├── main.dart                    # Entry point
├── core/
│   ├── constants/app_constants.dart  # App-wide constants
│   ├── theme/app_theme.dart         # Visual theme
│   └── utils/                        # Helper functions
├── models/                      # Data classes
│   ├── hive_model.dart
│   ├── wish_model.dart
│   └── user_model.dart
├── pages/                       # Screens
│   ├── auth_wrapper.dart        # Auth routing
│   ├── home_page.dart           # Main dashboard
│   ├── product_detail_page.dart # Hive detail
│   ├── contacts_page.dart       # Friends
│   └── ...
├── providers/                   # State management
│   ├── providers.dart           # All Riverpod providers
│   └── locale_provider.dart     # Language settings
├── services/                    # Business logic
│   ├── firestore_service.dart   # Database operations
│   ├── upload_service.dart      # Background image uploads
│   ├── metadata_service.dart    # URL metadata extraction
│   └── image_storage_service.dart
├── widgets/                     # Reusable UI components
│   ├── hive_card.dart
│   ├── image_picker_widget.dart
│   └── ...
└── l10n/                        # Localization (i18n)
    ├── app_en.arb               # English strings
    ├── app_fr.arb               # French strings
    └── ...
```

## 6.2 Data Flow

```
User Action
    ↓
Widget (e.g., onTap)
    ↓
ref.read(provider) → calls service method
    ↓
FirestoreService → writes to Cloud Firestore
    ↓
Firestore Stream updates
    ↓
StreamProvider emits new data
    ↓
ref.watch() in widget → Widget rebuilds automatically
```

## 6.3 Key Design Patterns

| Pattern | Where Used | Purpose |
|---------|-----------|---------|
| **MVC-like** | Models, Services, Pages | Separation of concerns |
| **Repository** | `FirestoreService` | Single source of truth for data |
| **Observer** | Riverpod providers | Reactive UI updates |
| **Factory** | `fromFirestore()` methods | Object creation from external data |
| **Immutable State** | `copyWith()`, `final` fields | Predictable state changes |
| **Optimistic Updates** | `temporarilyHiddenHivesProvider` | Instant UI feedback |
| **Queue** | `UploadService` | Background task processing |

---

# Part 7: Complete App Documentation

## 7.1 What is WishHive?

**WishHive** is a social wishlist management app where users can:

- Create **Hives** (categories/wishlists) to organize desired items
- Add **Wishes** (products/items) with images, links, prices, and notes
- **Share hives with friends** who can view and fulfill wishes
- **Track fulfillment** — friends can mark wishes as "done"
- **Hide/mute** friend content they don't want to see
- Manage **privacy** — hives can be public, private, or friends-only

## 7.2 Feature Matrix

| Feature | Status | Description |
|---------|--------|-------------|
| Auth (Email + Google) | ✅ | Firebase Auth with Google Sign-In |
| Profile Completion | ✅ | Username, avatar selection |
| Hive CRUD | ✅ | Create, Read, Update, Delete |
| Wish CRUD | ✅ | Create, Read, Update, Delete |
| Image Upload | ✅ | Camera/Gallery with background upload |
| Friend System | ✅ | Send/accept/reject friend requests |
| Friend Feed | ✅ | See friends' hives on dashboard |
| Wish Fulfillment | ✅ | Toggle wish as fulfilled/unfulfilled |
| Hide/Unhide Hives | ✅ | Hide friend hives from feed |
| Share Intent | ✅ | Share from other apps directly |
| URL Metadata | ✅ | Auto-extract title/image from URLs |
| Hero Animations | ✅ | Image transitions between screens |
| Localization | ✅ | English, French, Hindi, Telugu |
| Skeleton Loading | ✅ | Shimmer effects while loading |
| Offline Support | ✅ | Firestore offline persistence |

## 7.3 Tech Stack

| Layer | Technology |
|-------|-----------|
| **Language** | Dart 3.9+ |
| **Framework** | Flutter (Material 3) |
| **State Management** | Riverpod 3.0 |
| **Backend** | Firebase (Auth, Firestore, Storage) |
| **Image Caching** | `cached_network_image` |
| **URL Handling** | `url_launcher`, `metadata_fetch` |
| **Sharing** | `receive_sharing_intent` |
| **Image Processing** | `flutter_image_compress` |
| **Fonts** | Google Fonts (Inter, Poppins) |
| **Animations** | `lottie`, Hero, AnimatedContainer |
| **Navigation Bar** | `curved_navigation_bar` |
| **Persistence** | `shared_preferences` |

---

# Part 8: Future Improvements

## 8.1 High Impact (Should Do)

| Improvement | Description |
|------------|-------------|
| **Dark Mode** | Add `AppTheme.darkTheme` and toggle in settings |
| **Push Notifications** | Notify when a friend fulfills your wish (Firebase Cloud Messaging) |
| **Search** | Add search bar to find wishes/hives quickly |
| **Sort/Filter** | Sort by date, price, fulfillment status |
| **Image Crop** | Let users crop images before uploading |
| **Pagination** | Load hives/wishes in batches for large collections |

## 8.2 Medium Impact (Nice to Have)

| Improvement | Description |
|------------|-------------|
| **Wishlist Sharing Link** | Generate a shareable URL for a hive (Dynamic Links) |
| **Price Tracking** | Track price changes for linked products |
| **Multiple Images** | Allow multiple images per wish |
| **Categories/Tags** | Tag wishes (e.g., "Electronics", "Books") |
| **Export** | Export wishlist as PDF or CSV |
| **Undo Delete** | Add undo functionality to wish/hive deletion |
| **Drag to Reorder** | ReorderableListView for wish ordering |

## 8.3 Technical Improvements

| Improvement | Description |
|------------|-------------|
| **Unit Tests** | Test models, services, and providers |
| **Widget Tests** | Test UI components in isolation |
| **Integration Tests** | End-to-end user flows |
| **Error Reporting** | Firebase Crashlytics for crash logs |
| **Analytics** | Firebase Analytics for user behavior |
| **CI/CD** | GitHub Actions for automated builds |
| **Code Generation** | Use `freezed` + `json_serializable` for models |
| **Deep Linking** | Open specific hives from external URLs |
| **Web Support** | Deploy as a Progressive Web App |
| **Accessibility** | Add semantic labels, screen reader support |

## 8.4 Architecture Improvements

| Improvement | Description |
|------------|-------------|
| **Use `riverpod_generator`** | Auto-generate providers with annotations |
| **Separate Business Logic** | Move complex logic from pages to use-case classes |
| **Abstract Firebase** | Create repository interfaces for testability |
| **Input Validation** | Centralized form validation helpers |
| **Connectivity Handling** | Show offline banner, queue writes |

---

> **This guide was generated from the actual WishHive codebase.**
> Every code example is a real snippet from the app.
> Last updated: February 15, 2026
