import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/firestore_service.dart';
import 'package:flutter_application_1/widgets/shimmer_loading.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_application_1/pages/full_screen_image_page.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

import '../models/wish_model.dart';
import '../providers/providers.dart';
import '../services/image_storage_service.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'create_wish_sheet.dart';

class ProductDetailPage extends ConsumerStatefulWidget {
  final String title;
  final String imageUrl;
  final String hiveId;
  final String ownerId;
  final String ownerDisplayName;
  final String? heroTag;
  final List<String> allowedEditorIds; // Friends who can add wishes to this hive

  const ProductDetailPage({
    required this.title,
    required this.imageUrl,
    required this.hiveId,
    this.ownerId = '',
    this.ownerDisplayName = '',
    this.heroTag,
    this.allowedEditorIds = const [],
    super.key,
  });

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  bool get _isOwner {
    final uid = ref.read(uidProvider);
    return widget.ownerId.isEmpty || widget.ownerId == uid;
  }

  bool get _canAddWish {
    final uid = ref.read(uidProvider);
    if (uid == null) return false;
    return _isOwner || widget.allowedEditorIds.contains(uid);
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

  Widget _buildHeaderImage() {
    final path = widget.imageUrl.isNotEmpty
        ? widget.imageUrl
        : AppConstants.fallbackImage;

    Widget image;
    if (ImageStorageService.isLocalPath(path)) {
      image = Image.file(
        File(path),
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderImage(),
      );
    } else if (ImageStorageService.isNetworkPath(path)) {
      image = CachedNetworkImage(
        imageUrl: path,
        width: double.infinity,
        height: 200,
        memCacheHeight: 500, // Optimize memory for header
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholderImage(),
        errorWidget: (_, __, ___) => _placeholderImage(),
      );
    } else {
      image = Image.asset(
        path,
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderImage(),
      );
    }

    return image;
  }

  Widget _placeholderImage() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentHoney.withValues(alpha: 0.4),
            AppTheme.primaryAmber.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: const Icon(Icons.hive, size: 64, color: AppTheme.primaryAmber),
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
        color: AppTheme.accentHoney.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.star_outline, size: 24, color: AppTheme.primaryAmber),
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
          return CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                stretch: true,
                // Keep scaffold bg when collapsed; transparent when expanded (image shows)
                backgroundColor: theme.scaffoldBackgroundColor,
                // Always white text/icons since header sits over the dark scrim
                foregroundColor: Colors.white,
                title: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(blurRadius: 6, color: Colors.black54),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.sort_rounded, size: 28, color: Colors.white),
                    onPressed: () {},
                    tooltip: 'Menu',
                  ),
                  if (_isOwner)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white),
                      onPressed: _confirmDeleteHive,
                      tooltip: 'Delete Hive',
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Hero(
                    tag: widget.heroTag ?? 'hive-${widget.hiveId}',
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildHeaderImage(),
                          // Dark scrim at top so back button + title remain readable
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 110,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.55),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  stretchModes: const [StretchMode.zoomBackground],
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Wishes', style: theme.textTheme.titleLarge),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${wishes.length}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!_isOwner && widget.ownerDisplayName.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Owned by ${widget.ownerDisplayName}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
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
                        onLinkTap: wish.link.isNotEmpty
                            ? () => _launchUrl(wish.link)
                            : null,
                        onEdit: _isOwner ? () => _editWish(wish) : null,
                        onDelete: _isOwner ? () => _confirmDeleteWish(wish) : null,
                        buildImage: _buildWishImage,
                      );
                    },
                  ),
                ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryAmber),
        ),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: _canAddWish
          ? FloatingActionButton(
              onPressed: _showAddWishSheet,
              backgroundColor: AppTheme.primaryAmber,
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
      builder: (context) => CreateWishSheet(wishToEdit: wish),
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
        await service.deleteWish(wish.id);
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

class _WishTile extends StatefulWidget {
  final WishModel wish;
  final bool isCompleted; // Kept for compatibility if used, though we derive from wish
  final bool isOwner;
  final VoidCallback onToggle;
  final VoidCallback? onLinkTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final Widget Function(String) buildImage;

  const _WishTile({
    required this.wish,
    required this.isCompleted,
    required this.isOwner,
    required this.onToggle,
    required this.onLinkTap,
    required this.onEdit,
    required this.onDelete,
    required this.buildImage,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: widget.onToggle, // Allow everyone to toggle (owner logic handled in callback)
          onLongPress: widget.isOwner ? widget.onEdit : null, // Edit on long press for owner
          borderRadius: BorderRadius.circular(12),
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
                                 heroTag: 'wish_image_${widget.wish.id}',
                               ),
                             ),
                           );
                         },
                         borderRadius: BorderRadius.circular(8),
                         child: ClipRRect(
                           borderRadius: BorderRadius.circular(8),
                           child: SizedBox(
                             width: 48, 
                             height: 48,
                             child: widget.buildImage(widget.wish.imageUrl),
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
                              color: AppTheme.primaryAmber,
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
                      // Link Button
                      if (widget.wish.link.isNotEmpty)
                         Padding(
                           padding: const EdgeInsets.only(top: 4),
                           child: GestureDetector(
                             onTap: widget.onLinkTap,
                             child: Row(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                 Icon(
                                   Icons.link, 
                                   size: 16, 
                                   color: isCompleted ? Colors.grey : theme.colorScheme.primary
                                 ),
                                 const SizedBox(width: 4),
                                 Flexible(
                                   child: Text(
                                     'View Link',
                                     style: theme.textTheme.bodySmall?.copyWith(
                                       color: isCompleted ? Colors.grey : theme.colorScheme.primary,
                                       fontWeight: FontWeight.w600,
                                       decoration: isCompleted ? TextDecoration.lineThrough : null,
                                     ),
                                     maxLines: 1,
                                     overflow: TextOverflow.ellipsis,
                                   ),
                                 ),
                               ],
                             ),
                           ),
                         ),
                    ],
                  ),
                ),
                
                if (widget.isOwner)
                   Row(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       if (isCompleted)
                         Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.check_circle, size: 20, color: AppTheme.success),
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
                   )
                else if (widget.onLinkTap != null && !isCompleted && widget.wish.link.isNotEmpty)
                  // Show link button for non-owners if we didn't show it inline (redundant but safe)
                  // Actually, let's just stick to inline.
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
