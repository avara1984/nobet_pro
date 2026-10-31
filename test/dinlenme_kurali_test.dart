import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/dinlenme_kurali.dart';
import 'package:nobet_pro/modeller/modeller.dart';

/// Aylık ve Haftalık Nöbet ekranlarının paylaştığı dinlenme kuralının
/// saf çekirdeği. `NobetDurumu.dinlenmeIhlali` bu fonksiyona delege eder
/// (bkz. lib/durum/nobet_durumu.dart) — burada test edilen davranış
/// ikisi için de geçerlidir.
void main() {
  group('dinlenmeIhlaliMetni', () {
    test('gece (12\'lik) → gündüz ihlal üretir', () {
      final uyari = dinlenmeIhlaliMetni(
        personelAdi: 'Ali Veli',
        oncekiKod: kGece12,
        yeniKod: kGunduz12,
      );
      expect(uyari, isNotNull);
      expect(uyari, contains('Ali Veli'));
      expect(uyari, contains(kGece12));
    });

    test('gece (8\'lik) → sabah/akşam/mesai ihlal üretir', () {
      for (final yeni in [kSabah8, kAksam8, kMesai]) {
        final uyari = dinlenmeIhlaliMetni(
          personelAdi: 'Ayşe',
          oncekiKod: kGece8,
          yeniKod: yeni,
        );
        expect(uyari, isNotNull, reason: '$yeni için ihlal beklenir');
      }
    });

    test('gece (12\'lik) → gece (8\'lik) ihlal değil', () {
      expect(
        dinlenmeIhlaliMetni(
            personelAdi: 'Ali', oncekiKod: kGece12, yeniKod: kGece8),
        isNull,
      );
    });

    test('gece (8\'lik) → aynı vardiya (8\'lik) ihlal değil', () {
      expect(
        dinlenmeIhlaliMetni(
            personelAdi: 'Ali', oncekiKod: kGece8, yeniKod: kGece8),
        isNull,
      );
    });

    test('gece (8\'lik) → izin/boş ihlal değil', () {
      expect(
        dinlenmeIhlaliMetni(
            personelAdi: 'Ali', oncekiKod: kGece8, yeniKod: kNobetIzni),
        isNull,
      );
      expect(
        dinlenmeIhlaliMetni(personelAdi: 'Ali', oncekiKod: kGece8, yeniKod: ''),
        isNull,
      );
    });

    test('gece (8\'lik) → gece (12\'lik) ihlal üretir (madde 12A sıkı kural)',
        () {
      final uyari = dinlenmeIhlaliMetni(
          personelAdi: 'Ali', oncekiKod: kGece8, yeniKod: kGece12);
      expect(uyari, isNotNull);
      expect(uyari, contains('Ali'));
      expect(uyari, contains(kGece12));
    });

    test('gece (8\'lik) → gündüz(12\'lik) ihlal üretir', () {
      final uyari = dinlenmeIhlaliMetni(
          personelAdi: 'Ali', oncekiKod: kGece8, yeniKod: kGunduz12);
      expect(uyari, isNotNull);
    });

    test('gece → izin kodları ihlal değil', () {
      expect(
        dinlenmeIhlaliMetni(
            personelAdi: 'Ali', oncekiKod: kGece12, yeniKod: kYillikIzin),
        isNull,
      );
    });

    test('önceki kod gece değilse ihlal değil', () {
      expect(
        dinlenmeIhlaliMetni(
            personelAdi: 'Ali', oncekiKod: kGunduz12, yeniKod: kGunduz12),
        isNull,
      );
    });

    test('oncekiKod bilinmiyorsa (null) her zaman null döner', () {
      expect(
        dinlenmeIhlaliMetni(
            personelAdi: 'Ali', oncekiKod: null, yeniKod: kGunduz12),
        isNull,
      );
    });

    test('önceki kod boş string ise ihlal değil', () {
      expect(
        dinlenmeIhlaliMetni(personelAdi: 'Ali', oncekiKod: '', yeniKod: kGunduz12),
        isNull,
      );
    });
  });

  // Ters yön: yazılan vardiyadan çıkan personelin ERTESİ günü dolu mu?
  group('ertesiGunDinlenmeIhlaliMetni', () {
    String? ihlal(String yeni, String? sonraki) => ertesiGunDinlenmeIhlaliMetni(
        personelAdi: 'Ali Veli', yeniKod: yeni, sonrakiKod: sonraki);

    test('3 Aralık 08:00-20:00 varken 2 Aralık\'a 20:00-08:00 → ihlal', () {
      final uyari = ihlal(kGece12, kGunduz12);
      expect(uyari, isNotNull);
      expect(uyari, contains('Ali Veli'));
      expect(uyari, contains(kGece12));
      expect(uyari, contains(kGunduz12));
    });

    test('3 Aralık 08:00-20:00 varken 2 Aralık\'a 24:00-08:00 → ihlal', () {
      expect(ihlal(kGece8, kGunduz12), isNotNull);
    });

    test('20:00-08:00 yazılan günün ertesi sabah/akşam/mesai → ihlal', () {
      for (final s in [kGunduz12, kSabah8, kAksam8, kMesai]) {
        expect(ihlal(kGece12, s), isNotNull, reason: s);
      }
    });

    test('20:00-08:00 → ertesi gün yine gece ihlal değil', () {
      expect(ihlal(kGece12, kGece12), isNull);
      expect(ihlal(kGece12, kGece8), isNull);
    });

    test('24:00-08:00 yazılan günün ertesi: yalnızca yine 24:00-08:00 serbest', () {
      expect(ihlal(kGece8, kGece8), isNull);
      expect(ihlal(kGece8, kGece12), isNotNull);
      for (final s in [kGunduz12, kSabah8, kAksam8, kMesai]) {
        expect(ihlal(kGece8, s), isNotNull, reason: s);
      }
    });

    test('ertesi gün boş / izin / tatil ise uyarı yok', () {
      for (final s in ['', kNobetIzni, kYillikIzin, kIdariIzin, kHaftaTatili, kResmiTatil]) {
        expect(ihlal(kGece12, s), isNull, reason: 'gece12 → "$s"');
        expect(ihlal(kGece8, s), isNull, reason: 'gece8 → "$s"');
      }
      expect(ihlal(kGece12, null), isNull);
    });

    test('yazılan vardiya gece değilse ertesi güne bakılmaz', () {
      for (final yeni in [kGunduz12, kSabah8, kAksam8, kMesai, kYillikIzin, '']) {
        expect(ihlal(yeni, kGunduz12), isNull, reason: yeni);
        expect(ihlal(yeni, kGece12), isNull, reason: yeni);
      }
    });

    test('ileri yön ile tutarlı: ileri kural ihlal diyorsa ters kural da der (çalışma vardiyaları)', () {
      const calisma = [kGunduz12, kGece12, kGece8, kSabah8, kAksam8, kMesai];
      for (final a in calisma) {
        for (final b in calisma) {
          final ileri = dinlenmeIhlaliMetni(
              personelAdi: 'x', oncekiKod: a, yeniKod: b);
          final ters = ertesiGunDinlenmeIhlaliMetni(
              personelAdi: 'x', yeniKod: a, sonrakiKod: b);
          expect(ters != null, ileri != null, reason: '$a → $b');
        }
      }
    });
  });
}
