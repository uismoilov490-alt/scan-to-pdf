import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/ai_service.dart';
import '../services/subscription_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  StreamSubscription<User?>? _authSub;

  bool _isPro = false;
  AiQuota? _quota;
  bool _loadingProducts = true;
  bool _purchasing = false;
  bool _storeAvailable = false;
  String? _error;
  List<ProductDetails> _products = [];

  bool get isPro => _isPro;

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

  ProductDetails? get yearlyProduct => _products
      .where((p) => p.id == SubscriptionService.proYearlyId)
      .firstOrNull;

  Future<void> initialize() async {
    _isPro = await SubscriptionService.getIsProStored();
    notifyListeners();

    // Pro holatining asosiy manbai — server (obuna tugasa u o'chiradi).
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) => refreshAccount());

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
    _quota = account.quota;
    SubscriptionService.storeProStatus(isPro: account.pro);
    notifyListeners();
  }

  Future<void> _verifyWithServer(PurchaseDetails purchase) async {
    try {
      _applyAccount(await AiService.verifyPurchase(
        productId: purchase.productID,
        purchaseToken: purchase.verificationData.serverVerificationData,
      ));
    } on AiException catch (e) {
      // Server tekshiruvi hali sozlanmagan yoki tarmoq yo'q — Google Play
      // xaridni tasdiqlagan, shuning uchun ilovada Pro ko'rsatamiz.
      if (e.code == 'BILLING_NOT_CONFIGURED' || e.code == 'NETWORK' || e.needsLogin) {
        _isPro = true;
        await SubscriptionService.storeProStatus(
          isPro: true,
          purchaseId: purchase.purchaseID,
        );
      }
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
