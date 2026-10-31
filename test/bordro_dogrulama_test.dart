import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/bordro_hesap.dart';
import 'package:nobet_pro/core/para.dart';
import 'package:nobet_pro/modeller/bordro_modelleri.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/veri_servisi.dart';

void main() {
  group('Para', () {
    test('Türkçe biçim', () {
      expect(Para.tl(64220.31), '64.220,31');
      expect(Para.tl(1234.5), '1.234,50');
      expect(Para.tl(-1234.5), '-1.234,50');
      expect(Para.tl(999999999, basamak: 0), '999.999.999');
      expect(Para.tl(0), '0,00');
    });

    test('çözümleme — hem TR hem klavye yazımı', () {
      expect(Para.coz('64.220,31'), closeTo(64220.31, 0.001));
      expect(Para.coz('64220.31'), closeTo(64220.31, 0.001));
      expect(Para.coz('1234,5'), closeTo(1234.5, 0.001));
      expect(Para.coz('abc'), isNull);
      expect(Para.cozVeya('abc', 7), 7);
    });
  });

  group('Vergi dilimleri', () {
    const dilimler = kVarsayilanVergiDilimleri;

    test('ilk dilim içinde kalırsa düz oran', () {
      expect(dilimliVergi(10000, dilimler), closeTo(1500, 0.01));
    });

    test('dilim geçişi doğru bölünür', () {
      // 190.000 × %15 = 28.500 ; kalan 10.000 × %20 = 2.000
      expect(dilimliVergi(200000, dilimler), closeTo(28500 + 2000, 0.01));
    });

    test('kümülatif fark = bu ayın vergisi', () {
      final fark = dilimliVergiFarki(
          oncekiMatrah: 50000, yeniMatrah: 100000, dilimler: dilimler);
      final beklenen =
          dilimliVergi(100000, dilimler) - dilimliVergi(50000, dilimler);
      expect(fark, closeTo(beklenen, 0.001));
    });
  });

  group('bordroHesapla', () {
    final personel = Personel(id: 'p1', ad: 'Murat ZENCİROĞLU');
    final ayar = BordroAyari(yil: 2026);

    test('hizmet primi = Md.33 × %16 (referans bordro doğrulaması)', () {
      // Referans: 72.978,65 × 0,16 = 11.676,58
      final ucret =
          PersonelUcreti(personelId: 'p1', gunlukUcret: 72978.65 / 31);
      final r = bordroHesapla(
        personel: personel,
        ucret: ucret,
        ayar: ayar,
        yil: 2026,
        ay: 7,
        calismaGunu: 31,
        sgkGunu: 30,
        geceSaati: 0,
        tatilGunu: 0,
        yolGunu: 0,
        oncekiYillikMatrah: 0,
      );
      expect(r.gunlukUcretToplami, closeTo(72978.65, 0.01));
      expect(r.hizmetPrimi, closeTo(11676.58, 0.01));
    });

    test('gelir/kesinti kalemleri ve ödenecek tutar tutarlı', () {
      final ucret = PersonelUcreti(
        personelId: 'p1',
        gunlukUcret: 2354.15,
        hizmetZammi: 1200,
        sendikaUyesi: true,
      );
      final r = bordroHesapla(
        personel: personel,
        ucret: ucret,
        ayar: ayar,
        yil: 2026,
        ay: 7,
        calismaGunu: 31,
        sgkGunu: 30,
        geceSaati: 88,
        tatilGunu: 1,
        yolGunu: 22,
        oncekiYillikMatrah: 0,
      );

      // Brüt = kalemlerin toplamı
      final kalemToplami = r.gunlukUcretToplami +
          r.sosyalYardim +
          r.hizmetPrimi +
          r.hizmetZammi +
          r.yolYardimi +
          r.geceCalismaUcreti +
          r.tatilCalismaUcreti;
      expect(r.brutGelir, closeTo(kalemToplami, 0.001));

      // Md.23 gece = (günlük / 7,5) × 0,35 × gece saati
      expect(r.geceCalismaUcreti,
          closeTo((2354.15 / 7.5) * 0.35 * 88, 0.001));
      // Md.22 tatil = günlük × 2 × gün
      expect(r.tatilCalismaUcreti, closeTo(2354.15 * 2 * 1, 0.001));
      // Md.40 yol = genel ayar × gün (kişiye özel tanımlı değil)
      expect(r.yolYardimi, closeTo(212.10 * 22, 0.001));

      // Sendika kesintisi = bir günlük ücret
      expect(r.sendikaKesintisi, closeTo(2354.15, 0.001));
      // Vergi matrahı = SGK matrahı − SGK − işsizlik − sendika
      expect(
        r.aylikVergiMatrahi,
        closeTo(
            r.sgkMatrahi -
                r.sgkCalisanKesintisi -
                r.sgkIssizlikKesintisi -
                r.sendikaKesintisi,
            0.001),
      );
      // Ödenecek = brüt − toplam kesinti
      expect(r.odenecekTutar, closeTo(r.brutGelir - r.toplamKesinti, 0.001));

      // Damga = (brüt − istisna) × oran
      expect(
        r.damgaVergisi,
        closeTo((r.brutGelir - 33030.30).clamp(0.0, double.infinity) * 0.00759,
            0.001),
      );
    });

    test('sendika üyesi değilse kesinti yok', () {
      final r = bordroHesapla(
        personel: personel,
        ucret: PersonelUcreti(
            personelId: 'p1', gunlukUcret: 2000, sendikaUyesi: false),
        ayar: ayar,
        yil: 2026,
        ay: 7,
        calismaGunu: 31,
        sgkGunu: 30,
        geceSaati: 0,
        tatilGunu: 0,
        yolGunu: 0,
        oncekiYillikMatrah: 0,
      );
      expect(r.sendikaKesintisi, 0);
    });

    test('kişiye özel yol yardımı genel ayarın yerine geçer', () {
      final r = bordroHesapla(
        personel: personel,
        ucret: PersonelUcreti(
            personelId: 'p1', gunlukUcret: 2000, yolYardimiGunluk: 120),
        ayar: ayar,
        yil: 2026,
        ay: 7,
        calismaGunu: 31,
        sgkGunu: 30,
        geceSaati: 0,
        tatilGunu: 0,
        yolGunu: 10,
        oncekiYillikMatrah: 0,
      );
      expect(r.yolYardimi, closeTo(1200, 0.001));
    });

    test('geçiş ayı: hizmet primi farkı otomatik %16', () {
      final r = bordroHesapla(
        personel: personel,
        ucret: PersonelUcreti(personelId: 'p1', gunlukUcret: 2000),
        ayar: ayar,
        yil: 2026,
        ay: 7,
        calismaGunu: 31,
        sgkGunu: 30,
        geceSaati: 0,
        tatilGunu: 0,
        yolGunu: 0,
        oncekiYillikMatrah: 0,
        gecisAyi: true,
        ucretFarki: 10000,
        sosyalYardimFarki: 500,
      );
      expect(r.hizmetPrimiFarki, closeTo(1600, 0.001));
      expect(r.farkToplami, closeTo(10000 + 1600 + 500, 0.001));
    });

    test('geçiş ayı kapalıysa farklar sıfırlanır', () {
      final r = bordroHesapla(
        personel: personel,
        ucret: PersonelUcreti(personelId: 'p1', gunlukUcret: 2000),
        ayar: ayar,
        yil: 2026,
        ay: 7,
        calismaGunu: 31,
        sgkGunu: 30,
        geceSaati: 0,
        tatilGunu: 0,
        yolGunu: 0,
        oncekiYillikMatrah: 0,
        ucretFarki: 10000,
      );
      expect(r.ucretFarki, 0);
      expect(r.hizmetPrimiFarki, 0);
      expect(r.farkToplami, 0);
    });
  });

  group('Nöbet listesinden girdi', () {
    test('gece saati ve yol günü doğru sayılır', () {
      // Boş KurumAyari hazır Türkiye tatil listesini kullanır (15 Temmuz dahil);
      // bu test tatilsiz bir ay istediği için Temmuz'a denk gelmeyen tek bir
      // tatil tanımlayıp varsayılan listeyi devre dışı bırakıyoruz.
      final ayar = KurumAyari(resmiTatiller: {'01.01.2026'});
      final kayit = AyKaydi(yil: 2026, ay: 7); // 31 gün
      final sonraki = AyKaydi(yil: 2026, ay: 8);

      // Temmuz: 1-31 arası tek günler gece 12, çift günler gündüz 12
      for (var g = 1; g <= 31; g++) {
        kayit.ata(g, 'p1', g.isOdd ? kGece12 : kGunduz12);
      }
      // Ağustos 1-14: 7 gün çalışma, 7 gün nöbet izni
      for (var g = 1; g <= 14; g++) {
        sonraki.ata(g, 'p1', g <= 7 ? kGunduz12 : kNobetIzni);
      }

      final girdi = nobettenGirdi(
        ayar: ayar,
        kayit: kayit,
        oncekiAyKaydi: null,
        sonrakiAyKaydi: sonraki,
        personelId: 'p1',
        yil: 2026,
        ay: 7,
      );

      // Tek günler (1,3,...,31) = 16 gece × 11 saat
      expect(girdi.geceSaati, closeTo(16 * 11.0, 0.001));
      // Yol: Temmuz 15-31 = 17 gün (hepsi dolu) + Ağustos 1-7 = 7 gün
      expect(girdi.yolGunu, 17 + 7);
      expect(girdi.doluGun, 31);
      // Temmuz'da tanımlı resmi tatil yok → tatil çalışma günü yok
      expect(girdi.tatilGunu, 0);
    });

    test('tatil tanımlanmamışsa hazır listedeki 15 Temmuz tatil sayılır', () {
      final kayit = AyKaydi(yil: 2026, ay: 7);
      kayit.ata(15, 'p1', kGece12); // 15 Temmuz hazır listede resmi tatil

      final girdi = nobettenGirdi(
        ayar: KurumAyari(),
        kayit: kayit,
        oncekiAyKaydi: null,
        sonrakiAyKaydi: null,
        personelId: 'p1',
        yil: 2026,
        ay: 7,
      );
      expect(girdi.tatilGunu, 1);
    });

    test('izin kodları yol gününe sayılmaz', () {
      final kayit = AyKaydi(yil: 2026, ay: 7);
      for (var g = 15; g <= 31; g++) {
        kayit.ata(g, 'p1', g.isOdd ? kYillikIzin : kHaftaTatili);
      }
      expect(
        yolGunuSayisi(
            kayit: kayit,
            sonrakiAyKaydi: null,
            personelId: 'p1',
            yil: 2026,
            ay: 7),
        0,
      );
    });

    test('resmi tatilde gündüz vardiyası fazla mesai günü sayılır', () {
      final tatilAyari = KurumAyari(resmiTatiller: {'15.07.2026'});
      final kayit = AyKaydi(yil: 2026, ay: 7);
      kayit.ata(15, 'p1', kMesai); // 08:00 - 17:30, resmi tatilde

      final girdi = nobettenGirdi(
        ayar: tatilAyari,
        kayit: kayit,
        oncekiAyKaydi: null,
        sonrakiAyKaydi: null,
        personelId: 'p1',
        yil: 2026,
        ay: 7,
      );
      expect(girdi.tatilGunu, 1);
    });
  });

  group('Veri katmanı (BellekServis)', () {
    test('bordro CRUD ve süzgeç', () async {
      final servis = BellekServis();
      const birim = 'varsayilan#guvenlik';

      // Ayar varsayılanla gelir, kaydedilince okunur
      final ayar = await servis.bordroAyariGetir('varsayilan', 2026);
      expect(ayar.hizmetPrimiOrani, 0.16);
      ayar.sosyalYardim = 5000;
      await servis.bordroAyariKaydet('varsayilan', ayar);
      expect((await servis.bordroAyariGetir('varsayilan', 2026)).sosyalYardim,
          5000);

      // Personel ücreti
      await servis.personelUcretiKaydet(
          birim, PersonelUcreti(personelId: 'p1', gunlukUcret: 2000));
      await servis.personelUcretiKaydet(
          birim, PersonelUcreti(personelId: 'p1', gunlukUcret: 2500));
      var ucretler = await servis.personelUcretleriGetir(birim);
      expect(ucretler.length, 1, reason: 'aynı personel iki kez eklenmemeli');
      expect(ucretler.first.gunlukUcret, 2500);

      await servis.personelUcretiSil(birim, 'p1');
      expect((await servis.personelUcretleriGetir(birim)), isEmpty);

      // Bordro kayıtları
      final r = bordroHesapla(
        personel: Personel(id: 'p1', ad: 'A B'),
        ucret: PersonelUcreti(personelId: 'p1', gunlukUcret: 2000),
        ayar: BordroAyari(yil: 2026),
        yil: 2026,
        ay: 7,
        calismaGunu: 31,
        sgkGunu: 30,
        geceSaati: 0,
        tatilGunu: 0,
        yolGunu: 0,
        oncekiYillikMatrah: 0,
      );
      await servis.bordroKaydet(birim, r);
      expect(await servis.bordroGetir(birim, 'p1', 2026, 7), isNotNull);
      expect((await servis.bordrolariGetir(birim, yil: 2026)).length, 1);
      expect((await servis.bordrolariGetir(birim, yil: 2026, ay: 8)), isEmpty);
      expect((await servis.bordrolariGetir('varsayilan#temizlik')), isEmpty,
          reason: 'birimler birbirine karışmamalı');

      await servis.bordroSil(birim, 'p1', 2026, 7);
      expect(await servis.bordroGetir(birim, 'p1', 2026, 7), isNull);
    });
  });

  group('JSON gidiş-dönüş', () {
    test('BordroAyari', () {
      final a = BordroAyari(yil: 2026, sosyalYardim: 1234.56);
      final b = BordroAyari.haritadan(2026, a.haritasi);
      expect(b.sosyalYardim, 1234.56);
      expect(b.vergiDilimleri.length, a.vergiDilimleri.length);
      expect(b.vergiDilimleri.first.oran, a.vergiDilimleri.first.oran);
    });

    test('PersonelUcreti', () {
      final u = PersonelUcreti(
          personelId: 'p1', gunlukUcret: 111.5, sendikaUyesi: false);
      final v = PersonelUcreti.haritadan('p1', u.haritasi);
      expect(v.gunlukUcret, 111.5);
      expect(v.sendikaUyesi, false);
    });

    test('BordroSonucu', () {
      final r = bordroHesapla(
        personel: Personel(id: 'p1', ad: 'Ali VELİ'),
        ucret: PersonelUcreti(personelId: 'p1', gunlukUcret: 2000),
        ayar: BordroAyari(yil: 2026),
        yil: 2026,
        ay: 7,
        calismaGunu: 31,
        sgkGunu: 30,
        geceSaati: 12,
        tatilGunu: 1,
        yolGunu: 20,
        oncekiYillikMatrah: 1000,
      );
      final s = BordroSonucu.haritadan(r.haritasi);
      expect(s.personelAd, 'Ali VELİ');
      expect(s.odenecekTutar, closeTo(r.odenecekTutar, 0.001));
      expect(s.yillikMatrah, closeTo(r.yillikMatrah, 0.001));
      expect(s.geceSaati, 12);
    });
  });
}
