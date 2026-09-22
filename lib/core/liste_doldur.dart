import '../modeller/modeller.dart';
import 'tarih.dart';

/// "Liste Yap" özelliğinin paylaşılan çekirdek dolgu motoru.
///
/// `NobetDurumu._cekirdektenDoldur`'un tek-ay modeliyle aynı matematiği
/// kullanır, ama hedefi tek bir `AyKaydi`'ye değil, [hedefCoz] üzerinden
/// çözülen **mutlak gün** aralığına yazar — bu sayede Haftalık Nöbet
/// ekranı, aynı döngüyü seçilen ayın sonunda kesmeden bir sonraki ayın
/// taşan (ızgarada görünen) günlerine kadar KESİNTİSİZ sürdürebilir.
///
/// [ilkMutlakGun]/[sonMutlakGun] tek bir sayaçtır; `hedefCoz` her mutlak
/// günü hangi `AyKaydi`'nin hangi takvim gününe karşılık geldiğine çevirir.
void cekirdektenDoldur({
  required KurumAyari ayar,
  required List<Personel> personeller,
  required AyKaydi kaynak,
  required int kaynakBaslangic,
  required int kaynakGunSayisi,
  required int cekirdek,
  required int ilkMutlakGun,
  required int sonMutlakGun,
  required (AyKaydi kayit, DateTime tarih) Function(int mutlakGun) hedefCoz,
}) {
  final mesailer = mesaiKisileri(
    personeller: personeller,
    kaynak: kaynak,
    kaynakGunSayisi: kaynakGunSayisi,
  );

  for (var mutlakGun = ilkMutlakGun; mutlakGun <= sonMutlakGun; mutlakGun++) {
    final (kayit, tarih) = hedefCoz(mutlakGun);
    final kaynakGun =
        kaynakBaslangic + ((mutlakGun - ilkMutlakGun) % cekirdek);

    for (final p in personeller) {
      if (mesailer.contains(p.id)) {
        kayit.ata(tarih.day, p.id, mesaiKodu(ayar, tarih));
        continue;
      }
      final k = kaynak.kod(kaynakGun, p.id);
      // N.İ. ve boş hücreler nöbet izni olarak yazılır.
      kayit.ata(tarih.day, p.id, (k.isEmpty || k == kNobetIzni) ? kNobetIzni : k);
    }
  }
}

/// Şablonda 08:00-17:30 yazan kişiler dahiliye (mesai) sayılır. Personel
/// kaydında mesai işareti varsa o da geçerlidir.
Set<String> mesaiKisileri({
  required List<Personel> personeller,
  required AyKaydi kaynak,
  required int kaynakGunSayisi,
}) {
  final kume = <String>{
    for (final p in personeller)
      if (p.mesaiMi) p.id
  };
  for (var g = 1; g <= kaynakGunSayisi; g++) {
    for (final p in personeller) {
      if (kaynak.kod(g, p.id) == kMesai) kume.add(p.id);
    }
  }
  return kume;
}

String mesaiKodu(KurumAyari ayar, DateTime tarih) {
  if (T.haftaSonu(tarih)) return kHaftaTatili;
  if (ayar.resmiTatilMi(tarih)) return kResmiTatil;
  return kMesai;
}
