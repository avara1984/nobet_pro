import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/durum/nobet_durumu.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/veri_servisi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Personel.ayAktifMi', () {
    test('tarih yoksa her ay görevde', () {
      final p = Personel(id: 'a', ad: 'A');
      expect(p.ayAktifMi(2020, 1), isTrue);
      expect(p.ayAktifMi(2030, 12), isTrue);
    });

    test('başlangıçtan önceki aylarda görünmez, başladığı ay görünür', () {
      final p = Personel(id: 'a', ad: 'A', gorevBaslangic: DateTime(2027, 3, 15));
      expect(p.ayAktifMi(2027, 2), isFalse);
      expect(p.ayAktifMi(2027, 3), isTrue, reason: 'ay içinde başlıyor');
      expect(p.ayAktifMi(2027, 4), isTrue);
    });

    test('ayrılıştan sonraki aylarda görünmez, ayrıldığı ay görünür', () {
      final p = Personel(id: 'a', ad: 'A', gorevBitis: DateTime(2027, 6, 10));
      expect(p.ayAktifMi(2027, 6), isTrue);
      expect(p.ayAktifMi(2027, 7), isFalse);
      expect(p.ayAktifMi(2027, 1), isTrue);
    });

    test('ayın son günü başlayan o ayda, ayın ilk günü biten o ayda görünür', () {
      final basla = Personel(id: 'a', ad: 'A', gorevBaslangic: DateTime(2027, 3, 31));
      final bit = Personel(id: 'b', ad: 'B', gorevBitis: DateTime(2027, 3, 1));
      expect(basla.ayAktifMi(2027, 3), isTrue);
      expect(basla.ayAktifMi(2027, 2), isFalse);
      expect(bit.ayAktifMi(2027, 3), isTrue);
      expect(bit.ayAktifMi(2027, 4), isFalse);
    });
  });

  group('Personel JSON', () {
    test('tarihler gidiş-dönüşte korunur, eski kayıt tarihsiz açılır', () {
      final p = Personel(
          id: 'a',
          ad: 'A',
          gorevBaslangic: DateTime(2027, 3, 5),
          gorevBitis: DateTime(2027, 9, 30));
      final geri = Personel.haritadan('a', p.haritasi);
      expect(geri.gorevBaslangic, DateTime(2027, 3, 5));
      expect(geri.gorevBitis, DateTime(2027, 9, 30));
      expect(geri.kopya().gorevBaslangic, DateTime(2027, 3, 5));

      final eski = Personel.haritadan('b', {'ad': 'Eski Kayıt'});
      expect(eski.gorevBaslangic, isNull);
      expect(eski.gorevBitis, isNull);
      expect(Personel(id: 'c', ad: 'C').haritasi.containsKey('gorevBaslangic'),
          isFalse);
    });
  });

  group('NobetDurumu personel listesi', () {
    test('seçili aya göre süzülür, tümü ayrıca erişilebilir', () async {
      SharedPreferences.setMockInitialValues({});
      final tercihler = await SharedPreferences.getInstance();
      final servis = BellekServis();
      final d = NobetDurumu(
          servis: servis,
          kurumId: 'varsayilan',
          rol: Rol.yonetici,
          tercihler: tercihler,
          uid: 'u');
      final eskiler = await servis.personelleriGetir(d.birimId);
      for (final p in eskiler) {
        await servis.personelSil(d.birimId, p.id);
      }
      await servis.personelKaydet(
          d.birimId, Personel(id: 'p1', ad: 'Eski Personel', sira: 0));
      await servis.personelKaydet(
          d.birimId,
          Personel(
              id: 'p2',
              ad: 'Yeni Gelen',
              sira: 1,
              gorevBaslangic: DateTime(2027, 3, 1)));
      await d.baslat();

      await d.donemDegistir(2027, 2);
      expect(d.personeller.map((p) => p.id), ['p1']);
      expect(d.tumPersoneller.map((p) => p.id), ['p1', 'p2']);

      await d.donemDegistir(2027, 3);
      expect(d.personeller.map((p) => p.id), ['p1', 'p2']);
      d.dispose();
    });
  });
}
