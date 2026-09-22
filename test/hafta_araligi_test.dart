import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/hafta_araligi.dart';

void main() {
  group('haftalikBaslangic / haftalikBitis', () {
    test('Temmuz örneği: Haziran son Pazartesi → Ağustos ilk Pazar', () {
      // 2026 Temmuz: 1'i Çarşamba. Haziran'ın son Pazartesi'si 29.06.2026.
      final baslangic = haftalikBaslangic(2026, 7);
      expect(baslangic, DateTime(2026, 6, 29));
      expect(baslangic.weekday, DateTime.monday);

      // Ağustos'un ilk Pazar'ı 02.08.2026.
      final bitis = haftalikBitis(2026, 7);
      expect(bitis, DateTime(2026, 8, 2));
      expect(bitis.weekday, DateTime.sunday);
    });

    test('ayın 1\'i tam Pazartesi olsa bile önceki haftaya gidilir', () {
      // 2026 Haziran: 1'i Pazartesi.
      final baslangic = haftalikBaslangic(2026, 6);
      expect(baslangic, isNot(DateTime(2026, 6, 1)));
      expect(baslangic, DateTime(2026, 5, 25));
      expect(baslangic.weekday, DateTime.monday);
    });

    test('ayın son günü tam Pazar olsa bile sonraki haftaya gidilir', () {
      // 2026 Mayıs: 31'i Pazar.
      final bitis = haftalikBitis(2026, 5);
      expect(bitis, isNot(DateTime(2026, 5, 31)));
      expect(bitis, DateTime(2026, 6, 7));
      expect(bitis.weekday, DateTime.sunday);
    });

    test('Aralık → Ocak yıl geçişi', () {
      final baslangic = haftalikBaslangic(2026, 12);
      final bitis = haftalikBitis(2026, 12);
      expect(baslangic.isBefore(DateTime(2026, 12, 1)), isTrue);
      expect(bitis.year, 2027);
      expect(bitis.month, 1);
      expect(baslangic.weekday, DateTime.monday);
      expect(bitis.weekday, DateTime.sunday);
    });

    test('Ocak → Aralık (önceki yıl) geçişi', () {
      final baslangic = haftalikBaslangic(2027, 1);
      expect(baslangic.year, 2026);
      expect(baslangic.month, 12);
      expect(baslangic.weekday, DateTime.monday);
    });
  });

  group('haftalaraBol / haftalikGunler', () {
    test('her blok tam 7 gün, Pazartesi ile başlar Pazar ile biter', () {
      final haftalar = haftalikGunler(2026, 7);
      expect(haftalar, isNotEmpty);
      for (final hafta in haftalar) {
        expect(hafta.length, 7);
        expect(hafta.first.weekday, DateTime.monday);
        expect(hafta.last.weekday, DateTime.sunday);
      }
    });

    test('bloklar ardışık ve boşluksuz', () {
      final haftalar = haftalikGunler(2026, 7);
      for (var i = 1; i < haftalar.length; i++) {
        final oncekiSon = haftalar[i - 1].last;
        final buIlk = haftalar[i].first;
        expect(buIlk.difference(oncekiSon).inDays, 1);
      }
    });

    test('aralık, haftalikBaslangic/haftalikBitis ile birebir eşleşir', () {
      final haftalar = haftalikGunler(2026, 7);
      expect(haftalar.first.first, haftalikBaslangic(2026, 7));
      expect(haftalar.last.last, haftalikBitis(2026, 7));
    });
  });
}
