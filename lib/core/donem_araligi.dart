import 'tarih.dart';

/// "15 - 14 Nöbet" ekranının tarih aralığı — bordro döneminde de kullanılan
/// aynı kural: seçilen ayın 15'inden bir sonraki ayın 14'üne kadar
/// (`core/bordro_hesap.dart`'taki `yolGunuSayisi` ile aynı sınırlar).
///
/// [yil]/[ay] ekranın üst çubuğunda seçili olan "referans ay"dır — dönem
/// HER ZAMAN bu ayın 15'inden başlar, bir önceki aya taşmaz.
List<DateTime> donemGunleri(int yil, int ay) {
  final gunler = <DateTime>[];
  final buAySonGun = DateTime(yil, ay + 1, 0).day;
  for (var g = 15; g <= buAySonGun; g++) {
    gunler.add(DateTime(yil, ay, g));
  }
  final sonrakiAy = ay == 12 ? 1 : ay + 1;
  final sonrakiYil = ay == 12 ? yil + 1 : yil;
  for (var g = 1; g <= 14; g++) {
    gunler.add(DateTime(sonrakiYil, sonrakiAy, g));
  }
  return gunler;
}

/// Dönemin başlangıcının ait olduğu (yıl, ay) — her zaman [yil]/[ay]'ın
/// kendisi (15'i bu ayda).
(int yil, int ay) donemBaslangicAyi(int yil, int ay) => (yil, ay);

/// Dönemin bitişinin ait olduğu (yıl, ay) — 14'ü bir sonraki ayda.
(int yil, int ay) donemBitisAyi(int yil, int ay) =>
    ay == 12 ? (yil + 1, 1) : (yil, ay + 1);

/// Ekran başlığında kullanılan "15.01.2026 - 14.02.2026" gibi kısa özet.
String donemBasligi(int yil, int ay) {
  final gunler = donemGunleri(yil, ay);
  return '${T.tarih(gunler.first)} - ${T.tarih(gunler.last)}';
}
