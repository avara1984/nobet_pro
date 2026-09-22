/// Haftalık Nöbet ekranının tarih aralığı hesabı.
///
/// Seçilen ay için ızgara, bir önceki ayın son Pazartesi'sinden bir
/// sonraki ayın ilk Pazar'ına kadar (ikisi de dahil) uzanır — her zaman
/// tam Pazartesi–Pazar haftalarına dolgulu. Ayın 1'i tam olarak
/// Pazartesi'yse bile başlangıç bilinçli olarak bir önceki haftaya gider
/// (aynı kural sonda da geçerli) — bu, kullanıcının tarif ettiği
/// davranışın birebir karşılığıdır: her zaman önceki/sonraki aydan bir
/// tampon hafta görünür.
library;

/// [yil]-[ay]'dan önceki ayın içindeki SON Pazartesi.
DateTime haftalikBaslangic(int yil, int ay) {
  // DateTime(yil, ay, 0) = önceki ayın son günü; ay=1 için otomatik
  // olarak (yil-1, 12) normalize edilir.
  var g = DateTime(yil, ay, 0);
  while (g.weekday != DateTime.monday) {
    g = g.subtract(const Duration(days: 1));
  }
  return g;
}

/// [yil]-[ay]'dan sonraki ayın içindeki İLK Pazar (aralığın kapsayıcı
/// üst sınırı).
DateTime haftalikBitis(int yil, int ay) {
  // DateTime(yil, ay+1, 1) = sonraki ayın ilk günü; ay=12 için otomatik
  // olarak (yil+1, 1) normalize edilir.
  var g = DateTime(yil, ay + 1, 1);
  while (g.weekday != DateTime.sunday) {
    g = g.add(const Duration(days: 1));
  }
  return g;
}

/// [baslangic]–[bitis] (ikisi de dahil) aralığını 7 günlük
/// Pazartesi–Pazar bloklarına böler. Aralık uzunluğu her zaman 7'nin
/// katı olmalıdır — [haftalikBaslangic]/[haftalikBitis] çiftinden
/// geliyorsa bu garantidir (biri Pazartesi, diğeri Pazar).
List<List<DateTime>> haftalaraBol(DateTime baslangic, DateTime bitis) {
  final gunler = <DateTime>[];
  for (var g = baslangic;
      !g.isAfter(bitis);
      g = g.add(const Duration(days: 1))) {
    gunler.add(g);
  }
  assert(gunler.length % 7 == 0,
      'Aralık tam haftalara bölünemiyor: ${gunler.length} gün');
  return [
    for (var i = 0; i < gunler.length; i += 7) gunler.sublist(i, i + 7),
  ];
}

/// [yil]-[ay] için doğrudan hafta bloklarını üretir — Haftalık Nöbet
/// ekranının kullandığı asıl giriş noktası.
List<List<DateTime>> haftalikGunler(int yil, int ay) =>
    haftalaraBol(haftalikBaslangic(yil, ay), haftalikBitis(yil, ay));
