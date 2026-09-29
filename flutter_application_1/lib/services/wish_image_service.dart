/// Service to automatically assign a contextually relevant fallback image
/// to a wish when no image is provided by the user or the shared URL.
///
/// Uses Unsplash Source API (free, no key required) for now.
/// The user can replace these with custom asset paths later.
class WishImageService {
  WishImageService._();

  // ─── Category image URLs (Local Assets) ────────────────────────────────────

  static const String _shopping = 'assets/categories/shoppin.jpeg';
  static const String _food = 'assets/categories/Foo.jpeg';
  static const String _travel = 'assets/categories/Trave.jpeg';
  static const String _gift = 'assets/categories/Gift.jpeg';
  static const String _tech = 'assets/categories/Tec.jpeg';
  static const String _books = 'assets/categories/Book.jpeg';
  static const String _beauty = 'assets/categories/Beaut.jpeg';
  static const String _sports = 'assets/categories/Sport.jpeg';
  static const String _flowers = 'assets/categories/Flower.jpeg';
  static const String _gaming = 'assets/categories/Gamin.jpeg';
  static const String _movie = 'assets/categories/Movie.jpeg';
  static const String _music = 'assets/categories/Musi.jpeg';
  static const String _party = 'assets/categories/Part.jpeg';
  static const String _fitness = 'assets/categories/Fitnes.jpeg';
  static const String _anniversary = 'assets/categories/anniversary.jpeg';
  static const String _bike = 'assets/categories/bike.jpeg';
  static const String _jewellery = 'assets/categories/jwellery.jpeg';
  static const String _pet = 'assets/categories/pet.jpeg';
  static const String _wedding = 'assets/categories/wedding.jpeg';
  
  static const String _default = 'assets/categories/Gift.jpeg';

  // ─── Keyword maps ──────────────────────────────────────────────────────────

  static const _shoppingKeywords = [
    'shirt', 'dress', 'shoes', 'jeans', 'pant', 'jacket', 'clothes', 'cloth',
    'fashion', 'wear', 'amazon', 'flipkart', 'myntra', 'ajio', 'nykaa fashion',
    'meesho', 'cart', 'buy', 'purchase', 'order', 'shopping', 'accessory',
    'accessories', 'bag', 'wallet', 'watch', 'tops', 'kurti', 'saree', 'frock', 'ethnic',
  ];

  static const _foodKeywords = [
    'food', 'pizza', 'burger', 'noodle', 'pasta', 'sushi', 'biryani',
    'restaurant', 'swiggy', 'zomato', 'snack', 'cake', 'chocolate',
    'ice cream', 'coffee', 'tea', 'eat', 'lunch', 'dinner', 'breakfast',
    'meal', 'fruit', 'vegetable', 'grocery', 'blinkit', 'dunzo'
  ];

  static const _travelKeywords = [
    'travel', 'flight', 'trip', 'hotel', 'booking', 'airbnb', 'makemytrip',
    'cab', 'uber', 'ola', 'train', 'bus', 'ticket', 'vacation', 'holiday',
    'tour', 'airport', 'airline', 'indigo', 'air india', 'goibibo', 'yatra',
    'cleartrip','agoda', 'hostel', 'resort', 'cruise'
  ];

  static const _giftKeywords = [
    'gift', 'surprise', 'birthday', 'present', 'celebration',
    'festive', 'christmas', 'diwali', 'eid', 'valentine',
    'hamper', 'bouquet with', 'greeting'
  ];

  static const _techKeywords = [
    'phone', 'laptop', 'computer', 'tablet', 'ipad', 'iphone', 'samsung',
    'gadget', 'tech', 'electronic', 'camera', 'headphone', 'earphone',
    'speaker', 'keyboard', 'mouse', 'monitor', 'tv', 'television', 'smart',
    'apple.com', 'samsung.com', 'oneplus', 'realme', 'oppo', 'vivo',
    'motorola', 'boat', 'jbl', 'sony', 'lg', 'dell', 'hp', 'lenovo', 'asus'
  ];

