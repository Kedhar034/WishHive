import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/money.dart';
import '../models/wish_model.dart';
import '../providers/providers.dart';
import '../services/firestore_service.dart';
import '../services/image_storage_service.dart';
import '../services/product_lookup_service.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/fetch_details_chip.dart';
import 'full_screen_image_page.dart';

/// Everything about one wish, opened by tapping it in a hive.
///
/// Tapping a wish used to mark it fulfilled, so there was nowhere to see its
/// details, check the price again, or reach Edit without the menu. Marking it
/// fulfilled now has its own control here and on the row.
class WishDetailSheet extends ConsumerStatefulWidget {
  final WishModel wish;
  final String hiveOwnerId;
  final bool canModify;
  final void Function(WishModel wish) onToggle;
  final void Function(WishModel wish) onEdit;
  final void Function(WishModel wish) onDelete;
  final void Function(String url) onOpenLink;

  const WishDetailSheet({
    super.key,
    required this.wish,
    required this.hiveOwnerId,
    required this.canModify,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenLink,
  });

  static Future<void> show(
    BuildContext context, {
    required WishModel wish,
    required String hiveOwnerId,
    required bool canModify,
    required void Function(WishModel wish) onToggle,
    required void Function(WishModel wish) onEdit,
    required void Function(WishModel wish) onDelete,
    required void Function(String url) onOpenLink,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WishDetailSheet(
        wish: wish,
        hiveOwnerId: hiveOwnerId,
        canModify: canModify,
        onToggle: onToggle,
        onEdit: onEdit,
        onDelete: onDelete,
        onOpenLink: onOpenLink,
      ),
    );
  }

  @override
  ConsumerState<WishDetailSheet> createState() => _WishDetailSheetState();
}

class _WishDetailSheetState extends ConsumerState<WishDetailSheet> {
  bool _fetching = false;
  bool _gaveUp = false;

  /// A price checked by someone who may not change the wish, shown to them
  /// alone and never saved.
  FetchedProduct? _checkedForViewer;

  /// Live from the hive's stream, so a claim, an edit or a refreshed price
  /// shows up here without reopening the sheet.
  WishModel _current() {
    final wishes = ref
        .watch(wishesByHiveProvider(
            (hiveId: widget.wish.hiveId, ownerId: widget.hiveOwnerId)))
        .value;
    return wishes?.firstWhere(
          (w) => w.id == widget.wish.id,
          orElse: () => widget.wish,
        ) ??
        widget.wish;
  }

  bool _hasPhoto(WishModel wish) =>
      wish.imageUrl.isNotEmpty && !ImageStorageService.isAssetPath(wish.imageUrl);

