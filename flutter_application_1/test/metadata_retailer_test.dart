// Retailer extraction, against the page shapes the real sites serve.
//
// Two failures this guards:
//   Amazon publishes no og tags and no schema.org block. Its title lives in
//   #productTitle and its gallery in a data-a-dynamic-image attribute, so a
//   shared link used to come through named after the site with no picture.
//
//   Myntra puts an Organization block first and the Product block second. A
//   parser that reads only the first ld+json script finds nothing and falls
//   back to og:image, which on Myntra is an auto-cropped thumbnail.

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_application_1/services/metadata_service.dart';

const _amazon = '''
<html><head><title>Apple iPhone 15</title></head><body>
  <span id="productTitle">  Apple iPhone 15 (128 GB) - Black  </span>
  <img id="landingImage" src="https://m.media-amazon.com/images/I/small.jpg"
       data-a-dynamic-image='{"https://m.media-amazon.com/images/I/a._SX342_.jpg":[342,342],"https://m.media-amazon.com/images/I/a._SX679_.jpg":[679,679],"https://m.media-amazon.com/images/I/a._SX466_.jpg":[466,466]}'>
</body></html>
''';

const _myntra = '''
<html><head>
  <meta property="og:title" content="Buy HRX Tee - Apparel for Men">
  <meta property="og:image" content="https://assets.myntassets.com/h_200,w_200,c_fill,g_auto/thumb.jpg">
  <script type="application/ld+json">{"@type":"Organization","name":"Myntra"}</script>
  <script type="application/ld+json">{"@type":"Product","name":"HRX by Hrithik Roshan Men Yellow T-shirt",
    "image":"https://assets.myntassets.com/h_1440,q_100,w_1080/full.jpg",
    "offers":{"@type":"Offer","price":"304","priceCurrency":"INR"}}</script>
</head><body></body></html>
''';

void main() {
  group('Amazon', () {
    final m = MetadataService.parseDocument(
        html_parser.parse(_amazon), 'https://www.amazon.in/dp/B0CHX1W1XY');

    test('takes the product title, not the page title', () {
      expect(m.title, 'Apple iPhone 15 (128 GB) - Black');
    });

    test('takes the widest image from the gallery attribute', () {
      expect(m.imageUrl, contains('_SX679_'));
    });
  });

  group('Myntra', () {
    final m = MetadataService.parseDocument(
        html_parser.parse(_myntra), 'https://www.myntra.com/x/1/buy');

    test('reads the Product block even though it is not the first', () {
      expect(m.title, 'HRX by Hrithik Roshan Men Yellow T-shirt');
    });

    test('prefers the full image over the og thumbnail', () {
      expect(m.imageUrl, contains('full.jpg'));
      expect(m.imageUrl, isNot(contains('thumb.jpg')));
    });

    test('picks up the price', () {
      expect(m.price, 304);
      expect(m.currency, 'INR');
    });
  });

  test('only one image is kept', () {
    for (final page in [_amazon, _myntra]) {
      final m = MetadataService.parseDocument(
          html_parser.parse(page), 'https://example.com/p');
      expect(m.images.length, lessThanOrEqualTo(1));
      if (m.imageUrl != null) expect(m.images.single, m.imageUrl);
    }
  });

  test('a page with nothing usable does not throw', () {
    final m = MetadataService.parseDocument(
        html_parser.parse('<html><body>hi</body></html>'),
        'https://example.com/p');
    expect(m.images, isEmpty);
    expect(m.imageUrl, isNull);
  });
}
