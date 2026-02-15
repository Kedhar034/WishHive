import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Service for persisting user-picked images to the device filesystem.
///
/// Images are stored inside the app's documents directory under 'beehive_images/'.
/// Each image gets a unique filename to avoid collisions.
class ImageStorageService {
  static const String _imageDir = 'beehive_images';
  static const _uuid = Uuid();

  /// Save an image file to the app's document directory.
  /// Returns the absolute path of the saved image.
  static Future<String> saveImage(File imageFile) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${appDir.path}/$_imageDir');

      // Create directory if it doesn't exist
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }

      // Generate unique filename preserving the original extension
      final extension = imageFile.path.split('.').last.toLowerCase();
      final fileName = '${_uuid.v4()}.$extension';
      final savedPath = '${imageDir.path}/$fileName';

      // Copy the image to our app directory
      await imageFile.copy(savedPath);

      debugPrint('Image saved to: $savedPath');
      return savedPath;
    } catch (e) {
      debugPrint('Error saving image: $e');
      rethrow;
    }
  }

  /// Uploads an image to Firebase Storage and returns the download URL.
  /// 
  /// Storage Path: users/{userId}/wishes/{uuid}.{ext}
  static Future<String> uploadImage(File imageFile, String userId) async {
    try {
      final extension = imageFile.path.split('.').last.toLowerCase();
      final fileName = '${_uuid.v4()}.$extension';
      
      final ref = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(userId)
          .child('wishes')
          .child(fileName);

      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('Image uploaded to: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      rethrow;
    }
  }

  /// Compresses the image and uploads it to Firebase Storage.
  static Future<String> compressAndUploadImage(File imageFile, String userId) async {
    File fileToUpload = imageFile;
    // Attempt compression
    try {
      final targetPath = '${imageFile.path}_compressed.jpg';
      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        imageFile.path,
        targetPath,
        quality: 80,
        minWidth: 1080,
        minHeight: 1080,
      );
      
      if (compressedFile != null) {
        fileToUpload = File(compressedFile.path);
      }
    } catch (e) {
      debugPrint('Compression failed, uploading original: $e');
    }

    try {
      final url = await uploadImage(fileToUpload, userId);
      // Clean up compressed file if it's different
      if (fileToUpload.path != imageFile.path && await fileToUpload.exists()) {
        await fileToUpload.delete();
      }
      return url;
    } catch (e) {
      rethrow;
    }
  }

  /// Delete an image from the filesystem by its path.
  static Future<void> deleteImage(String imagePath) async {
    try {
      if (imagePath.isEmpty) return;

      // Only delete files in our image directory
      if (!imagePath.contains(_imageDir)) return;

      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('Image deleted: $imagePath');
      }
    } catch (e) {
      debugPrint('Error deleting image: $e');
    }
  }

  /// Check if an image path is a local filesystem path (not an asset or URL).
  static bool isLocalPath(String path) {
    if (path.isEmpty) return false;
    return !path.startsWith('assets/') &&
        !path.startsWith('http://') &&
        !path.startsWith('https://');
  }

  /// Check if an image path is an asset path.
  static bool isAssetPath(String path) {
    return path.startsWith('assets/');
  }

  /// Check if an image path is a network URL.
  static bool isNetworkPath(String path) {
    return path.startsWith('http://') || path.startsWith('https://');
  }

  /// Check if a local image file exists.
  static Future<bool> imageExists(String path) async {
    if (!isLocalPath(path)) return false;
    return File(path).exists();
  }
}
