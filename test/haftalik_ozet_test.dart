import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/haftalik_ozet.dart';
import 'package:nobet_pro/core/mesai_hesap.dart' as mh;
import 'package:nobet_pro/modeller/modeller.dart';

void main() {
  final ayar = KurumAyari();
  const personelId = 'p1';

  group('haftalikToplamSaat', () {
    test('tek ay içindeki hafta — 7 gün kGunduz12 (11 saat/gün)', () {
      final kayit = AyKaydi(yil: 2026, ay: 7);
      // 2026 Temmuz: 6-12 Temmuz tam bir Pazartesi–Pazar haftası.
      for (var g = 6; g <= 12; g++) {
        kayit.ata(g, personelId, kGunduz12);
      }
      final hafta = [
        for (var g = 6; g <= 12; g++) DateTime(2026, 7, g),
      ];
      final toplam = haftalikToplamSaat(
        haftaGunleri: hafta,
        ayar: ayar,
        personelId: personelId,
        kayitBul: (_) => kayit,
      );
      expect(toplam, closeTo(77.0, 0.001)); // 7 * 11.0
    });

    test('tamamı N.İ. (boş) olan hafta = 0.0', () {
      final kayit = AyKaydi(yil: 2026, ay: 7);
      final hafta = [
        for (var g = 6; g <= 12; g++) DateTime(2026, 7, g),
      ];
      final toplam = haftalikToplamSaat(
        haftaGunleri: hafta,
        ayar: ayar,
        personelId: personelId,
        kayitBul: (_) => kayit,
      );
      expect(toplam, 0.0);
    });

    test('iki farklı AyKaydi\'ye yayılan sınır haftası doğru toplanır', () {
      // Haziran'ın son Pazartesi'si (29.06.2026) - Temmuz'un ilk Pazar'ı
      // (05.07.2026): 29-30 Haziran (2 gün) + 1-5 Temmuz (5 gün).
      final haziran = AyKaydi(yil: 2026, ay: 6);
      final temmuz = AyKaydi(yil: 2026, ay: 7);
      haziran.ata(29, personelId, kGunduz12);
      haziran.ata(30, personelId, kGunduz12);
      for (var g = 1; g <= 5; g++) {
        temmuz.ata(g, personelId, kGunduz12);
      }

      final hafta = [
        DateTime(2026, 6, 29),
        DateTime(2026, 6, 30),
        for (var g = 1; g <= 5; g++) DateTime(2026, 7, g),
      ];

      final toplam = haftalikToplamSaat(
        haftaGunleri: hafta,
        ayar: ayar,
        personelId: personelId,
        kayitBul: (tarih) => tarih.month == 6 ? haziran : temmuz,
      );
      expect(toplam, closeTo(77.0, 0.001)); // 7 * 11.0, doğru AyKaydi/gunSayisi
    });

    test(
        '31 Aralık kGece12, 1 Ocak kResmiTatil — '
        'AyKaydi kodu yarinTatil olarak okunur (3,5 saat sayılır)', () {
      // Senaryo: 31 Aralık'ta 20:00–08:00 nöbet; 1 Ocak tatil.
      // Haftanın geri kalanı kGunduz12 (11h/gün).
      // Beklenen: 5 × 11 + 0 (1 Oca N.İ.) + 3,5 = 58,5 saat.
      final aralik = AyKaydi(yil: 2026, ay: 12);
      final ocak = AyKaydi(yil: 2027, ay: 1);

      // Paz–Per: kGunduz12
      for (var g = 27; g <= 30; g++) {
        aralik.ata(g, personelId, kGunduz12);
      }
      aralik.ata(31, personelId, kGece12);  // 31 Aralık — 20:00–08:00
      ocak.ata(1, personelId, kResmiTatil); // 1 Ocak resmi tatil
      // 2 Ocak boş (N.İ.)

      final hafta = [
        for (var g = 27; g <= 31; g++) DateTime(2026, 12, g),
        DateTime(2027, 1, 1),
        DateTime(2027, 1, 2),
      ];

      final toplam = haftalikToplamSaat(
        haftaGunleri: hafta,
        ayar: ayar, // ayar.resmiTatiller boş — sadece AyKaydi koduna bakıyor
        personelId: personelId,
        kayitBul: (t) => t.month == 12 ? aralik : ocak,
      );
      // 4 × 11 (Paz–Per kGunduz12) + 3,5 (31 Ara kGece12 gece yarısına kadar)
      // + 0 (1 Oca kResmiTatil) + 0 (2 Oca boş) = 47,5
      expect(toplam, closeTo(47.5, 0.001));
    });

    test(
        '31 Aralık kGece12 ama 1 Ocak tatil DEĞİL — 11 saat tam sayılır', () {
      // resmiTatiller boş DEĞİL ama 1 Ocak yok → tatil değil
      final ayarTatilsiz = KurumAyari(resmiTatiller: {'15.07.2027'});
      final aralik = AyKaydi(yil: 2026, ay: 12);
      final ocak = AyKaydi(yil: 2027, ay: 1);
      aralik.ata(31, personelId, kGece12);

      final hafta = [DateTime(2026, 12, 31), DateTime(2027, 1, 1)];
      final toplam = haftalikToplamSaat(
        haftaGunleri: hafta,
        ayar: ayarTatilsiz,
        personelId: personelId,
        kayitBul: (t) => t.month == 12 ? aralik : ocak,
      );
      expect(toplam, closeTo(11.0, 0.001)); // 31 Ara tam 11 saat
    });

    test(
        'gunSonucu yarinKodResmiTatil parametresi — kGece12 + tatil kodu = 3,5 saat',
        () {
      final aralik = AyKaydi(yil: 2026, ay: 12);
      aralik.ata(31, personelId, kGece12);
      final sonuc = mh.gunSonucu(
        ayar: ayar,
        kayit: aralik,
        gun: 31,
        yil: 2026,
        ay: 12,
        gunSayisi: 31,
        personelId: personelId,
        yarinKodResmiTatil: true,
      );
      expect(sonuc.normal, closeTo(3.5, 0.001));
      expect(sonuc.fazlaGun, closeTo(0.0, 0.001)); // son gün — Ocak'a devredilir
    });

    test('sınır haftasında yanlış AyKaydi seçilirse toplam farklı çıkar '
        '(regresyon: gunSayisi/AyKaydi eşleşmesi önemli)', () {
      final haziran = AyKaydi(yil: 2026, ay: 6);
      final temmuz = AyKaydi(yil: 2026, ay: 7);
      haziran.ata(29, personelId, kGunduz12);
      haziran.ata(30, personelId, kGunduz12);
      for (var g = 1; g <= 5; g++) {
        temmuz.ata(g, personelId, kGunduz12);
      }

      final hafta = [
        DateTime(2026, 6, 29),
        DateTime(2026, 6, 30),
        for (var g = 1; g <= 5; g++) DateTime(2026, 7, g),
      ];

      // Bilerek hep aynı (yanlış) AyKaydi'yi döndürür — Temmuz günleri
      // Haziran kaydında bulunamayacağı için boş (0 saat) sayılır.
      final yanlisToplam = haftalikToplamSaat(
        haftaGunleri: hafta,
        ayar: ayar,
        personelId: personelId,
        kayitBul: (_) => haziran,
      );
      expect(yanlisToplam, closeTo(22.0, 0.001)); // sadece 29-30 Haziran
      expect(yanlisToplam, isNot(closeTo(77.0, 0.001)));
    });
  });
}
