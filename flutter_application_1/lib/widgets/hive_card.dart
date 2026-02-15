import 'dart:io';
import 'package:flutter/material.dart';
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

  const HiveCard({
    super.key,
    required this.title,
    required this.items,
    required this.price,
    required this.imageUrl,
    this.heroTag,
    this.ownerName,
  });

  Widget _buildImage() {
    final path = imageUrl.isNotEmpty ? imageUrl : AppConstants.fallbackImage;

    Widget image;
    if (ImageStorageService.isLocalPath(path)) {
      image = Image.file(
        File(path),
        height: 100,
        width: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackImage(),
      );
    } else if (ImageStorageService.isNetworkPath(path)) {
      image = Image.network(
        path,
        height: 100,
        width: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackImage(),
      );
    } else {
      image = Image.asset(
        path,
        height: 100,
        width: 100,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackImage(),
      );
    }

    Widget imageWidget = ClipRRect(
      borderRadius: BorderRadius.circular(12),
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
      height: 100,
      width: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentHoney.withValues(alpha: 0.4),
            AppTheme.primaryAmber.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.hive, size: 40, color: AppTheme.primaryAmber),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
