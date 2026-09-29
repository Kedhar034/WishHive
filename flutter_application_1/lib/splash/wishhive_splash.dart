// WishHive splash animation (v2)
// Generated from the same timeline that rendered the 9:16 and 16:9 videos,
// so the app plays exactly the same motion.
//
// Usage:
//   WishHiveSplash(onFinished: () => Navigator.of(context).pushReplacement(...))

// ignore_for_file: non_constant_identifier_names

import 'dart:math' as math;
import 'package:flutter/material.dart';

class WishHiveSplash extends StatefulWidget {
  const WishHiveSplash({super.key, this.onFinished, this.holdAfter = const Duration(milliseconds: 500)});

  /// Called once the animation has finished and held for [holdAfter].
  final VoidCallback? onFinished;

  /// How long the final lockup stays on screen before [onFinished].
  final Duration holdAfter;

  @override
  State<WishHiveSplash> createState() => _WishHiveSplashState();
}

class _WishHiveSplashState extends State<WishHiveSplash> with SingleTickerProviderStateMixin {
  static const _fps = 60.0;
  static const _frames = 180.0;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_frames / _fps * 1000).round()),
  );
  bool _started = false;

  static const _paths = [
    'assets/splash/tile.webp', 'assets/splash/bag.webp', 'assets/splash/eye_l.webp', 'assets/splash/eye_r.webp',
    'assets/splash/sparkle1.webp', 'assets/splash/sparkle2.webp', 'assets/splash/icon.webp', 'assets/splash/wordmark.webp',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Decode every layer first so no frame is ever drawn half-loaded.
    Future.wait(_paths.map((p) => precacheImage(AssetImage(p), context))).then((_) {
      if (!mounted) return;
      _c.forward().whenComplete(() async {
        await Future<void>.delayed(widget.holdAfter);
        if (mounted) widget.onFinished?.call();
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (!box.hasBoundedWidth || !box.hasBoundedHeight || box.maxWidth <= 0 || box.maxHeight <= 0) {
        return const ColoredBox(color: Color(0xFF050A1C));
      }
      final size = Size(box.maxWidth, box.maxHeight);
      return AnimatedBuilder(
        animation: _c,
        builder: (context, _) => _Scene(frame: _c.value * _frames, size: size),
      );
    });
  }
}

// ───────────────────────── timeline ─────────────────────────

enum _Ease { lin, inOutCubic, outCubic, outQuint, outBack, spring }

double _ease(_Ease e, double p) {
  if (e == _Ease.inOutCubic) {
    return p < 0.5 ? 4 * p * p * p : 1 - math.pow(-2 * p + 2, 3).toDouble() / 2;
  } else if (e == _Ease.outCubic) {
    return 1 - math.pow(1 - p, 3).toDouble();
  } else if (e == _Ease.outQuint) {
    return 1 - math.pow(1 - p, 5).toDouble();
  } else if (e == _Ease.outBack) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * math.pow(p - 1, 3).toDouble() + c1 * math.pow(p - 1, 2).toDouble();
  } else if (e == _Ease.spring) {
    double r(double q) => 1 - math.exp(-6.5 * q) * math.cos(9.5 * q);
    return r(p) / r(1);
  }
  return p; // lin
}

double _c01(double v) => v < 0 ? 0.0 : (v > 1 ? 1.0 : v);

class _K {
  const _K(this.f, this.v, this.e);
  final double f, v;
  final _Ease e;
}

double _track(List<_K> k, double f) {
  if (f <= k.first.f) return k.first.v;
  for (var i = 0; i < k.length - 1; i++) {
    final a = k[i], b = k[i + 1];
    if (f < b.f) return a.v + (b.v - a.v) * _ease(a.e, (f - a.f) / (b.f - a.f));
  }
  return k.last.v;
}

