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
}
