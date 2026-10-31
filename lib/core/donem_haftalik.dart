/// "Haftalık 15 - 14" ekranının tarih aralığı: [yil]-[ay]'ın 15'inden bir
/// sonraki ayın 14'üne kadar süren bordro dönemi (bkz. `donem_araligi.dart`),
/// her iki ucu da tam Pazartesi–Pazar haftalarına tamamlanmış hâlde.
///
/// Başlangıç, 15'ini içeren haftanın Pazartesi'sidir (15'i Pazartesi ise
/// 15'inin kendisi); bitiş, 14'ünü içeren haftanın Pazar'ıdır (14'ü Pazar
/// ise 14'ünün kendisi). Haftalık Nöbet'teki "her zaman bir tampon hafta"
/// kuralı burada uygulanmaz — dönem sınırı zaten hafta ortasına denk gelir.
/// Örnek: Ekim 2026 → 12.10.2026 (Pzt) – 15.11.2026 (Paz).
library;

import 'hafta_araligi.dart';

/// Dönemin ilk günü: [yil]-[ay]'ın 15'i.
DateTime donemIlkGun(int yil, int ay) => DateTime(yil, ay, 15);

/// Dönemin son günü: bir sonraki ayın 14'ü.
DateTime donemSonGun(int yil, int ay) => DateTime(yil, ay + 1, 14);

/// 15'ini içeren haftanın Pazartesi'si.
DateTime donemHaftalikBaslangic(int yil, int ay) {
  var g = donemIlkGun(yil, ay);
  while (g.weekday != DateTime.monday) {
    g = g.subtract(const Duration(days: 1));
  }
  return g;
}

/// 14'ünü içeren haftanın Pazar'ı.
DateTime donemHaftalikBitis(int yil, int ay) {
  var g = donemSonGun(yil, ay);
  while (g.weekday != DateTime.sunday) {
    g = g.add(const Duration(days: 1));
  }
  return g;
}

/// Dönemi kapsayan Pazartesi–Pazar hafta blokları.
List<List<DateTime>> donemHaftalikGunler(int yil, int ay) => haftalaraBol(
    donemHaftalikBaslangic(yil, ay), donemHaftalikBitis(yil, ay));

/// [tarih] 15 - 14 dönemine (dolgu günleri hariç) ait mi?
bool donemIcindeMi(DateTime tarih, int yil, int ay) {
  final t = DateTime(tarih.year, tarih.month, tarih.day);
  return !t.isBefore(donemIlkGun(yil, ay)) && !t.isAfter(donemSonGun(yil, ay));
}