class _T {
  static const fadeIn = <_K>[_K(0.0, 0.0, _Ease.lin), _K(8.0, 1.0, _Ease.lin)];
  static const bgLit = <_K>[_K(20.0, 0.0, _Ease.inOutCubic), _K(56.0, 1.0, _Ease.lin)];
  static const rotY = <_K>[_K(0.0, -88.0, _Ease.outCubic), _K(42.0, 0.0, _Ease.lin)];
  static const rotZ = <_K>[_K(0.0, -10.0, _Ease.outCubic), _K(42.0, 0.0, _Ease.lin)];
  static const intro = <_K>[_K(0.0, 0.72, _Ease.outCubic), _K(42.0, 1.0, _Ease.lin)];
  static const sweep1 = <_K>[_K(10.0, -0.7, _Ease.inOutCubic), _K(48.0, 1.7, _Ease.lin)];
  static const bagY = <_K>[_K(36.0, 0.78, _Ease.inOutCubic), _K(64.0, -0.035, _Ease.inOutCubic), _K(74.0, 0.0, _Ease.lin)];
  static const bagStretch = <_K>[_K(36.0, 0.1, _Ease.inOutCubic), _K(60.0, 0.05, _Ease.inOutCubic), _K(74.0, 0.0, _Ease.lin)];
  static const bagAlpha = <_K>[_K(36.0, 0.0, _Ease.lin), _K(40.0, 1.0, _Ease.lin)];
  static const squash = <_K>[_K(68.0, 0.0, _Ease.outCubic), _K(74.0, 0.07, _Ease.inOutCubic), _K(82.0, -0.045, _Ease.inOutCubic), _K(90.0, 0.018, _Ease.inOutCubic), _K(98.0, 0.0, _Ease.lin), _K(126.0, 0.0, _Ease.outCubic), _K(132.0, 0.055, _Ease.inOutCubic), _K(140.0, -0.03, _Ease.inOutCubic), _K(148.0, 0.01, _Ease.inOutCubic), _K(156.0, 0.0, _Ease.lin)];
  static const eyes = <_K>[_K(80.0, 0.0, _Ease.outBack), _K(90.0, 1.0, _Ease.lin)];
  static const spark1 = <_K>[_K(86.0, 0.0, _Ease.outBack), _K(100.0, 1.0, _Ease.lin)];
  static const spark2 = <_K>[_K(90.0, 0.0, _Ease.outBack), _K(104.0, 1.0, _Ease.lin)];
  static const iconFade = <_K>[_K(104.0, 0.0, _Ease.lin), _K(112.0, 1.0, _Ease.lin)];
  static const slide = <_K>[_K(108.0, 0.0, _Ease.spring), _K(152.0, 1.0, _Ease.lin)];
  static const shrink = <_K>[_K(108.0, 0.0, _Ease.inOutCubic), _K(136.0, 1.0, _Ease.lin)];
  static const turn = <_K>[_K(108.0, 0.0, _Ease.outCubic), _K(122.0, 22.0, _Ease.spring), _K(158.0, 0.0, _Ease.lin)];
  static const word = <_K>[_K(124.0, 0.0, _Ease.outQuint), _K(160.0, 1.0, _Ease.lin)];
  static const wordAlpha = <_K>[_K(124.0, 0.0, _Ease.lin), _K(134.0, 1.0, _Ease.lin)];
  static const glint = <_K>[_K(150.0, -0.7, _Ease.inOutCubic), _K(178.0, 1.7, _Ease.lin)];
}

// ───────────────────────── geometry ─────────────────────────

class _Box {
  const _Box(this.x, this.y, this.w, this.h);
  final double x, y, w, h;
}

const double _icon = 1254; // source size of the icon artwork
const _bag = _Box(156.0, 286.0, 936.0, 808.0);
const _eyeL = _Box(599.0, 759.0, 125.0, 200.0);
const _eyeR = _Box(774.0, 734.0, 120.0, 194.0);
const _sp1 = _Box(874.0, 215.0, 128.0, 170.0);
const _sp2 = _Box(963.0, 344.0, 172.0, 136.0);
const _eyeLc = Offset(661.5, 859.0);
const _eyeRc = Offset(834.0, 831.0);
const _sp1a = Offset(921.60, 337.15);
const _sp2a = Offset(1007.66, 435.91);

