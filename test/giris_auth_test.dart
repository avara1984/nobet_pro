import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/kimlik.dart';
import 'package:nobet_pro/core/tema.dart';
import 'package:nobet_pro/ekranlar/giris_ekrani.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/giris_servisi.dart';
import 'package:nobet_pro/servisler/veri_servisi.dart';

/// Kullanıcıları bellekte tutan test servisi.
class _FakeServis extends BellekServis {
  _FakeServis(this.users);
  final List<Kullanici> users;

  @override
  Future<List<Kullanici>> kullanicilariGetir(String kurumId) async =>
      List.of(users);

  @override
  Future<void> kullaniciKaydet(String kurumId, Kullanici k) async {
    users.removeWhere((u) => u.uid == k.uid);
    users.add(k);
  }
}

void main() {
  group('Kullanici round-trip', () {
    test('kimlik / sifreHash / onayli korunur', () {
      final k = Kullanici(
        uid: 'u1',
        ad: 'Ali Veli',
        eposta: '',
        rol: Rol.izleyici,
        kurumId: 'x',
        kimlik: '10000000146',
        sifreHash: 'abc123',
        onayli: false,
      );
      final geri = Kullanici.haritadan('u1', k.haritasi);
      expect(geri.kimlik, '10000000146');
      expect(geri.sifreHash, 'abc123');
      expect(geri.onayli, false);
    });

    test('eski kayıt (onayli alanı yok) onaylı sayılır', () {
      final eski = Kullanici.haritadan(
          'u2', {'ad': 'Eski', 'rol': 'yonetici', 'kurumId': 'x'});
      expect(eski.onayli, true);
      expect(eski.kimlik, '');
      expect(eski.sifreHash, '');
    });

    test('kopyala onayli günceller, diğerlerini korur', () {
      final k = Kullanici(
        uid: 'u3',
        ad: 'B',
        eposta: '',
        rol: Rol.izleyici,
        kurumId: 'x',
        kimlik: '11111111111',
        sifreHash: 'h',
        onayli: false,
      );
      final onayli = k.kopyala(onayli: true);
      expect(onayli.onayli, true);
      expect(onayli.kimlik, '11111111111');
      expect(onayli.sifreHash, 'h');
    });
  });

  group('Kimlik', () {
    test('şifre özeti ve doğrulama', () {
      final h = Kimlik.sifreOzeti('sifre123');
      expect(h.length, 64); // sha256 hex
      expect(Kimlik.sifreDogru('sifre123', h), true);
      expect(Kimlik.sifreDogru('yanlis', h), false);
      expect(Kimlik.sifreDogru('sifre123', ''), false);
    });

    test('tc biçim kontrolü', () {
      expect(Kimlik.tcGecerli('10000000146'), true);
      expect(Kimlik.tcGecerli('123'), false); // kısa
      expect(Kimlik.tcGecerli('01234567890'), false); // 0 ile başlar
      expect(Kimlik.tcGecerli('1234567890a'), false); // harf
    });
  });

  group('GirisEkrani', () {
    testWidgets('yönetici yoksa ilk kurulum formu gelir', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: Tema.acik,
        home: GirisEkrani(
            giris: YerelGirisServisi(_FakeServis([])), kurumId: 'x', girisYapildi: (_, __) {}),
      ));
      await t.pumpAndSettle();
      expect(find.text('OLUŞTUR VE GİRİŞ YAP'), findsOneWidget);
      expect(find.textContaining('İlk kurulum'), findsOneWidget);
    });

    testWidgets('yönetici varsa giriş formu gelir', (t) async {
      final admin = Kullanici.yonetici(
        uid: 'a',
        ad: 'Admin',
        kurumId: 'x',
        profil: YoneticiProfili.superAdmin,
        kimlik: '10000000146',
        sifreHash: Kimlik.sifreOzeti('123456'),
      );
      await t.pumpWidget(MaterialApp(
        theme: Tema.acik,
        home: GirisEkrani(
            giris: YerelGirisServisi(_FakeServis([admin])), kurumId: 'x', girisYapildi: (_, __) {}),
      ));
      await t.pumpAndSettle();
      expect(find.text('GİRİŞ YAP'), findsOneWidget);
      expect(find.text('Hesabınız yok mu? Üye olun'), findsOneWidget);
    });

    testWidgets('giriş alanı: rakam girişi 11 haneyle sınırlı, kullanıcı adı değil',
        (t) async {
      final admin = Kullanici.yonetici(
        uid: 'a',
        ad: 'Admin',
        kurumId: 'x',
        profil: YoneticiProfili.superAdmin,
        kimlik: '10000000146',
        sifreHash: Kimlik.sifreOzeti('123456'),
      );
      await t.pumpWidget(MaterialApp(
        theme: Tema.acik,
        home: GirisEkrani(
            giris: YerelGirisServisi(_FakeServis([admin])), kurumId: 'x', girisYapildi: (_, __) {}),
      ));
      await t.pumpAndSettle();
      final alan =
          find.widgetWithText(TextField, 'T.C. Kimlik No veya Kullanıcı Adı');

      await t.enterText(alan, '1234567890123456');
      expect(t.widget<TextField>(alan).controller!.text, '12345678901');

      await t.enterText(alan, 'cok.uzun.kullanici.adi.123456789');
      expect(t.widget<TextField>(alan).controller!.text,
          'cok.uzun.kullanici.adi.123456789');
    });

    testWidgets('doğru TC + şifre ile giriş yapılır', (t) async {
      Kullanici? giren;
      final admin = Kullanici.yonetici(
        uid: 'a',
        ad: 'Admin',
        kurumId: 'x',
        profil: YoneticiProfili.superAdmin,
        kimlik: '10000000146',
        sifreHash: Kimlik.sifreOzeti('123456'),
      );
      await t.pumpWidget(MaterialApp(
        theme: Tema.acik,
        home: GirisEkrani(
            giris: YerelGirisServisi(_FakeServis([admin])),
            kurumId: 'x',
            girisYapildi: (k, _) => giren = k),
      ));
      await t.pumpAndSettle();
      await t.enterText(
          find.widgetWithText(TextField, 'T.C. Kimlik No veya Kullanıcı Adı'), '10000000146');
      await t.enterText(find.widgetWithText(TextField, 'Şifre'), '123456');
      await t.tap(find.text('GİRİŞ YAP'));
      await t.pumpAndSettle();
      expect(giren?.uid, 'a');
    });

    testWidgets('yanlış şifre ile giriş yapılmaz', (t) async {
      Kullanici? giren;
      final admin = Kullanici.yonetici(
        uid: 'a',
        ad: 'Admin',
        kurumId: 'x',
        profil: YoneticiProfili.superAdmin,
        kimlik: '10000000146',
        sifreHash: Kimlik.sifreOzeti('123456'),
      );
      await t.pumpWidget(MaterialApp(
        theme: Tema.acik,
        home: GirisEkrani(
            giris: YerelGirisServisi(_FakeServis([admin])),
            kurumId: 'x',
            girisYapildi: (k, _) => giren = k),
      ));
      await t.pumpAndSettle();
      await t.enterText(
          find.widgetWithText(TextField, 'T.C. Kimlik No veya Kullanıcı Adı'), '10000000146');
      await t.enterText(find.widgetWithText(TextField, 'Şifre'), 'yanlis');
      await t.tap(find.text('GİRİŞ YAP'));
      await t.pumpAndSettle();
      expect(giren, isNull);
    });

    testWidgets('onaysız personel giriş yapamaz', (t) async {
      Kullanici? giren;
      final admin = Kullanici.yonetici(
        uid: 'a',
        ad: 'Admin',
        kurumId: 'x',
        profil: YoneticiProfili.superAdmin,
        kimlik: '10000000146',
        sifreHash: Kimlik.sifreOzeti('123456'),
      );
      final personel = Kullanici(
        uid: 'p',
        ad: 'Mehmet',
        eposta: '',
        rol: Rol.izleyici,
        kurumId: 'x',
        kimlik: '22222222222',
        sifreHash: Kimlik.sifreOzeti('abc123'),
        onayli: false,
      );
      await t.pumpWidget(MaterialApp(
        theme: Tema.acik,
        home: GirisEkrani(
            giris: YerelGirisServisi(_FakeServis([admin, personel])),
            kurumId: 'x',
            girisYapildi: (k, _) => giren = k),
      ));
      await t.pumpAndSettle();
      await t.enterText(
          find.widgetWithText(TextField, 'T.C. Kimlik No veya Kullanıcı Adı'), '22222222222');
      await t.enterText(find.widgetWithText(TextField, 'Şifre'), 'abc123');
      await t.tap(find.text('GİRİŞ YAP'));
      await t.pumpAndSettle();
      expect(giren, isNull);
    });
  });
}
