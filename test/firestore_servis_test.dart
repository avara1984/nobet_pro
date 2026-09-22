import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/modeller/bordro_modelleri.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/firestore_servis.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreServis servis;
  const kurum = 'varsayilan';
  const birim = 'varsayilan#guvenlik';

  setUp(() {
    db = FakeFirebaseFirestore();
    servis = FirestoreServis(veritabani: db);
  });

  group('Temel CRUD', () {
    test('kurum ayarı: yoksa varsayılanı yazar, sonra okur', () async {
      final ilk = await servis.kurumAyariGetir(kurum);
      expect(ilk.vardiyalar, isNotEmpty);

      ilk.ad = 'TEST HASTANESİ';
      await servis.kurumAyariKaydet(ilk);
      expect((await servis.kurumAyariGetir(kurum)).ad, 'TEST HASTANESİ');

      // Doküman gerçekten nobet_pro koleksiyonunda 'j' alanıyla durmalı
      final doc = await db.collection('nobet_pro').doc('kurum_$kurum').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['j'], isA<String>());
    });

    test('personel ekle/güncelle/sil ve sıralama', () async {
      await servis.personelKaydet(
          birim, Personel(id: 'p2', ad: 'İkinci', sira: 1));
      await servis.personelKaydet(
          birim, Personel(id: 'p1', ad: 'Birinci', sira: 0));
      var liste = await servis.personelleriGetir(birim);
      expect(liste.map((p) => p.id).toList(), ['p1', 'p2']);

      await servis.personelKaydet(
          birim, Personel(id: 'p1', ad: 'Birinci Yeni', sira: 0));
      liste = await servis.personelleriGetir(birim);
      expect(liste.length, 2, reason: 'güncelleme kopya oluşturmamalı');
      expect(liste.first.ad, 'Birinci Yeni');

      await servis.personelSil(birim, 'p1');
      expect((await servis.personelleriGetir(birim)).length, 1);
    });

    test('ay kaydı versiyonlu yazılıp okunur', () async {
      final kayit = AyKaydi(yil: 2026, ay: 7, versiyon: kVersiyonTaslak);
      kayit.ata(1, 'p1', kGunduz12);
      await servis.ayKaydiKaydet(birim, kayit);

      final geri = await servis.ayKaydiGetir(birim, 2026, 7,
          versiyon: kVersiyonTaslak);
      expect(geri.kod(1, 'p1'), kGunduz12);

      // Asıl liste (boş versiyon) etkilenmemeli
      final asil = await servis.ayKaydiGetir(birim, 2026, 7);
      expect(asil.kod(1, 'p1'), '');

      await servis.versiyonSil(birim, 2026, 7, kVersiyonTaslak);
      final silinmis = await servis.ayKaydiGetir(birim, 2026, 7,
          versiyon: kVersiyonTaslak);
      expect(silinmis.kod(1, 'p1'), '');
    });

    test('kullanıcılar: ilk açılışta varsayılan yönetici', () async {
      final ilk = await servis.kullanicilariGetir(kurum);
      expect(ilk.length, 1);
      expect(ilk.first.rol, Rol.yonetici);

      await servis.kullaniciKaydet(
        kurum,
        Kullanici.yonetici(
          uid: 'u2',
          ad: 'Bordrocu',
          kurumId: kurum,
          profil: YoneticiProfili.bordro,
        ),
      );
      final liste = await servis.kullanicilariGetir(kurum);
      expect(liste.length, 2);
      final bordrocu = liste.firstWhere((k) => k.uid == 'u2');
      expect(bordrocu.yoneticiProfili, YoneticiProfili.bordro,
          reason: 'profil JSON gidiş-dönüşünde korunmalı');
    });
  });

  group('Bordro', () {
    BordroSonucu ornekBordro(String pid, String ad, int yil, int ay) =>
        BordroSonucu(
          personelId: pid,
          personelAd: ad,
          yil: yil,
          ay: ay,
          calismaGunu: 31,
          sgkGunu: 30,
          geceSaati: 88,
          tatilGunu: 1,
          yolGunu: 22,
          gunlukUcretToplami: 1,
          sosyalYardim: 1,
          hizmetPrimi: 1,
          hizmetZammi: 1,
          yolYardimi: 1,
          geceCalismaUcreti: 1,
          tatilCalismaUcreti: 1,
          brutGelir: 7,
          sgkMatrahi: 7,
          sgkCalisanKesintisi: 1,
          sgkIssizlikKesintisi: 1,
          aylikVergiMatrahi: 5,
          oncekiYillikMatrah: 0,
          yillikMatrah: 5,
          gelirVergisi: 1,
          gelirVergisiIstisnasi: 0,
          netGelirVergisi: 1,
          damgaVergisi: 0,
          sendikaKesintisi: 0,
          toplamKesinti: 3,
          odenecekTutar: 4,
        );

    test('bordro CRUD + önek taraması birimleri karıştırmaz', () async {
      await servis.bordroKaydet(birim, ornekBordro('p1', 'Ali', 2026, 7));
      await servis.bordroKaydet(birim, ornekBordro('p1', 'Ali', 2026, 8));
      await servis.bordroKaydet(
          'varsayilan#temizlik', ornekBordro('p9', 'Veli', 2026, 7));

      final hepsi = await servis.bordrolariGetir(birim);
      expect(hepsi.length, 2, reason: 'temizlik kaydı gelmemeli');
      expect(hepsi.first.ay, 8, reason: 'yeni dönem önce');

      expect((await servis.bordrolariGetir(birim, yil: 2026, ay: 7)).length, 1);
      expect(await servis.bordroGetir(birim, 'p1', 2026, 7), isNotNull);

      await servis.bordroSil(birim, 'p1', 2026, 7);
      expect(await servis.bordroGetir(birim, 'p1', 2026, 7), isNull);
    });

    test('bordro ayarı ve ücretler', () async {
      final ayar = await servis.bordroAyariGetir(kurum, 2026);
      ayar.sosyalYardim = 9999;
      await servis.bordroAyariKaydet(kurum, ayar);
      expect(
          (await servis.bordroAyariGetir(kurum, 2026)).sosyalYardim, 9999);

      await servis.personelUcretiKaydet(
          birim, PersonelUcreti(personelId: 'p1', gunlukUcret: 2000));
      await servis.personelUcretiKaydet(
          birim, PersonelUcreti(personelId: 'p1', gunlukUcret: 2500));
      final ucretler = await servis.personelUcretleriGetir(birim);
      expect(ucretler.length, 1);
      expect(ucretler.first.gunlukUcret, 2500);
    });
  });

  group('Yedekleme', () {
    test('dışa aktar / içe aktar gidiş-dönüşü', () async {
      await servis.kurumAyariGetir(kurum); // varsayılanı yazar
      await servis.personelKaydet(birim, Personel(id: 'p1', ad: 'Ali VELİ'));
      final kayit = AyKaydi(yil: 2026, ay: 7);
      kayit.ata(1, 'p1', kGece12);
      await servis.ayKaydiKaydet(birim, kayit);

      final json = await servis.tumVeriyiDisaAktar();
      final harita = jsonDecode(json) as Map<String, dynamic>;
      final veri = Map<String, dynamic>.from(harita['veri'] as Map);
      expect(veri.keys, contains('kurum_$kurum'));
      expect(veri.keys, contains('personeller_$birim'));
      expect(veri.keys, contains('nobet_${birim}_2026-07'));

      // Temiz bir "cihaza" geri yükle
      final db2 = FakeFirebaseFirestore();
      final servis2 = FirestoreServis(veritabani: db2);
      await servis2.yedektenYukle(json);

      final personeller = await servis2.personelleriGetir(birim);
      expect(personeller.single.ad, 'Ali VELİ');
      final geriKayit = await servis2.ayKaydiGetir(birim, 2026, 7);
      expect(geriKayit.kod(1, 'p1'), kGece12);
    });

    test('yerel yedek biçimiyle uyumlu (veri altında düz anahtarlar)', () async {
      // YerelServis.tumVeriyiDisaAktar biçimini taklit eden bir yedek
      final yerelYedek = jsonEncode({
        'surum': 1,
        'tarih': DateTime.now().toIso8601String(),
        'veri': {
          'personeller_$birim': jsonEncode([
            {'id': 'p7', 'ad': 'Yerelden Gelen', 'aktif': true, 'sira': 0},
          ]),
        },
      });
      await servis.yedektenYukle(yerelYedek);
      final liste = await servis.personelleriGetir(birim);
      expect(liste.single.ad, 'Yerelden Gelen');
    });
  });

  group('Sağlık kontrolü', () {
    test('koleksiyon erişilebilirse hata fırlatmaz', () async {
      await expectLater(servis.saglikKontrolu(kurum), completes);
    });
  });
}
