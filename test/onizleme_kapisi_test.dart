import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/durum/nobet_durumu.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/veri_servisi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<NobetDurumu> ac(Rol rol, {required bool yayinda}) async {
    SharedPreferences.setMockInitialValues({});
    final tercihler = await SharedPreferences.getInstance();
    final servis = BellekServis();
    final simdi = DateTime.now();
    final nd0 = NobetDurumu(
        servis: servis,
        kurumId: 'varsayilan',
        rol: rol,
        tercihler: tercihler,
        uid: 'u');
    await servis.ayKaydiKaydet(
        nd0.birimId,
        AyKaydi(
            yil: simdi.year,
            ay: simdi.month,
            versiyon: kVersiyonOnayli,
            yayinda: yayinda));
    nd0.dispose();
    final d = NobetDurumu(
        servis: servis,
        kurumId: 'varsayilan',
        rol: rol,
        tercihler: tercihler,
        uid: 'u');
    await d.baslat();
    return d;
  }

  group('Önizleme kapısı', () {
    test('yayında olmayan ayda Süper Admin önizleyebilir', () async {
      final d = await ac(Rol.yonetici, yayinda: false);
      expect(await d.onizlemeyeIzinVar(), isTrue);
      d.dispose();
    });

    test('yayında olmayan ayda editör önizleyemez', () async {
      final d = await ac(Rol.editor, yayinda: false);
      expect(await d.onizlemeyeIzinVar(), isFalse);
      d.dispose();
    });

    test('yayında olmayan ayda personel önizleyemez', () async {
      final d = await ac(Rol.izleyici, yayinda: false);
      expect(await d.onizlemeyeIzinVar(), isFalse);
      d.dispose();
    });

    test('yayındaki ayda editör ve personel önizleyebilir', () async {
      final e = await ac(Rol.editor, yayinda: true);
      final p = await ac(Rol.izleyici, yayinda: true);
      expect(await e.onizlemeyeIzinVar(), isTrue);
      expect(await p.onizlemeyeIzinVar(), isTrue);
      e.dispose();
      p.dispose();
    });
  });
}
