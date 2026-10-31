import 'package:flutter/material.dart';
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

  Future<(NobetDurumu, OturumDurumu)> kur() async {
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

  Future<void> ciz(WidgetTester t, NobetDurumu nd, OturumDurumu o, Widget ekran) async {
    t.view.physicalSize = const Size(1800, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NobetDurumu>.value(value: nd),
        ChangeNotifierProvider<OturumDurumu>.value(value: o),
      ],
      child: MaterialApp(theme: Tema.acik, home: Scaffold(body: ekran)),
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
}
