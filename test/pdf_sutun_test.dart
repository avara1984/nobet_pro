import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/modeller/modeller.dart';
import 'package:nobet_pro/servisler/pdf_servis.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adlar = [
    'Murat ZENCİROĞLU',
    'Mehmet SAYAR',
    'Eser ÇERÇİ',
    'Fatih İŞLEK',
    'Tekin ÖZTÜRK',
    'Derya KANDEMİR',
    'Hakan AYDIN',
    'Serkan YILMAZ',
    'Mehmet Ali ÖZDEMİR',
  ];

  Future<int> sayfaSayisi(int kisi) async {
    final personeller = [
      for (var i = 0; i < kisi; i++) Personel(id: 'p$i', ad: adlar[i], sira: i)
    ];
    final kayit = AyKaydi(yil: 2026, ay: 10);
    for (var g = 1; g <= 31; g++) {
      for (var i = 0; i < kisi; i++) {
        final k = (g + i) % 4;
        kayit.atamalar['${g}_p$i'] = k == 0
            ? kGunduz12
            : (k == 1 ? kGece12 : (k == 2 ? kMesai : kNobetIzni));
      }
    }
    final bytes = await PdfServis.olustur(
      ayar: KurumAyari(),
      personeller: personeller,
      kayit: kayit,
      gunSayisi: 31,
      ozetler: [
        for (final p in personeller)
          PersonelOzeti(
              personel: p,
              vardiyaSayilari: {},
              toplamSaat: 180,
              geceSaati: 80,
              normalMesai: 180,
              fazlaMesaiGunu: 1,
              yillikIzinKullanilan: 0)
      ],
      birim: Birim.guvenlik,
      hedefSaat: 191,
    );
    return RegExp(r'/Type\s*/Page(?!s)')
        .allMatches(latin1.decode(bytes, allowInvalid: true))
        .length;
  }

  group('Aylık PDF sütun düzeni', () {
    test('6 personelli liste tek sayfa', () async {
      expect(await sayfaSayisi(6), 1);
    });

    test('8 ve 9 personelli liste de tek sayfada kalır (kompakt düzen)',
        () async {
      expect(await sayfaSayisi(8), 1);
      expect(await sayfaSayisi(9), 1);
    });
  });
}
