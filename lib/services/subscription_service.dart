import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionService {
  static const String proMonthlyId = 'scan_pro_monthly';
  static const String proYearlyId = 'scan_pro_yearly';
  static const Set<String> productIds = {proMonthlyId, proYearlyId};

  static const _keyIsPro = 'sub_is_pro';
  static const _keyPurchaseId = 'sub_purchase_id';

  static Future<bool> getIsProStored() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsPro) ?? false;
  }

  static Future<void> storeProStatus({
    required bool isPro,
    String? purchaseId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsPro, isPro);
    if (isPro && purchaseId != null) {
      await prefs.setString(_keyPurchaseId, purchaseId);
    } else {
      await prefs.remove(_keyPurchaseId);
    }
  }

  static Future<ProductDetailsResponse> queryProducts() {
    return InAppPurchase.instance.queryProductDetails(productIds);
  }
}
