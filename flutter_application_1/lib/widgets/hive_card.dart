import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/image_storage_service.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/money.dart';

/// A hive as a card.
///
/// Two shapes: a wide card for the home carousel, and a compact tile for the
/// friends grid. The colour is the one the owner picked, falling back to a
/// tint derived from the id. Text contrast follows the colour, so a blue card
/// reads white and a tinted one reads ink.
class HiveCard extends StatelessWidget {
  final String title;
  final int items;
  final double price;
  final String imageUrl;
  final String? heroTag;
  final String? ownerName;
  final bool isCompact;
  final int notificationCount;

  /// Falls back to the title so a card is never left untinted.
  final String? tintSeed;

  /// The owner choice, one of AppTheme.namedTints.
  final String? colorKey;

  /// Occasion and date, e.g. "Birthday · 12 Oct".
  final String? dateLabel;

  /// The card in front is flat and shows its owner line; the ones behind only
  /// ever show their top face.
  final bool showDetails;

  /// 0 for a full card, 1 for one collapsed to a title strip in the deck.
  /// The two layouts cross-fade, so the title never jumps position.
  final double collapse;

  const HiveCard({
    super.key,
    required this.title,
    required this.items,
    required this.price,
    required this.imageUrl,
    this.heroTag,
    this.ownerName,
    this.isCompact = false,
    this.notificationCount = 0,
    this.tintSeed,
    this.colorKey,
    this.dateLabel,
    this.showDetails = false,
    this.collapse = 0,
  });

  /// Height of the wide card. HiveDeck lays its slots out against this.
  static const double wideHeight = 156;

  /// Width of the flush cover panel on the wide card.
  static const double _coverPanel = 132;

  Color get _tint => AppTheme.colorFor(colorKey, tintSeed ?? title);
  Color get _fg => AppTheme.onColor(_tint);
  Color get _fgSoft => _fg.withValues(alpha: 0.7);

  Widget _cover({required double side, required BorderRadius radius}) {
    final path = imageUrl.isNotEmpty ? imageUrl : AppConstants.fallbackImage;

    Widget image;
    if (ImageStorageService.isLocalPath(path)) {
      image = Image.file(File(path), height: side, width: side, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackCover(side));
    } else if (ImageStorageService.isNetworkPath(path)) {
      image = CachedNetworkImage(
        imageUrl: path,
        height: side,
        width: side,
        memCacheHeight: (side * 3).round(),
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _fallbackCover(side),
        placeholder: (_, __) => _fallbackCover(side),
      );
    } else {
      image = Image.asset(path, height: side, width: side, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackCover(side));
    }

    Widget cover = ClipRRect(borderRadius: radius, child: image);
    if (heroTag != null) {
      cover = Hero(
        tag: heroTag!,
        child: Material(type: MaterialType.transparency, child: cover),
      );
    }
    return cover;
  }

  Widget _fallbackCover(double side) => Container(
        height: side,
        width: side,
        color: Colors.white.withValues(alpha: 0.9),
        child: Icon(Icons.card_giftcard_rounded,
            size: side * 0.52, color: AppTheme.brandBlue.withValues(alpha: 0.8)),
      );

  /// The cover filling whatever box it is given, edge to edge. The card clips
  /// the corners, so this carries no radius, border or padding of its own.
  Widget _coverFill() {
    final path = imageUrl.isNotEmpty ? imageUrl : AppConstants.fallbackImage;

    Widget image;
    if (ImageStorageService.isLocalPath(path)) {
      image = Image.file(File(path),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallbackPanel());
    } else if (ImageStorageService.isNetworkPath(path)) {
      image = CachedNetworkImage(
        imageUrl: path,
        fit: BoxFit.cover,
        memCacheWidth: (_coverPanel * 3).round(),
        errorWidget: (_, __, ___) => _fallbackPanel(),
        placeholder: (_, __) => _fallbackPanel(),
      );
    } else {
      image = Image.asset(path,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallbackPanel());
    }

    if (heroTag != null) {
      return Hero(
        tag: heroTag!,
        child: Material(type: MaterialType.transparency, child: image),
      );
    }
    return image;
  }

  Widget _fallbackPanel() => ColoredBox(
        color: Colors.white.withValues(alpha: 0.85),
        child: Center(
          child: Icon(Icons.card_giftcard_rounded,
              size: 40, color: AppTheme.brandBlue.withValues(alpha: 0.8)),
        ),
      );