// wordmark.webp: 1741 x 325, letters span x 18..1711, y 5..268
const double _wmW = 1741, _wmH = 325, _wmLx0 = 18, _wmLx1 = 1711, _wmLy0 = 5, _wmLy1 = 268;
const double _letterH = 0.36; // letter height, in icon sizes
const double _visL = 36 / _icon, _visW = (1217 - 36) / _icon; // visible tile inside the icon box
const double _gap = 0.14; // icon -> name gap, in icon sizes

class _Layout {
  _Layout(double w, double h) {
    final k1 = _letterH / (_wmLy1 - _wmLy0);
    lettersW = (_wmLx1 - _wmLx0) * k1;
    final lockW = _visW + _gap + lettersW;
    s = math.min(w * (w > h ? 0.64 : 0.84) / lockW, 0.36 * h);
    c = math.min(1.7, 0.46 * math.min(w, h) / s);
    final left = w / 2 - lockW * s / 2;
    k = k1 * s;
    iconDx = (left - _visL * s + s / 2) - w / 2;
    lettersLeft = left + (_visW + _gap) * s;
    clipLeft = left + (_visW + 0.03) * s;
  }
  late final double s, c, lettersW, k, iconDx, lettersLeft, clipLeft;
}

// ───────────────────────── scene ─────────────────────────

class _Scene extends StatelessWidget {
  const _Scene({required this.frame, required this.size});
  final double frame;
  final Size size;

  double t(List<_K> k) => _track(k, frame);

