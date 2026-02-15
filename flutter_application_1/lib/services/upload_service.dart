import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'image_storage_service.dart';

/// Represents a pending upload task.
class UploadTask {
  final String wishId;
  final String localPath;
  final String userId;
  final int attempt;

  UploadTask({
    required this.wishId,
    required this.localPath,
    required this.userId,
    this.attempt = 0,
  });
}


/// Service to handle background image uploads.
/// 
/// It maintains a queue of images that need to be uploaded to Firebase Storage.
/// Once uploaded, it updates the corresponding Firestore document with the network URL.
class UploadService extends Notifier<List<UploadTask>> {
  @override
  List<UploadTask> build() {
    return [];
  }

  bool _isUploading = false;

  /// Add a new upload task to the queue.
  void addToQueue(String wishId, File imageFile, String userId) {
    debugPrint('[UploadService] Adding to queue: Wish=$wishId, Path=${imageFile.path}');
    
    final task = UploadTask(
      wishId: wishId,
      localPath: imageFile.path,
      userId: userId,
    );
    
    state = [...state, task];
    _processQueue();
  }

  /// Process the next item in the queue.
  Future<void> _processQueue() async {
    if (_isUploading || state.isEmpty) return;

    _isUploading = true;
    final task = state.first;

    try {
      debugPrint('[UploadService] Starting upload via service for wish: ${task.wishId}');
      
      final file = File(task.localPath);
      if (!await file.exists()) {
        debugPrint('[UploadService] File not found: ${task.localPath}. Skipping.');
        _removeFromQueue(task);
        _isUploading = false;
        _processQueue(); // Process next
        return;
      }

      // 1. Compress Image
      final targetPath = '${task.localPath}_compressed.jpg';
      var fileToUpload = file;
      
      try {
        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          task.localPath,
          targetPath,
          quality: 80,
          minWidth: 1920,
          minHeight: 1080,
        );
        
        if (compressedFile != null) {
          fileToUpload = File(compressedFile.path);
          debugPrint('[UploadService] Compressed image: ${file.lengthSync()} -> ${fileToUpload.lengthSync()}');
        }
      } catch (e) {
        debugPrint('[UploadService] Compression failed, uploading original: $e');
      }

      // 2. Upload to Firebase Storage
      final downloadUrl = await ImageStorageService.uploadImage(fileToUpload, task.userId);
      
      // 3. Update Firestore Document
      await FirebaseFirestore.instance
          .collection('wishes')
          .doc(task.wishId)
          .update({'imageUrl': downloadUrl});
      
      debugPrint('[UploadService] Success! Updated wish ${task.wishId} with URL: $downloadUrl');
      
      // 4. Remove from queue and delete local files
      _removeFromQueue(task);
      
      // Clean up local files (Original & Compressed)
      try {
        if (await file.exists()) await file.delete();
        if (fileToUpload.path != file.path && await fileToUpload.exists()) {
          await fileToUpload.delete();
        }
        debugPrint('[UploadService] Deleted local cache files');
      } catch (e) {
         debugPrint('[UploadService] Failed to delete local cache files: $e');
      }

    } catch (e) {
      debugPrint('[UploadService] Upload failed for ${task.wishId}: $e');
      // Simple retry logic: move to end of queue or keep it?
      // For now, let's remove it to avoid blocking the queue forever, 
      // or we could implement a retry counter.
      // Let's retry 3 times.
      if (task.attempt < 3) {
         debugPrint('[UploadService] Retrying later...');
         _removeFromQueue(task);
         state = [...state, UploadTask(
            wishId: task.wishId,
            localPath: task.localPath,
            userId: task.userId,
            attempt: task.attempt + 1
         )];
      } else {
         debugPrint('[UploadService] Max retries reached. Giving up on ${task.wishId}');
         _removeFromQueue(task);
      }
    } finally {
      _isUploading = false;
      // Continue with next item
      _processQueue();
    }
  }

  void _removeFromQueue(UploadTask task) {
    state = state.where((t) => t != task).toList();
  }
}

final uploadServiceProvider = NotifierProvider<UploadService, List<UploadTask>>(() {
  return UploadService();
});
