import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nobet_pro/core/kimlik.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/giris_servisi.dart';
import 'package:nobet_pro/servisler/veri_servisi.dart';

class _Kullanicilar extends BellekServis {
  _Kullanicilar(this.users);
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

class _Oturum implements OturumKoprusu {
  String? token; // son girilen özel token
  String? idTokenDegeri; // null → oturum yok
  int anonim = 0;
  int cikislar = 0;

  @override
  Future<void> tokenIleGirisYap(String t) async {
    token = t;
    idTokenDegeri = 'id-$t';
  }

  @override
  Future<String?> idToken() async => idTokenDegeri;

  @override
  Future<void> anonimOturumSagla() async => anonim++;

  @override
  Future<void> cikis() async {
    cikislar++;
    idTokenDegeri = null;
  }
}

class _Cagri {
  _Cagri(this.ad, this.govde, this.yetki);
  final String ad;
  final Map<String, dynamic> govde;
  final String? yetki;
}

http.Response _yanit(int durum, Map<String, dynamic> govde) => http.Response.bytes(
    utf8.encode(jsonEncode(govde)), durum,
    headers: {'content-type': 'application/json; charset=utf-8'});

const _profil = {
  'uid': 'u1',
  'ad': 'Ayşe Yönetici',
  'rol': 'yonetici',
  'kurumId': 'x',
  'kimlik': '10000000146',
  'yoneticiProfili': 'superAdmin',
  'sifreHash': '',
  'onayli': true,
};

void main() {
  late List<_Cagri> cagrilar;
  late _Oturum oturum;
  late _Kullanicilar veri;
  Map<String, http.Response Function()> yanitlar = {};

  BulutGirisServisi kur() => BulutGirisServisi(
        veri: veri,
        oturum: oturum,
        adres: 'https://sunucu.test',
        istemci: MockClient((istek) async {
          final ad = istek.url.pathSegments.last;
          cagrilar.add(_Cagri(ad, jsonDecode(istek.body) as Map<String, dynamic>,
              istek.headers['Authorization']));
          final y = yanitlar[ad];
          if (y == null) return _yanit(500, {'hata': 'tanımsız: $ad'});
          return y();
        }),
      );

  setUp(() {
    cagrilar = [];
    oturum = _Oturum();
    veri = _Kullanicilar([]);
    yanitlar = {
      'npDurum': () => _yanit(200, {'yoneticiVar': true, 'kilitli': false}),
    };
  });

  group('BulutGirisServisi.girisYap', () {
    test('sunucuya JSON gönderir, özel token ile Firebase\'e girer', () async {
      yanitlar['npGiris'] =
          () => _yanit(200, {'token': 'T1', 'kullanici': _profil});
      final k = await kur().girisYap('x', ' 10000000146 ', 'sifre123');

      expect(cagrilar.single.ad, 'npGiris');
      expect(cagrilar.single.govde,
          {'kurumId': 'x', 'kimlik': '10000000146', 'sifre': 'sifre123'});
      expect(oturum.token, 'T1');
      expect(k.uid, 'u1');
      expect(k.ad, 'Ayşe Yönetici');
      expect(k.yoneticiProfili, YoneticiProfili.superAdmin);
      expect(k.sifreHash, '');
    });

    test('sunucu hatası mesajı kullanıcıya iletilir, oturum açılmaz', () async {
      yanitlar['npGiris'] = () =>
          _yanit(401, {'hata': 'T.C. Kimlik No / kullanıcı adı veya şifre hatalı.'});
      await expectLater(
        kur().girisYap('x', '1', 'a'),
        throwsA(isA<GirisHatasi>()
            .having((e) => e.mesaj, 'mesaj', contains('şifre hatalı'))
            .having((e) => e.ag, 'ag', false)),
      );
      expect(oturum.token, isNull);

      yanitlar['npGiris'] = () => _yanit(
          429, {'hata': 'Çok fazla hatalı deneme. Yaklaşık 15 dakika sonra tekrar deneyin.'});
      await expectLater(
        kur().girisYap('x', '1', 'a'),
        throwsA(isA<GirisHatasi>()
            .having((e) => e.mesaj, 'mesaj', contains('Çok fazla'))),
      );
    });

    test('ağ hatası "ulaşılamadı" olarak işaretlenir', () async {
      final servis = BulutGirisServisi(
        veri: veri,
        oturum: oturum,
        adres: 'https://sunucu.test',
        istemci: MockClient((_) async => throw Exception('bağlantı yok')),
      );
      await expectLater(
        servis.girisYap('x', '1', 'a'),
        throwsA(isA<GirisHatasi>().having((e) => e.ag, 'ag', true)),
      );
    });
  });

  group('BulutGirisServisi.durum / ben', () {
    test('durum bayrakları okunur', () async {
      yanitlar['npDurum'] =
          () => _yanit(200, {'yoneticiVar': false, 'kilitli': true});
      final d = await kur().durum('x');
      expect(d.yoneticiVar, false);
      expect(d.kilitli, true);
    });

    test('ben: oturum yoksa sunucuya gitmeden null', () async {
      expect(await kur().ben('x'), isNull);
      expect(cagrilar, isEmpty);
    });

    test('ben: ID token gönderir, taze token ile yeniden girer', () async {
      oturum.idTokenDegeri = 'eski-id';
      yanitlar['npBen'] =
          () => _yanit(200, {'token': 'T2', 'kullanici': _profil});
      final k = await kur().ben('x');

      expect(cagrilar.single.yetki, 'Bearer eski-id');
      expect(oturum.token, 'T2');
      expect(k?.uid, 'u1');
    });

    test('ben: reddedilen hesap ağ hatası sayılmaz, sunucu çökmesi sayılır', () async {
      oturum.idTokenDegeri = 'id';
      yanitlar['npBen'] = () => _yanit(403, {'hata': 'Hesabınız pasif durumda.'});
      await expectLater(kur().ben('x'),
          throwsA(isA<GirisHatasi>().having((e) => e.ag, 'ag', false)));

      yanitlar['npBen'] = () => _yanit(500, {'hata': 'Sunucu hatası.'});
      await expectLater(kur().ben('x'),
          throwsA(isA<GirisHatasi>().having((e) => e.ag, 'ag', true)));
    });

    test('çıkış Firebase oturumunu kapatır', () async {
      await kur().cikis();
      expect(oturum.cikislar, 1);
    });
  });

  group('kayıt / şifre: geçiş bitmeden (kilitli=false) eski yol', () {
    test('üye ol kayıt dokümanına yazar, anonim oturum sağlar', () async {
      await kur().uyeOl('x',
          ad: 'Veli Yeni', kimlik: '22222222222', sifre: 'abc123');
      expect(oturum.anonim, 1);
      expect(cagrilar.map((c) => c.ad), ['npDurum']);
      final k = veri.users.single;
      expect(k.onayli, false);
      expect(k.kimlik, '22222222222');
      expect(Kimlik.sifreDogru('abc123', k.sifreHash), true);
    });

    test('üye ol: TC çakışması reddedilir', () async {
      veri.users.add(Kullanici(
          uid: 'a', ad: 'A', eposta: '', rol: Rol.izleyici, kurumId: 'x',
          kimlik: '22222222222'));
      await expectLater(
        kur().uyeOl('x', ad: 'Başka', kimlik: '22222222222', sifre: 'abc123'),
        throwsA(isA<GirisHatasi>()
            .having((e) => e.mesaj, 'mesaj', contains('zaten kayıtlı'))),
      );
    });

    test('ilk kurulum: yönetici yazılır, ardından sunucudan giriş alınır', () async {
      yanitlar['npGiris'] =
          () => _yanit(200, {'token': 'T3', 'kullanici': _profil});
      final k = await kur().yoneticiOlustur('x',
          ad: 'Ayşe Yönetici', kimlik: '10000000146', sifre: 'sifre123');

      final yazilan = veri.users.single;
      expect(yazilan.yoneticiProfili, YoneticiProfili.superAdmin);
      expect(Kimlik.sifreDogru('sifre123', yazilan.sifreHash), true);
      expect(cagrilar.map((c) => c.ad), ['npDurum', 'npGiris']);
      expect(oturum.token, 'T3');
      expect(k.uid, 'u1');
    });

    test('şifre ayarla kayıttaki özeti günceller', () async {
      veri.users.add(Kullanici(
          uid: 'a', ad: 'A', eposta: '', rol: Rol.izleyici, kurumId: 'x',
          kimlik: '22222222222', sifreHash: Kimlik.sifreOzeti('eski123')));
      await kur().sifreAyarla('x', 'a', 'yeni1234');
      expect(Kimlik.sifreDogru('yeni1234', veri.users.single.sifreHash), true);
      expect(cagrilar.map((c) => c.ad), ['npDurum']);
    });
  });

  group('kayıt / şifre: geçiş bitince (kilitli=true) yalnızca sunucu', () {
    setUp(() {
      yanitlar['npDurum'] =
          () => _yanit(200, {'yoneticiVar': true, 'kilitli': true});
    });

    test('üye ol sunucuya gider, kayıt doğrudan yazılmaz', () async {
      yanitlar['npUyeOl'] = () => _yanit(200, {'tamam': true});
      await kur().uyeOl('x',
          ad: 'Veli Yeni', kimlik: '22222222222', sifre: 'abc123');
      expect(cagrilar.last.ad, 'npUyeOl');
      expect(cagrilar.last.govde['sifre'], 'abc123');
      expect(veri.users, isEmpty);
      expect(oturum.anonim, 0, reason: 'anonim oturum açılmamalı');
    });

    test('şifre ayarla ID token ile sunucuya gider', () async {
      oturum.idTokenDegeri = 'yonetici-id';
      yanitlar['npSifreAyarla'] = () => _yanit(200, {'tamam': true});
      await kur().sifreAyarla('x', 'a', 'yeni1234');
      expect(cagrilar.last.ad, 'npSifreAyarla');
      expect(cagrilar.last.yetki, 'Bearer yonetici-id');
      expect(cagrilar.last.govde, {'kurumId': 'x', 'uid': 'a', 'sifre': 'yeni1234'});
    });

    test('ilk kurulum sunucuya gider ve oturum açar', () async {
      yanitlar['npYoneticiOlustur'] =
          () => _yanit(200, {'token': 'T4', 'kullanici': _profil});
      final k = await kur().yoneticiOlustur('x',
          ad: 'Ayşe Yönetici', kimlik: '10000000146', sifre: 'sifre123');
      expect(cagrilar.last.ad, 'npYoneticiOlustur');
      expect(oturum.token, 'T4');
      expect(k.uid, 'u1');
      expect(veri.users, isEmpty);
    });
  });

  group('YerelGirisServisi.ben', () {
    test('kayıtlı uid\'den profil; pasif/onaysız ise null', () async {
      final yerel = YerelGirisServisi(_Kullanicilar([
        Kullanici(uid: 'a', ad: 'A', eposta: '', rol: Rol.izleyici, kurumId: 'x'),
        Kullanici(
            uid: 'p', ad: 'P', eposta: '', rol: Rol.izleyici, kurumId: 'x',
            aktif: false),
      ]));
      expect((await yerel.ben('x', uid: 'a'))?.uid, 'a');
      expect(await yerel.ben('x', uid: 'p'), isNull);
      expect(await yerel.ben('x', uid: 'yok'), isNull);
      expect(await yerel.ben('x'), isNull);
    });
  });
}
