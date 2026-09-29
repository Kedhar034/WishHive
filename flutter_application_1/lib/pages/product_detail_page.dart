import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_application_1/pages/full_screen_image_page.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:share_plus/share_plus.dart';

import '../models/wish_model.dart';
import '../providers/providers.dart';
import '../services/image_storage_service.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/money.dart';
import '../widgets/hive_title.dart';
import '../widgets/report_sheet.dart';
import 'create_wish_sheet.dart';

class ProductDetailPage extends ConsumerStatefulWidget {
  final String title;
  final String imageUrl;
  final String hiveId;
  final String ownerId;
  final String ownerDisplayName;
  final String? heroTag;
  final List<String> allowedEditorIds; // Friends who can add wishes to this hive

  /// The card colour key, so the header matches the card it opened from.
  final String? cardColor;

  const ProductDetailPage({
    required this.title,
    required this.imageUrl,
    required this.hiveId,
    this.ownerId = '',
    this.ownerDisplayName = '',
    this.heroTag,
    this.allowedEditorIds = const [],
    this.cardColor,
    super.key,
  });

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  bool _isGridView = false;
  bool _showConfetti = false;

  bool get _isOwner {
    final uid = ref.read(uidProvider);
    return widget.ownerId.isEmpty || widget.ownerId == uid;
  }

  bool get _canAddWish {
    final uid = ref.read(uidProvider);
    if (uid == null) return false;
    return _isOwner || widget.allowedEditorIds.contains(uid);
  }

  /// The owner, or the friend who contributed this wish. Contributors were
  /// previously locked out of editing or removing their own additions.
  bool _canModify(WishModel wish) {
    if (_isOwner) return true;
    final uid = ref.read(uidProvider);
    return uid != null && wish.addedByUid == uid;
  }

  /// Whose collection this hive's wishes live in.
  String _hiveOwnerId() {
    final uid = ref.read(uidProvider);
    return widget.ownerId.isNotEmpty ? widget.ownerId : (uid ?? '');
  }

  Future<void> _shareHive() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final link = await ref
          .read(firestoreServiceProvider)
          .ensureShareLink(widget.hiveId);

