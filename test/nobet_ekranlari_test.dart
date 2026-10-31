import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/tema.dart';
import 'package:nobet_pro/durum/nobet_durumu.dart';
import 'package:nobet_pro/ekranlar/donem_nobet_ekrani.dart';
import 'package:nobet_pro/ekranlar/haftalik_nobet_ekrani.dart';
import 'package:nobet_pro/ekranlar/nobet_listesi_ekrani.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/veri_servisi.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Üç nöbet ekranının (Nöbet Listesi, Haftalık Nöbet/15-14, 15 - 14 Nöbet)
/// ortak kodu (`nobet_ortak.dart`) kullandığı için, hepsinin gerçek veriyle
/// hatasız çizildiğini ve ortak parçaların (personel başlığı, ad/soyad ayırma)
/// çalıştığını doğrular.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(NobetDurumu, OturumDurumu)> kur(
      {List<(int, String, String)> ek = const []}) async {
    SharedPreferences.setMockInitialValues({});
    final tercihler = await SharedPreferences.getInstance();
    final servis = BellekServis();
    final nd = NobetDurumu(
      servis: servis,
      kurumId: 'varsayilan',
      rol: Rol.yonetici,
      tercihler: tercihler,
      uid: 'u',
    );
    await servis.personelKaydet(
        nd.birimId, Personel(id: 'p1', ad: 'Ayşe Yılmaz', sira: 0));
    await servis.personelKaydet(
        nd.birimId, Personel(id: 'p2', ad: 'Mehmet Kaya', sira: 1));
    final simdi = DateTime.now();
    for (final v in [kVersiyonOnayli, kVersiyonNobet]) {
      final k = AyKaydi(yil: simdi.year, ay: simdi.month, versiyon: v);
      k.ata(1, 'p1', kGunduz12);
      k.ata(2, 'p2', kGece12);
      for (final (g, pid, kod) in ek) {
        k.ata(g, pid, kod);
      }
      await servis.ayKaydiKaydet(nd.birimId, k);
    }
    await nd.baslat();
    final oturum = OturumDurumu()
      ..ayarla(Kullanici.yonetici(
        uid: 'u',
        ad: 'Test Yönetici',
        kurumId: 'varsayilan',
        profil: YoneticiProfili.superAdmin,
      ));
    return (nd, oturum);
  }

  Future<void> ciz(WidgetTester t, NobetDurumu nd, OturumDurumu o, Widget ekran,
      {ThemeData? tema, double genislik = 1800}) async {
    t.view.physicalSize = Size(genislik, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NobetDurumu>.value(value: nd),
        ChangeNotifierProvider<OturumDurumu>.value(value: o),
      ],
      child: MaterialApp(theme: tema ?? Tema.acik, home: Scaffold(body: ekran)),
    ));
    // Yanıp sönen "!" animasyonu yüzünden pumpAndSettle kullanılmaz.
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  /// Ağacı kaldırır ve durumu kapatır (5 dakikalık duyuru zamanlayıcısını iptal eder).
  Future<void> bitir(WidgetTester t, NobetDurumu nd) async {
    await t.pumpWidget(const SizedBox());
    nd.dispose();
  }

  void personelBasliklari(WidgetTester t) {
    // Ortak nobetPersonelBaslikHucre / nobetAdSoyadAyir: ad ve soyad ayrı satırda.
    expect(find.text('Ayşe'), findsWidgets);
    expect(find.text('Yılmaz'), findsWidgets);
    expect(find.text('Mehmet'), findsWidgets);
    expect(find.text('Kaya'), findsWidgets);
    expect(t.takeException(), isNull);
  }

  testWidgets('Nöbet Listesi ekranı çizilir', (t) async {
    final (nd, o) = await kur();
    await ciz(t, nd, o, const NobetListesiEkrani(genis: true));
    personelBasliklari(t);
    await bitir(t, nd);
  });

  testWidgets('Haftalık Nöbet ekranı çizilir', (t) async {
    final (nd, o) = await kur();
    await ciz(t, nd, o, const HaftalikNobetEkrani(key: ValueKey('h'), genis: true));
    personelBasliklari(t);
    await bitir(t, nd);
  });

  testWidgets('Haftalık 15-14 ekranı çizilir', (t) async {
    final (nd, o) = await kur();
    await ciz(t, nd, o,
        const HaftalikNobetEkrani(key: ValueKey('h1514'), genis: true, donem: true));
    personelBasliklari(t);
    await bitir(t, nd);
  });

  testWidgets('15 - 14 Nöbet ekranı çizilir', (t) async {
    final (nd, o) = await kur();
    await ciz(t, nd, o, const DonemNobetEkrani(genis: true));
    personelBasliklari(t);
    await bitir(t, nd);
  });

  // --- Dinlenme kuralı: ters yön (ertesi gün dolu) — gerçek tıklama akışı ----
  group('Nöbet Listesi: ertesi günü dolu olan güne gece yazmak', () {
    /// 3. güne [ertesi] yazılı, 2. gündeki Ayşe hücresine [yazilacak] seçilir.
    /// Ayşe'nin 3. gün hücresi `find.text(ertesi)` ile bulunur; bir satır yukarısı 2. gündür.
    Future<(NobetDurumu, OturumDurumu)> hazirla(WidgetTester t, String ertesi) async {
      final (nd, o) = await kur();
      await nd.versiyonDegistir(kVersiyonNobet); // Onaylanan Liste PIN'li; bu serbest
      nd.kodAta(3, 'p1', ertesi);
      await ciz(t, nd, o, const NobetListesiEkrani(genis: true));
      return (nd, o);
    }

    /// Ayşe'nin (ilk personel sütunu) 2. gün hücresine dokunur: x = "Ayşe"
    /// başlığının ortası, y = "02.<ay>.<yıl>" tarih satırının ortası.
    Future<void> ikinciGuneYaz(WidgetTester t, String yazilacak) async {
      final simdi = DateTime.now();
      final tarih = '02.${simdi.month.toString().padLeft(2, '0')}.${simdi.year}';
      final x = t.getCenter(find.text('Ayşe').first).dx;
      final y = t.getCenter(find.text(tarih)).dy;
      await t.tapAt(Offset(x, y));
      await t.pump(const Duration(milliseconds: 400));
      // Vardiya listesinde satırın alt yazısı "<kod> · <süre>" biçimindedir.
      final satir = find.textContaining('$yazilacak ·').first;
      await t.ensureVisible(satir); // uzun listede ekran dışında kalabilir
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(satir);
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('3. günde 08:00-20:00 varken 2. güne 20:00-08:00 → uyarı çıkar', (t) async {
      final (nd, _) = await hazirla(t, kGunduz12);
      await ikinciGuneYaz(t, kGece12);

      expect(find.text('DİKKAT: NÖBET İHLALİ'), findsOneWidget);
      expect(find.textContaining('ertesi gün $kGunduz12'), findsOneWidget);
      expect(nd.kayit.kod(2, 'p1'), isNot(kGece12), reason: 'onay verilmeden yazılmamalı');

      await t.tap(find.text('Vazgeç'));
      await t.pump(const Duration(milliseconds: 300));
      expect(nd.kayit.kod(2, 'p1'), isNot(kGece12), reason: 'vazgeçilince yazılmamalı');

      await bitir(t, nd);
    });

    testWidgets('3. günde 08:00-20:00 varken 2. güne 24:00-08:00 → uyarı çıkar', (t) async {
      final (nd, _) = await hazirla(t, kGunduz12);
      await ikinciGuneYaz(t, kGece8);
      expect(find.text('DİKKAT: NÖBET İHLALİ'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await t.pump(const Duration(milliseconds: 300));
      await bitir(t, nd);
    });

    testWidgets('uyarıda "Yine de yaz" denirse vardiya yazılır', (t) async {
      final (nd, _) = await hazirla(t, kGunduz12);
      await ikinciGuneYaz(t, kGece12);
      await t.tap(find.text('Yine de yaz (riskli)'));
      await t.pump(const Duration(milliseconds: 300));
      expect(nd.kayit.kod(2, 'p1'), kGece12);
      await bitir(t, nd);
    });

    testWidgets('ertesi gün de gece ise (arka arkaya gece) uyarı çıkmaz', (t) async {
      final (nd, _) = await hazirla(t, kGece12);
      await ikinciGuneYaz(t, kGece12);
      expect(find.text('DİKKAT: NÖBET İHLALİ'), findsNothing);
      expect(nd.kayit.kod(2, 'p1'), kGece12);
      await bitir(t, nd);
    });
  });

  // Haftalık ve 15 - 14 ekranları kuralı kendi `_vardiyaSec`'inden çağırır; aynı
  // senaryo orada da uyarı vermeli. Bu ekranlar varsayılan olarak "Onaylanan
  // Liste"yi gösterir: hücreye dokununca önce PIN (varsayılan 0000) sorulur.
  for (final (ad, ekran) in <(String, Widget Function())>[
    ('Haftalık Nöbet',
        () => const HaftalikNobetEkrani(key: ValueKey('hk'), genis: true)),
    ('Haftalık 15-14',
        () => const HaftalikNobetEkrani(
            key: ValueKey('hk1514'), genis: true, donem: true)),
    ('15 - 14 Nöbet', () => const DonemNobetEkrani(genis: true)),
  ]) {
    testWidgets('$ad: ertesi günü gündüz olan güne gece yazınca uyarı çıkar',
        (t) async {
      // 17'sinde 08:00-20:00 var (15 - 14 döneminde ve haftalık ekranda görünür).
      final (nd, o) = await kur(ek: [(17, 'p1', kGunduz12)]);
      await ciz(t, nd, o, ekran());

      final simdi = DateTime.now();
      final ay = simdi.month.toString().padLeft(2, '0');
      final x = t.getCenter(find.text('Ayşe').first).dx;
      final y = t.getCenter(find.text('16.$ay.${simdi.year}').first).dy;
      await t.tapAt(Offset(x, y));
      await t.pump(const Duration(milliseconds: 400));

      // "Onaylanan Liste" PIN'i
      await t.enterText(find.byType(TextField).last, '0000');
      await t.tap(find.text('Aç'));
      await t.pump(const Duration(milliseconds: 500));

      final satir = find.textContaining('$kGece12 ·').first;
      await t.ensureVisible(satir);
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(satir);
      await t.pump(const Duration(milliseconds: 400));

      expect(find.text('DİKKAT: NÖBET İHLALİ'), findsOneWidget);
      expect(find.textContaining('ertesi gün $kGunduz12'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await t.pump(const Duration(milliseconds: 300));
      await bitir(t, nd);
    });
  }

  // --- Android'de vardiya yazısı +0,5 punto, en dar sütunda taşmaz --------------
  group('Android vardiya yazısı', () {
    // Gerçek ölçü için Roboto Bold yüklenir (testte varsayılan yazı tipi her
    // harfi punto kadar geniş çizer, taşma ölçülemez).
    Future<ThemeData> robotoTema() async {
      final yukleyici = FontLoader('RobotoTest')
        ..addFont(Future.value(
            ByteData.sublistView(File('assets/fonts/Roboto-Bold.ttf').readAsBytesSync())));
      await yukleyici.load();
      return Tema.acik.copyWith(
          textTheme: Tema.acik.textTheme.apply(fontFamily: 'RobotoTest'));
    }

    /// [ekran] çizilir; [desen]e uyan her vardiya yazısının punto boyu
    /// [beklenenPunto] olmalı ve kırpılmamalı (didExceedMaxLines == false).
    Future<void> kontrol(WidgetTester t, TargetPlatform platform, Widget ekran,
        RegExp desen, double beklenenPunto,
        {double genislik = 1800}) async {
      final tema = await robotoTema();
      debugDefaultTargetPlatformOverride = platform;
      try {
        // 15 - 14 dönemi 15'inden başlar: 16-17'sine de vardiya yazılır.
        final (nd, o) = await kur(ek: [
          (16, 'p1', kGunduz12),
          (16, 'p2', kGece12),
          (17, 'p1', kGece8),
          (17, 'p2', kGunduz12),
        ]);
        await ciz(t, nd, o, ekran, tema: tema, genislik: genislik);

        final kapsuller = find.byWidgetPredicate(
            (w) => w is Text && w.data != null && desen.hasMatch(w.data!));
        expect(kapsuller, findsWidgets, reason: 'kapsül yazıları görünmeli');

        for (final e in kapsuller.evaluate()) {
          final yazi = e.widget as Text;
          expect(yazi.style!.fontSize, closeTo(beklenenPunto, .001),
              reason: '${yazi.data} punto');
          final cizim = e.renderObject! as RenderParagraph;
          expect(cizim.didExceedMaxLines, isFalse,
              reason: '${yazi.data} kırpılmamalı');
        }
        await bitir(t, nd);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    // Nöbet Listesi: telefonda en dar otomatik sığdırma (64 px, boşluksuz etiket).
    final bosluksuz = RegExp(r'^\d\d:\d\d-\d\d:\d\d$');
    // Haftalık ekranlar: sabit 85 px sütun, boşluklu etiket.
    final bosluklu = RegExp(r'^\d\d:\d\d - \d\d:\d\d$');
    const liste = NobetListesiEkrani(genis: true);
    const haftalik = HaftalikNobetEkrani(key: ValueKey('a1'), genis: true);
    const haftalik1514 =
        HaftalikNobetEkrani(key: ValueKey('a2'), genis: true, donem: true);
    const donem = DonemNobetEkrani(genis: true);
    const listeOlcek = 11.5 * (64 / 85);

    for (final (ad, ekran, desen, taban, genislik) in <(String, Widget, RegExp, double, double)>[
      ('Nöbet Listesi', liste, bosluksuz, listeOlcek, 560),
      ('Haftalık Nöbet', haftalik, bosluklu, 11.5, 1800),
      ('Haftalık 15-14', haftalik1514, bosluklu, 11.5, 1800),
      ('15 - 14 Nöbet', donem, bosluklu, 11.5, 1800),
    ]) {
      testWidgets('Android: $ad vardiya yazısı +0,5 punto ve kırpılmaz', (t) async {
        await kontrol(t, TargetPlatform.android, ekran, desen, taban + .5,
            genislik: genislik);
      });
      testWidgets('Windows: $ad vardiya yazısı değişmez', (t) async {
        await kontrol(t, TargetPlatform.windows, ekran, desen, taban,
            genislik: genislik);
      });
    }
  });
}
