import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/hive_model.dart';
import '../pages/product_detail_page.dart';
import '../providers/providers.dart';
import 'share_link_service.dart';

// A single tap can reach the app more than once: app_links reports the launch
// URI through both getInitialLink() and uriLinkStream, and receive_sharing_intent
// picks up the same VIEW intent. Guarding here covers every combination, since
// both entry points funnel through openSharedHive().
String? _inFlightShareId;
String? _lastHandledShareId;
DateTime? _lastHandledAt;

const Duration _dedupeWindow = Duration(seconds: 8);

bool _shouldSkip(String shareId) {
  if (_inFlightShareId == shareId) return true;
  final at = _lastHandledAt;
  return _lastHandledShareId == shareId &&
      at != null &&
      DateTime.now().difference(at) < _dedupeWindow;
}

/// Redeem a hive share link, open the hive, then offer to connect with the
/// owner.
///
/// Shared by both entry points: tapping the link (App Links) and sharing it
/// into the app (SEND intent). Hive access and friendship stay separate — the
/// link grants the first, the user chooses the second.
Future<void> openSharedHive(
  BuildContext context,
  WidgetRef ref,
  String shareId,
) async {
  if (_shouldSkip(shareId)) {
    debugPrint('[ShareLink] ignoring duplicate open for $shareId');
    return;
  }
  _inFlightShareId = shareId;

  try {
    await _open(context, ref, shareId);
  } finally {
    _inFlightShareId = null;
    _lastHandledShareId = shareId;
    _lastHandledAt = DateTime.now();
  }
}

Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  String shareId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final result = await ShareLinkService.instance.redeem(shareId);

  // Access could not be granted — usually the owner turned the link off. Say so
  // plainly and offer the route that does work, rather than dropping the user
  // back on the home screen with nothing.
  if (!result.canOpen) {
    if (result.ownerId != null && context.mounted) {
      await _explainNoAccess(context, ref, result.ownerId!);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
    }
    return;
  }
  if (result.hiveId == null) {
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
    return;
  }

  final doc =
      await FirebaseFirestore.instance.doc('hives/${result.hiveId}').get();
  if (!doc.exists) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That hive is no longer available.')),
    );
    return;
  }
  final hive = HiveModel.fromFirestore(doc);

  if (!context.mounted) return;
  navigator.push(
    MaterialPageRoute(
      builder: (_) => ProductDetailPage(
        hiveId: hive.id,
        title: hive.title,
        imageUrl: hive.imageUrl,
        ownerId: hive.ownerId,
        ownerDisplayName: hive.ownerDisplayName,
        allowedEditorIds: hive.allowedEditorIds,
      ),
    ),
  );

  // Offered on top of the hive rather than after the user backs out of it,
  // which read as the prompt arriving late. Non-blocking, so it never gets in
  // the way of the thing they actually opened.
  if (result.ownerId == null) return;
  await Future<void>.delayed(const Duration(milliseconds: 700));
  _offerFriendRequest(messenger, ref, result.ownerId!, hive.ownerDisplayName);
}

void _offerFriendRequest(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  String ownerId,
  String ownerName,
) {
  final me = ref.read(userProvider).value;
  if (me == null || me.uid == ownerId) return;
  if (me.friends.any((f) => f.uid == ownerId)) return;
  if (me.friendRequestsSent.contains(ownerId)) return;

  final name = ownerName.isNotEmpty ? ownerName : 'them';

  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      content: Text('Also see the hives $name shares with friends?'),
      action: SnackBarAction(
        label: 'ADD FRIEND',
        textColor: AppTheme.primaryAmber,
        onPressed: () async {
          try {
            await ref.read(firestoreServiceProvider).sendFriendRequest(ownerId);
            messenger.showSnackBar(
              SnackBar(content: Text('Request sent to $name.')),
            );
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not send request: $e')),
            );
          }
        },
      ),
    ),
  );
}

/// The link no longer grants access. Explain why and offer to connect, so the
/// user has a way forward instead of a dead end.
Future<void> _explainNoAccess(
  BuildContext context,
  WidgetRef ref,
  String ownerId,
) async {
  final profile =
      await ref.read(firestoreServiceProvider).getPublicProfile(ownerId);
  if (!context.mounted) return;

  final name = profile?.displayName.isNotEmpty == true
      ? profile!.displayName
      : 'This person';
  final me = ref.read(userProvider).value;
  final alreadyFriends = me?.friends.any((f) => f.uid == ownerId) ?? false;
  final alreadySent = me?.friendRequestsSent.contains(ownerId) ?? false;

  final messenger = ScaffoldMessenger.of(context);

  if (alreadyFriends || alreadySent || me?.uid == ownerId) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          alreadySent
              ? 'This link is no longer active. Your friend request to $name is still pending.'
              : 'This link is no longer active.',
        ),
      ),
    );
    return;
  }

  final send = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('This hive is private'),
      content: Text(
        'The share link is no longer active, so you cannot open this hive.\n\n'
        'It is not public — only $name decides who sees it. Send a friend '
        'request and you will see the hives they share with friends.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Send request'),
        ),
      ],
    ),
  );
  if (send != true) return;

  try {
    await ref.read(firestoreServiceProvider).sendFriendRequest(ownerId);
    messenger.showSnackBar(SnackBar(content: Text('Request sent to $name.')));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not send request: $e')),
    );
  }
}
