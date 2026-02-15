import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/image_storage_service.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';

/// Reusable widget to display a hive as a card.
/// Supports local filesystem images, asset images, and network images.
class HiveCard extends StatelessWidget {
  final String title;
  final int items;
  final double price;
  final String imageUrl;
  final String? heroTag;
  final String? ownerName; // Added
  final bool isCompact; // Added for horizontal slider

  const HiveCard({
    super.key,
    required this.title,
    required this.items,
    required this.price,
    required this.imageUrl,
    this.heroTag,
    this.ownerName,
    this.isCompact = false,
  });

  Widget _buildImage() {
    final path = imageUrl.isNotEmpty ? imageUrl : AppConstants.fallbackImage;

    Widget image;
    if (ImageStorageService.isLocalPath(path)) {
      image = Image.file(
        File(path),
        height: isCompact ? 120 : 100,
        width: isCompact ? double.infinity : 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackImage(),
      );
    } else if (ImageStorageService.isNetworkPath(path)) {
      image = CachedNetworkImage(
        imageUrl: path,
        height: isCompact ? 120 : 100,
        width: isCompact ? double.infinity : 100,
        memCacheHeight: (isCompact ? 120 : 100) * 2, // 2x for retina
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _fallbackImage(),
        placeholder: (_, __) => _fallbackImage(),
      );
    } else {
      image = Image.asset(
        path,
        height: isCompact ? 120 : 100,
        width: isCompact ? double.infinity : 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackImage(),
      );
    }

    Widget imageWidget = ClipRRect(
      borderRadius: isCompact 
          ? const BorderRadius.vertical(top: Radius.circular(16))
          : BorderRadius.circular(12),
      child: image,
    );

    // Wrap in Hero if tag provided
    if (heroTag != null) {
      imageWidget = Hero(
        tag: heroTag!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _fallbackImage() {
    return Container(
      height: isCompact ? 120 : 100,
      width: isCompact ? double.infinity : 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentHoney.withValues(alpha: 0.4),
            AppTheme.primaryAmber.withValues(alpha: 0.3),
          ],
        ),
        // Match border radius of parent
        borderRadius: isCompact 
          ? const BorderRadius.vertical(top: Radius.circular(16))
          : BorderRadius.circular(12),
      ),
      child: const Icon(Icons.hive, size: 40, color: AppTheme.primaryAmber),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isCompact) {
      return Container(
        // height is controlled by parent SizedBox
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImage(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                     if (ownerName != null)
                      Text(
                        'by $ownerName',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                     const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$items items', style: theme.textTheme.labelSmall),
                        Text(
                          '₹${price.toStringAsFixed(0)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppTheme.success,
                            fontWeight: FontWeight.bold,
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
      );
    }

    return Container(
      height: 130,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildImage(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '$items ${items == 1 ? 'item' : 'items'}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${price.toStringAsFixed(2)}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (ownerName != null && ownerName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          ownerName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}
