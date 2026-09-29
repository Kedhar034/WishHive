import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/image_storage_service.dart';

/// Full-screen image viewer.
///
/// Shows a swipeable gallery when a product page yielded more than one image,
/// and behaves exactly as before for a single one.
class FullScreenImagePage extends StatefulWidget {
  final List<String> images;
  final String heroTag;
  final int initialIndex;

  const FullScreenImagePage({
    super.key,
    required String imageUrl,
    required this.heroTag,
    List<String>? images,
    this.initialIndex = 0,
  }) : images = images ?? const [],
       _single = imageUrl;

  final String _single;

  List<String> get _resolved {
    final list = images.where((e) => e.trim().isNotEmpty).toList();
    if (list.isEmpty) return _single.isEmpty ? const [] : [_single];
    // The primary image is what the thumbnail showed, so it leads.
    if (_single.isNotEmpty && !list.contains(_single)) list.insert(0, _single);
    return list;
  }

  @override
  State<FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<FullScreenImagePage> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, (widget._resolved.length - 1).clamp(0, 999));
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget._resolved;
    final multiple = images.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: multiple
            ? Text(
                '${_index + 1} / ${images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: images.isEmpty
          ? const Center(child: Icon(Icons.image_not_supported, color: Colors.white54, size: 64))
          : Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final image = _buildImage(images[i]);
                    return Center(
                      child: InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 4.0,
                        // Only the first page carries the hero, so the
                        // transition from the thumbnail stays correct.
                        child: i == widget.initialIndex
                            ? Hero(tag: widget.heroTag, child: image)
                            : image,
                      ),
                    );
                  },
                ),
                if (multiple)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 28 + MediaQuery.of(context).padding.bottom,
                    child: _Dots(count: images.length, active: _index),
                  ),
              ],
            ),
    );
  }

  Widget _buildImage(String imageUrl) {
    if (ImageStorageService.isAssetPath(imageUrl)) {
      return Image.asset(imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _errorWidget());
    }
    if (ImageStorageService.isLocalPath(imageUrl)) {
      return Image.file(File(imageUrl), fit: BoxFit.contain, errorBuilder: (_, __, ___) => _errorWidget());
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(color: Colors.white38, strokeWidth: 2),
      ),
      errorWidget: (_, __, ___) => _errorWidget(),
    );
  }

  Widget _errorWidget() => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
      );
}

class _Dots extends StatelessWidget {
  final int count;
  final int active;

  const _Dots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    // Long galleries would overflow a plain dot row.
    if (count > 8) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 20 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
