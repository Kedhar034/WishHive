/// App-wide constants for Beehive.
class AppConstants {
  static const String appName = 'WishHive';
  static const String appTagline = 'Your new mind is here.';

  // Default images available in the app (Categories)
  static const List<String> defaultImages = [
    'assets/categories/Beaut.jpeg',
    'assets/categories/Book.jpeg',
    'assets/categories/Fitnes.jpeg',
    'assets/categories/Flower.jpeg',
    'assets/categories/Foo.jpeg',
    'assets/categories/Gamin.jpeg',
    'assets/categories/Gift.jpeg',
    'assets/categories/Movie.jpeg',
    'assets/categories/Musi.jpeg',
    'assets/categories/Part.jpeg',
    'assets/categories/Sport.jpeg',
    'assets/categories/Tec.jpeg',
    'assets/categories/Trave.jpeg',
    'assets/categories/anniversary.jpeg',
    'assets/categories/bike.jpeg',
    'assets/categories/jwellery.jpeg',
    'assets/categories/pet.jpeg',
    'assets/categories/shoppin.jpeg',
    'assets/categories/wedding.jpeg',
  ];

  static const String fallbackImage = 'https://placehold.co/600x400';
  
  // Avatars for user profiles (Characters c1 to c12 only)
  static const List<String> avatarImages = [
    'assets/images/c1.jpeg',
    'assets/images/c2.jpeg',
    'assets/images/c3.jpeg',
    'assets/images/c4.jpeg',
    'assets/images/c5.jpeg',
    'assets/images/c6.jpeg',
    'assets/images/c7.jpeg',
    'assets/images/c8.jpeg',
    'assets/images/c9.jpeg',
    'assets/images/c10.jpeg',
    'assets/images/c11.jpeg',
    'assets/images/c12.jpeg',
  ];

  // Default cover images for Hives (using same categories)
  static const List<String> hiveImages = defaultImages;
}
