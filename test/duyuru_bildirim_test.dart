import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nobet_pro/durum/nobet_durumu.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/veri_servisi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Üç referans an, gün ölçeğinde ayrılmış (saat/dakika hassasiyetiyle
  // gerçek saatle yarışan flaky karşılaştırmalardan kaçınmak için):
  // BellekServis'in örnek duyurusu (simdi - 3 gün) < eskiGorulen
  // (simdi - 2 gün, testte önceden diske yazılan "son görülen") <
  // duyuruTarihi (simdi - 1 gün, testte eklenen duyuru) < gerçek "şimdi"
  // (duyurularGoruldu() bunu kullanır).
  final simdi = DateTime.now();
  final eskiGorulen = simdi.subtract(const Duration(days: 2));
  final duyuruTarihi = simdi.subtract(const Duration(days: 1));

  String anahtar(String uid) => 'son_gorulen_duyuru_$uid';

  Future<NobetDurumu> ac(SharedPreferences tercihler, VeriServisi servis,
      {required String uid}) async {
    final d = NobetDurumu(
      servis: servis,
      kurumId: 'varsayilan',
      rol: Rol.yonetici,
      tercihler: tercihler,
      uid: uid,
    );
    await d.baslat();
    return d;
  }

  group('Okunmamış duyuru sayısı', () {
    test('ilk girişte geçmiş duyurular okunmamış sayılmaz', () async {
      SharedPreferences.setMockInitialValues({});
      final tercihler = await SharedPreferences.getInstance();
      final d = await ac(tercihler, BellekServis(), uid: 'ilk-giris');
      expect(d.okunmamisDuyuruSayisi, 0);
    });

    test('görülen zamandan sonra eklenen duyuru sayaca yansır', () async {
      SharedPreferences.setMockInitialValues(
          {anahtar('u1'): eskiGorulen.toIso8601String()});
      final tercihler = await SharedPreferences.getInstance();
      final d = await ac(tercihler, BellekServis(), uid: 'u1');
      expect(d.okunmamisDuyuruSayisi, 0,
          reason: 'örnek duyuru eskiGorulen’den önceki bir tarihte');

      await d.duyuruKaydet(Duyuru(
        id: 'yeni1',
        baslik: 'Test duyurusu',
        icerik: 'İçerik',
        tarih: duyuruTarihi,
      ));

      expect(d.okunmamisDuyuruSayisi, 1);
    });

    test('duyurularGoruldu() sayacı sıfırlar ve kalıcı yazar', () async {
      SharedPreferences.setMockInitialValues(
          {anahtar('u2'): eskiGorulen.toIso8601String()});
      final tercihler = await SharedPreferences.getInstance();
      final servis = BellekServis();
      final d = await ac(tercihler, servis, uid: 'u2');

      await d.duyuruKaydet(Duyuru(
        id: 'yeni2',
        baslik: 'Test duyurusu 2',
        icerik: 'İçerik',
        tarih: duyuruTarihi,
      ));
      expect(d.okunmamisDuyuruSayisi, 1);

      await d.duyurularGoruldu();
      expect(d.okunmamisDuyuruSayisi, 0);

      // Kalıcılık: aynı tercihler + aynı uid ile açılan yeni bir oturum,
      // önceki "görüldü" zamanını diskten okumalı.
      final d2 = await ac(tercihler, servis, uid: 'u2');
      expect(d2.okunmamisDuyuruSayisi, 0);
    });

    test('farklı kullanıcının "görüldü" zamanı birbirine karışmaz', () async {
      SharedPreferences.setMockInitialValues({
        anahtar('kullanici-a'): eskiGorulen.toIso8601String(),
        anahtar('kullanici-b'): eskiGorulen.toIso8601String(),
      });
      final tercihler = await SharedPreferences.getInstance();
      final servis = BellekServis();
      await servis.duyuruKaydet(
        'varsayilan',
        Duyuru(
          id: 'paylasilan1',
          baslik: 'Ortak bilgisayardan duyuru',
          icerik: 'İçerik',
          tarih: duyuruTarihi,
        ),
      );

      final a = await ac(tercihler, servis, uid: 'kullanici-a');
      expect(a.okunmamisDuyuruSayisi, 1);
      await a.duyurularGoruldu();
      expect(a.okunmamisDuyuruSayisi, 0);

      // Aynı (paylaşılan) cihazda B kullanıcısı giriş yapar — A'nın
      // duyuruyu görmüş olması B'nin (hâlâ eski) "görüldü" zamanını
      // etkilememeli.
      final b = await ac(tercihler, servis, uid: 'kullanici-b');
      expect(b.okunmamisDuyuruSayisi, 1,
          reason: 'A duyuruyu okudu diye B de okumuş sayılmamalı');
    });

    test('birim kısıtlı görünüm diğer birime özel duyuruyu saymaz', () async {
      SharedPreferences.setMockInitialValues(
          {anahtar('u3'): eskiGorulen.toIso8601String()});
      final tercihler = await SharedPreferences.getInstance();
      final d = await ac(tercihler, BellekServis(), uid: 'u3');

      await d.duyuruKaydet(Duyuru(
        id: 'guvenlikOzel',
        baslik: 'Güvenlik duyurusu',
        icerik: 'İçerik',
        tarih: duyuruTarihi,
        hedef: Birim.guvenlik,
      ));
      // Başlangıç birimi Güvenlik (NobetDurumu varsayılanı).
      expect(d.okunmamisDuyuruSayisi, 1);

      await d.birimDegistir(Birim.temizlik);
      expect(d.okunmamisDuyuruSayisi, 0,
          reason: 'Temizlik biriminde Güvenliğe özel duyuru görünmemeli');
    });
  });
}
