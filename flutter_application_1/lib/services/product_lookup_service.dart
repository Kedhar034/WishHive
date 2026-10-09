import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Product details as returned by the resolveProduct Cloud Function.
class FetchedProduct {
  final String? title;
  final double? price;
  final String? currency;
  final List<String> images;
  final String? brand;
  final double? rating;
  final int? ratingCount;
  final String? description;

  /// When the store was read, which is what "as of" refers to — not when
  /// this particular user asked.
  final DateTime fetchedAt;

  const FetchedProduct({
    this.title,
    this.price,
    this.currency,
    this.images = const [],
    this.brand,
    this.rating,
    this.ratingCount,
    this.description,
    required this.fetchedAt,
  });

  bool get hasPrice => price != null && price! > 0;
  String? get mainImage => images.isEmpty ? null : images.first;

  factory FetchedProduct.fromMap(Map<String, dynamic> map, int fetchedAtMillis) {
    final p = Map<String, dynamic>.from(map);
    return FetchedProduct(
      title: p['title'] as String?,
      price: (p['price'] as num?)?.toDouble(),
      currency: p['currency'] as String?,
      images: List<String>.from(p['images'] ?? const []),
      brand: p['brand'] as String?,
      rating: (p['rating'] as num?)?.toDouble(),
      ratingCount: (p['ratingCount'] as num?)?.toInt(),
      description: p['description'] as String?,
      fetchedAt: fetchedAtMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(fetchedAtMillis)
          : DateTime.now(),
    );
  }
}

enum LookupStatus { found, miss, notFound, unsupported, hiveLink, limitReached, failed }

class ProductLookupResult {
  final LookupStatus status;
  final FetchedProduct? product;
  final String? message;

  const ProductLookupResult(this.status, {this.product, this.message});

  bool get isFound => status == LookupStatus.found && product != null;
}

class ProductLookupService {
  ProductLookupService._();

  static final _fns = FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Free and silent: details someone already fetched for this product.
  static Future<ProductLookupResult> cached(String url) =>
      _call(url, 'cache', const Duration(seconds: 10));

  /// The user asked for full details. May call Zyte, which takes a while.
  static Future<ProductLookupResult> fetch(String url) =>
      _call(url, 'fetch', const Duration(seconds: 70));

  static Future<ProductLookupResult> _call(
    String url,
    String mode,
    Duration timeout,
  ) async {
    try {
      final res = await _fns
          .httpsCallable(
            'resolveProduct',
            options: HttpsCallableOptions(timeout: timeout),
          )
          .call<Map<String, dynamic>>({'url': url, 'mode': mode});
      final data = Map<String, dynamic>.from(res.data);

      switch (data['status']) {
        case 'found':
          return ProductLookupResult(
            LookupStatus.found,
            product: FetchedProduct.fromMap(
              Map<String, dynamic>.from(data['product'] ?? const {}),
              (data['fetchedAt'] as num?)?.toInt() ?? 0,
            ),
          );
        case 'miss':
          return const ProductLookupResult(LookupStatus.miss);
        case 'hive-link':
          return const ProductLookupResult(LookupStatus.hiveLink);
        case 'unsupported':
          return const ProductLookupResult(LookupStatus.unsupported);
        default:
          return const ProductLookupResult(LookupStatus.notFound);
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[ProductLookup] $mode failed: ${e.code} ${e.message}');
      if (e.code == 'resource-exhausted') {
        return ProductLookupResult(LookupStatus.limitReached, message: e.message);
      }
      return const ProductLookupResult(LookupStatus.failed);
    } catch (e) {
      debugPrint('[ProductLookup] $mode failed: $e');
      return const ProductLookupResult(LookupStatus.failed);
    }
  }

  /// Any web link except our own hive links. Zyte decides whether the page
  /// is a product; when it is not, the user keeps what the phone read.
  static bool canFetchDetails(String url) {
    if (!looksLikeUrl(url)) return false;
    final host = Uri.parse(url.trim()).host.toLowerCase();
    return host != 'flutterapplication-77c19.web.app' &&
        host != 'www.flutterapplication-77c19.web.app';
  }

  static bool looksLikeUrl(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.contains('.');
  }
}
