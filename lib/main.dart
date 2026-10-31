// =============================================================================
// NÖBET PRO — uygulama girişi
//
// Veriler Firestore'da tutulur (tüm cihazlar aynı veriyi görür).
// Firebase başlatılamazsa uygulama otomatik olarak tamamen yerel moda
// (cihazın kendi diski) düşer — internet olmadan da çalışmaya devam eder.
// =============================================================================

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/tema.dart';
import 'durum/ekran_olcegi.dart';
import 'durum/nobet_durumu.dart';
import 'ekranlar/ana_ekran.dart';
import 'ekranlar/giris_ekrani.dart';
import 'firebase_options.dart';
import 'modeller/modeller.dart';
import 'servisler/bildirim_servisi.dart';
import 'servisler/firestore_servis.dart';
import 'servisler/giris_servisi.dart';
import 'servisler/veri_servisi.dart';
import 'servisler/yerel_servis.dart';

const String kKurumId = 'varsayilan';

// "Beni hatırla" tercihi ve son giren kullanıcı (SharedPreferences anahtarları)
const String _kHatirla = 'beniHatirla';
const String _kHatirlananUid = 'hatirlananUid';
const String _kHatirlananKimlik = 'hatirlananKimlik';
// Son giriş yapan kullanıcının tam kaydı (JSON) — ağ zayıf/zaman aşımına
// uğrarsa sunucuyu beklemeden bu önbellekten giriş yapılır.
const String _kHatirlananKullaniciJson = 'hatirlananKullaniciJson';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tercihler = await SharedPreferences.getInstance();

  VeriServisi servis;
  GirisServisi giris;
  var bulut = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Çevrimdışı önbelleği açıkça etkinleştir — internet kesildiğinde
    // daha önce eşitlenmiş veri okunmaya devam eder.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    final aday = FirestoreServis();
    final adayGiris = BulutGirisServisi(veri: aday);

    // "Beni hatırla" kapalıysa önceki oturumdan kalan Firebase oturumu
    // (veya eski sürümlerden kalan anonim oturum) temizlenir.
    final auth = FirebaseAuth.instance;
    if (!(tercihler.getBool(_kHatirla) ?? false) && auth.currentUser != null) {
      await adayGiris.cikis();
    }

    // Bulut modunun GERÇEKTEN kullanılabilir olduğunu doğrula (initializeApp
    // çevrimdışıyken de başarılı olur). Giriş yapılmış bir oturum varsa
    // Firestore'dan (gerekirse önbellekten) tek bir okuma; yoksa giriş
    // sunucusuna ulaşılabildiği kontrol edilir. Başarısızsa yerel moda düş.
    final oturumlu = auth.currentUser != null && !auth.currentUser!.isAnonymous;
    if (oturumlu) {
      await aday
          .saglikKontrolu(kKurumId)
          .timeout(const Duration(seconds: 10));
    } else {
      await adayGiris
          .durum(kKurumId)
          .timeout(const Duration(seconds: 10));
    }
    servis = aday;
    giris = adayGiris;
    bulut = true;
  } catch (e) {
    debugPrint('Bulut moduna geçilemedi, yerel mod kullanılacak: $e');
    servis = YerelServis(tercihler);
    giris = YerelGirisServisi(servis);
  }

  runApp(NobetProApp(
      tercihler: tercihler, servis: servis, giris: giris, bulut: bulut));
}

class NobetProApp extends StatefulWidget {
  const NobetProApp({
    super.key,
    required this.tercihler,
    required this.servis,
    required this.giris,
    required this.bulut,
  });

  final SharedPreferences tercihler;
  final VeriServisi servis;
  final GirisServisi giris;

  /// Firestore modunda mı çalışıyor? (false = yerel yedek mod)
  final bool bulut;

  @override
  State<NobetProApp> createState() => _NobetProAppState();
}

class _NobetProAppState extends State<NobetProApp> {
  late bool _koyu;
  late final VeriServisi _servis;
  late final GirisServisi _giris;
  final _oturum = OturumDurumu();
  late final EkranOlcegi _olcek;
  bool _hazir = false;

  @override
  void initState() {
    super.initState();
    _olcek = EkranOlcegi(widget.tercihler);
    _koyu = widget.tercihler.getBool('koyuTema') ?? false;
    _servis = widget.servis;
    _giris = widget.giris;
    _sonKullaniciyiAc();
  }

