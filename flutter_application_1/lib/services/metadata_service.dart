import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import 'package:metadata_fetch/metadata_fetch.dart';

class LinkMetadata {
  final String title;
  final String? imageUrl;
  final String url;
  final String? description;

  /// Every image found, best first. [imageUrl] is always the first entry when
  /// there is one, so existing single-image callers keep working unchanged.
  final List<String> images;

  final double? price;
  final String? currency;
  final double? rating;
  final int? ratingCount;
  final String? brand;

  LinkMetadata({
    required this.title,
    this.imageUrl,
    required this.url,
    this.description,
    this.images = const [],
    this.price,
    this.currency,
    this.rating,
    this.ratingCount,
    this.brand,
  });

  bool get hasPrice => price != null && price! > 0;
}

class MetadataService {
  /// Fetches metadata from the given [url].
  /// Returns a [LinkMetadata] object if successful, or null if it fails.
  static Future<LinkMetadata?> extract(String url) async {
    try {
      // A desktop User-Agent, deliberately. Amazon answers a mobile one with
      // a stripped page that has no og tags, no #productTitle and no
      // schema.org block, so a shared link came back named after the site.
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-IN,en;q=0.9',
        },
      );

      if (response.statusCode != 200) {
        return LinkMetadata(title: 'Shared Link', url: url, imageUrl: null);
      }

      final document = MetadataFetch.responseToDocument(response);
      if (document == null) {
        return LinkMetadata(title: '', url: url, imageUrl: null);
      }