  Widget _badge() => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle),
        child: Text('$notificationCount',
            style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: Colors.white,
                fontSize: 11,
                height: 1.0,
                fontWeight: FontWeight.w600)),
      );

  String get _money => formatMoney(price);
  String get _countLabel => '$items ${items == 1 ? 'wish' : 'wishes'}';

  @override
  Widget build(BuildContext context) {
    final card = isCompact ? _tile(context) : _wide(context);
    if (notificationCount == 0) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(top: 12, right: 12, child: _badge()),
      ],
    );
  }

  /// The wide card used in the home deck, in whichever state the deck asks
  /// for. Both layouts are always built at their natural size and clipped, so
  /// a shrinking card never squashes its own contents.
  Widget _wide(BuildContext context) {
    // The cover stretches to the card height, so the card must have one. Where
    // a parent already imposes a height — every slot in the deck — that tight
    // constraint wins and this is ignored; where none does, such as the live
    // preview in the create sheet, it stops the stretch reaching for infinity.
    if (collapse <= 0) {
      return SizedBox(
        height: wideHeight,
        child: _wideBody(context, full: true),
      );
    }

    // The two layouts hand over rather than cross-fade. The strip has no cover
    // panel, so its title sits where the full layout puts its image; showing
    // both at once reads as a ghost of the card printed over itself.
    final fullOpacity = (1 - collapse / 0.45).clamp(0.0, 1.0);
    final stripOpacity = ((collapse - 0.55) / 0.45).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rHive),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: ColoredBox(color: _tint)),
          if (fullOpacity > 0)
            OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: wideHeight + 60,
              child: Opacity(
                opacity: fullOpacity,
                child: SizedBox(
                    height: wideHeight, child: _wideBody(context, full: true)),
              ),
            ),
          if (stripOpacity > 0)
            Opacity(opacity: stripOpacity, child: _strip()),
        ],
      ),
    );
  }

  /// The collapsed form: the name, and how many wishes are inside.
  Widget _strip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _fg)),
          ),
          const SizedBox(width: 12),
          Text(_countLabel,
              style: TextStyle(
                  fontFamily: AppTheme.fontFamily, fontSize: 13, color: _fgSoft)),
        ],
      ),
    );
  }

  Widget _wideBody(BuildContext context, {required bool full}) {
    // The cover runs the full height flush against the left edge, with the
    // card clipping the corners, so the image carries no frame or padding of
    // its own. The overlap from the deck falls on the lower right, where only
    // the amount sits.
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _coverPanel, child: _coverFill()),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dateLabel != null && dateLabel!.isNotEmpty)
                  Text(dateLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 13,
                          color: _fgSoft)),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 20,
                        height: 1.15,
                        fontWeight: FontWeight.w500,
                        color: _fg)),
                const SizedBox(height: 4),
                Text(_countLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 14,
                        color: _fgSoft)),
                Text(_money, style: AppTheme.money(size: 22, color: _fg)),
                if (showDetails && ownerName != null && ownerName!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _OwnerLine(name: ownerName!, onTint: _fg),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.rHive),
      child: ColoredBox(
        color: full ? _tint : Colors.transparent,
        child: body,
      ),
    );
  }

  /// The compact tile used in the friends grid and the horizontal row.
  Widget _tile(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _tint,
        borderRadius: BorderRadius.circular(AppTheme.rHive),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _cover(side: 34, radius: BorderRadius.circular(11)),
              ),
              const Spacer(),
              if (dateLabel != null && dateLabel!.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(dateLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.ink)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  color: _fg)),
          const Spacer(),
          const SizedBox(height: 10),
          Text('$_countLabel · $_money',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.fontFamily, fontSize: 13, color: _fgSoft)),
          if (ownerName != null && ownerName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: _fg.withValues(alpha: 0.12)),
            const SizedBox(height: 8),
            _OwnerLine(name: ownerName!, onTint: _fg),
          ],
        ],
      ),
    );
  }
}

/// The owner sits quietly at the bottom of the card: a small initial and a
/// first name, never an avatar circle competing with the cover.
class _OwnerLine extends StatelessWidget {
  final String name;
  final Color onTint;

  const _OwnerLine({required this.name, required this.onTint});

  @override
  Widget build(BuildContext context) {
    final first = name.trim().split(' ').first;
    final initial = first.isEmpty ? '?' : first[0].toUpperCase();

    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTint.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Text(initial,
              style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 11,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                  color: onTint.withValues(alpha: 0.8))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: onTint.withValues(alpha: 0.85))),
        ),
      ],
    );
  }
}