  /// "Beni hatırla" işaretlenmişse son giren kullanıcıyla oturumu doğrudan
  /// açar; aksi hâlde yalnızca bağlantıyı ısıtır ve giriş ekranı gösterilir.
  ///
  /// Ağ (özellikle bulut modda) yavaş/kesikse sunucu isteği zaman aşımına
  /// uğrayabilir — bu durumda kullanıcıyı şifre girmeye zorlamak yerine,
  /// bir önceki başarılı girişte kaydedilmiş TAM kullanıcı kaydı (JSON)
  /// önbellekten kullanılır. Yetki/aktiflik değişmiş olabilir; bu, bir
  /// sonraki başarılı sunucu bağlantısında normal akışla kontrol edilir.
  Future<void> _sonKullaniciyiAc() async {
    if (!(widget.tercihler.getBool(_kHatirla) ?? false)) {
      if (mounted) setState(() => _hazir = true);
      return;
    }
    final uid = widget.tercihler.getString(_kHatirlananUid);
    try {
      // Bulutta kayıtlı Firebase oturumundan, yerelde kayıtlı uid'den güncel
      // profil okunur. Silinmiş/pasifleştirilmiş veya onayı geri alınmış
      // kullanıcı için otomatik giriş yapılmaz.
      final k = await _giris
          .ben(kKurumId, uid: uid)
          .timeout(Duration(seconds: widget.bulut ? 15 : 5));
      if (k != null) _oturum.ayarla(k);
    } on GirisHatasi catch (e) {
      if (e.ag) {
        _onbellektenAc(uid);
      } else {
        // Hesap reddedildi (silinmiş, pasif, oturum geçersiz).
        await _giris.cikis();
      }
    } catch (e) {
      debugPrint(
          'Kullanıcı bilgisi okunamadı, önbellekten devam ediliyor: $e');
      _onbellektenAc(uid);
    } finally {
      if (mounted) setState(() => _hazir = true);
    }
  }

  /// Sunucuya ulaşılamadığında son başarılı girişte saklanan kullanıcı
  /// kaydıyla devam eder. Yetki/aktiflik değişmiş olabilir; bu, bir sonraki
  /// başarılı sunucu bağlantısında normal akışla kontrol edilir.
  void _onbellektenAc(String? uid) {
    final json = widget.tercihler.getString(_kHatirlananKullaniciJson);
    if (json == null) return;
    try {
      final harita = jsonDecode(json) as Map<String, dynamic>;
      _oturum.ayarla(Kullanici.haritadan(uid ?? '', harita));
    } catch (_) {
      // Önbellek bozuksa sessizce normal giriş ekranına düş.
    }
  }

  void _girisYapildi(Kullanici k, bool hatirla) {
    widget.tercihler.setBool(_kHatirla, hatirla);
    if (hatirla) {
      widget.tercihler.setString(_kHatirlananUid, k.uid);
      widget.tercihler.setString(_kHatirlananKimlik, k.kimlik);
      widget.tercihler
          .setString(_kHatirlananKullaniciJson, jsonEncode(k.haritasi));
    } else {
      widget.tercihler.remove(_kHatirlananUid);
      widget.tercihler.remove(_kHatirlananKimlik);
      widget.tercihler.remove(_kHatirlananKullaniciJson);
    }
    _oturum.ayarla(k);
  }

  /// Bilinçli çıkışta hatırlama iptal edilir — aksi hâlde kullanıcı
  /// çıkış yapsa bile uygulama bir sonraki açılışta yine onu içeri alırdı.
  /// T.C. Kimlik No, alanı elle doldurmamak için saklı kalır.
  Future<void> _cikisYap() async {
    await widget.tercihler.setBool(_kHatirla, false);
    await widget.tercihler.remove(_kHatirlananUid);
    await widget.tercihler.remove(_kHatirlananKullaniciJson);
    await _giris.cikis();
    _oturum.temizle();
  }

