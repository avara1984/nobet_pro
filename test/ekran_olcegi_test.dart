import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/durum/ekran_olcegi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> tercih([Map<String, Object> ilk = const {}]) async {
    SharedPreferences.setMockInitialValues(ilk);
    return SharedPreferences.getInstance();
  }

  test('varsayılan %100, adım adım değişir ve sınırlarda durur', () async {
    final o = EkranOlcegi(await tercih());
    expect(o.yuzde, 100);
    expect(o.varsayilan, isTrue);
    o.azalt();
    expect(o.yuzde, 90);
    for (var i = 0; i < 20; i++) {
      o.azalt();
    }
    expect(o.yuzde, 60);
    for (var i = 0; i < 20; i++) {
      o.artir();
    }
    expect(o.yuzde, 130);
    o.sifirla();
    expect(o.yuzde, 100);
  });

  test('seçim cihazda hatırlanır; bozuk değer sınırlanır', () async {
    final t = await tercih();
    EkranOlcegi(t).ayarla(0.8);
    expect(EkranOlcegi(t).yuzde, 80);

    final asiri = EkranOlcegi(await tercih({'ekran_olcegi': 5.0}));
    expect(asiri.yuzde, 130);
  });
}
