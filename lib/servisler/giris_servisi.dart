import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../core/kimlik.dart';
import '../modeller/modeller.dart';
import 'veri_servisi.dart';

/// Giriş, kayıt ve şifre işlemleri. Ekranlar kullanıcı listesini doğrudan
/// okumaz; hangi uygulamanın çalıştığını (bulut/yerel) bu katman bilir.
///
///  * [BulutGirisServisi]: şifre doğrulama sunucuda (Cloud Functions) yapılır,
///    istemci kullanıcı listesini ve şifre özetlerini hiç görmez.
///  * [YerelGirisServisi]: yedek yerel mod; mantık cihazdadır (bulut yok).
abstract class GirisServisi {
  /// Giriş ekranının hangi formu göstereceği: yönetici var mı?
  Future<GirisDurumu> durum(String kurumId);

  /// T.C. kimlik / kullanıcı adı + şifre ile giriş. Hata → [GirisHatasi].
  Future<Kullanici> girisYap(String kurumId, String kimlik, String sifre);

  /// Kendi kendine kayıt (onaysız başlar).
  Future<void> uyeOl(String kurumId,
      {required String ad, required String kimlik, required String sifre});

  /// İlk kurulum: ilk yöneticiyi oluşturur ve giriş yapmış hâlde döner.
  Future<Kullanici> yoneticiOlustur(String kurumId,
      {required String ad, required String kimlik, required String sifre});

  /// Bir kullanıcının şifresini belirler (yönetici işlemi).
  Future<void> sifreAyarla(String kurumId, String uid, String sifre);

  /// "Beni hatırla" açılışı: kayıtlı oturum varsa güncel profili döner,
  /// yoksa null. Sunucu hesabı reddederse [GirisHatasi] (ağ hatası değil),
  /// ulaşılamazsa [GirisHatasi.ag] true.
  ///
  /// [uid]: yalnızca yerel modda kullanılır (bulutta kimlik Firebase
  /// oturumundan gelir).
  Future<Kullanici?> ben(String kurumId, {String? uid});

  /// Oturumu kapatır.
  Future<void> cikis();
}

class GirisDurumu {
  const GirisDurumu({required this.yoneticiVar, this.kilitli = false});

  /// Kimlik + şifresi tanımlı, onaylı bir yönetici var mı? Yoksa ilk kurulum.
  final bool yoneticiVar;

  /// Sunucuda şifre geçişi tamamlandı mı? Tamamlandıysa kayıt ve şifre
  /// işlemleri yalnızca sunucu üzerinden yapılır.
  final bool kilitli;
}

/// Kullanıcıya gösterilebilir giriş hatası.
class GirisHatasi implements Exception {
  const GirisHatasi(this.mesaj, {this.ag = false});

  final String mesaj;

  /// Sunucuya ulaşılamadı / sunucu geçici hata verdi (hesap reddedilmedi).
  final bool ag;

  @override
  String toString() => mesaj;
}

// =============================================================================
// YEREL (cihazdaki mantık)
// =============================================================================
class YerelGirisServisi implements GirisServisi {
  YerelGirisServisi(this._veri);

  final VeriServisi _veri;

  bool _yoneticiVar(List<Kullanici> liste) => liste.any((k) =>
      k.rol == Rol.yonetici &&
      k.kimlik.isNotEmpty &&
      k.sifreHash.isNotEmpty &&
      k.onayli);

  @override
  Future<GirisDurumu> durum(String kurumId) async => GirisDurumu(
      yoneticiVar: _yoneticiVar(await _veri.kullanicilariGetir(kurumId)));

  @override
  Future<Kullanici> girisYap(
      String kurumId, String kimlik, String sifre) async {
    final girilen = kimlik.trim();
    final kucuk = girilen.toLowerCase();
    final liste = await _veri.kullanicilariGetir(kurumId);
    final eslesen = liste.where((k) =>
        k.kimlik == girilen ||
        (k.kullaniciAdi.isNotEmpty && k.kullaniciAdi.toLowerCase() == kucuk));
    if (eslesen.isEmpty) {
      throw const GirisHatasi(
          'Bu T.C. Kimlik No veya kullanıcı adıyla kayıt bulunamadı.');
    }
    final k = eslesen.first;
    if (!Kimlik.sifreDogru(sifre, k.sifreHash)) {
      throw const GirisHatasi('Şifre hatalı.');
    }
    if (!k.onayli) {
      throw const GirisHatasi('Hesabınız henüz yönetici onayı bekliyor.');
    }
    if (!k.aktif) {
      throw const GirisHatasi('Hesabınız pasif durumda. Yöneticinize başvurun.');
    }
    return k;
  }

