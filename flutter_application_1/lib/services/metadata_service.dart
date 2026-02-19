import 'package:http/http.dart' as http;
import 'package:metadata_fetch/metadata_fetch.dart';

class LinkMetadata {
  final String title;
  final String? imageUrl;
  final String url;
  final String? description;

  LinkMetadata({
    required this.title,
    this.imageUrl,
    required this.url,
    this.description,
  });
}

class MetadataService {
  /// Fetches metadata from the given [url].
  /// Returns a [LinkMetadata] object if successful, or null if it fails.
  static Future<LinkMetadata?> extract(String url) async {
    try {
      // 1. Prepare a browser-like User-Agent to avoid being blocked (e.g. by Amazon)
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      );

      if (response.statusCode != 200) {
        // If failed, try basic extract provided by the package as fallback
        // or just return plain url data
        return LinkMetadata(title: 'Shared Link', url: url, imageUrl: null);
      }

      // 2. Parse the response
      final document = MetadataFetch.responseToDocument(response);
      if (document == null) {
         return LinkMetadata(title: '', url: url, imageUrl: null);
      }

      // 3. Extract Metadata
      final data = MetadataParser.parse(document);
      
      // 4. Smart Title Cleanup (Amazon fix)
      String title = data.title ?? data.url ?? '';
      
      // Remove common suffixes
      final suffixes = [' | Amazon.in', ' : Amazon.in', ' : Amazon.com', ' | Blinkit'];
      for (final suffix in suffixes) {
        if (title.endsWith(suffix)) {
          title = title.substring(0, title.length - suffix.length);
        }
      }

      // 5. Image Fallback - Maximum Robustness
      String? image = data.image;
      
      if (image == null || image.isEmpty) {
        // Manual fallback: sometimes library misses specific tags or specific structures
        // We parse the raw HTML body for common image meta tags
        try {
          final html = document.outerHtml;
          
          // Helper to extract content from meta tags
          String? getMeta(String property) {
            final RegExp regExp = RegExp(
              '<meta[^>]*property=["\']$property["\'][^>]*content=["\']([^"\']+)["\']',
              caseSensitive: false,
            );
            final match = regExp.firstMatch(html);
            return match?.group(1);
          }

          // Helper to extract content from itemprop (Schema.org)
           String? getItemProp(String property) {
            final RegExp regExp = RegExp(
              '<meta[^>]*itemprop=["\']$property["\'][^>]*content=["\']([^"\']+)["\']',
              caseSensitive: false,
            );
            final match = regExp.firstMatch(html);
            return match?.group(1);
          }
          
          // Try OG Image again manually
          image = getMeta('og:image');
          image ??= getMeta('og:image:secure_url'); // HTTPS variant
          
          // Try Twitter Image
          image ??= getMeta('twitter:image');
          image ??= getMeta('twitter:image:src');

          // Try Link Rel Image Src
          if (image == null) {
             final RegExp linkRegExp = RegExp(
              '<link[^>]*rel=["\']image_src["\'][^>]*href=["\']([^"\']+)["\']',
              caseSensitive: false,
            );
             final match = linkRegExp.firstMatch(html);
             image = match?.group(1);
          }

          // Try Itemprop Image (Schema.org)
          if (image == null) {
            image = getItemProp('image');
          }
          
          // Try Preload as Image (often the main LCP image)
          if (image == null) {
            final RegExp preloadRegExp = RegExp(
              '<link[^>]*rel=["\']preload["\'][^>]*as=["\']image["\'][^>]*href=["\']([^"\']+)["\']',
              caseSensitive: false,
            );
            final match = preloadRegExp.firstMatch(html);
            image = match?.group(1);
          }

          // Fix relative URLs
          if (image != null && !image!.startsWith('http')) {
             final uri = Uri.parse(url);
             if (image!.startsWith('//')) {
               image = '${uri.scheme}:$image';
             } else if (image!.startsWith('/')) {
               image = '${uri.scheme}://${uri.host}$image';
             } else {
               image = '${uri.scheme}://${uri.host}/$image';
             }
          }

          // Try Link Rel Image Src
          if (image == null) {
             final RegExp linkRegExp = RegExp(
              '<link[^>]*rel=["\']image_src["\'][^>]*href=["\']([^"\']+)["\']',
              caseSensitive: false,
            );
             final match = linkRegExp.firstMatch(html);
             image = match?.group(1);
          }

          // Try Itemprop Image (Schema.org)
          if (image == null) {
            final RegExp itemPropRegExp = RegExp(
              '<meta[^>]*itemprop=["\']image["\'][^>]*content=["\']([^"\']+)["\']',
              caseSensitive: false,
            );
            final match = itemPropRegExp.firstMatch(html);
            image = match?.group(1);
          }
          
          // Try Preload as Image (often the main LCP image)
          if (image == null) {
            final RegExp preloadRegExp = RegExp(
              '<link[^>]*rel=["\']preload["\'][^>]*as=["\']image["\'][^>]*href=["\']([^"\']+)["\']',
              caseSensitive: false,
            );
            final match = preloadRegExp.firstMatch(html);
            image = match?.group(1);
          }

          // Fix relative URLs
          if (image != null && !image.startsWith('http')) {
             final uri = Uri.parse(url);
             if (image.startsWith('//')) {
               image = '${uri.scheme}:$image';
             } else if (image.startsWith('/')) {
               image = '${uri.scheme}://${uri.host}$image';
             } else {
               image = '${uri.scheme}://${uri.host}/$image';
             }
          }
          } catch (e) {
           // ignore manual parse errors
          }
      }

      // Filter out invalid Amazon/Ad tracking pixels that masquerade as images
      if (image != null) {
          if (image!.contains('fls-eu.amazon') || 
              image!.contains('pixel') || 
              image!.contains('doubleclick')) {
             image = null;
          }
      }
      
      return LinkMetadata(
        title: title.trim(),
        imageUrl: image,
        url: url,
        description: data.description,
      );
    } catch (e) {
      // Return basic data if fetch fails but we have a URL
      return LinkMetadata(title: '', url: url, imageUrl: null);
    }
  }
}
