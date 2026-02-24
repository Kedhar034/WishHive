/// Service to automatically assign a contextually relevant fallback image
/// to a wish when no image is provided by the user or the shared URL.
///
/// Uses Unsplash Source API (free, no key required) for now.
/// The user can replace these with custom asset paths later.
class WishImageService {
  WishImageService._();

  // ─── Category image URLs (Unsplash free source) ──────────────────────────

  static const String _shopping =
      'https://images.unsplash.com/photo-1483985988355-763728e1935b?w=400&q=70';
  static const String _food =
      'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&q=70';
  static const String _travel =
      'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?w=400&q=70';
  static const String _gift =
      'https://images.unsplash.com/photo-1549465220-1a8b9238cd48?w=400&q=70';
  static const String _tech =
      'https://images.unsplash.com/photo-1518770660439-4636190af475?w=400&q=70';
  static const String _books =
      'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=400&q=70';
  static const String _beauty =
      'https://images.unsplash.com/photo-1522335789203-aabd1fc54bc9?w=400&q=70';
  static const String _sports =
      'https://images.unsplash.com/photo-1517649763962-0c623066013b?w=400&q=70';
  static const String _flowers =
      'https://images.unsplash.com/photo-1490750967868-88df5691cc60?w=400&q=70';
  static const String _default =
      'https://images.unsplash.com/photo-1513885535751-8b9238bd345a?w=400&q=70'; // star/wish

  // ─── Keyword maps ──────────────────────────────────────────────────────────

  static const _shoppingKeywords = [
    'shirt', 'dress', 'shoes', 'jeans', 'pant', 'jacket', 'clothes', 'cloth',
    'fashion', 'wear', 'amazon', 'flipkart', 'myntra', 'ajio', 'nykaa fashion',
    'meesho', 'cart', 'buy', 'purchase', 'order', 'shopping', 'accessory',
    'accessories', 'bag', 'wallet', 'watch', 'jewel', 'tops', 'kurti', 'saree', 'frock', 'ethnic', 
    'ethnic wear', 'ethnic wear for women', 'ethnic wear for men', 'ethnic wear for girls', 'ethnic wear for boys',
    'ethnic wear for women', 'ethnic wear for men', 'ethnic wear for girls', 'ethnic wear for boys', 'ethnic wear for women', 'ethnic wear for men', 'ethnic wear for girls', 'ethnic wear for boys',       
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
    'gift', 'surprise', 'birthday', 'present', 'celebration', 'anniversary',
    'wedding', 'festive', 'christmas', 'diwali', 'eid', 'valentine',
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
    'sport', 'gym', 'fitness', 'cricket', 'football', 'tennis', 'basketball',
    'badminton', 'cycling', 'bike', 'yoga', 'pilates', 'running', 'sneaker',
    'nike', 'adidas', 'puma', 'reebok', 'decathlon', 'gear', 'equipment',
    'dumbbell', 'protein'
  ];

  static const _flowersKeywords = [
    'flower', 'bouquet', 'rose', 'plant', 'succulent', 'lily', 'orchid',
    'tulip', 'daisy', 'floral', 'garden', 'nursery', 'bonsai', 'pot'
  ];

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Returns a relevant fallback image URL based on the wish name and product link.
  /// Returns an empty string only if both inputs are empty (shouldn't happen).
  static String getAutoImage(String wishName, String link) {
    final text = '${wishName.toLowerCase()} ${link.toLowerCase()}';

    if (_anyMatch(text, _foodKeywords)) return _food;
    if (_anyMatch(text, _travelKeywords)) return _travel;
    if (_anyMatch(text, _giftKeywords)) return _gift;
    if (_anyMatch(text, _techKeywords)) return _tech;
    if (_anyMatch(text, _booksKeywords)) return _books;
    if (_anyMatch(text, _beautyKeywords)) return _beauty;
    if (_anyMatch(text, _sportsKeywords)) return _sports;
    if (_anyMatch(text, _flowersKeywords)) return _flowers;
    if (_anyMatch(text, _shoppingKeywords)) return _shopping;

    return _default;
  }

  static bool _anyMatch(String text, List<String> keywords) {
    return keywords.any((kw) => text.contains(kw));
  }
}
