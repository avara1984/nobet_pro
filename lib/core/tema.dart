import 'package:flutter/material.dart';

import '../modeller/modeller.dart';

/// Uygulama renk paleti (tasarım referansından).
class R {
  static const mavi = Color(0xFF2563EB);
  static const maviKoyu = Color(0xFF1D4ED8);
  static const yan = Color(0xFF16223D);
  static const yesil = Color(0xFF16A34A);
  static const turuncu = Color(0xFFF59E0B);
  static const kirmizi = Color(0xFFDC2626);
  static const gri = Color(0xFF9CA3AF);
  static const cizgi = Color(0xFFE5E7EB);
  static const baslikZemin = Color(0xFFF9FAFB);

  static const koyuZemin = Color(0xFF0F172A);
  static const koyuKart = Color(0xFF152036);
  static const koyuBaslik = Color(0xFF1B2740);
}

class Tema {
  static ThemeData get acik => _olustur(Brightness.light);
  static ThemeData get koyu => _olustur(Brightness.dark);

  static ThemeData _olustur(Brightness parlaklik) {
    final koyuMu = parlaklik == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: parlaklik,
      colorScheme: ColorScheme.fromSeed(
        seedColor: R.mavi,
        brightness: parlaklik,
      ),
      scaffoldBackgroundColor:
          koyuMu ? R.koyuZemin : const Color(0xFFF4F6FA),
      fontFamily: 'Segoe UI',
    );

    return base.copyWith(
      dividerTheme: DividerThemeData(
        color: koyuMu ? Colors.white10 : R.cizgi,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: R.maviKoyu,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: koyuMu ? Colors.white24 : R.cizgi),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  /// Kart / panel arka planı
  static Color kart(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? R.koyuKart : Colors.white;

  /// Tablo başlık arka planı
  static Color tabloBaslik(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? R.koyuBaslik : R.baslikZemin;

  /// Nöbet tablolarının (Nöbet Listesi, Haftalık, 15-14) başlık satırı —
  /// açık kırmızı zemin; üç ekranda aynı renk.
  static Color nobetTabloBaslik(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? R.kirmizi.withValues(alpha: .12)
          : const Color(0xFFFDEEEE);

  /// İnce çizgi rengi
  static Color kenar(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? Colors.white10 : R.cizgi;
}

// -----------------------------------------------------------------------------
// VARDİYA RENKLERİ
// -----------------------------------------------------------------------------
/// Bir vardiya hücresinin zemin + yazı rengi ve rozet (hap) olarak mı
/// çizileceği. Renkler vardiya koduna göre sabittir — nöbet tablosunda
/// gündüz/gece/izin türleri bir bakışta ayırt edilsin diye.
class VardiyaBoya {
  const VardiyaBoya(this.zemin, this.yazi, {this.rozet = true});

  final Color zemin;
  final Color yazi;

  /// false ise düz (rozetsiz) soluk metin olarak çizilir — N.İ. ve H.T.
  /// tabloyu boğmasın diye vurgusuz bırakılır.
  final bool rozet;
}

/// Açık tema: pastel zemin + koyu yazı.
const Map<String, ({int z, int y})> _acikVardiyaBoya = {
  kGunduz12: (z: 0xFFFEF3C7, y: 0xFF92400E),
  kGece12: (z: 0xFFE0E7FF, y: 0xFF3730A3),
  kGece8: (z: 0xFFC7D2FE, y: 0xFF312E81),
  kSabah8: (z: 0xFFFFEDD5, y: 0xFF9A3412),
  kAksam8: (z: 0xFFFFE4E6, y: 0xFF9F1239),
  kMesai: (z: 0xFFDBEAFE, y: 0xFF1E40AF),
  kYillikIzin: (z: 0xFFD1FAE5, y: 0xFF065F46),
  kIdariIzin: (z: 0xFFEDE9FE, y: 0xFF5B21B6),
  kResmiTatil: (z: 0xFFFEE2E2, y: 0xFF991B1B),
};

/// Koyu tema: yarı saydam zemin + açık yazı.
const Map<String, ({int z, int y})> _koyuVardiyaBoya = {
  kGunduz12: (z: 0x33F59E0B, y: 0xFFFCD34D),
  kGece12: (z: 0x336366F1, y: 0xFFA5B4FC),
  kGece8: (z: 0x334F46E5, y: 0xFF818CF8),
  kSabah8: (z: 0x33F97316, y: 0xFFFDBA74),
  kAksam8: (z: 0x33F43F5E, y: 0xFFFDA4AF),
  kMesai: (z: 0x333B82F6, y: 0xFF93C5FD),
  kYillikIzin: (z: 0x3310B981, y: 0xFF6EE7B7),
  kIdariIzin: (z: 0x338B5CF6, y: 0xFFC4B5FD),
  kResmiTatil: (z: 0x33EF4444, y: 0xFFFCA5A5),
};

/// Vardiya kodunun hücre boyası. Tanımsız kodlar rozetsiz çizilir.
VardiyaBoya vardiyaBoyasi(String kod, {required bool koyu}) {
  // Boş hücre N.İ. sayılır; N.İ. ve H.T. vurgusuz kalır.
  if (kod.isEmpty || kod == kNobetIzni || kod == kHaftaTatili) {
    return VardiyaBoya(
      Colors.transparent,
      koyu ? Colors.white : Colors.black,
      rozet: false,
    );
  }
  final harita = koyu ? _koyuVardiyaBoya : _acikVardiyaBoya;
  final b = harita[kod];
  if (b == null) {
    return VardiyaBoya(
      Colors.transparent,
      koyu ? const Color(0xFF97A3B2) : const Color(0xFF6B7280),
      rozet: false,
    );
  }
  return VardiyaBoya(Color(b.z), Color(b.y));
}
