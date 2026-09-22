import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/modeller/modeller.dart';

void main() {
  Kullanici admin(YoneticiProfili p) => Kullanici.yonetici(
        uid: 'u1',
        ad: 'Test Kullanıcı',
        kurumId: 'varsayilan',
        profil: p,
      );

  group('Yetki matrisi', () {
    test('Süper Admin — her şey açık', () {
      final k = admin(YoneticiProfili.superAdmin);
      expect(k.rol, Rol.yonetici);
      expect(k.rol.yonetebilir, isTrue, reason: 'yönetim ekranları');
      expect(k.rol.duzenleyebilir, isTrue, reason: 'nöbet düzenleme');
      expect(k.sadecePdf, isFalse);
      expect(k.kisitliBirim, isNull, reason: 'iki birime de girer');
      expect(k.bordroYetkisi, isTrue);
      expect(k.rolEtiketiUzun, 'Süper Admin');
    });

    test('Temizlik Nöbet Admini — sadece temizlik, bordro yok', () {
      final k = admin(YoneticiProfili.temizlikNobet);
      expect(k.rol, Rol.editor);
      expect(k.rol.duzenleyebilir, isTrue, reason: 'nöbet listesi hazırlar');
      expect(k.rol.yonetebilir, isFalse, reason: 'yönetim ekranlarına giremez');
      expect(k.sadecePdf, isFalse);
      expect(k.kisitliBirim, Birim.temizlik);
      expect(k.bordroYetkisi, isFalse);
      expect(k.rolEtiketiUzun, 'Temizlik Nöbet Admini');
    });

    test('Bordro Admini — nöbet salt okunur, bordro tam yetki', () {
      final k = admin(YoneticiProfili.bordro);
      expect(k.sadecePdf, isTrue, reason: 'nöbet tarafı salt okunur');
      expect(k.kisitliBirim, isNull, reason: 'iki birimi de görebilir');
      expect(k.bordroYetkisi, isTrue, reason: 'asıl işi bordro');
      expect(k.rol.yonetebilir, isFalse, reason: 'yönetim ekranlarına giremez');
      expect(k.rolEtiketiUzun, 'Bordro Admini');
    });

    test('yalnızca Süper Admin ve Bordro Admini bordroya erişir', () {
      final yetkili = YoneticiProfili.values
          .where((p) => p.bordroYetkisi)
          .toSet();
      expect(yetkili,
          {YoneticiProfili.superAdmin, YoneticiProfili.bordro});
    });
  });

  group('Profil tutarlılığı', () {
    test('profil, çelişen elle verilmiş bayrakları ezer', () {
      // Diskte profil "bordro" ama bayraklar eski/yanlış yazılmış olsun
      final k = Kullanici.haritadan('u1', {
        'ad': 'Eski Kayıt',
        'rol': 'yonetici', // profille çelişiyor
        'sadecePdf': false, // profille çelişiyor
        'kisitliBirim': 'guvenlik', // profille çelişiyor
        'yoneticiProfili': 'bordro',
      });
      expect(k.yoneticiProfili, YoneticiProfili.bordro);
      expect(k.rol, Rol.editor, reason: 'profil kazanır');
      expect(k.sadecePdf, isTrue, reason: 'profil kazanır');
      expect(k.kisitliBirim, isNull, reason: 'profil kazanır');
    });

    test('profilsiz eski kayıtlar davranışını korur', () {
      final k = Kullanici.haritadan('u2', {
        'ad': 'Eski Yönetici',
        'rol': 'yonetici',
        'sadecePdf': false,
        'kisitliBirim': '',
      });
      expect(k.yoneticiProfili, isNull);
      expect(k.rol, Rol.yonetici);
      expect(k.bordroYetkisi, isTrue,
          reason: 'geriye dönük: yönetici bordroya erişmeye devam eder');
      expect(k.rolEtiketiUzun, 'Yönetici');
    });

    test('profilsiz sadecePdf kullanıcı bordroya erişemez', () {
      final k = Kullanici.haritadan('u3', {
        'ad': 'Eski Bordro',
        'rol': 'yonetici',
        'sadecePdf': true,
      });
      expect(k.bordroYetkisi, isFalse);
    });

    test('profilsiz personel bordroya erişemez', () {
      final k = Kullanici.haritadan('u4', {'ad': 'Personel', 'rol': 'izleyici'});
      expect(k.bordroYetkisi, isFalse);
    });
  });

  group('JSON gidiş-dönüş ve kopyala', () {
    test('profil diske yazılıp geri okunur', () {
      for (final p in YoneticiProfili.values) {
        final k = admin(p);
        final geri = Kullanici.haritadan(k.uid, k.haritasi);
        expect(geri.yoneticiProfili, p);
        expect(geri.rol, p.rol);
        expect(geri.sadecePdf, p.sadecePdf);
        expect(geri.kisitliBirim, p.kisitliBirim);
        expect(geri.bordroYetkisi, p.bordroYetkisi);
      }
    });

    test('kopyala profili korur ve bayrakları profile göre yeniler', () {
      final k = admin(YoneticiProfili.superAdmin)
          .kopyala(ad: 'Yeni Ad', yoneticiProfili: YoneticiProfili.bordro);
      expect(k.ad, 'Yeni Ad');
      expect(k.yoneticiProfili, YoneticiProfili.bordro);
      expect(k.sadecePdf, isTrue);
      expect(k.rol, Rol.editor);
    });

    test('profilSil kullanıcıyı normal kullanıcıya çevirir', () {
      final k = admin(YoneticiProfili.superAdmin)
          .kopyala(rol: Rol.izleyici, profilSil: true);
      expect(k.yoneticiProfili, isNull);
      expect(k.rol, Rol.izleyici);
      expect(k.sadecePdf, isFalse);
      expect(k.kisitliBirim, isNull);
      expect(k.bordroYetkisi, isFalse);
    });

    test('kopyala sadece adı değiştirirken profili bozmaz', () {
      final k = admin(YoneticiProfili.temizlikNobet).kopyala(ad: 'Ayşe');
      expect(k.yoneticiProfili, YoneticiProfili.temizlikNobet);
      expect(k.kisitliBirim, Birim.temizlik);
    });
  });

  group('Profil çözümleme', () {
    test('bilinmeyen/boş değer null döner', () {
      expect(YoneticiProfiliX.coz(null), isNull);
      expect(YoneticiProfiliX.coz(''), isNull);
      expect(YoneticiProfiliX.coz('olmayan_rol'), isNull);
      expect(YoneticiProfiliX.coz('superAdmin'), YoneticiProfili.superAdmin);
    });
  });
}