      await Share.share(
        '${widget.title} — my wishlist on WishHive\n$link',
        subject: widget.title,
      );
    } catch (e) {
      debugPrint('Share failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not create a share link.')),
      );
    }
  }

  void _showAddWishSheet() {
    final uid = ref.read(uidProvider);
    final user = ref.read(userProvider).value;
    // When a friend adds a wish to owner's hive, we pass ownerId and addedBy info
    showMaterialModalBottomSheet(
      context: context,
      expand: false,
      builder: (context) => CreateWishSheet(
        preselectedHiveId: widget.hiveId,
        friendHiveOwnerId: _isOwner ? null : widget.ownerId,
        addedByUid: _isOwner ? null : uid,
        addedByName: _isOwner ? null : (user?.displayName ?? 'A Friend'),
      ),
    );
  }

  void _showNoteViewSheet(BuildContext context, WishModel wish) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.brandBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.note_alt_outlined, 
                      color: AppTheme.brandBlue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          wish.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (wish.addedByName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              'Added by ${wish.addedByName}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              Text(
                wish.note,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 32),
              if (_isOwner) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _editWish(wish);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit Note'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _confirmDeleteWish(wish);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          foregroundColor: Colors.red,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open URL')),
        );
      }
    }
  }

  /// The cover, sized by whatever tile it is placed in rather than by a fixed
  /// height of its own.
  Widget _buildHeaderImage() {
    final path = widget.imageUrl.isNotEmpty
        ? widget.imageUrl
        : AppConstants.fallbackImage;

    if (ImageStorageService.isLocalPath(path)) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderImage(),
      );
    }
    if (ImageStorageService.isNetworkPath(path)) {
      return CachedNetworkImage(
        imageUrl: path,
        memCacheHeight: 300,
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholderImage(),
        errorWidget: (_, __, ___) => _placeholderImage(),
      );
    }
    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholderImage(),
    );
  }

  Widget _placeholderImage() {
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.85),
      child: const Center(
        child: Icon(Icons.card_giftcard_rounded,
            size: 42, color: AppTheme.brandBlue),
      ),
    );
  }

  Widget _buildWishImage(String imageUrl) {
    if (imageUrl.isEmpty) return const SizedBox.shrink();

    Widget image;
    if (ImageStorageService.isLocalPath(imageUrl)) {
      image = Image.file(
        File(imageUrl),
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _wishPlaceholder(),
      );
    } else if (ImageStorageService.isNetworkPath(imageUrl)) {
      image = CachedNetworkImage(
        imageUrl: imageUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        placeholder: (_, __) => _wishPlaceholder(),
        errorWidget: (_, __, ___) => _wishPlaceholder(),
      );
    } else {
      image = Image.asset(
        imageUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _wishPlaceholder(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: image,
    );
  }

  Widget _wishPlaceholder() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.tintSky.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.star_outline, size: 24, color: AppTheme.brandBlue),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetUid = widget.ownerId.isNotEmpty ? widget.ownerId : ref.watch(uidProvider);
    final wishesAsync = ref.watch(wishesByHiveProvider((hiveId: widget.hiveId, ownerId: targetUid!)));

    return Scaffold(
      body: wishesAsync.when(
        data: (wishes) {
          final scrollView = CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // Header panel: brand blue for your own hive, the hive tint
              // when you are looking at someone else. Every action that used
              // to live in the app bar is still here.
              SliverToBoxAdapter(
                child: _HiveHeader(
                  title: widget.title,
                  ownerDisplayName: widget.ownerDisplayName,
                  isOwner: _isOwner,
                  wishCount: wishes.length,
                  totalCost: wishes.fold<double>(0, (sum, w) => sum + w.cost),
                  accent: AppTheme.colorFor(widget.cardColor, widget.hiveId),
                  cover: Hero(
                    tag: widget.heroTag ?? 'hive-${widget.hiveId}',
                    child: Material(
                      type: MaterialType.transparency,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: _buildHeaderImage(),
                        ),
                      ),
                    ),
                  ),
                  isGridView: _isGridView,
                  onToggleView: () => setState(() => _isGridView = !_isGridView),
                  onShare: _isOwner ? _shareHive : null,
                  onDelete: _isOwner ? _confirmDeleteHive : null,
                  onReport: _isOwner
                      ? null
                      : () => ReportSheet.show(
                            context,
                            targetType: 'hive',
                            targetId: widget.hiveId,
                            targetOwnerUid: widget.ownerId,
                            targetLabel: widget.title,
                          ),
                ),
              ),

              if (wishes.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star_outline,
                            size: 64,
                            color: theme.colorScheme.primary.withValues(alpha: 0.25)),
                        const SizedBox(height: 16),
                        Text(
                          'No wishes yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        if (_isOwner) ...[
                           const SizedBox(height: 6),
                           Text(
                             'Add a wish to this hive!',
                             style: theme.textTheme.bodyMedium,
                           ),
                        ],
                      ],
                    ),
                  ),
                )
              else if (_isGridView)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final wish = wishes[index];
                        return _WishGridCard(
                          wish: wish,
                          isOwner: _isOwner,
                          onToggle: () => _handleWishToggle(wish),
                          onNoteTap: () => _showNoteViewSheet(context, wish),
                          onImageTap: wish.imageUrl.isEmpty
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FullScreenImagePage(
                                        imageUrl: wish.imageUrl,
                                        images: wish.images,
                                        heroTag: 'wish_image_${wish.id}',
                                      ),
                                    ),
                                  ),
                          onLinkTap: wish.link.isNotEmpty
                              ? () => _launchUrl(wish.link)
                              : null,
                          onEdit: _canModify(wish) ? () => _editWish(wish) : null,
                          onDelete: _canModify(wish) ? () => _confirmDeleteWish(wish) : null,
                          buildImage: _buildWishImage,
                        );
                      },
                      childCount: wishes.length,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  sliver: SliverList.separated(
                    itemCount: wishes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final wish = wishes[index];
                      final isCompleted = wish.fulfilledBy.isNotEmpty;
                      
                      return _WishTile(
                        wish: wish,
                        isCompleted: isCompleted,
                        isOwner: _isOwner,
                        onToggle: () => _handleWishToggle(wish),
                        onNoteTap: () => _showNoteViewSheet(context, wish),
                        onLinkTap: wish.link.isNotEmpty
                            ? () => _launchUrl(wish.link)
                            : null,
                        onEdit: _canModify(wish) ? () => _editWish(wish) : null,
                        onDelete: _canModify(wish) ? () => _confirmDeleteWish(wish) : null,
                        buildImage: _buildWishImage,
                      );
                    },
                  ),
                ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          );
          return Stack(
            children: [
              scrollView,
              if (_showConfetti)
                ConfettiWidget(
                  onFinished: () {
                    setState(() => _showConfetti = false);
                  },
                ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.brandBlue),
        ),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: _canAddWish
          ? FloatingActionButton(
              onPressed: _showAddWishSheet,
              backgroundColor: AppTheme.brandBlue,
              foregroundColor: Colors.white,
              elevation: 4,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Future<void> _handleWishToggle(WishModel wish) async {
    final uid = ref.read(uidProvider);
    final user = ref.read(userProvider).value; 
    
    if (uid == null || user == null) return;

    final wasCompleted = wish.fulfilledBy.isNotEmpty;

    // If owner is viewing an unseen fulfilled wish, mark it as seen
    if (_isOwner && wish.fulfilledBy.isNotEmpty && !wish.ownerSeen) {
      ref.read(firestoreServiceProvider).markWishSeen(wish.id);
    }

    // Allow owner to toggle fulfillment too (Mark as Completed)
    // Logic: 
    // - If it's done by someone else: Only that person or owner can undo it? 
    //   Actually, let's keep it simple:
    //   - If not fulfilled: Claim it.
    //   - If fulfilled by ME: Unclaim it.
    //   - If fulfilled by OTHERS: 
    //     - If I am OWNER: I can unclaim it (reset).
    //     - If I am NOT OWNER: I cannot touch it.

    try {
      await ref.read(firestoreServiceProvider).toggleWishFulfillment(
        hiveOwnerId: widget.ownerId.isNotEmpty ? widget.ownerId : uid,
        wishId: wish.id, 
        fulfillerId: uid, 
        fulfillerName: user.displayName.isNotEmpty ? user.displayName : 'A Friend',
        isOwnerOverride: _isOwner, // Pass owner status to service if needed, or handle logic here.
      );
      if (!wasCompleted) {
        setState(() {
          _showConfetti = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  void _editWish(WishModel wish) {
    showMaterialModalBottomSheet(
      context: context,
      expand: false,
      builder: (context) => CreateWishSheet(
        wishToEdit: wish,
        friendHiveOwnerId: _isOwner ? null : widget.ownerId,
      ),
    );
  }

  Future<void> _confirmDeleteWish(WishModel wish) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Wish?'),
        content: Text('Are you sure you want to delete "${wish.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = ref.read(firestoreServiceProvider);
        await service.deleteWish(wish.id, ownerId: _hiveOwnerId());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wish deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteHive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Hive?'),
        content: const Text(
            'Are you sure you want to delete this Hive?\nAll wishes inside it will also be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Hive', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (!_isOwner) return; 
        await ref.read(firestoreServiceProvider).deleteHive(widget.hiveId);
        
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hive deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete hive: $e')),
          );
        }
      }
    }
  }
}

/// The hive header.
///
/// Stats are counted from the wishes already on screen, so nothing extra is
/// read. Reserved is a count only — never which wish, and never by whom.
class _HiveHeader extends StatelessWidget {
  final String title;
  final String ownerDisplayName;
  final bool isOwner;
  final int wishCount;
  final double totalCost;
  final Color accent;
  final Widget cover;
  final bool isGridView;
  final VoidCallback onToggleView;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  const _HiveHeader({
    required this.title,
    required this.ownerDisplayName,
    required this.isOwner,
    required this.wishCount,
    required this.totalCost,
    required this.accent,
    required this.cover,
    required this.isGridView,
    required this.onToggleView,
    this.onShare,
    this.onDelete,
    this.onReport,
  });

  /// White reads on brand blue; ink reads on every card tint.
  Color get _fg => AppTheme.onColor(accent);

  Widget _circleButton(IconData icon, VoidCallback? onTap, String tooltip) {
    if (onTap == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: IconButton(
        icon: Icon(icon, size: 20, color: _fg),
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: _fg.withValues(alpha: 0.14),
          padding: const EdgeInsets.all(10),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: _fg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.money(size: 20, color: _fg)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13,
                    color: _fg.withValues(alpha: 0.75))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 8, 20, 22),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, size: 20, color: _fg),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                style: IconButton.styleFrom(
                  backgroundColor: _fg.withValues(alpha: 0.14),
                  padding: const EdgeInsets.all(10),
                ),
              ),
              const Spacer(),
              _circleButton(
                  isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  onToggleView,
                  'Toggle View'),
              _circleButton(Icons.ios_share, onShare, 'Share Hive'),
              _circleButton(Icons.delete_outline, onDelete, 'Delete Hive'),
              _circleButton(Icons.flag_outlined, onReport, 'Report Hive'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              cover,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isOwner && ownerDisplayName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '$ownerDisplayName' "'s hive",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 13,
                              color: _fg.withValues(alpha: 0.8)),
                        ),
                      ),
                    HiveTitle(title, size: 30, color: _fg),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _stat('$wishCount', wishCount == 1 ? 'wish' : 'wishes'),
              const SizedBox(width: 10),
              _stat(formatMoney(totalCost), 'total'),
            ],
          ),
        ],
      ),
    );
  }
}

