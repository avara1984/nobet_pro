import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/donem_haftalik.dart';

void main() {
  test('Ekim 2026: 15 Ekim Perşembe → 12 Ekim Pazartesi, 14 Kasım Cumartesi → 15 Kasım Pazar', () {
    expect(donemHaftalikBaslangic(2026, 10), DateTime(2026, 10, 12));
    expect(donemHaftalikBaslangic(2026, 10).weekday, DateTime.monday);
    expect(donemHaftalikBitis(2026, 10), DateTime(2026, 11, 15));
    expect(donemHaftalikBitis(2026, 10).weekday, DateTime.sunday);
    final haftalar = donemHaftalikGunler(2026, 10);
    expect(haftalar.length, 5);
    expect(haftalar.every((h) => h.length == 7), isTrue);
    expect(haftalar.first.first.weekday, DateTime.monday);
    expect(haftalar.last.last.weekday, DateTime.sunday);
  });

  test('15\'i Pazartesi ise o gün başlar; 14\'ü Pazar ise o gün biter', () {
    // 15.06.2026 Pazartesi
    expect(donemHaftalikBaslangic(2026, 6), DateTime(2026, 6, 15));
    // 14.06.2026 Pazar
    expect(donemHaftalikBitis(2026, 5), DateTime(2026, 6, 14));
    expect(donemHaftalikBaslangic(2026, 5), DateTime(2026, 5, 11));
  });

  test('Aralık → Ocak yıl geçişi', () {
    expect(donemHaftalikBaslangic(2026, 12), DateTime(2026, 12, 14));
    expect(donemHaftalikBitis(2026, 12), DateTime(2027, 1, 17));
  });

  test('donemIcindeMi dolgu günlerini dışarıda bırakır', () {
    expect(donemIcindeMi(DateTime(2026, 10, 14), 2026, 10), isFalse);
    expect(donemIcindeMi(DateTime(2026, 10, 15), 2026, 10), isTrue);
    expect(donemIcindeMi(DateTime(2026, 11, 14), 2026, 10), isTrue);
    expect(donemIcindeMi(DateTime(2026, 11, 15), 2026, 10), isFalse);
  });

  test('Kasım 2026: 15 Kasım Pazar → 9 Kasım Pazartesi; 14 Aralık Pazartesi → 20 Aralık Pazar', () {
    expect(donemHaftalikBaslangic(2026, 11), DateTime(2026, 11, 9));
    expect(donemHaftalikBitis(2026, 11), DateTime(2026, 12, 20));
    expect(donemHaftalikGunler(2026, 11).length, 6);
    // Toplam yalnızca 15 Kasım – 14 Aralık günlerine bakar.
    expect(donemIcindeMi(DateTime(2026, 11, 14), 2026, 11), isFalse);
    expect(donemIcindeMi(DateTime(2026, 11, 15), 2026, 11), isTrue);
    expect(donemIcindeMi(DateTime(2026, 12, 14), 2026, 11), isTrue);
    expect(donemIcindeMi(DateTime(2026, 12, 15), 2026, 11), isFalse);
  });
}