  @override
  Future<void> uyeOl(String kurumId,
      {required String ad,
      required String kimlik,
      required String sifre}) async {
    final liste = await _veri.kullanicilariGetir(kurumId);
    if (liste.any((k) => k.kimlik == kimlik)) {
      throw const GirisHatasi('Bu T.C. Kimlik No zaten kayıtlı.');
    }
    await _veri.kullaniciKaydet(
      kurumId,
      Kullanici(
        uid: 'k${DateTime.now().microsecondsSinceEpoch}',
        ad: ad,
        eposta: '',
        rol: Rol.izleyici,
        kurumId: kurumId,
        kimlik: kimlik,
        sifreHash: Kimlik.sifreOzeti(sifre),
        onayli: false,
      ),
    );
  }

  @override
  Future<Kullanici> yoneticiOlustur(String kurumId,
      {required String ad,
      required String kimlik,
      required String sifre}) async {
    // Servisler ilk açılışta kimliksiz varsayılan bir "Yönetici" oluşturur;
    // varsa onu yükselt (mükerrer kayıt olmasın), yoksa yeni admin yarat.
    final liste = await _veri.kullanicilariGetir(kurumId);
    final bos = liste
        .where((k) => k.rol == Rol.yonetici && k.kimlik.isEmpty)
        .toList();
    final yonetici = bos.isNotEmpty
        ? bos.first.kopyala(
            ad: ad,
            kimlik: kimlik,
            sifreHash: Kimlik.sifreOzeti(sifre),
            onayli: true,
          )
        : Kullanici.yonetici(
            uid: 'k${DateTime.now().microsecondsSinceEpoch}',
            ad: ad,
            kurumId: kurumId,
            profil: YoneticiProfili.superAdmin,
            kimlik: kimlik,
            sifreHash: Kimlik.sifreOzeti(sifre),
            onayli: true,
          );
    await _veri.kullaniciKaydet(kurumId, yonetici);
    return yonetici;
  }

  @override
  Future<void> sifreAyarla(String kurumId, String uid, String sifre) async {
    final liste = await _veri.kullanicilariGetir(kurumId);
    final k = liste.where((x) => x.uid == uid);
    if (k.isEmpty) throw const GirisHatasi('Kullanıcı bulunamadı.');
    await _veri.kullaniciKaydet(
        kurumId, k.first.kopyala(sifreHash: Kimlik.sifreOzeti(sifre)));
  }

  @override
  Future<Kullanici?> ben(String kurumId, {String? uid}) async {
    if (uid == null) return null;
    final liste = await _veri.kullanicilariGetir(kurumId);
    final uygun = liste.where((k) => k.uid == uid && k.onayli && k.aktif);
    return uygun.isEmpty ? null : uygun.first;
  }

  @override
  Future<void> cikis() async {}
}

// =============================================================================
// BULUT (sunucuda doğrulama)
// =============================================================================

/// Firebase Auth'a erişim — testlerde sahtesi verilir.
abstract class OturumKoprusu {
  /// Sunucunun verdiği özel token ile Firebase'e girer.
  Future<void> tokenIleGirisYap(String token);

  /// Anonim olmayan oturumun ID token'ı; oturum yoksa null.
  Future<String?> idToken();

  /// Hiç oturum yoksa anonim oturum açar (geçiş sürecinde kayıt/ilk kurulum
  /// doğrudan Firestore'a yazdığı için gerekir).
  Future<void> anonimOturumSagla();

  Future<void> cikis();
}

class FirebaseOturumKoprusu implements OturumKoprusu {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  @override
  Future<void> tokenIleGirisYap(String token) async {
    await _auth.signInWithCustomToken(token);
  }

  @override
  Future<String?> idToken() async {
    final u = _auth.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u.getIdToken();
  }

  @override
  Future<void> anonimOturumSagla() async {
    if (_auth.currentUser == null) await _auth.signInAnonymously();
  }

  @override
  Future<void> cikis() => _auth.signOut();
}

