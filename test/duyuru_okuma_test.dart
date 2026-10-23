import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/durum/nobet_durumu.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/firestore_servis.dart';
import 'package:nobet_pro/servisler/veri_servisi.dart';
import 'package:nobet_pro/servisler/yerel_servis.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const kurum = 'varsayilan';

  Kullanici kisi(String uid,
          {bool sadecePdf = false,
          bool onayli = true,
          Birim? kisitli,
          bool aktif = true}) =>
      Kullanici(
        uid: uid,
        ad: 'Kişi $uid',
        eposta: '',
        rol: Rol.izleyici,
        kurumId: kurum,
        sadecePdf: sadecePdf,
        onayli: onayli,
        kisitliBirim: kisitli,
        aktif: aktif,
      );

  group('Okuma kaydı saklama', () {
    test('BellekServis: kullanıcı başına yazılır, tümü toplanır', () async {
      final s = BellekServis();
      await s.duyuruOkumalariniKaydet(kurum, 'a', {'d1': DateTime(2026, 1, 1)});
      await s.duyuruOkumalariniKaydet(kurum, 'b', {'d1': DateTime(2026, 1, 2)});
      expect((await s.duyuruOkumalariniGetir(kurum, 'a')).keys, ['d1']);
      final tum = await s.tumDuyuruOkumalari(kurum);
      expect(tum.keys.toSet(), {'a', 'b'});
      expect(tum['b']!['d1'], DateTime(2026, 1, 2));
    });

    test('YerelServis: gidiş-dönüş ve yedeğe dahil', () async {
      SharedPreferences.setMockInitialValues({});
      final tercihler = await SharedPreferences.getInstance();
      final s = YerelServis(tercihler);
      await s.duyuruOkumalariniKaydet(kurum, 'a', {'d1': DateTime(2026, 5, 4, 10)});
      await s.duyuruOkumalariniKaydet(kurum, 'b', {'d2': DateTime(2026, 5, 5)});
      expect(await s.duyuruOkumalariniGetir(kurum, 'a'),
          {'d1': DateTime(2026, 5, 4, 10)});
      final tum = await s.tumDuyuruOkumalari(kurum);
      expect(tum.keys.toSet(), {'a', 'b'});
      final yedek = jsonDecode(await s.tumVeriyiDisaAktar()) as Map;
      expect((yedek['veri'] as Map).keys.any((k) => '$k'.startsWith('duyuruokuma_')),
          isTrue);
    });

    test('FirestoreServis: gidiş-dönüş ve yedeğe dahil', () async {
      final db = FakeFirebaseFirestore();
      final s = FirestoreServis(veritabani: db);
      await s.duyuruOkumalariniKaydet(kurum, 'a', {'d1': DateTime(2026, 5, 4, 10)});
      await s.duyuruOkumalariniKaydet(kurum, 'b', {'d2': DateTime(2026, 5, 5)});
      expect(await s.duyuruOkumalariniGetir(kurum, 'a'),
          {'d1': DateTime(2026, 5, 4, 10)});
      final tum = await s.tumDuyuruOkumalari(kurum);
      expect(tum.keys.toSet(), {'a', 'b'});
      // Doküman duyurular_ önekiyle başlamamalı (Cloud Function tetiklenmesin).
      final doc = await db.collection('nobet_pro').doc('duyuruokuma_${kurum}_a').get();
      expect(doc.exists, isTrue);
      final yedek = jsonDecode(await s.tumVeriyiDisaAktar()) as Map;
      expect((yedek['veri'] as Map).keys.any((k) => '$k'.startsWith('duyuruokuma_')),
          isTrue);
    });
  });

  group('NobetDurumu okuma işaretleme', () {
    Future<NobetDurumu> ac(VeriServisi servis, String uid) async {
      SharedPreferences.setMockInitialValues({});
      final tercihler = await SharedPreferences.getInstance();
      final d = NobetDurumu(
          servis: servis,
          kurumId: kurum,
          rol: Rol.yonetici,
          tercihler: tercihler,
          uid: uid);
      await d.baslat();
      return d;
    }

    test('ekranı açan kullanıcı tüm duyuruları okumuş yazılır, zaman korunur',
        () async {
      final servis = BellekServis();
      final a = await ac(servis, 'a');
      await a.duyurularGoruldu();
      final ilk = (await servis.duyuruOkumalariniGetir(kurum, 'a'));
      expect(ilk, isNotEmpty);
      final id = ilk.keys.first;
      final ilkZaman = ilk[id]!;

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.duyurularGoruldu();
      final ikinci = await servis.duyuruOkumalariniGetir(kurum, 'a');
      expect(ikinci[id], ilkZaman, reason: 'zaman yeniden yazılmamalı');
      a.dispose();
    });

    test('farklı kullanıcılar ayrı kaydedilir; bilgi ikisini de içerir',
        () async {
      final servis = BellekServis();
      final a = await ac(servis, 'a');
      final b = await ac(servis, 'b');
      await a.duyurularGoruldu();
      await b.duyurularGoruldu();
      final bilgi = await a.duyuruOkumaBilgisi();
      expect(bilgi.okumalar.keys.toSet(), {'a', 'b'});
      a.dispose();
      b.dispose();
    });
  });

  group('DuyuruOkumaBilgisi.hedefKitle', () {
    final guvenlikDuyurusu = Duyuru(
        id: 'd1',
        baslik: 'G',
        icerik: '',
        tarih: DateTime(2026, 1, 1),
        hedef: Birim.guvenlik);
    final herkes =
        Duyuru(id: 'd2', baslik: 'H', icerik: '', tarih: DateTime(2026, 1, 1));

    final bilgi = DuyuruOkumaBilgisi([
      kisi('normal'),
      kisi('temizlik', kisitli: Birim.temizlik),
      kisi('guvenlik', kisitli: Birim.guvenlik),
      kisi('bordro', sadecePdf: true),
      kisi('onaysiz', onayli: false),
      kisi('pasif', aktif: false),
    ], {
      'normal': {'d1': DateTime(2026, 2, 1)},
    });

    test('hedefsiz duyuru: onaylı, aktif, sadece-PDF olmayanlar', () {
      expect(bilgi.hedefKitle(herkes).map((k) => k.uid).toSet(),
          {'normal', 'temizlik', 'guvenlik'});
    });

    test('birime özel duyuru: diğer birime kısıtlı kullanıcı dışarıda', () {
      expect(bilgi.hedefKitle(guvenlikDuyurusu).map((k) => k.uid).toSet(),
          {'normal', 'guvenlik'});
    });

    test('okuma zamanı kullanıcıya ve duyuruya göre bulunur', () {
      final normal = bilgi.kullanicilar.first;
      expect(bilgi.okumaZamani(normal, guvenlikDuyurusu), DateTime(2026, 2, 1));
      expect(bilgi.okumaZamani(normal, herkes), isNull);
    });
  });
}
