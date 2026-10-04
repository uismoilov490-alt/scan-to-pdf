import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Bepul rejadagi reklama (Google AdMob): bosh sahifada banner va har
/// [_savesPerInterstitial] ta saqlangan fayldan keyin to'liq ekranli reklama.
/// Oylik tarifda hech narsa ko'rsatilmaydi.
class AdService {
  AdService._();

  // AdMob hisobi ochilguncha Google'ning rasmiy test ID'lari ishlatiladi;
  // haqiqiylari build paytida --dart-define bilan beriladi.
  static const bannerUnitId = String.fromEnvironment(
    'ADMOB_BANNER_ID',
    defaultValue: 'ca-app-pub-3940256099942544/9214589741',
  );
  static const interstitialUnitId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ID',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
  static const _savesPerInterstitial = 2;

  /// false — foydalanuvchi oylik tarifda (reklama yo'q).
  static final enabled = ValueNotifier<bool>(true);

  static bool _initialized = false;
  static bool _loading = false;
  static int _saves = 0;
  static bool _pending = false;
  static InterstitialAd? _interstitial;

  static Future<void> init() async {
    if (_initialized || !Platform.isAndroid) return;
    _initialized = true;
    await MobileAds.instance.initialize();
    _loadInterstitial();
  }

  static void setPro(bool isPro) {
    if (enabled.value == !isPro) return;
    enabled.value = !isPro;
    if (isPro) {
      _pending = false;
      _interstitial?.dispose();
      _interstitial = null;
    } else {
      _loadInterstitial();
    }
  }

  static void _loadInterstitial() {
    if (!_initialized || !enabled.value || _interstitial != null || _loading)
      return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          debugPrint('[ads] interstitial: $error');
        },
      ),
    );
  }

  /// Foydalanuvchi natija faylini saqlaganda chaqiriladi.
  static void recordSave() {
    if (!enabled.value) return;
    _saves++;
    if (_saves % _savesPerInterstitial == 0) _pending = true;
  }

  /// Reklama ish jarayonini bo'lmasligi uchun foydalanuvchi bosh sahifaga
  /// qaytganda ko'rsatiladi ([AdRouteObserver]).
  static void showIfPending() {
    final ad = _interstitial;
    if (!_pending || !enabled.value || ad == null) return;
    _pending = false;
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    ad.show();
  }
}

/// Bosh sahifaga qaytilganda navbatdagi to'liq ekranli reklamani ko'rsatadi.
class AdRouteObserver extends NavigatorObserver {
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute?.isFirst == true && route is PageRoute) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => AdService.showIfPending(),
      );
    }
  }
}

/// Ekran pastidagi moslashuvchan banner (oylik tarifda yashiriladi).
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;

  @override
  void initState() {
    super.initState();
    AdService.enabled.addListener(_onEnabledChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width != _width) {
      _width = width;
      _load();
    }
  }

  void _onEnabledChanged() {
    if (AdService.enabled.value) {
      _load();
    } else {
      _disposeAd();
      if (mounted) setState(() {});
    }
  }

  Future<void> _load() async {
    _disposeAd();
    if (!AdService.enabled.value || !Platform.isAndroid || _width == null)
      return;
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      _width!,
    );
    if (size == null || !mounted) return;
    final ad = BannerAd(
      adUnitId: AdService.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[ads] banner: $error');
          ad.dispose();
          if (_ad == ad) _ad = null;
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  void _disposeAd() {
    _ad?.dispose();
    _ad = null;
    _loaded = false;
  }

  @override
  void dispose() {
    AdService.enabled.removeListener(_onEnabledChanged);
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!AdService.enabled.value || ad == null || !_loaded)
      return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