  Future<void> _fetch(WishModel wish) async {
    setState(() => _fetching = true);
    final result = await ProductLookupService.fetch(wish.link);
    if (!mounted) return;
    setState(() => _fetching = false);

    if (result.status == LookupStatus.limitReached) {
      CustomSnackBar.showError(
          context, result.message ?? 'Daily limit reached. Try again tomorrow.');
      return;
    }
    final product = result.product;
    if (!result.isFound || product == null) {
      setState(() => _gaveUp = true);
      CustomSnackBar.showError(
          context, "Couldn't get details from this store right now.");
      return;
    }

    if (!widget.canModify) {
      setState(() => _checkedForViewer = product);
      return;
    }

    final needsPhoto = !_hasPhoto(wish);
    try {
      await FirestoreService().applyFetchedDetails(
        ownerId: widget.hiveOwnerId,
        wishId: wish.id,
        price: product.hasPrice ? product.price : null,
        priceFetchedAt: product.fetchedAt,
        imageUrl: needsPhoto ? product.mainImage : null,
        images: needsPhoto ? product.images : null,
      );
    } catch (e) {
      if (mounted) CustomSnackBar.showError(context, 'Could not save the new details.');
      return;
    }
    if (!mounted) return;

    if (!product.hasPrice) {
      setState(() => _gaveUp = true);
      CustomSnackBar.showError(context, 'The store did not show a price right now.');
    } else if (wish.cost > 0 && (product.price! - wish.cost).abs() >= 1) {
      CustomSnackBar.showSuccess(context,
          'Price is now ${formatMoney(product.price!)} (was ${formatMoney(wish.cost)}).');
    } else {
      CustomSnackBar.showSuccess(
          context, 'Price checked: ${formatMoney(product.price!)}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wish = _current();
    final completed = wish.fulfilledBy.isNotEmpty;
    final canFetch = ProductLookupService.canFetchDetails(wish.link);
    final missing = wish.cost <= 0 || !_hasPhoto(wish);
    final stale = isPriceStale(wish.priceFetchedAt);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 24 + MediaQuery.of(context).padding.bottom),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (wish.imageUrl.isNotEmpty) _photo(context, wish),
            const SizedBox(height: 16),
            Text(
              wish.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                decoration: completed ? TextDecoration.lineThrough : null,
                color: completed ? Colors.grey : null,
              ),
            ),
            if (wish.subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(wish.subtitle, style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: 14),
            _priceBlock(theme, wish),
            if (canFetch && wish.link.isNotEmpty && !_gaveUp && (missing || stale || _fetching))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FetchDetailsChip(
                    label: missing
                        ? (wish.cost <= 0 && !_hasPhoto(wish)
                            ? 'Get price & photo'
                            : wish.cost <= 0
                                ? 'Get price'
                                : 'Get photo')
                        : "Check today's price",
                    icon: missing ? Icons.auto_awesome : Icons.refresh_rounded,
                    hint: missing
                        ? "Some details couldn't be read when this was added."
                        : 'Prices change. This one is from ${formatPriceDate(wish.priceFetchedAt!)}.',
                    loading: _fetching,
                    onTap: () => _fetch(wish),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (wish.storeName.isNotEmpty) _fact(theme, Icons.storefront_outlined, wish.storeName),
                if (wish.quantity > 1) _fact(theme, Icons.numbers, 'Qty ${wish.quantity}'),
                if (wish.date != null)
                  _fact(theme, Icons.calendar_month_outlined, 'For ${formatPriceDate(wish.date!)}'),
                if (wish.addedByName.isNotEmpty)
                  _fact(theme, Icons.person_outline, 'Added by ${wish.addedByName}'),
                if (completed) _fact(theme, Icons.check_circle, 'Fulfilled', color: AppTheme.success),
              ],
            ),
            if (wish.note.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(wish.note, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
            ],
            const SizedBox(height: 24),
            if (wish.link.isNotEmpty)
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => widget.onOpenLink(wish.buyLink),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(wish.storeName.isNotEmpty
                      ? 'Buy on ${wish.storeName}'
                      : 'Open link'),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => widget.onToggle(wish),
                icon: Icon(completed ? Icons.undo_rounded : Icons.check_circle_outline),
                label: Text(completed ? 'Mark as not fulfilled' : 'Mark as fulfilled'),
              ),
            ),
            if (widget.canModify) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onEdit(wish);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDelete(wish);
                      },
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _priceBlock(ThemeData theme, WishModel wish) {
    final viewer = _checkedForViewer;
    if (wish.cost <= 0 && viewer == null) {
      return Text('No price added',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wish.cost > 0)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(formatMoney(wish.cost),
                  style: AppTheme.money(size: 26, color: theme.colorScheme.onSurface)),
              if (wish.priceFetchedAt != null) ...[
                const SizedBox(width: 8),
                Text('as of ${formatPriceDate(wish.priceFetchedAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
              ],
            ],
          ),
        if (viewer != null && viewer.hasPrice)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Today: ${formatMoney(viewer.price!)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.brandBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _fact(ThemeData theme, IconData icon, String text, {Color? color}) {
    final c = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(text, style: theme.textTheme.labelMedium?.copyWith(color: c)),
        ],
      ),
    );
  }

  Widget _photo(BuildContext context, WishModel wish) {
    final path = wish.imageUrl;
    final Widget image;
    if (ImageStorageService.isLocalPath(path)) {
      image = Image.file(File(path), fit: BoxFit.contain);
    } else if (ImageStorageService.isNetworkPath(path)) {
      image = CachedNetworkImage(
        imageUrl: path,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported_outlined),
      );
    } else {
      image = Image.asset(path, fit: BoxFit.cover);
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FullScreenImagePage(
            imageUrl: wish.imageUrl,
            images: wish.images,
            heroTag: 'wish_detail_${wish.id}',
          ),
        ),
      ),
      child: Hero(
        tag: 'wish_detail_${wish.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 220,
            color: Colors.white,
            alignment: Alignment.center,
            child: image,
          ),
        ),
      ),
    );
  }
}