class _WishTile extends StatefulWidget {
  final WishModel wish;
  final bool isCompleted; // Kept for compatibility if used, though we derive from wish
  final bool isOwner;
  final VoidCallback onToggle;
  final VoidCallback? onLinkTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Widget Function(String) buildImage;
  final VoidCallback? onNoteTap;

  const _WishTile({
    required this.wish,
    required this.isCompleted,
    required this.isOwner,
    required this.onToggle,
    required this.onLinkTap,
    required this.onEdit,
    required this.onDelete,
    required this.buildImage,
    this.onNoteTap,
  });

  @override
  State<_WishTile> createState() => _WishTileState();
}

class _WishTileState extends State<_WishTile> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      lowerBound: 0.8,
      upperBound: 1.0,
    );
    
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    // Initial check without animation
    if (widget.wish.fulfilledBy.isNotEmpty) {
      _controller.value = 1.0; 
    }
  }

  @override
  void didUpdateWidget(covariant _WishTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isFulfilled = widget.wish.fulfilledBy.isNotEmpty;
    final wasFulfilled = oldWidget.wish.fulfilledBy.isNotEmpty;

    if (isFulfilled && !wasFulfilled) {
      // Trigger pop animation
      _controller.forward(from: 0.0);
    } else if (!isFulfilled && wasFulfilled) {
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = widget.wish.fulfilledBy.isNotEmpty;

    if (widget.wish.isNote) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.rRow),
            border: Border.all(
              color: AppTheme.brandBlue.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.rRow),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onNoteTap,
                borderRadius: BorderRadius.circular(AppTheme.rRow),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppTheme.brandBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.note_alt_outlined, 
                              size: 20, 
                              color: AppTheme.brandBlue
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.wish.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                if (widget.wish.addedByName.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      'Added by ${widget.wish.addedByName}',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: Colors.grey[500],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.isOwner)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                              onSelected: (val) {
                                if (val == 'edit') widget.onEdit?.call();
                                if (val == 'delete') widget.onDelete?.call();
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.wish.note,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                          height: 1.4,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: InkWell(
          onTap: widget.onToggle, // Allow everyone to toggle (owner logic handled in callback)
          onLongPress: widget.isOwner ? widget.onEdit : null, // Edit on long press for owner
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (!widget.isOwner)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? AppTheme.success
                              : Colors.transparent,
                          border: Border.all(
                            color: isCompleted
                                ? AppTheme.success
                                : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: isCompleted
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                
                if (widget.wish.imageUrl.isNotEmpty) ...[
                   Hero(
                     tag: 'wish_image_${widget.wish.id}',
                     child: Material(
                       color: Colors.transparent,
                       child: InkWell(
                         onTap: () {
                           Navigator.push(
                             context,
                             MaterialPageRoute(
                               builder: (_) => FullScreenImagePage(
                                 imageUrl: widget.wish.imageUrl,
                                 images: widget.wish.images,
                                 heroTag: 'wish_image_${widget.wish.id}',
                               ),
                             ),
                           );
                         },
                         borderRadius: BorderRadius.circular(14),
                         child: ClipRRect(
                           borderRadius: BorderRadius.circular(14),
                           child: SizedBox(
                             width: 48,
                             height: 48,
                             child: Stack(
                               fit: StackFit.expand,
                               children: [
                                 widget.buildImage(widget.wish.imageUrl),
                                 // Signals there is more than one photo, so the
                                 // gallery is discoverable rather than hidden
                                 // behind a tap.
                                 if (widget.wish.images.length > 1)
                                   Positioned(
                                     right: 2,
                                     top: 2,
                                     child: Container(
                                       padding: const EdgeInsets.all(2),
                                       decoration: BoxDecoration(
                                         color: Colors.black54,
                                         borderRadius: BorderRadius.circular(4),
                                       ),
                                       child: const Icon(
                                         Icons.collections_outlined,
                                         size: 11,
                                         color: Colors.white,
                                       ),
                                     ),
                                   ),
                               ],
                             ),
                           ),
                         ),
                       ),
                     ),
                   ),
                   const SizedBox(width: 12),
                ],

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Notification dot for unseen fulfillment
                          if (isCompleted && !widget.wish.ownerSeen && widget.isOwner)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              widget.wish.name,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: isCompleted
                                    ? Colors.grey
                                    : theme.textTheme.bodyLarge?.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isCompleted)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            'Fulfilled',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppTheme.brandBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                      // Show who added this wish (when it was added by a friend)
                      if (widget.wish.addedByName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_outline, size: 12, color: Colors.grey[500]),
                              const SizedBox(width: 3),
                              Text(
                                'Added by ${widget.wish.addedByName}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.grey[500],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Its own hit target, so opening the link can never be
                    // mistaken for marking the wish done.
                    if (widget.wish.link.isNotEmpty && widget.onLinkTap != null)
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, size: 20),
                        color: theme.colorScheme.primary,
                        tooltip: 'Open link',
                        onPressed: widget.onLinkTap,
                        visualDensity: VisualDensity.compact,
                      ),
                    if (widget.isOwner) ...[
                      if (isCompleted)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.check_circle,
                              size: 20, color: AppTheme.success),
                        ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                        onSelected: (val) {
                          if (val == 'edit') widget.onEdit?.call();
                          if (val == 'delete') widget.onDelete?.call();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WishGridCard extends StatelessWidget {
  final WishModel wish;
  final bool isOwner;
  final VoidCallback onToggle;
  final VoidCallback onNoteTap;
  final VoidCallback? onLinkTap;

  /// Opens the image viewer. The picture is the obvious thing to tap, so it
  /// gets its own target rather than toggling the wish like the rest of the
  /// tile does.
  final VoidCallback? onImageTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Widget Function(String) buildImage;

  const _WishGridCard({
    required this.wish,
    required this.isOwner,
    required this.onToggle,
    required this.onNoteTap,
    required this.onLinkTap,
    this.onImageTap,
    required this.onEdit,
    required this.onDelete,
    required this.buildImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = wish.fulfilledBy.isNotEmpty;

    if (wish.isNote) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.rRow),
          border: Border.all(
            color: AppTheme.brandBlue.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rRow),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onNoteTap,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.brandBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.note_alt_outlined, 
                            size: 16, 
                            color: AppTheme.brandBlue
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            wish.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isOwner)
                          _buildMenu(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(
                        wish.note,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                          height: 1.3,
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (wish.addedByName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'By ${wish.addedByName}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.rRow),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.rRow),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            onLongPress: isOwner ? onEdit : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 11,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (wish.imageUrl.isNotEmpty)
                        GestureDetector(
                          onTap: onImageTap,
                          child: buildImage(wish.imageUrl),
                        )
                      else
                        Container(
                          color: AppTheme.tintSky.withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.shopping_bag_outlined, 
                            size: 32, 
                            color: AppTheme.brandBlue
                          ),
                        ),
                      
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 40,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.25),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),

                      if (isCompleted)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check, size: 10, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Claimed',
                                  style: TextStyle(
                                    fontSize: 9, 
                                    color: Colors.white, 
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (isOwner)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: _buildMenu(iconColor: Colors.white),
                        ),
                    ],
                  ),
                ),
                
                Expanded(
                  flex: 9,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              wish.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                decoration: isCompleted ? TextDecoration.lineThrough : null,
                                color: isCompleted ? Colors.grey : theme.colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (wish.addedByName.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  'For you by ${wish.addedByName}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.grey[500],
                                    fontSize: 9,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (wish.cost > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '₹${wish.cost.toStringAsFixed(0)}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else
                              const SizedBox.shrink(),

                            if (wish.link.isNotEmpty && onLinkTap != null)
                              IconButton(
                                icon: const Icon(Icons.open_in_new_rounded),
                                iconSize: 16,
                                color: theme.colorScheme.primary,
                                tooltip: 'Open link',
                                onPressed: onLinkTap,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                // A real 36px target, rather than a 22px dot.
                                constraints: const BoxConstraints(
                                    minWidth: 36, minHeight: 36),
                                style: IconButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary
                                      .withValues(alpha: 0.10),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu({Color? iconColor}) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 18, color: iconColor ?? Colors.grey),
      padding: EdgeInsets.zero,
      onSelected: (val) {
        if (val == 'edit') onEdit?.call();
        if (val == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
      ],
    );
  }
}

class ConfettiWidget extends StatefulWidget {
  final VoidCallback onFinished;

  const ConfettiWidget({
    super.key,
    required this.onFinished,
  });

  @override
  State<ConfettiWidget> createState() => _ConfettiWidgetState();
}

class _ConfettiWidgetState extends State<ConfettiWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished();
      }
    });

    _particles = List.generate(100, (index) => _ConfettiParticle());
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              progress: _controller.value,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _ConfettiParticle {
  late double x;
  late double y;
  late double size;
  late Color color;
  late double speedX;
  late double speedY;
  late double gravity;
  late double angle;
  late double spinSpeed;
  late _ConfettiShape shape;

  static final List<Color> _colors = [
    const Color(0xFFFF4081), // Pink
    const Color(0xFF00E676), // Green
    const Color(0xFF00B0FF), // Blue
    const Color(0xFFFFD700), // Gold
    const Color(0xFFFF3D00), // Orange/Red
    const Color(0xFFE040FB), // Purple
  ];

  _ConfettiParticle() {
    final random = math.Random();
    
    // Spawns from the center-ish area of the screen to form an explosion
    x = 0.5;
    y = 0.45;
    
    // Spread in all directions (360 degrees)
    final angleRad = random.nextDouble() * 2 * math.pi;
    final speed = 12.0 + random.nextDouble() * 22.0;
    speedX = math.cos(angleRad) * speed;
    speedY = math.sin(angleRad) * speed - 12.0; // Give it a strong upward eject

    size = 5.0 + random.nextDouble() * 6.0;
    color = _colors[random.nextInt(_colors.length)];
    gravity = 0.6 + random.nextDouble() * 0.4;
    angle = random.nextDouble() * 360.0;
    spinSpeed = (random.nextDouble() - 0.5) * 12.0;
    shape = _ConfettiShape.values[random.nextInt(_ConfettiShape.values.length)];
  }

  void update(double progress, double width, double height) {
    // Math scaling: Convert progress [0.0, 1.0] to visual physics steps
    final t = progress * 2.0 * 15.0;
    
    final startX = width * 0.5;
    final startY = height * 0.45;
    
    x = startX + speedX * t;
    y = startY + speedY * t + 0.5 * gravity * t * t;
    angle += spinSpeed;
  }
}

enum _ConfettiShape { circle, square, triangle }

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final particle in particles) {
      particle.update(progress, size.width, size.height);

      if (particle.x < -20 || particle.x > size.width + 20 || particle.y > size.height + 20) {
        continue;
      }

      paint.color = particle.color;

      canvas.save();
      canvas.translate(particle.x, particle.y);
      canvas.rotate(particle.angle * math.pi / 180.0);

      final halfSize = particle.size / 2;

      switch (particle.shape) {
        case _ConfettiShape.circle:
          canvas.drawCircle(Offset.zero, halfSize, paint);
          break;
        case _ConfettiShape.square:
          canvas.drawRect(
            Rect.fromLTRB(-halfSize, -halfSize, halfSize, halfSize),
            paint,
          );
          break;
        case _ConfettiShape.triangle:
          final path = Path()
            ..moveTo(0, -halfSize)
            ..lineTo(halfSize, halfSize)
            ..lineTo(-halfSize, halfSize)
            ..close();
          canvas.drawPath(path, paint);
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
