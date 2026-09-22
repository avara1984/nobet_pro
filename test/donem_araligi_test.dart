import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/donem_araligi.dart';

void main() {
  group('donemGunleri', () {
    test('normal ay — 15 Temmuz - 14 Ağustos', () {
      final gunler = donemGunleri(2026, 7);
      expect(gunler.length, 31); // Temmuz'dan 17 + Ağustos'tan 14
      expect(gunler.first, DateTime(2026, 7, 15));
      expect(gunler.last, DateTime(2026, 8, 14));
      expect(gunler[16], DateTime(2026, 7, 31)); // Temmuz'un son günü
      expect(gunler[17], DateTime(2026, 8, 1)); // Ağustos'un ilk günü
    });

    test('yıl sınırı — Aralık seçilince Ocak yıl atlar', () {
      final gunler = donemGunleri(2026, 12);
      expect(gunler.first, DateTime(2026, 12, 15));
      expect(gunler.last, DateTime(2027, 1, 14));
    });

    test('şubat (28 gün) — 15 Şubat - 14 Mart', () {
      final gunler = donemGunleri(2026, 2); // 2026 artık yıl değil
      expect(gunler.first, DateTime(2026, 2, 15));
      expect(gunler.last, DateTime(2026, 3, 14));
      expect(gunler.length, 14 + 14); // Şubat 15-28 (14 gün) + Mart 1-14
    });
  });

  group('donemBaslangicAyi / donemBitisAyi', () {
    test('normal ay', () {
      expect(donemBaslangicAyi(2026, 7), (2026, 7));
      expect(donemBitisAyi(2026, 7), (2026, 8));
    });

    test('Aralık → Ocak yıl geçişi', () {
      expect(donemBaslangicAyi(2026, 12), (2026, 12));
      expect(donemBitisAyi(2026, 12), (2027, 1));
    });
  });
}