class BulutGirisServisi implements GirisServisi {
  BulutGirisServisi({
    required VeriServisi veri,
    OturumKoprusu? oturum,
    http.Client? istemci,
    this.adres = varsayilanAdres,
    this.zamanAsimi = const Duration(seconds: 20),
  })  : _yerel = YerelGirisServisi(veri),
        _oturum = oturum ?? FirebaseOturumKoprusu(),
        _istemci = istemci ?? http.Client();

  static const String varsayilanAdres =
      'https://europe-west1-nobet-sistemi.cloudfunctions.net';

  final String adres;
  final Duration zamanAsimi;
  final YerelGirisServisi _yerel;
  final OturumKoprusu _oturum;
  final http.Client _istemci;

  Future<Map<String, dynamic>> _cagir(String ad, Map<String, dynamic> govde,
      {String? idToken}) async {
    final http.Response yanit;
    try {
      yanit = await _istemci
          .post(
            Uri.parse('$adres/$ad'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              if (idToken != null) 'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(govde),
          )
          .timeout(zamanAsimi);
    } catch (_) {
      throw const GirisHatasi(
          'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.',
          ag: true);
    }
    var json = <String, dynamic>{};
    try {
      json = jsonDecode(utf8.decode(yanit.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (yanit.statusCode != 200) {
      throw GirisHatasi(
        (json['hata'] as String?) ?? 'Sunucu hatası (${yanit.statusCode}).',
        ag: yanit.statusCode >= 500,
      );
    }
    return json;
  }

  Future<Kullanici> _oturumAc(Map<String, dynamic> yanit) async {
    await _oturum.tokenIleGirisYap(yanit['token'] as String);
    final m = Map<String, dynamic>.from(yanit['kullanici'] as Map);
    return Kullanici.haritadan((m['uid'] ?? '') as String, m);
  }

  @override
  Future<GirisDurumu> durum(String kurumId) async {
    final y = await _cagir('npDurum', {'kurumId': kurumId});
    return GirisDurumu(
      yoneticiVar: y['yoneticiVar'] == true,
      kilitli: y['kilitli'] == true,
    );
  }

  @override
  Future<Kullanici> girisYap(
      String kurumId, String kimlik, String sifre) async {
    final y = await _cagir('npGiris',
        {'kurumId': kurumId, 'kimlik': kimlik.trim(), 'sifre': sifre});
    return _oturumAc(y);
  }

  @override
  Future<void> uyeOl(String kurumId,
      {required String ad,
      required String kimlik,
      required String sifre}) async {
    if ((await durum(kurumId)).kilitli) {
      await _cagir('npUyeOl',
          {'kurumId': kurumId, 'ad': ad, 'kimlik': kimlik, 'sifre': sifre});
      return;
    }
    await _oturum.anonimOturumSagla();
    await _yerel.uyeOl(kurumId, ad: ad, kimlik: kimlik, sifre: sifre);
  }

  @override
  Future<Kullanici> yoneticiOlustur(String kurumId,
      {required String ad,
      required String kimlik,
      required String sifre}) async {
    if ((await durum(kurumId)).kilitli) {
      final y = await _cagir('npYoneticiOlustur',
          {'kurumId': kurumId, 'ad': ad, 'kimlik': kimlik, 'sifre': sifre});
      return _oturumAc(y);
    }
    await _oturum.anonimOturumSagla();
    await _yerel.yoneticiOlustur(kurumId, ad: ad, kimlik: kimlik, sifre: sifre);
    // Geçiş bitmedi: kayıt doğrudan yazıldı; oturumu sunucudan al.
    return girisYap(kurumId, kimlik, sifre);
  }

  @override
  Future<void> sifreAyarla(String kurumId, String uid, String sifre) async {
    if ((await durum(kurumId)).kilitli) {
      await _cagir(
        'npSifreAyarla',
        {'kurumId': kurumId, 'uid': uid, 'sifre': sifre},
        idToken: await _oturum.idToken(),
      );
      return;
    }
    await _yerel.sifreAyarla(kurumId, uid, sifre);
  }

  @override
  Future<Kullanici?> ben(String kurumId, {String? uid}) async {
    final token = await _oturum.idToken();
    if (token == null) return null;
    final y = await _cagir('npBen', {'kurumId': kurumId}, idToken: token);
    return _oturumAc(y);
  }

  @override
  Future<void> cikis() => _oturum.cikis();
}
