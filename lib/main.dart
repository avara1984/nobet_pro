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

    // Anonim oturum — Firestore kuralları `request.auth != null` istediği
    // için gerekli. Uygulamanın kendi T.C.+şifre girişiyle ilgisi yoktur;
    // kullanıcı bunu hiç görmez. Cihaz başına tek anonim kimlik oluşur ve
    // saklanır, her açılışta yenisi yaratılmaz.
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance
          .signInAnonymously()
          .timeout(const Duration(seconds: 10));
    }

    final aday = FirestoreServis();
    // initializeApp çevrimdışıyken de başarılı olur; bulut modunun
    // GERÇEKTEN kullanılabilir olduğunu (ağ/önbellek + Firestore kuralları)
    // tek bir okuma ile doğrula. Başarısızsa yerel moda düş.
    await aday
        .saglikKontrolu(kKurumId)
        .timeout(const Duration(seconds: 10));
    servis = aday;
    bulut = true;
  } catch (e) {
    debugPrint('Bulut moduna geçilemedi, yerel mod kullanılacak: $e');
    servis = YerelServis(tercihler);
  }

  runApp(NobetProApp(tercihler: tercihler, servis: servis, bulut: bulut));
}

class NobetProApp extends StatefulWidget {
  const NobetProApp({
    super.key,
    required this.tercihler,
    required this.servis,
    required this.bulut,
  });

  final SharedPreferences tercihler;
  final VeriServisi servis;

  /// Firestore modunda mı çalışıyor? (false = yerel yedek mod)
  final bool bulut;

  @override
  State<NobetProApp> createState() => _NobetProAppState();
}

class _NobetProAppState extends State<NobetProApp> {
  late bool _koyu;
  late final VeriServisi _servis;
  final _oturum = OturumDurumu();
  late final EkranOlcegi _olcek;
  bool _hazir = false;

  @override
  void initState() {
    super.initState();
    _olcek = EkranOlcegi(widget.tercihler);
    _koyu = widget.tercihler.getBool('koyuTema') ?? false;
    _servis = widget.servis;
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
      final liste = await _servis
          .kullanicilariGetir(kKurumId)
          .timeout(Duration(seconds: widget.bulut ? 15 : 5));

      // Kullanıcı silinmiş/pasifleştirilmiş veya onayı geri alınmış
      // olabilir — bu durumda otomatik giriş yapılmaz.
      final uygun =
          liste.where((k) => k.uid == uid && k.onayli && k.aktif);
      if (uygun.isNotEmpty) _oturum.ayarla(uygun.first);
    } catch (e) {
      debugPrint(
          'Kullanıcı listesi okunamadı, önbellekten devam ediliyor: $e');
      final json = widget.tercihler.getString(_kHatirlananKullaniciJson);
      if (json != null) {
        try {
          final harita = jsonDecode(json) as Map<String, dynamic>;
          _oturum.ayarla(Kullanici.haritadan(uid ?? '', harita));
        } catch (_) {
          // Önbellek bozuksa sessizce normal giriş ekranına düş.
        }
      }
    } finally {
      if (mounted) setState(() => _hazir = true);
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
                      servis: _servis,
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
