import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/constants/app_constants.dart';

/// A reusable image picker widget that supports camera, gallery, and default images.
class ImagePickerWidget extends StatelessWidget {
  final File? selectedImage;
  final String? initialImageUrl;
  final double size;
  final VoidCallback onImagePicked;

  const ImagePickerWidget({
    super.key,
    required this.selectedImage,
    required this.onImagePicked,
    this.initialImageUrl,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onImagePicked,
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            width: 2,
          ),
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        ),
        child: _buildImageContent(),
      ),
    );
  }

  Widget _buildImageContent() {
    if (selectedImage != null) {
      if (selectedImage!.path.startsWith('assets/')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            selectedImage!.path,
            fit: BoxFit.cover,
            width: size,
            height: size,
            errorBuilder: (_, __, ___) => _buildPlaceholder(),
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          selectedImage!,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        ),
      );
    } else if (initialImageUrl != null && initialImageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: initialImageUrl!.startsWith('assets/')
            ? Image.asset(
                initialImageUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              )
            : Image.network(
                initialImageUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              ),
      );
    } else {
      return _buildPlaceholder();
    }
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_a_photo_outlined,
          size: size * 0.3,
          color: Colors.grey, // Context not available in helper, using generic
        ),
        const SizedBox(height: 4),
        const Text(
          'Add Photo',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  /// Static helper to show source selection and pick an image.
  /// Returns the picked File or null if cancelled.
  static Future<File?> pickImage(
    BuildContext context, {
    List<String> defaultImages = const [],
  }) async {
    // Show modal bottom sheet that returns the RESULT directly (File? or String? path)
    // We return 'camera', 'gallery', or the actual path string if a default is picked.
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true, // Allow it to be taller
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Choose Image',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                
                // Camera / Gallery Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildOption(context, Icons.camera_alt, 'Camera', () {
                       Navigator.pop(context, 'camera');
                    }),
                    _buildOption(context, Icons.photo_library, 'Gallery', () {
                       Navigator.pop(context, 'gallery');
                    }),
                  ],
                ),
                
                if (defaultImages.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Or select default',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Default Images Grid
                  Flexible(
                    child: GridView.builder(
                      controller: scrollController,
                      shrinkWrap: true,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: defaultImages.length,
                      itemBuilder: (context, index) {
                        final img = defaultImages[index];
                        return GestureDetector(
                          onTap: () => Navigator.pop(context, img),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                img, 
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Icon(Icons.error),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ]
              ],
            ),
          );
        },
      ),
    );

    if (result == null) return null;

    if (result == 'camera') {
        final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
        return picked != null ? File(picked.path) : null;
    } else if (result == 'gallery') {
        final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
        return picked != null ? File(picked.path) : null;
    } else if (result is String) {
        // It's a path from default images
        return File(result); // We return it as a File object, but logic upstream must handle assets
        // Wait, ImagePickerWidget.pickImage returns Future<File?>.
        // If we select an asset path, we can't easily return a File object that works for 'asset'.
        // BUT, the caller (CreateWishSheet) expects a File?.
        // CreateWishSheet handles assets specially if _selectedImage path starts with 'assets/'.
        // So `File('assets/images/c1.jpeg')` is valid as a holder of the path string.
        return File(result);
    }
    
    return null;
  }

  static Widget _buildOption(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).primaryColor),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