  static const _booksKeywords = [
    'book', 'novel', 'textbook', 'ebook', 'kindle', 'read', 'author',
    'fiction', 'non-fiction', 'biography', 'comic', 'manga', 'magazine',
    'literature', 'poetry', 'education', 'study', 'course'
  ];

  static const _beautyKeywords = [
    'beauty', 'makeup', 'skincare', 'cosmetic', 'nykaa', 'loreal', 'lakme',
    'lipstick', 'foundation', 'serum', 'moisturizer', 'shampoo', 'conditioner',
    'perfume', 'fragrance', 'nail', 'hair', 'face wash', 'sunscreen'
  ];

  static const _sportsKeywords = [
    'sport', 'cricket', 'football', 'tennis', 'basketball',
    'badminton', 'running', 'sneaker', 'nike', 'adidas', 'puma', 'reebok', 
    'decathlon', 'gear', 'equipment'
  ];

  static const _fitnessKeywords = [
    'gym', 'fitness', 'yoga', 'pilates', 'dumbbell', 'protein', 'workout', 'exercise'
  ];

  static const _flowersKeywords = [
    'flower', 'bouquet', 'rose', 'plant', 'succulent', 'lily', 'orchid',
    'tulip', 'daisy', 'floral', 'garden', 'nursery', 'bonsai', 'pot'
  ];

  static const _gamingKeywords = [
    'game', 'gaming', 'playstation', 'xbox', 'nintendo', 'steam', 'console',
    'controller', 'video game'
  ];

  static const _movieKeywords = [
    'movie', 'cinema', 'film', 'theater', 'netflix', 'prime', 'ticket'
  ];

  static const _musicKeywords = [
    'music', 'song', 'spotify', 'concert', 'guitar', 'piano', 'instrument'
  ];

  static const _partyKeywords = [
    'party', 'club', 'dj', 'dance', 'event'
  ];

  static const _anniversaryKeywords = [
    'anniversary', 'wedding anniversary'
  ];

  static const _bikeKeywords = [
    'bike', 'motorcycle', 'scooter', 'riding', 'helmet'
  ];

  static const _jewelleryKeywords = [
    'jewellery', 'jewelry', 'necklace', 'ring', 'earring', 'bracelet', 'gold', 'silver', 'diamond'
  ];

  static const _petKeywords = [
    'pet', 'dog', 'cat', 'animal', 'puppy', 'kitten', 'pet food'
  ];

  static const _weddingKeywords = [
    'wedding', 'marriage', 'bride', 'groom', 'bridal'
  ];

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Returns a relevant fallback image URL based on the wish name and product link.
  /// Returns an empty string only if both inputs are empty (shouldn't happen).
  static String getAutoImage(String wishName, String link) {
    final text = '${wishName.toLowerCase()} ${link.toLowerCase()}';

    if (_anyMatch(text, _foodKeywords)) return _food;
    if (_anyMatch(text, _travelKeywords)) return _travel;
    if (_anyMatch(text, _techKeywords)) return _tech;
    if (_anyMatch(text, _booksKeywords)) return _books;
    if (_anyMatch(text, _beautyKeywords)) return _beauty;
    if (_anyMatch(text, _gamingKeywords)) return _gaming;
    if (_anyMatch(text, _movieKeywords)) return _movie;
    if (_anyMatch(text, _musicKeywords)) return _music;
    if (_anyMatch(text, _partyKeywords)) return _party;
    if (_anyMatch(text, _fitnessKeywords)) return _fitness;
    if (_anyMatch(text, _sportsKeywords)) return _sports;
    if (_anyMatch(text, _flowersKeywords)) return _flowers;
    if (_anyMatch(text, _anniversaryKeywords)) return _anniversary;
    if (_anyMatch(text, _weddingKeywords)) return _wedding;
    if (_anyMatch(text, _bikeKeywords)) return _bike;
    if (_anyMatch(text, _jewelleryKeywords)) return _jewellery;
    if (_anyMatch(text, _petKeywords)) return _pet;
    if (_anyMatch(text, _giftKeywords)) return _gift;
    if (_anyMatch(text, _shoppingKeywords)) return _shopping;

    return _default;
  }

  static bool _anyMatch(String text, List<String> keywords) {
    return keywords.any((kw) => text.contains(kw));
  }
}
