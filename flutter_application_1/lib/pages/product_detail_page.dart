import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
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

  const ProductDetailPage({
    required this.title,
    required this.imageUrl,
    required this.hiveId,
    this.ownerId = '',
    this.ownerDisplayName = '',
    super.key,
  });

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  bool get _isOwner {
    final uid = ref.read(uidProvider);
    return widget.ownerId.isEmpty || widget.ownerId == uid;
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    // Start content fade-in after Hero settles
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
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
      image = Image.network(
        path,
        width: double.infinity,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderImage(),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: image,
    );
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
        borderRadius: BorderRadius.circular(16),
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
      image = Image.network(
        imageUrl,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _wishPlaceholder(),
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
    final wishesStream = ref.watch(firestoreServiceProvider).wishesStream(targetUid!, widget.hiveId);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: StreamBuilder<List<WishModel>>(
        stream: wishesStream,
        builder: (context, snapshot) {
          final wishes = snapshot.data ?? [];
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          final error = snapshot.error;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                stretch: true,
                backgroundColor: AppTheme.surfaceWhite,
                foregroundColor: AppTheme.textPrimary,
                title: Text(widget.title),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.sort_rounded, size: 28, color: AppTheme.textPrimary),
                    onPressed: () {
                      // TODO: Implement menu action
                    },
                    tooltip: 'Menu',
                  ),
                  if (_isOwner)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: _confirmDeleteHive,
                      tooltip: 'Delete Hive',
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Hero(
                      tag: 'hive-${widget.hiveId}',
                      child: _buildHeaderImage(),
                    ),
                  ),
                  stretchModes: const [StretchMode.zoomBackground],
                ),
              ),

              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnim,
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
              ),

              if (isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryAmber),
                  ),
                )
              else if (error != null)
                SliverFillRemaining(
                  child: Center(child: Text('Error: $error')),
                )
              else if (wishes.isEmpty)
                SliverFillRemaining(
                  child: FadeTransition(
                    opacity: _fadeAnim,
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
                      
                      return FadeTransition(
                        opacity: _fadeAnim,
                        child: _WishTile(
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
                        ),
                      );
                    },
                  ),
                ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleWishToggle(WishModel wish) async {
    final uid = ref.read(uidProvider);
    final user = ref.read(userProvider).value; 
    
    if (uid == null || user == null) return;

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
        fulfillerName: user.displayName,
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

class _WishTile extends StatelessWidget {
  final WishModel wish;
  final bool isCompleted;
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: isCompleted
            ? Colors.grey.shade50
            : AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCompleted
              ? Colors.grey.shade200
              : AppTheme.divider,
          width: 1,
        ),
        boxShadow: isCompleted
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            GestureDetector(
              onTap: onToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
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
            const SizedBox(width: 10),

            if (wish.imageUrl.isNotEmpty) ...[
              buildImage(wish.imageUrl),
              const SizedBox(width: 10),
            ],

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wish.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                      color: isCompleted ? Colors.grey : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (wish.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      wish.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isCompleted
                            ? Colors.grey
                            : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (wish.cost > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '₹${wish.cost.toStringAsFixed(2)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isCompleted
                            ? Colors.grey
                            : AppTheme.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (isCompleted)
                     Padding(
                       padding: const EdgeInsets.only(top: 2.0),
                       child: Text(
                         'Fulfilled by ${wish.fulfilledByName}',
                         style: theme.textTheme.labelSmall?.copyWith(
                           color: AppTheme.primaryAmber,
                           fontWeight: FontWeight.bold,
                         ),
                       ),
                     ),
                ],
              ),
            ),

            if (onLinkTap != null)
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                color: theme.colorScheme.primary,
                onPressed: onLinkTap,
                tooltip: 'Open link',
                visualDensity: VisualDensity.compact,
              ),
            if (isOwner) ...[
              IconButton(
                icon: Icon(Icons.edit_outlined,
                    size: 20, color: theme.colorScheme.primary),
                onPressed: onEdit,
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: Colors.red.shade300),
                onPressed: onDelete,
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
