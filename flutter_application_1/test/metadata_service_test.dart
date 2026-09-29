// Link metadata extraction.
//
//   flutter test
//
// Parsing is exercised directly against HTML fixtures — no network, so these
// stay fast and cannot be broken by a site redesign.

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_application_1/services/metadata_service.dart';

LinkMetadata parse(String body, {String url = 'https://shop.example.com/p/123'}) =>
    MetadataService.parseDocument(html_parser.parse(body), url);

String ldJson(String json) =>
    '<html><head><script type="application/ld+json">$json</script></head><body></body></html>';

void main() {
  group('schema.org Product', () {
    test('reads name, price, currency, rating and brand', () {
      final m = parse(ldJson('''
        {
          "@context": "https://schema.org",
          "@type": "Product",
          "name": "Running Shoes",
          "brand": { "@type": "Brand", "name": "Nova" },
          "image": "https://cdn.example.com/a.jpg",
          "offers": { "@type": "Offer", "price": "2499.00", "priceCurrency": "INR" },
          "aggregateRating": { "ratingValue": "4.3", "reviewCount": "128" }
        }
      '''));

      expect(m.title, 'Running Shoes');
      expect(m.price, 2499.0);
      expect(m.currency, 'INR');
      expect(m.rating, 4.3);
      expect(m.ratingCount, 128);
      expect(m.brand, 'Nova');
      expect(m.hasPrice, isTrue);
    });

    test('collects the full image list, first one as primary', () {
      final m = parse(ldJson('''
        {
          "@type": "Product",
          "name": "Kurta",
          "image": [
            "https://cdn.example.com/1.jpg",
            "https://cdn.example.com/2.jpg",
            "https://cdn.example.com/3.jpg"
          ]
        }
      '''));

      expect(m.images.length, 3);
      expect(m.imageUrl, 'https://cdn.example.com/1.jpg');
    });

    test('handles an ImageObject instead of a plain URL', () {
      final m = parse(ldJson('''
        {
          "@type": "Product",
          "name": "Lamp",
          "image": { "@type": "ImageObject", "url": "https://cdn.example.com/x.jpg" }
        }
      '''));
      expect(m.imageUrl, 'https://cdn.example.com/x.jpg');
    });

    test('finds a Product nested in @graph', () {
      final m = parse(ldJson('''
        {
          "@context": "https://schema.org",
          "@graph": [
            { "@type": "WebSite", "name": "Shop" },
            { "@type": "Product", "name": "Nested Item",
              "offers": { "price": 199, "priceCurrency": "INR" } }
          ]
        }
      '''));
      expect(m.title, 'Nested Item');
      expect(m.price, 199.0);
    });

    test('finds a Product in a top-level array', () {
      final m = parse(ldJson('''
        [
          { "@type": "BreadcrumbList" },
          { "@type": "Product", "name": "Array Item", "offers": { "price": "50" } }
        ]
      '''));
      expect(m.title, 'Array Item');
      expect(m.price, 50.0);
    });

    test('takes the first of several offers', () {
      final m = parse(ldJson('''
        {
          "@type": "Product",
          "name": "Multi",
          "offers": [
            { "price": "100", "priceCurrency": "INR" },
            { "price": "200", "priceCurrency": "INR" }
          ]
        }
      '''));
      expect(m.price, 100.0);
    });

    test('parses a formatted price string', () {
      final m = parse(ldJson('''
        { "@type": "Product", "name": "Formatted",
          "offers": { "price": "₹1,299.50" } }
      '''));
      expect(m.price, 1299.5);
    });

    test('malformed JSON-LD does not break extraction', () {
      final m = parse('''
        <html><head>
          <script type="application/ld+json">{ this is not json }</script>
          <meta property="og:title" content="Fallback Title">
          <meta property="og:image" content="https://cdn.example.com/f.jpg">
        </head><body></body></html>
      ''');
      expect(m.title, 'Fallback Title');
      expect(m.imageUrl, 'https://cdn.example.com/f.jpg');
    });
  });

  group('meta-tag fallback still works', () {
    test('reads Open Graph when there is no JSON-LD', () {
      final m = parse('''
        <html><head>
          <meta property="og:title" content="OG Product">
          <meta property="og:image" content="https://cdn.example.com/og.jpg">
          <meta property="og:description" content="Nice thing">
        </head><body></body></html>
      ''');
      expect(m.title, 'OG Product');
      expect(m.imageUrl, 'https://cdn.example.com/og.jpg');
      expect(m.price, isNull);
    });

    test('falls back to twitter:image', () {
      final m = parse('''
        <html><head>
          <meta property="og:title" content="Twitter Only">
          <meta property="twitter:image" content="https://cdn.example.com/t.jpg">
        </head><body></body></html>
      ''');
      expect(m.imageUrl, 'https://cdn.example.com/t.jpg');
    });

    test('strips the Amazon title suffix', () {
      final m = parse('''
        <html><head>
          <meta property="og:title" content="Wireless Earbuds : Amazon.in">
        </head><body></body></html>
      ''');
      expect(m.title, 'Wireless Earbuds');
    });

    test('resolves protocol-relative and root-relative image URLs', () {
      expect(
        parse('<html><head><meta property="og:image" content="//cdn.example.com/p.jpg"></head></html>').imageUrl,
        'https://cdn.example.com/p.jpg',
      );
      expect(
        parse('<html><head><meta property="og:image" content="/img/p.jpg"></head></html>').imageUrl,
        'https://shop.example.com/img/p.jpg',
      );
    });

    // These masquerade as product images and would show as a blank card.
    test('rejects tracking pixels', () {
      expect(
        parse('<html><head><meta property="og:image" content="https://fls-eu.amazon.com/1.gif"></head></html>').imageUrl,
        isNull,
      );
      expect(
        parse('<html><head><meta property="og:image" content="https://x.com/pixel.gif"></head></html>').imageUrl,
        isNull,
      );
    });

    test('an empty page yields empty values rather than throwing', () {
      final m = parse('<html><head></head><body></body></html>');
      expect(m.title, '');
      expect(m.imageUrl, isNull);
      expect(m.images, isEmpty);
      expect(m.hasPrice, isFalse);
    });
  });

  group('image list', () {
    test('deduplicates across JSON-LD and meta tags', () {
      final m = parse('''
        <html><head>
          <script type="application/ld+json">
            { "@type": "Product", "name": "Dup",
              "image": ["https://cdn.example.com/a.jpg"] }
          </script>
          <meta property="og:image" content="https://cdn.example.com/a.jpg">
          <meta property="twitter:image" content="https://cdn.example.com/b.jpg">
        </head><body></body></html>
      ''');
      expect(m.images, ['https://cdn.example.com/a.jpg', 'https://cdn.example.com/b.jpg']);
    });

    test('imageUrl always matches the first entry', () {
      final m = parse(ldJson('''
        { "@type": "Product", "name": "X",
          "image": ["https://cdn.example.com/1.jpg", "https://cdn.example.com/2.jpg"] }
      '''));
      expect(m.imageUrl, m.images.first);
    });
  });
}
