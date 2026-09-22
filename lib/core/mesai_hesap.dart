import '../modeller/modeller.dart';

/// Bir günün bordro sonucu — hem [NobetDurumu.saatBilgisi] hem yıllık
/// fazla mesai raporu bu tek fonksiyonu kullanır, mantık tek yerde durur.
typedef MesaiSonucu = ({
  double toplam,
  double gece,
  double normal,
  double fazlaGun,
  int yillikIzin,
});

const MesaiSonucu kBosMesaiSonucu =
    (toplam: 0.0, gece: 0.0, normal: 0.0, fazlaGun: 0.0, yillikIzin: 0);

/// Tek bir günün bordro değerlerini hesaplar (madde 2).
///
/// Ayın SON gününde gece vardiyası (20:00-08:00 veya 24:00-08:00) varsa,
/// o günün fazla mesai günü kasıtlı olarak 0 döner — bir sonraki ayın
/// hesabına [oncekiAySonKoduSarkanMi] ile devredilir, böylece aynı fazla
/// mesai iki farklı ayda çift sayılmaz.
MesaiSonucu gunSonucu({
  required KurumAyari ayar,
  required AyKaydi kayit,
  required int gun,
  required int yil,
  required int ay,
  required int gunSayisi,
  required String personelId,
  // AyKaydi'de bir sonraki günün kodu kResmiTatil ise true geçir.
  // KurumAyari.resmiTatiller listesine eklenmemiş tatil günlerini yakalar.
  bool yarinKodResmiTatil = false,
}) {
  final kod = kayit.kod(gun, personelId);
  if (kod.isEmpty ||
      kod == kNobetIzni ||
      kod == kHaftaTatili ||
      kod == kResmiTatil) {
    return kBosMesaiSonucu;
  }

  final tarih = DateTime(yil, ay, gun);
  final pazar = tarih.weekday == DateTime.sunday;
  final tamTatil = ayar.resmiTatilMi(tarih);
  final yarimGun = ayar.yarimGunMu(tarih);

  if (kod == kYillikIzin) {
    if (pazar || tamTatil) return kBosMesaiSonucu;
    return (toplam: 7.5, gece: 0.0, normal: 7.5, fazlaGun: 0.0, yillikIzin: 1);
  }

  if (kod == kIdariIzin) {
    if (pazar || tamTatil) return kBosMesaiSonucu;
    final s = yarimGun ? 3.5 : 9.0;
    return (toplam: s, gece: 0.0, normal: s, fazlaGun: 0.0, yillikIzin: 0);
  }

  final v = ayar.vardiyaBul(kod);
  final yarinTatil = ayar.resmiTatilMi(tarih.add(const Duration(days: 1)))
      || yarinKodResmiTatil;

  final toplam = v.saat;
  final gece = v.geceSaati;
  var normal = toplam;
  var fazlaGun = 0.0;

  const gunduzVardiyalari = {kSabah8, kAksam8, kMesai};

  if (kod == kGunduz12) {
    // 08:00–20:00 tamamen bugüne düşer.
    if (tamTatil) {
      normal = 0.0;
      fazlaGun = 1.0;
    } else if (yarimGun) {
      normal = 3.5;
      fazlaGun = 1.0;
    }
  } else if (kod == kGece8) {
    // 24:00–08:00 tamamen ertesi güne düşer.
    if (yarinTatil) {
      normal = 0.0;
      fazlaGun = 1.0;
    }
  } else if (kod == kGece12) {
    // 20:00–08:00: bugün tatilse tüm gün fazla; yarın tatilse gece kısmı fazla.
    if (tamTatil) {
      normal = 0.0;
      fazlaGun = 1.0;
    } else if (yarinTatil) {
      normal = 3.5;
      fazlaGun = 1.0;
    }
  } else if (gunduzVardiyalari.contains(kod)) {
    if (tamTatil) {
      normal = 0.0;
      fazlaGun = 1.0;
    } else if (yarimGun) {
      normal = 3.5;
      fazlaGun = 1.0;
    }
  }

  // Ayın son günündeki gece vardiyası bir sonraki aya sarkar — çift
  // sayılmasın diye burada değil, sonraki ayın hesabında sayılır.
  if (gun == gunSayisi && (kod == kGece12 || kod == kGece8)) {
    fazlaGun = 0.0;
  }

  return (
    toplam: toplam,
    gece: gece,
    normal: normal,
    fazlaGun: fazlaGun,
    yillikIzin: 0,
  );
}

/// Önceki ayın son gününden bu aya sarkan fazla mesai (1.0 veya 0.0).
double oncekiAydanSarkanFazlaMesai({
  required KurumAyari ayar,
  required AyKaydi? oncekiAyKayit,
  required String personelId,
  required int yil,
  required int ay,
}) {
  if (oncekiAyKayit == null) return 0.0;
  if (!ayar.resmiTatilMi(DateTime(yil, ay, 1))) return 0.0;
  final oncekiAy = ay == 1 ? 12 : ay - 1;
  final oncekiYil = ay == 1 ? yil - 1 : yil;
  final oncekiGunSayisi = DateTime(oncekiYil, oncekiAy + 1, 0).day;
  final k = oncekiAyKayit.kod(oncekiGunSayisi, personelId);
  return (k == kGece12 || k == kGece8) ? 1.0 : 0.0;
}

/// Bir ayın tamamı için bir personelin toplam fazla mesai gün sayısı.
double aylikFazlaMesaiGunu({
  required KurumAyari ayar,
  required AyKaydi kayit,
  required AyKaydi? oncekiAyKayit,
  required String personelId,
  required int yil,
  required int ay,
}) {
  final gunSayisi = DateTime(yil, ay + 1, 0).day;
  var toplam = oncekiAydanSarkanFazlaMesai(
    ayar: ayar,
    oncekiAyKayit: oncekiAyKayit,
    personelId: personelId,
    yil: yil,
    ay: ay,
  );
  for (var g = 1; g <= gunSayisi; g++) {
    toplam += gunSonucu(
      ayar: ayar,
      kayit: kayit,
      gun: g,
      yil: yil,
      ay: ay,
      gunSayisi: gunSayisi,
      personelId: personelId,
    ).fazlaGun;
  }
  return toplam;
}
