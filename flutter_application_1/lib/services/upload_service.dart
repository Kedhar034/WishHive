import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'image_storage_service.dart';

/// What a pending upload belongs to, which decides the Storage folder and the
/// document that receives the download URL.
enum UploadKind { wish, hiveCover }

/// Represents a pending upload task.
class UploadTask {
  final String docId;
  final String localPath;
  final String userId;
  final UploadKind kind;
  final int attempt;

  UploadTask({
    required this.docId,
    required this.localPath,
    required this.userId,
    this.kind = UploadKind.wish,
    this.attempt = 0,
  });

  Map<String, dynamic> toJson() => {
        'docId': docId,
        'localPath': localPath,
        'userId': userId,
        'kind': kind.name,
        'attempt': attempt,
      };

  // Tasks persisted before hive covers existed carry `wishId` and no kind.
  factory UploadTask.fromJson(Map<String, dynamic> j) => UploadTask(
        docId: (j['docId'] ?? j['wishId']) as String,
        localPath: j['localPath'] as String,
        userId: j['userId'] as String,
        kind: j['kind'] == UploadKind.hiveCover.name
            ? UploadKind.hiveCover
            : UploadKind.wish,
        attempt: (j['attempt'] as num?)?.toInt() ?? 0,
      );

  UploadTask retried() => UploadTask(
        docId: docId,
        localPath: localPath,
        userId: userId,
        kind: kind,
        attempt: attempt + 1,
      );

  DocumentReference<Map<String, dynamic>> get docRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection(kind == UploadKind.hiveCover ? 'hives' : 'wishes')
          .doc(docId);

  String get storageFolder => kind == UploadKind.hiveCover ? 'hives' : 'wishes';
}


/// Service to handle background image uploads.
/// 
/// It maintains a queue of images that need to be uploaded to Firebase Storage.
/// Once uploaded, it updates the corresponding Firestore document with the network URL.
class UploadService extends Notifier<List<UploadTask>> {
  static const String _prefsKey = 'pending_uploads';

  @override
  List<UploadTask> build() {
    _restore();
    return [];
  }

  bool _isUploading = false;

  /// The queue used to live only in memory, so killing the app stranded any
  /// in-flight upload and left the wish pointing at a local device path that
  /// nobody else could resolve.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? const [];
      if (raw.isEmpty) return;

      final restored = raw
          .map((s) => UploadTask.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .where((t) => File(t.localPath).existsSync())
          .toList();

      if (restored.isEmpty) {
        await prefs.remove(_prefsKey);
        return;
      }
      debugPrint('[UploadService] Restored ${restored.length} pending upload(s)');
      state = [...state, ...restored];
      _processQueue();
    } catch (e) {
      debugPrint('[UploadService] Restore failed: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setStringList(
          _prefsKey,
          state.map((t) => jsonEncode(t.toJson())).toList(),
        );
      }
    } catch (e) {
      debugPrint('[UploadService] Persist failed: $e');
    }
  }

  /// Add a new upload task to the queue.
  void addToQueue(String wishId, File imageFile, String userId) {
    _enqueue(UploadTask(docId: wishId, localPath: imageFile.path, userId: userId));
  }

  /// Queues a hive cover. The hive document keeps the local path until the
  /// upload lands, so the owner sees the picture immediately.
  void addHiveCover(String hiveId, File imageFile, String userId) {
    final queued = state.any((t) =>
        t.kind == UploadKind.hiveCover &&
        t.docId == hiveId &&
        t.localPath == imageFile.path);
    if (queued) return;
    _enqueue(UploadTask(
      docId: hiveId,
      localPath: imageFile.path,
      userId: userId,
      kind: UploadKind.hiveCover,
    ));
  }

  final Set<String> _adoptedFor = {};

  /// Covers picked before hive covers were uploaded were saved as a path on the
  /// owner's phone, which no friend and no link preview can load. Any such file
  /// still on this device is queued once per sign-in.
  Future<void> adoptLocalHiveCovers(String userId) async {
    if (!_adoptedFor.add(userId)) return;
    try {
      final hives = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('hives')
          .get();
      for (final doc in hives.docs) {
        final path = doc.data()['imageUrl'] as String? ?? '';
        if (!ImageStorageService.isLocalPath(path)) continue;
        if (!File(path).existsSync()) continue;
        addHiveCover(doc.id, File(path), userId);
      }
    } catch (e) {
      debugPrint('[UploadService] Adopting local hive covers failed: $e');
    }
  }

  void _enqueue(UploadTask task) {
    debugPrint('[UploadService] Adding to queue: ${task.kind.name}=${task.docId}, Path=${task.localPath}');
    state = [...state, task];
    _persist();
    _processQueue();
  }

  /// Process the next item in the queue.
  Future<void> _processQueue() async {
    if (_isUploading || state.isEmpty) return;

    _isUploading = true;
    final task = state.first;

    try {
      debugPrint('[UploadService] Starting upload for ${task.kind.name}: ${task.docId}');
      
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
      final downloadUrl = await ImageStorageService.uploadImage(
        fileToUpload,
        task.userId,
        folder: task.storageFolder,
      );

      // 3. Update Firestore Document
      if (task.kind == UploadKind.hiveCover) {
        // The owner may have picked another cover, or removed it, while this
        // one was uploading. Only replace the path this task was queued for.
        final current = await task.docRef.get();
        if (current.exists && current.data()?['imageUrl'] == task.localPath) {
          await task.docRef.update({'imageUrl': downloadUrl});
        }
      } else {
        await task.docRef.update({'imageUrl': downloadUrl});
      }

      debugPrint('[UploadService] Success! Updated ${task.kind.name} ${task.docId} with URL: $downloadUrl');

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
      debugPrint('[UploadService] Upload failed for ${task.docId}: $e');
      // Simple retry logic: move to end of queue or keep it?
      // For now, let's remove it to avoid blocking the queue forever, 
      // or we could implement a retry counter.
      // Let's retry 3 times.
      if (task.attempt < 3) {
         debugPrint('[UploadService] Retrying later...');
         _removeFromQueue(task);
         state = [...state, task.retried()];
         _persist();
         // Back off so a persistent failure does not spin the queue.
         await Future.delayed(Duration(seconds: 2 << task.attempt));
      } else {
         debugPrint('[UploadService] Max retries reached. Giving up on ${task.docId}');
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
    _persist();
  }
}

final uploadServiceProvider = NotifierProvider<UploadService, List<UploadTask>>(() {
  return UploadService();
});