  void _temaDegistir() {
    setState(() => _koyu = !_koyu);
    widget.tercihler.setBool('koyuTema', _koyu);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _oturum),
        ChangeNotifierProvider.value(value: _olcek),
        Provider<GirisServisi>.value(value: _giris),
      ],
      child: MaterialApp(
        title: 'Nöbet Sistemi',
        debugShowCheckedModeBanner: false,
        scrollBehavior: _OlcekScrollDavranisi(),
        builder: (context, child) => _OlcekKatmani(child: child!),
        // Tarih seçici gibi yerleşik Material widget'ları (Cancel/OK,
        // ay/gün adları) Türkçe görünsün diye.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('tr', 'TR')],
        locale: const Locale('tr', 'TR'),
        theme: Tema.acik,
        darkTheme: Tema.koyu,
        themeMode: _koyu ? ThemeMode.dark : ThemeMode.light,
        home: !_hazir
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : Consumer<OturumDurumu>(
                builder: (context, oturum, _) {
                  if (!oturum.girisYapildi) {
                    return GirisEkrani(
                      giris: _giris,
                      kurumId: kKurumId,
                      girisYapildi: _girisYapildi,
                      baslangicKimlik: widget.tercihler
                              .getString(_kHatirlananKimlik) ??
                          '',
                      baslangicHatirla:
                          widget.tercihler.getBool(_kHatirla) ?? true,
                    );
                  }
                  return ChangeNotifierProvider<NobetDurumu>(
                    key: ValueKey(oturum.kullanici!.uid),
                    create: (_) {
                      final nd = NobetDurumu(
                        servis: _servis,
                        kurumId: kKurumId,
                        rol: oturum.rol,
                        tercihler: widget.tercihler,
                        uid: oturum.kullanici!.uid,
                        sadecePdf: oturum.kullanici?.sadecePdf ?? false,
                        bordroYetkisi:
                            oturum.kullanici?.bordroYetkisi ?? false,
                        kisitliBirimGiris: oturum.kullanici?.kisitliBirim,
                      );
                      nd.baslat().then((_) => bildirimleriBaslat(nd));
                      return nd;
                    },
                    child: AnaEkran(
                      temaDegistir: _temaDegistir,
                      koyuTema: _koyu,
                      cikisYap: _cikisYap,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Tüm uygulamayı [EkranOlcegi] oranında büyütür/küçültür. Alt ağaç,
/// gerçek boyutun oran kadar bölünmüş hâlinde yerleşir (ör. %80'de
/// pencere 1,25 kat "geniş" görünür) ve ekrana sığacak şekilde ölçeklenir —
/// tablolar bu sayede daha çok sütun gösterebilir. Ctrl + tekerlek ve
/// Ctrl +/−/0 kısayolları da burada dinlenir.
class _OlcekKatmani extends StatelessWidget {
  const _OlcekKatmani({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final o = context.watch<EkranOlcegi>();
    final s = o.deger;
    var icerik = child;
    if ((s - 1).abs() > 0.001) {
      final mq = MediaQuery.of(context);
      final boyut = mq.size / s;
      icerik = FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: boyut.width,
          height: boyut.height,
          child: MediaQuery(data: mq.copyWith(size: boyut), child: child),
        ),
      );
    }
    if (!EkranOlcegi.desteklenir) return icerik;

    return CallbackShortcuts(
      bindings: {
        for (final k in [
          LogicalKeyboardKey.equal,
          LogicalKeyboardKey.add,
          LogicalKeyboardKey.numpadAdd,
        ])
          SingleActivator(k, control: true): o.artir,
        for (final k in [LogicalKeyboardKey.minus, LogicalKeyboardKey.numpadSubtract])
          SingleActivator(k, control: true): o.azalt,
        for (final k in [LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0])
          SingleActivator(k, control: true): o.sifirla,
      },
      child: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent &&
              HardwareKeyboard.instance.isControlPressed &&
              e.scrollDelta.dy != 0) {
            e.scrollDelta.dy < 0 ? o.artir() : o.azalt();
          }
        },
        child: icerik,
      ),
    );
  }
}

/// Ctrl basılıyken tekerlek sayfayı kaydırmasın (yakınlaştırmaya ayrılır).
class _OlcekScrollDavranisi extends MaterialScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      _CtrlDuyarliFizik(parent: super.getScrollPhysics(context));
}

class _CtrlDuyarliFizik extends ScrollPhysics {
  const _CtrlDuyarliFizik({super.parent});

  @override
  ScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _CtrlDuyarliFizik(parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !HardwareKeyboard.instance.isControlPressed &&
      super.shouldAcceptUserOffset(position);
}
