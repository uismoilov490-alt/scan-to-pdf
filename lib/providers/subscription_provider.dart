import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/ai_service.dart';
import '../services/subscription_service.dart';
import '../services/ad_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  StreamSubscription<User?>? _authSub;

  bool _isPro = false;
  String _plan = 'free';
  DateTime? _proUntil;
  AiQuota? _quota;
  bool _loadingProducts = true;
  bool _purchasing = false;
  bool _storeAvailable = false;
  String? _error;
  List<ProductDetails> _products = [];

  bool get isPro => _isPro;

  /// free | monthly (server ma'lumoti)
  String get plan => _plan;
  DateTime? get proUntil => _proUntil;
  bool get signedIn => FirebaseAuth.instance.currentUser != null;

  /// Bugungi AI limiti (server ma'lumoti; tizimga kirilmagan bo'lsa null).
  AiQuota? get quota => _quota;
  bool get loadingProducts => _loadingProducts;
  bool get purchasing => _purchasing;
  bool get storeAvailable => _storeAvailable;
  String? get error => _error;
  List<ProductDetails> get products => _products;

  ProductDetails? get monthlyProduct => _products
      .where((p) => p.id == SubscriptionService.proMonthlyId)
      .firstOrNull;

  Future<void> initialize() async {
    _isPro = await SubscriptionService.getIsProStored();
    AdService.setPro(_isPro);
    notifyListeners();

    // Pro holatining asosiy manbai — server (obuna tugasa u o'chiradi).
    _authSub = FirebaseAuth.instance.authStateChanges().listen(
      (_) => refreshAccount(),
    );

    _storeAvailable = await _iap.isAvailable();
    if (!_storeAvailable) {
      _loadingProducts = false;
      notifyListeners();
      return;
    }

    _purchaseSub = _iap.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (dynamic e) {
        _error = e.toString();
        notifyListeners();
      },
    );

    await _loadProducts();
    await _iap.restorePurchases();
  }

  /// Serverdan Pro holati va AI limitini yangilaydi.
  Future<void> refreshAccount() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _quota = null;
      _isPro = false;
      _plan = 'free';
      _proUntil = null;
      AdService.setPro(false);
      notifyListeners();
      return;
    }
    try {
      _applyAccount(await AiService.me());
    } on AiException {
      // Server yetib bo'lmasa oxirgi ma'lum holat qoladi
    }
  }

  /// AI so'rovidan kelgan yangi limitni darhol ko'rsatish uchun.
  void updateQuota(AiQuota? quota) {
    if (quota == null) return;
    _quota = quota;
    notifyListeners();
  }

  void _applyAccount(AiAccount account) {
    _isPro = account.pro;
    _plan = account.plan;
    _proUntil = account.proUntil;
    _quota = account.quota;
    SubscriptionService.storeProStatus(isPro: account.pro);
    AdService.setPro(account.pro);
    notifyListeners();
  }

  /// Pro holatini faqat server beradi (xaridni Google Play orqali tekshiradi) —
  /// ilovaning o'zi Pro yoqmaydi, aks holda soxta xarid bilan aldash mumkin.
  /// Hisobga kirilmagan bo'lsa xarid keyin "Xaridlarni tiklash" bilan bog'lanadi.
  Future<void> _verifyWithServer(PurchaseDetails purchase) async {
    try {
      _applyAccount(
        await AiService.verifyPurchase(
          productId: purchase.productID,
          purchaseToken: purchase.verificationData.serverVerificationData,
        ),
      );
    } on AiException catch (e) {
      if (e.needsLogin) _error = 'sub_login_to_link';
    }
  }

  Future<void> _loadProducts() async {
    _loadingProducts = true;
    _error = null;
    notifyListeners();

    try {
      final response = await SubscriptionService.queryProducts();
      if (response.error != null) {
        _error = response.error!.message;
      } else {
        _products = List.of(response.productDetails)
          ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
      }
    } catch (e) {
      _error = e.toString();
    }

    _loadingProducts = false;
    notifyListeners();
  }

  Future<void> buyProduct(ProductDetails product) async {
    if (_purchasing) return;
    _purchasing = true;
    _error = null;
    notifyListeners();

    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (e) {
      _error = e.toString();
      _purchasing = false;
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    if (_purchasing) return;
    _purchasing = true;
    _error = null;
    notifyListeners();
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _error = e.toString();
      _purchasing = false;
      notifyListeners();
    }
  }

  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (SubscriptionService.productIds.contains(purchase.productID)) {
            await _verifyWithServer(purchase);
          }
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.error:
          _error = purchase.error?.message ?? 'Purchase failed';
        case PurchaseStatus.canceled:
          break;
      }
    }
    _purchasing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
