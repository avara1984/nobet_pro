import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tüm uygulamanın yakınlaştırma oranı (tarayıcıdaki Ctrl +/− gibi).
/// Cihaza özeldir: her bilgisayar kendi oranını hatırlar. Web'de tarayıcının
/// kendi yakınlaştırması olduğu için devre dışıdır.
class EkranOlcegi extends ChangeNotifier {
  EkranOlcegi(this._tercihler) {
    final kayitli = _tercihler.getDouble(_anahtar);
    if (kayitli != null) _deger = _sinirla(kayitli);
  }

  static const _anahtar = 'ekran_olcegi';
  static const double enAz = 0.6;
  static const double enCok = 1.3;
  static const double adim = 0.1;

  final SharedPreferences _tercihler;
  double _deger = 1.0;

  /// Kullanılabilir mi? (Web'de hayır.)
  static bool get desteklenir => !kIsWeb;

  double get deger => desteklenir ? _deger : 1.0;
  int get yuzde => (deger * 100).round();
  bool get varsayilan => (deger - 1.0).abs() < 0.001;

  static double _sinirla(double v) =>
      ((v * 100).round() / 100).clamp(enAz, enCok).toDouble();

  void ayarla(double v) {
    final yeni = _sinirla(v);
    if (yeni == _deger) return;
    _deger = yeni;
    _tercihler.setDouble(_anahtar, yeni);
    notifyListeners();
  }

  void artir() => ayarla(_deger + adim);
  void azalt() => ayarla(_deger - adim);
  void sifirla() => ayarla(1.0);
}