  @override
  Widget build(BuildContext context) {
    final W = size.width, H = size.height;
    final L = _Layout(W, H);
    final s = L.s;
    final fade = t(_T.fadeIn);
    final lit = t(_T.bgLit);
    final scale = (L.c + (1 - L.c) * t(_T.shrink)) * t(_T.intro);
    final S = s * scale;
    final cx = W / 2 + L.iconDx * t(_T.slide), cy = H / 2;
    final q = t(_T.squash);
    final deg = math.pi / 180;

    // background (radius measured like the video render)
    final r = 0.75 * math.max(W, H) / math.min(W, H);
    Widget bg(List<Color> colors, List<double> stops) => Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(0, -0.16), radius: r, colors: colors, stops: stops),
            ),
          ),
        );

    // floor shadow
    final shW = 0.78 * S * (1 + q), shH = 0.10 * S;

    // name
    final wp = t(_T.word);
    final startOff = -(L.lettersW * s + 0.11 * s);
    final wordLeft = (L.lettersLeft - L.clipLeft) + (1 - wp) * startOff - _wmLx0 * L.k;
    final wordTop = H / 2 - (_wmLy0 + _wmLy1) / 2 * L.k;

    return Stack(children: [
      bg(const [Color(0xFF13295F), Color(0xFF0A1638), Color(0xFF050A1C)], const [0, 0.5, 1]),
      Positioned.fill(
        child: Opacity(
          opacity: _c01(lit),
          child: Stack(children: [
            bg(const [Color(0xFF2F8CFF), Color(0xFF1769FF), Color(0xFF0A47EE)], const [0, 0.45, 1]),
          ]),
        ),
      ),
      // shadow
      Positioned(
        left: cx - shW / 2,
        top: cy + 0.47 * S - shH / 2,
        width: shW,
        height: shH,
        child: Opacity(
          opacity: _c01(0.9 * lit * fade),
          child: Transform.scale(
            scaleX: shW / shH,
            scaleY: 1,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x8C000C3C), Color(0x00000C3C)]),
              ),
            ),
          ),
        ),
      ),
      // name, swiping out from behind the icon
      Positioned(
        left: L.clipLeft,
        top: 0,
        right: 0,
        bottom: 0,
        child: ClipRect(
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: wordLeft,
              top: wordTop,
              width: _wmW * L.k,
              height: _wmH * L.k,
              child: Opacity(
                opacity: _c01(t(_T.wordAlpha)),
                child: Image.asset('assets/splash/wordmark.webp', fit: BoxFit.fill, filterQuality: FilterQuality.medium),
              ),
            ),
          ]),
        ),
      ),
      // icon
      Positioned(
        left: cx - S / 2,
        top: cy - S / 2,
        width: S,
        height: S,
        child: Opacity(
          opacity: _c01(fade),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, -1 / (3.2 * S))
              ..rotateZ(t(_T.rotZ) * deg)
              ..rotateY((t(_T.rotY) + t(_T.turn)) * deg),
            child: Transform(
              alignment: const Alignment(0, 0.94),
              transform: Matrix4.diagonal3Values(1 + q, 1 - q, 1.0),
              child: _Icon(S: S, frame: frame),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Icon extends StatelessWidget {
  const _Icon({required this.S, required this.frame});
  final double S, frame;

  double t(List<_K> k) => _track(k, frame);

  Widget _layer(String asset, _Box b, {required Alignment origin, required Matrix4 transform, double opacity = 1}) {
    final u = S / _icon;
    final inset = 0.032 * S;
    return Positioned(
      left: b.x * u - inset,
      top: b.y * u - inset,
      width: b.w * u,
      height: b.h * u,
      child: Opacity(
        opacity: _c01(opacity),
        child: Transform(
          alignment: origin,
          transform: transform,
          child: Image.asset(asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
        ),
      ),
    );
  }

  static Alignment _origin(_Box b, Offset p) => Alignment((p.dx - b.x) / b.w * 2 - 1, (p.dy - b.y) / b.h * 2 - 1);

  // The clipped glass face of the tile (CSS: clip-path inset(3.2% round 20%)).
  Widget _face(List<Widget> children) => Positioned(
        left: 0.032 * S,
        top: 0.032 * S,
        right: 0.032 * S,
        bottom: 0.032 * S,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0.2 * S),
          child: Stack(clipBehavior: Clip.none, children: children),
        ),
      );

  Widget _band(double p) => Positioned(
        left: -0.032 * S,
        top: -0.032 * S,
        width: S,
        height: S,
        child: FractionalTranslation(
          translation: Offset(p - 0.5, 0),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.183, -0.317),
                end: Alignment(1.183, 0.317),
                colors: [Color(0x00FFFFFF), Color(0x8CFFFFFF), Color(0x24FFFFFF), Color(0x00FFFFFF)],
                stops: [0.36, 0.47, 0.54, 0.62],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = t(_T.bagStretch);
    final e = math.max(0.0, t(_T.eyes));
    final v1 = math.max(0.0, t(_T.spark1)), v2 = math.max(0.0, t(_T.spark2));
    final iconFade = t(_T.iconFade);
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: Image.asset('assets/splash/tile.webp', fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
      if (iconFade < 1)
        _face([
          _layer('assets/splash/bag.webp', _bag,
              origin: const Alignment(0, 1),
              transform: Matrix4.translationValues(0.0, t(_T.bagY) * S, 0.0)..multiply(Matrix4.diagonal3Values(1 - 0.5 * st, 1 + st, 1.0)),
              opacity: t(_T.bagAlpha)),
          _layer('assets/splash/eye_l.webp', _eyeL,
              origin: _origin(_eyeL, _eyeLc), transform: Matrix4.diagonal3Values(1.0, e, 1.0), opacity: e > 0.02 ? 1.0 : 0.0),
          _layer('assets/splash/eye_r.webp', _eyeR,
              origin: _origin(_eyeR, _eyeRc), transform: Matrix4.diagonal3Values(1.0, e, 1.0), opacity: e > 0.02 ? 1.0 : 0.0),
          _layer('assets/splash/sparkle1.webp', _sp1,
              origin: _origin(_sp1, _sp1a), transform: Matrix4.diagonal3Values(v1, v1, 1.0), opacity: math.min(1.0, v1 * 3)),
          _layer('assets/splash/sparkle2.webp', _sp2,
              origin: _origin(_sp2, _sp2a), transform: Matrix4.diagonal3Values(v2, v2, 1.0), opacity: math.min(1.0, v2 * 3)),
          _band(t(_T.sweep1)),
        ]),
      if (iconFade > 0)
        Positioned.fill(
          child: Opacity(
            opacity: _c01(iconFade),
            child: Image.asset('assets/splash/icon.webp', fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
        ),
      _face([_band(t(_T.glint))]),
    ]);
  }
}
