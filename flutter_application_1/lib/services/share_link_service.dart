import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'firestore_service.dart';

/// Outcome of redeeming a share link.
enum ShareRedeemStatus { granted, already, disabled, invalid, error }

class ShareRedeemResult {
  final ShareRedeemStatus status;
  final String? hiveId;
  final String? ownerId;

  const ShareRedeemResult(this.status, {this.hiveId, this.ownerId});

  bool get canOpen =>
      status == ShareRedeemStatus.granted || status == ShareRedeemStatus.already;

  String get message {
    switch (status) {
      case ShareRedeemStatus.granted:
        return 'You now have access to this hive.';
      case ShareRedeemStatus.already:
        return '';
      case ShareRedeemStatus.disabled:
        return 'This link is no longer active.';
      case ShareRedeemStatus.invalid:
        return 'This link is not valid.';
      case ShareRedeemStatus.error:
        return 'Could not open that link. Please try again.';
    }
  }
}

/// Listens for incoming hive share links and redeems them.
///
/// Handles both a cold start (the app was launched by the link) and a warm one
/// (the app was already running). A link that arrives while signed out is held
/// until sign-in completes.
class ShareLinkService {
  ShareLinkService._();
  static final ShareLinkService instance = ShareLinkService._();

  final _appLinks = AppLinks();
  final FirebaseFunctions _fns =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  StreamSubscription<Uri>? _sub;
  String? _pendingShareId;

  /// Emits the share token once the app is ready to act on it. Redemption
  /// itself happens in openSharedHive() so both entry points behave identically.
  final _links = StreamController<String>.broadcast();
  Stream<String> get onShareLink => _links.stream;

  /// Set to false while signed out so links are held rather than dropped.
  bool signedIn = false;

  Future<void> init() async {
    if (_sub != null) return;
    try {
      // uriLinkStream also replays the launch URI, so getInitialLink() alone
      // would double-report it. Subscribe first and let the stream be the
      // single source; fall back to the initial link only if nothing arrives.
      _sub = _appLinks.uriLinkStream.listen(_handleUri,
          onError: (e) => debugPrint('[ShareLink] stream error: $e'));

      final initial = await _appLinks.getInitialLink();
      if (initial != null && _pendingShareId == null && !_seenFromStream) {
        _handleUri(initial);
      }
    } catch (e) {
      debugPrint('[ShareLink] init failed: $e');
    }
  }

  bool _seenFromStream = false;

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  static String? shareIdFrom(Uri uri) {
    if (uri.host != FirestoreService.shareDomain) return null;
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments.first != 'h') return null;
    final id = segments[1].trim();
    return id.isEmpty ? null : id;
  }

  void _handleUri(Uri uri) {
    final shareId = shareIdFrom(uri);
    if (shareId == null) return;
    _seenFromStream = true;
    debugPrint('[ShareLink] received $shareId');
    _pendingShareId = shareId;
    if (signedIn) _drain();
  }

  /// Called once authentication is known to be complete.
  void onSignedIn() {
    signedIn = true;
    _drain();
  }

  void _drain() {
    final shareId = _pendingShareId;
    if (shareId == null) return;
    _pendingShareId = null;
    _links.add(shareId);
  }

  Future<ShareRedeemResult> redeem(String shareId) async {
    try {
      final res = await _fns
          .httpsCallable('redeemShareLink')
          .call<Map<String, dynamic>>({'shareId': shareId});

      final data = res.data;
      final status = switch (data['status'] as String?) {
        'granted' => ShareRedeemStatus.granted,
        'already' => ShareRedeemStatus.already,
        'disabled' => ShareRedeemStatus.disabled,
        _ => ShareRedeemStatus.invalid,
      };
      return ShareRedeemResult(
        status,
        hiveId: data['hiveId'] as String?,
        ownerId: data['ownerId'] as String?,
      );
    } catch (e) {
      debugPrint('[ShareLink] redeem failed: $e');
      return const ShareRedeemResult(ShareRedeemStatus.error);
    }
  }
}
