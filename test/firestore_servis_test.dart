import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/modeller/bordro_modelleri.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/firestore_servis.dart';
import 'package:nobet_pro/servisler/veri_servisi.dart';

/// Windows'ta çöken `runTransaction` çağrısını yakalamak için: çağrılırsa test düşer.
class _IslemYasakliDb extends FakeFirebaseFirestore {
  int islemCagrisi = 0;

  @override
  Future<T> runTransaction<T>(TransactionHandler<T> transactionHandler,
      {Duration timeout = const Duration(seconds: 30),
      int maxAttempts = 5}) async {
    islemCagrisi++;
    throw StateError('runTransaction çağrılmamalıydı');
  }
}

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

  group('Veri güvenliği', () {
    Kullanici kisi(String uid) => Kullanici(
        uid: uid, ad: uid, eposta: '', rol: Rol.editor, kurumId: kurum);

    test('bozuk kullanıcı kaydı boş sayılıp varsayılanla ezilmez', () async {
      const doc = 'kullanicilar_$kurum';
      await db.collection('nobet_pro').doc(doc).set({'j': '{bozuk json'});

      await expectLater(
          servis.kullanicilariGetir(kurum), throwsA(isA<VeriBozukHatasi>()));
      await expectLater(servis.kullaniciKaydet(kurum, kisi('a')),
          throwsA(isA<VeriBozukHatasi>()));

      final hamli = await db.collection('nobet_pro').doc(doc).get();
      expect(hamli.data()!['j'], '{bozuk json',
          reason: 'bozuk kayıt olduğu gibi kalmalı');
    });

    test('bozuk personel / ay kaydı hata verir, boş dönmez', () async {
      await db
          .collection('nobet_pro')
          .doc('personeller_$birim')
          .set({'j': 'bozuk'});
      await expectLater(
          servis.personelleriGetir(birim), throwsA(isA<VeriBozukHatasi>()));

      await db
          .collection('nobet_pro')
          .doc('nobet_${birim}_2026-07')
          .set({'j': '[1,2'});
      await expectLater(servis.ayKaydiGetir(birim, 2026, 7),
          throwsA(isA<VeriBozukHatasi>()));
    });

    // Not: eşzamanlı yazma çakışmasının yeniden denenmesi gerçek Firestore'un
    // transaction davranışıdır; fake_cloud_firestore bunu taklit etmez, bu
    // yüzden burada test edilemez.
    test('art arda kayıtlar birikir', () async {
      await servis.kullanicilariGetir(kurum); // varsayılan yönetici
      for (var i = 0; i < 4; i++) {
        await servis.kullaniciKaydet(kurum, kisi('k$i'));
        await servis.personelKaydet(
            birim, Personel(id: 'p$i', ad: 'P$i', sira: i));
      }
      expect((await servis.kullanicilariGetir(kurum)).map((k) => k.uid).toSet(),
          {'yonetici', 'k0', 'k1', 'k2', 'k3'});
      expect((await servis.personelleriGetir(birim)).length, 4);
    });

    test('ilk açılış yöneticisi mevcut kullanıcıları ezmez', () async {
      await servis.kullaniciKaydet(kurum, kisi('a'));
      final liste = await servis.kullanicilariGetir(kurum);
      expect(liste.map((k) => k.uid), ['a']);
    });

    test('son kullanıcı silinemez, diğerleri silinebilir', () async {
      await servis.kullaniciKaydet(kurum, kisi('a'));
      await servis.kullaniciKaydet(kurum, kisi('b'));
      await servis.kullaniciSil(kurum, 'a');
      await servis.kullaniciSil(kurum, 'b'); // son kullanıcı → yok sayılır
      expect((await servis.kullanicilariGetir(kurum)).map((k) => k.uid), ['b']);
    });

    test('1 MiB sınırını aşan kayıt açık hatayla reddedilir', () async {
      final dev = YuklenmisBordro(
        personelId: 'p1',
        personelAd: 'Ali',
        yil: 2026,
        ay: 7,
        dosyaAdi: 'b.pdf',
        yuklemeTarihi: DateTime(2026, 7, 20),
        pdfBase64: 'A' * 1100000,
      );
      await expectLater(servis.bordroYukle(birim, dev),
          throwsA(isA<VeriCokBuyukHatasi>()));
      expect(await servis.bordroYuklemesiniGetir(birim, 'p1', 2026, 7), isNull);
    });
  });

  group('Windows: transaction kullanılmaz (eklenti çöküyor)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    Future<void> tumListeIslemleri(FirestoreServis s) async {
      Kullanici kisi(String uid) => Kullanici(
          uid: uid, ad: uid, eposta: '', rol: Rol.editor, kurumId: kurum);
      expect((await s.kullanicilariGetir(kurum)).single.uid, 'yonetici');
      await s.kullaniciKaydet(kurum, kisi('a'));
      await s.kullaniciKaydet(kurum, kisi('a')); // güncelleme, kopya yok
      await s.kullaniciKaydet(kurum, kisi('b'));
      await s.kullaniciSil(kurum, 'a');
      expect((await s.kullanicilariGetir(kurum)).map((k) => k.uid).toSet(), {'yonetici', 'b'});

      await s.personelKaydet(birim, Personel(id: 'p1', ad: 'Ali'));
      await s.personelSil(birim, 'p1');
      expect(await s.personelleriGetir(birim), isEmpty);

      await s.duyuruKaydet(
          kurum, Duyuru(id: 'd1', baslik: 'B', icerik: 'İ', tarih: DateTime(2026, 7, 1)));
      expect((await s.duyurulariGetir(kurum)).single.id, 'd1');
      await s.duyuruSil(kurum, 'd1');

      await s.personelUcretiKaydet(
          birim, PersonelUcreti(personelId: 'p1', gunlukUcret: 1500));
      expect((await s.personelUcretleriGetir(birim)).single.gunlukUcret, 1500);

      // Versiyonlu kayıt, versiyon listesini de günceller (Onaylanan Liste kaydı).
      final k = AyKaydi(yil: 2026, ay: 7, versiyon: kVersiyonOnayli);
      k.ata(1, 'p1', kGunduz12);
      await s.ayKaydiKaydet(birim, k);
      expect((await s.ayKaydiGetir(birim, 2026, 7, versiyon: kVersiyonOnayli)).kod(1, 'p1'),
          kGunduz12);
    }

    test('Windows platformunda hiçbir liste işlemi runTransaction çağırmaz', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final yasakli = _IslemYasakliDb();
      await tumListeIslemleri(FirestoreServis(veritabani: yasakli));
      expect(yasakli.islemCagrisi, 0);
    });

    test('islemKullan: false verilince de transaction kullanılmaz', () async {
      final yasakli = _IslemYasakliDb();
      await tumListeIslemleri(
          FirestoreServis(veritabani: yasakli, islemKullan: false));
      expect(yasakli.islemCagrisi, 0);
    });

    test('Android/web\'de transaction kullanılmaya devam eder', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final yasakli = _IslemYasakliDb();
      await expectLater(
        FirestoreServis(veritabani: yasakli).kullaniciKaydet(
            kurum,
            Kullanici(uid: 'a', ad: 'a', eposta: '', rol: Rol.editor, kurumId: kurum)),
        throwsA(isA<StateError>()),
      );
      expect(yasakli.islemCagrisi, 1);
    });
  });

  group('Koleksiyon ayrımı ve Onay Kodu', () {
    test('bordro ve ücret belgeleri nobet_bordro koleksiyonuna, gerisi nobet_pro\'ya yazılır',
        () async {
      await servis.personelUcretiKaydet(
          birim, PersonelUcreti(personelId: 'p1', gunlukUcret: 2000));
      await servis.bordroAyariKaydet(kurum, BordroAyari(yil: 2026));
      await servis.personelKaydet(birim, Personel(id: 'p1', ad: 'Ali'));

      Future<bool> var_(String kol, String id) async =>
          (await db.collection(kol).doc(id).get()).exists;
      expect(await var_('nobet_bordro', 'ucretler_$birim'), isTrue);
      expect(await var_('nobet_bordro', 'bordro_ayari_2026'), isTrue);
      expect(await var_('nobet_pro', 'ucretler_$birim'), isFalse);
      expect(await var_('nobet_pro', 'personeller_$birim'), isTrue);
      expect(await var_('nobet_bordro', 'personeller_$birim'), isFalse);
      // Okuma da yeni yerden yapılır
      expect((await servis.personelUcretleriGetir(birim)).single.gunlukUcret, 2000);
    });

    test('yedek bordro belgelerini de düz anahtarlarla içerir ve geri yükler', () async {
      await servis.personelUcretiKaydet(
          birim, PersonelUcreti(personelId: 'p1', gunlukUcret: 2000));
      await servis.personelKaydet(birim, Personel(id: 'p1', ad: 'Ali'));

      final json = await servis.tumVeriyiDisaAktar();
      final veri = (jsonDecode(json) as Map<String, dynamic>)['veri'] as Map;
      expect(veri.keys, contains('ucretler_$birim'));
      expect(veri.keys, contains('personeller_$birim'));

      final db2 = FakeFirebaseFirestore();
      final servis2 = FirestoreServis(veritabani: db2);
      await servis2.yedektenYukle(json);
      expect((await servis2.personelUcretleriGetir(birim)).single.gunlukUcret, 2000);
      expect(
          (await db2.collection('nobet_bordro').doc('ucretler_$birim').get()).exists, isTrue);
    });

    test('kurum ayarına Onay Kodu yazılmaz', () async {
      final ayar = await servis.kurumAyariGetir(kurum);
      ayar.onayKodu = '4821';
      await servis.kurumAyariKaydet(ayar);

      final ham = await db.collection('nobet_pro').doc('kurum_$kurum').get();
      expect(jsonDecode(ham.data()!['j'] as String), isNot(contains('onayKodu')));
      expect((await servis.kurumAyariGetir(kurum)).onayKodu, '');
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