      return parseDocument(document, url);
    } catch (e) {
      debugPrint('MetadataService.extract failed: $e');
      return LinkMetadata(title: '', url: url, imageUrl: null);
    }
  }

  /// Split out from [extract] so the parsing can be exercised directly in tests
  /// without a network request.
  static LinkMetadata parseDocument(dom.Document document, String url) {
    // metadata_fetch throws on malformed ld+json rather than skipping it, so a
    // single broken block on a page would otherwise take down the whole
    // extraction and leave the wish with no title or image at all.
    Metadata? data;
    try {
      data = MetadataParser.parse(document);
    } catch (e) {
      debugPrint('MetadataParser failed, using manual fallbacks: $e');
    }
    final html = document.outerHtml;

    // Most retailers embed a full schema.org/Product block, which carries price,
    // rating, brand and the whole image list. Meta tags only ever carry a title
    // and one image, which is why price never appeared before.
    final product = _firstProduct(html);

    String title = _cleanTitle(
      _stringOf(product?['name']) ??
          _retailerTitle(document) ??
          data?.title ??
          _metaTitle(html) ??
          data?.url ??
          '',
    );

    final images = <String>[];
    void addImage(String? candidate) {
      final fixed = _absolute(candidate, url);
      if (fixed != null && !_isTrackingPixel(fixed) && !images.contains(fixed)) {
        images.add(fixed);
      }
    }

    for (final img in _imageList(product?['image'])) {
      addImage(img);
    }
    // Before the generic fallbacks: Amazon keeps its gallery in an attribute,
    // and the generic pass would otherwise settle for the first <img> on the
    // page, which is a thumbnail or a banner.
    for (final img in _amazonImages(document)) {
      addImage(img);
    }
    for (final img in _metaImages(html)) {
      addImage(img);
    }
    addImage(data?.image);

    final offer = _firstOffer(product);
    final rating = _asMap(product?['aggregateRating']);

    // Only the best image is kept. Extra images came from whatever else the
    // page happened to carry — related products, banners — which is what made
    // a wish show a picture of something it was not.
    final best = images.isEmpty ? <String>[] : [images.first];

    return LinkMetadata(
      title: title.trim(),
      imageUrl: best.isEmpty ? null : best.first,
      images: best,
      url: url,
      description: _stringOf(product?['description']) ?? data?.description,
      price: _parseNumber(offer?['price'] ?? offer?['lowPrice']),
      currency: _stringOf(offer?['priceCurrency']),
      rating: _parseNumber(rating?['ratingValue']),
      ratingCount:
          _parseNumber(rating?['reviewCount'] ?? rating?['ratingCount'])?.round(),
      brand: _brandName(product?['brand']),
    );
  }

  /// Product titles from retailers that publish no usable metadata.
  static String? _retailerTitle(dom.Document document) {
    for (final selector in const [
      '#productTitle', // Amazon
      '#title span',
      'h1.pdp-title',  // Myntra
      'h1.pdp-name',
      'span.B_NuCI',   // Flipkart
      'h1[itemprop="name"]',
    ]) {
      final text = document.querySelector(selector)?.text.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  /// Amazon keeps its gallery in a data-a-dynamic-image attribute, whose value
  /// is a JSON map of url to [width, height]. The widest is the one worth
  /// keeping.
  static Iterable<String> _amazonImages(dom.Document document) sync* {
    for (final selector in const ['#landingImage', '[data-a-dynamic-image]']) {
      final raw = document
          .querySelector(selector)
          ?.attributes['data-a-dynamic-image'];
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;

        var bestUrl = '';
        var bestWidth = -1;
        decoded.forEach((key, value) {
          final width = (value is List && value.isNotEmpty && value.first is num)
              ? (value.first as num).toInt()
              : 0;
          if (width > bestWidth) {
            bestWidth = width;
            bestUrl = key.toString();
          }
        });
        if (bestUrl.isNotEmpty) yield bestUrl;
      } catch (_) {
        // Malformed attribute: fall through to whatever else was found.
      }
    }

    final src = document.querySelector('#landingImage')?.attributes['src'];
    if (src != null && src.isNotEmpty) yield src;
  }

  // ─── schema.org/Product ───────────────────────────────────────────────────

  static final RegExp _ldJsonBlock = RegExp(
    r'<script[^>]*type=["' "'" r']application/ld\+json["' "'" r'][^>]*>([\s\S]*?)</script>',
    caseSensitive: false,
  );

  /// Finds the first schema.org Product in any ld+json block on the page.
  /// Handles a bare object, a top-level array and an @graph wrapper.
  static Map<String, dynamic>? _firstProduct(String html) {
    for (final match in _ldJsonBlock.allMatches(html)) {
      final raw = match.group(1);
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        final found = _searchForProduct(decoded);
        if (found != null) return found;
      } catch (_) {
        // A malformed block on the page must not break the whole extraction.
      }
    }
    return null;
  }

  static Map<String, dynamic>? _searchForProduct(dynamic node, [int depth = 0]) {
    if (depth > 6) return null;

    if (node is List) {
      for (final item in node) {
        final found = _searchForProduct(item, depth + 1);
        if (found != null) return found;
      }
      return null;
    }

    if (node is Map) {
      final map = node.cast<String, dynamic>();
      if (_isType(map['@type'], 'Product')) return map;
      for (final key in const ['@graph', 'mainEntity', 'itemListElement']) {
        final found = _searchForProduct(map[key], depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  static bool _isType(dynamic type, String wanted) {
    if (type is String) return type.toLowerCase().contains(wanted.toLowerCase());
    if (type is List) return type.any((t) => _isType(t, wanted));
    return false;
  }

  static Map<String, dynamic>? _firstOffer(Map<String, dynamic>? product) {
    final offers = product?['offers'];
    if (offers is List && offers.isNotEmpty) return _asMap(offers.first);
    return _asMap(offers);
  }

  static Map<String, dynamic>? _asMap(dynamic value) =>
      value is Map ? value.cast<String, dynamic>() : null;

  static String? _stringOf(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static String? _brandName(dynamic brand) {
    if (brand is String) return _stringOf(brand);
    final map = _asMap(brand);
    return map == null ? null : _stringOf(map['name']);
  }

  /// schema.org allows `image` to be a string, a list, or an ImageObject.
  static List<String> _imageList(dynamic value) {
    if (value == null) return const [];
    if (value is String) return [value];
    if (value is List) {
      return value.expand<String>(_imageList).toList();
    }
    final map = _asMap(value);
    if (map != null) {
      final url = _stringOf(map['url']) ?? _stringOf(map['contentUrl']);
      if (url != null) return [url];
    }
    return const [];
  }

  /// Handles "₹1,299.00", "1299.00", 1299 and "INR 1299".
  static double? _parseNumber(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is! String) return null;
    final cleaned = value.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    // Guard against strings that collapse to several dots.
    final parts = cleaned.split('.');
    final normalised =
        parts.length <= 2 ? cleaned : '${parts.first}.${parts[1]}';
    return double.tryParse(normalised);
  }

  // ─── meta-tag fallbacks (unchanged behaviour) ─────────────────────────────

  static String? _meta(String html, String property) {
    final regExp = RegExp(
      '<meta[^>]*property=["\']$property["\'][^>]*content=["\']([^"\']+)["\']',
      caseSensitive: false,
    );
    return regExp.firstMatch(html)?.group(1);
  }

  static String? _itemProp(String html, String property) {
    final regExp = RegExp(
      '<meta[^>]*itemprop=["\']$property["\'][^>]*content=["\']([^"\']+)["\']',
      caseSensitive: false,
    );
    return regExp.firstMatch(html)?.group(1);
  }

  /// Used when MetadataParser bails out, so a page with one broken JSON-LD
  /// block still yields a usable title instead of an empty wish.
  static String? _metaTitle(String html) {
    return _meta(html, 'og:title') ??
        _meta(html, 'twitter:title') ??
        _itemProp(html, 'name') ??
        RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
            .firstMatch(html)
            ?.group(1)
            ?.trim();
  }

  static List<String> _metaImages(String html) {
    final found = <String?>[
      _meta(html, 'og:image'),
      _meta(html, 'og:image:secure_url'),
      _meta(html, 'twitter:image'),
      _meta(html, 'twitter:image:src'),
      RegExp(
        '<link[^>]*rel=["\']image_src["\'][^>]*href=["\']([^"\']+)["\']',
        caseSensitive: false,
      ).firstMatch(html)?.group(1),
      _itemProp(html, 'image'),
      RegExp(
        '<link[^>]*rel=["\']preload["\'][^>]*as=["\']image["\'][^>]*href=["\']([^"\']+)["\']',
        caseSensitive: false,
      ).firstMatch(html)?.group(1),
    ];
    return found.whereType<String>().toList();
  }

  static const _titleSuffixes = [
    ' | Amazon.in',
    ' : Amazon.in',
    ' : Amazon.com',
    ' | Blinkit',
  ];

  static String _cleanTitle(String title) {
    var result = title;
    for (final suffix in _titleSuffixes) {
      if (result.endsWith(suffix)) {
        result = result.substring(0, result.length - suffix.length);
      }
    }
    return result;
  }

  static bool _isTrackingPixel(String url) =>
      url.contains('fls-eu.amazon') ||
      url.contains('pixel') ||
      url.contains('doubleclick');

  static String? _absolute(String? candidate, String pageUrl) {
    if (candidate == null || candidate.trim().isEmpty) return null;
    final value = candidate.trim();
    if (value.startsWith('http')) return value;

    final uri = Uri.tryParse(pageUrl);
    if (uri == null) return null;
    if (value.startsWith('//')) return '${uri.scheme}:$value';
    if (value.startsWith('/')) return '${uri.scheme}://${uri.host}$value';
    return '${uri.scheme}://${uri.host}/$value';
  }
}
