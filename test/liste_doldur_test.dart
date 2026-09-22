import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/liste_doldur.dart';
import 'package:nobet_pro/modeller/modeller.dart';

/// "Liste Yap" özelliğinin paylaşılan çekirdek motoru — Haftalık Nöbet
/// ekranının bu motoru ay sınırını aşarak (mutlak gün + hedefCoz) nasıl
/// kullandığını doğrular.
void main() {
  final ayar = KurumAyari();
  final personeller = [
    Personel(id: 'p1', ad: 'Bir'),
    Personel(id: 'p2', ad: 'İki'),
  ];

  test('tek ay içinde 2 günlük döngü tekrarlanır', () {
    final kayit = AyKaydi(yil: 2026, ay: 7);
    kayit.ata(1, 'p1', kGunduz12);
    kayit.ata(1, 'p2', kGece12);
    kayit.ata(2, 'p1', kGece12);
    kayit.ata(2, 'p2', kGunduz12);

    cekirdektenDoldur(
      ayar: ayar,
      personeller: personeller,
      kaynak: kayit,
      kaynakBaslangic: 1,
      kaynakGunSayisi: 2,
      cekirdek: 2,
      ilkMutlakGun: 3,
      sonMutlakGun: 6,
      hedefCoz: (g) => (kayit, DateTime(2026, 7, g)),
    );

    expect(kayit.kod(3, 'p1'), kGunduz12); // 1. günün tekrarı
    expect(kayit.kod(4, 'p1'), kGece12); // 2. günün tekrarı
    expect(kayit.kod(5, 'p1'), kGunduz12);
    expect(kayit.kod(6, 'p1'), kGece12);
  });

  test('mutlak gün aralığı ay sınırını aşınca döngü kesintisiz sürer', () {
    // Haziran'ın son 2 günü çekirdek — kaynak, hedeften (Temmuz + Ağustos
    // taşan günleri) tamamen ayrı bir AyKaydi (gerçek "geçen aydan devam
    // et" kullanımıyla birebir aynı kurulum: kaynak asla hedefle aynı
    // günlere yazılmaz).
    final haziran = AyKaydi(yil: 2026, ay: 6);
    final temmuz = AyKaydi(yil: 2026, ay: 7);
    final agustos = AyKaydi(yil: 2026, ay: 8);
    haziran.ata(29, 'p1', kGunduz12);
    haziran.ata(30, 'p1', kGece12);

    cekirdektenDoldur(
      ayar: ayar,
      personeller: personeller,
      kaynak: haziran,
      kaynakBaslangic: 29,
      kaynakGunSayisi: 30,
      cekirdek: 2,
      ilkMutlakGun: 1,
      sonMutlakGun: 33, // Temmuz'un 31 günü + Ağustos'un ilk 2 günü
      hedefCoz: (mutlakGun) => mutlakGun <= 31
          ? (temmuz, DateTime(2026, 7, mutlakGun))
          : (agustos, DateTime(2026, 8, mutlakGun - 31)),
    );

    // Döngü mutlakGun=1'den başlıyor: 1->kaynakGun 29, 2->30, 3->29...
    expect(temmuz.kod(1, 'p1'), kGunduz12);
    expect(temmuz.kod(2, 'p1'), kGece12);
    expect(temmuz.kod(31, 'p1'), kGunduz12); // 31 tek -> faz 29 ile aynı
    // Ağustos'un 1. günü (mutlakGun 32) fazı temmuz'un 31 ile aynı devam
    // etmeli — ay sınırında döngü kesilmiyor.
    expect(agustos.kod(1, 'p1'), kGece12);
    expect(agustos.kod(2, 'p1'), kGunduz12);
  });

  test('mesai (dahiliye) personeli döngüye girmez, hafta sonu H.T. alır', () {
    final kayit = AyKaydi(yil: 2026, ay: 8);
    // 02.08.2026 Pazar.
    final mesaili = [
      Personel(id: 'm1', ad: 'Dahiliye', gorev: GorevTipi.mesai),
    ];
    kayit.ata(1, 'm1', kMesai);

    cekirdektenDoldur(
      ayar: ayar,
      personeller: mesaili,
      kaynak: kayit,
      kaynakBaslangic: 1,
      kaynakGunSayisi: 1,
      cekirdek: 1,
      ilkMutlakGun: 2,
      sonMutlakGun: 2,
      hedefCoz: (g) => (kayit, DateTime(2026, 8, g)),
    );

    expect(kayit.kod(2, 'm1'), kHaftaTatili);
  });

  test('boş/N.İ. kaynak günü hedefte N.İ. olarak yazılır', () {
    final kayit = AyKaydi(yil: 2026, ay: 8);
    cekirdektenDoldur(
      ayar: ayar,
      personeller: personeller,
      kaynak: kayit,
      kaynakBaslangic: 1,
      kaynakGunSayisi: 1,
      cekirdek: 1,
      ilkMutlakGun: 2,
      sonMutlakGun: 2,
      hedefCoz: (g) => (kayit, DateTime(2026, 8, g)),
    );
    expect(kayit.kod(2, 'p1'), kNobetIzni);
  });
}
