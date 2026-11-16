import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/env.dart';
import '../core/api.dart';
import '../core/crash_reporter.dart';
import '../core/subscription.dart';
import 'auth_controller.dart';

/// Mağazada satılan tek bir seçenek: kademe + dönem + RevenueCat paketi.
class StorePlan {
  const StorePlan({required this.tier, required this.yearly, required this.package});

  final String tier; // plus | pro | max
  final bool yearly;
  final Package package;

  String get priceString => package.storeProduct.priceString;
  String get productId => package.storeProduct.identifier;
}

enum PurchaseOutcome { success, cancelled, pending, failed }

/// RevenueCat paket kimliği → (kademe, yıllık mı). Panelde paketler `plus_monthly`, `pro_yearly`… diye adlandırılır;
/// adlandırma tutmazsa ürün kimliğinden (`rebi_pro_yearly`) çıkarılır.
(String, bool)? classifyPackage(String packageId, String productId, {PackageType? type}) {
  final hay = '${packageId.toLowerCase()} ${productId.toLowerCase()}';
  String? tier;
  for (final t in storeTiers.reversed) {
    if (RegExp('(^|[^a-z])$t([^a-z]|\$)').hasMatch(hay)) {
      tier = t;
      break;
    }
  }
  if (tier == null) return null;
  final yearly = type == PackageType.annual || RegExp(r'year|annual|yillik|\b1y\b').hasMatch(hay);
  return (tier, yearly);
}

/// Uygulama içi abonelik (RevenueCat). Kullanıcı kimliği Supabase `auth.users.id`'dir; böylece sunucu webhook'u
/// satın almayı doğru hesaba yazar. Hak bilgisi yine sunucunun yazdığı `app_metadata`'dan okunur
/// (`userHasRebiPlus`); bu sınıf yalnızca satın alma/geri yükleme ve eşitlemeyi yürütür.
class StoreController extends ChangeNotifier {
  StoreController(this._auth) {
    if (!storePurchasesEnabled) return;
    unawaited(_configure());
    _auth.addListener(_onAuth);
  }

  /// Testler ve önizleme için: RevenueCat'e bağlanmadan hazır paketlerle.
  @visibleForTesting
  StoreController.preview(this._auth, this.plans);

  final AuthController _auth;
  bool _configured = false;
  String? _loggedInAs;
  bool _disposed = false;

  List<StorePlan> plans = const [];
  bool loadingPlans = false;
  bool busy = false;
  String? error;

  bool get enabled => storePurchasesEnabled;

  Future<void> _configure() async {
    try {
      final key = defaultTargetPlatform == TargetPlatform.android ? Env.revenueCatGoogleKey : Env.revenueCatAppleKey;
      if (kDebugMode) await Purchases.setLogLevel(LogLevel.info);
      final config = PurchasesConfiguration(key)..appUserID = _auth.user?.id;
      await Purchases.configure(config);
      _configured = true;
      _loggedInAs = _auth.user?.id;
      // Yenileme/iptal uygulama açıkken gelirse sunucu webhook'la zaten günceller; JWT'yi tazelemek yeter.
      Purchases.addCustomerInfoUpdateListener((_) => _scheduleSessionRefresh());
      await loadPlans();
    } catch (e, st) {
      CrashReporting.report(e, st, fatal: false, library: 'revenuecat configure');
    }
  }

  void _onAuth() {
    if (!_configured) return;
    final uid = _auth.user?.id;
    if (uid == _loggedInAs) return;
    _loggedInAs = uid;
    unawaited(() async {
      try {
        if (uid != null) {
          await Purchases.logIn(uid);
        } else if (!await Purchases.isAnonymous) {
          await Purchases.logOut();
        }
      } catch (e, st) {
        CrashReporting.report(e, st, fatal: false, library: 'revenuecat login');
      }
    }());
  }

  Future<void> loadPlans() async {
    if (!_configured || loadingPlans) return;
    loadingPlans = true;
    _notify();
    try {
      final offerings = await Purchases.getOfferings();
      final pkgs = offerings.current?.availablePackages ?? const <Package>[];
      final out = <StorePlan>[];
      for (final p in pkgs) {
        final c = classifyPackage(p.identifier, p.storeProduct.identifier, type: p.packageType);
        if (c == null) continue;
        out.add(StorePlan(tier: c.$1, yearly: c.$2, package: p));
      }
      out.sort((a, b) {
        final t = storeTiers.indexOf(a.tier).compareTo(storeTiers.indexOf(b.tier));
        return t != 0 ? t : (a.yearly ? 1 : 0).compareTo(b.yearly ? 1 : 0);
      });
      plans = out;
    } catch (e, st) {
      CrashReporting.report(e, st, fatal: false, library: 'revenuecat offerings');
    } finally {
      loadingPlans = false;
      _notify();
    }
  }

  Future<PurchaseOutcome> purchase(StorePlan plan) async {
    if (!_configured || busy) return PurchaseOutcome.failed;
    busy = true;
    error = null;
    _notify();
    try {
      final change = await _androidUpgradeFrom(plan);
      await Purchases.purchase(PurchaseParams.package(plan.package, productChangeInfo: change));
      await _syncWithServer();
      return PurchaseOutcome.success;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return PurchaseOutcome.cancelled;
      if (code == PurchasesErrorCode.paymentPendingError) return PurchaseOutcome.pending;
      error = e.message;
      return PurchaseOutcome.failed;
    } catch (e, st) {
      CrashReporting.report(e, st, fatal: false, library: 'revenuecat purchase');
      return PurchaseOutcome.failed;
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Google Play'de kademe değişikliği eski aboneliği değiştirmeli; yoksa kullanıcı iki abonelik öder.
  /// App Store bunu abonelik grubu üzerinden kendisi yapar.
  Future<StoreProductChangeInfo?> _androidUpgradeFrom(StorePlan plan) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final info = await Purchases.getCustomerInfo();
    for (final id in info.activeSubscriptions) {
      final base = id.split(':').first;
      if (base != plan.productId.split(':').first) {
        return StoreProductChangeInfo(base, replacementMode: StoreReplacementMode.withTimeProration);
      }
    }
    return null;
  }

  /// "Satın alımları geri yükle" (App Store zorunluluğu). true: etkin bir abonelik bulundu.
  Future<bool> restore() async {
    if (!_configured || busy) return false;
    busy = true;
    error = null;
    _notify();
    try {
      final info = await Purchases.restorePurchases();
      await _syncWithServer();
      return info.entitlements.active.isNotEmpty;
    } catch (e, st) {
      CrashReporting.report(e, st, fatal: false, library: 'revenuecat restore');
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Sunucu RevenueCat'ten güncel hakkı okuyup `app_metadata`'ya yazar; ardından yeni JWT alınır.
  Future<void> _syncWithServer() async {
    final uid = _auth.user?.id;
    if (uid == null) return;
    try {
      await apiPost('/subscription/sync', {'user_id': uid});
    } catch (e, st) {
      // Webhook yine de yazar; birazdan oturum yenilenince hak görünür.
      CrashReporting.report(e, st, fatal: false, library: 'subscription sync');
    }
    await _refreshSession();
  }

  Timer? _refreshTimer;

  void _scheduleSessionRefresh() {
    _refreshTimer?.cancel();
    // Webhook'un sunucuya ulaşması için kısa bir pay.
    _refreshTimer = Timer(const Duration(seconds: 4), _refreshSession);
  }

  Future<void> _refreshSession() async {
    try {
      await supabase?.auth.refreshSession();
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
