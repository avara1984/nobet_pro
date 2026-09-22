import 'package:flutter_test/flutter_test.dart';
import 'package:nobet_pro/core/kapsama_motoru.dart';
import 'package:nobet_pro/modeller/modeller.dart';

/// Madde 3 kapsama denetimi — referans uygulamadaki kuralın birebir
/// karşılığı: her satır KENDİ İÇİNDE 24 saati kapatmalıdır,
/// `20:00 - 08:00` ertesi güne taşınmaz.
void main() {
  final personeller = [
    Personel(id: 'p1', ad: 'Bir'),
    Personel(id: 'p2', ad: 'İki'),
    Personel(id: 'p3', ad: 'Üç'),
    Personel(id: 'p4', ad: 'Dört'),
  ];

  Madde3Motoru motor(
    AyKaydi kayit, {
    Birim birim = Birim.guvenlik,
    Set<String> tatiller = const {},
    List<Personel>? kisiler,
  }) =>
      Madde3Motoru(
        ayar: KurumAyari(resmiTatiller: {...tatiller}),
        personeller: kisiler ?? personeller,
        kayit: kayit,
        gunSayisi: 31,
        birim: birim,
      );

  group('8 saat usulü (resmî tatil)', () {
    test('08-16 + 16-24 + 24-08 aynı gün 24 saati kapatır', () {
      // Kullanıcının bildirdiği senaryo: 30.08.2026 resmî tatil.
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(30, 'p1', kSabah8); // 08:00 - 16:00
      k.ata(30, 'p2', kGece8); // 24:00 - 08:00
      k.ata(30, 'p3', kAksam8); // 16:00 - 24:00
      k.ata(30, 'p4', kHaftaTatili);

      final sonuc = motor(k, tatiller: {'30.08.2026'})
          .gunDurumu(30, 2026, 8);
      expect(sonuc.durum, GercekDurum.tamam,
          reason: '8\'lik sistemde gün tam kapalı, uyarı verilmemeli');
    });

    test('ertesi gün 12\'lik sisteme dönmek uyarı üretmez', () {
      // 30'u 8'lik, 31'i 12'lik. Eski model, 30'un gece bölgesini ertesi
      // güne taşıdığı için 31.08 00:00-08:00'i açık sayıp yanlış uyarı
      // veriyordu. Kadrodaki dahiliye personeli kullanıcının gerçek
      // listesindeki gibi eklendi.
      final kisiler = [
        ...personeller,
        Personel(id: 'p5', ad: 'Dahiliye', gorev: GorevTipi.mesai),
      ];
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(30, 'p1', kSabah8);
      k.ata(30, 'p2', kGece8);
      k.ata(30, 'p3', kAksam8);
      k.ata(31, 'p1', kGunduz12); // 08:00 - 20:00
      k.ata(31, 'p3', kGece12); // 20:00 - 08:00

      final m = motor(k, tatiller: {'30.08.2026'}, kisiler: kisiler);
      expect(m.gunDurumu(30, 2026, 8).durum, GercekDurum.tamam);
      expect(m.gunDurumu(31, 2026, 8).durum, GercekDurum.tamam,
          reason: '20:00-08:00 aynı satırda [20,24)+[0,8) kapatır');
    });

    test('8\'lik sistemde gündüz 2. kişi aranmaz', () {
      // Hafta içi, dahiliye yok — 12'lik olsa 2 kişi gerekirdi.
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(3, 'p1', kSabah8);
      k.ata(3, 'p2', kAksam8);
      k.ata(3, 'p3', kGece8);
      expect(motor(k).gunDurumu(3, 2026, 8).durum, GercekDurum.tamam);
    });

    test('8\'lik sistemde eksik dilim saat açığı olarak bildirilir', () {
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(3, 'p1', kSabah8); // 08-16
      k.ata(3, 'p2', kGece8); // 00-08
      // 16:00-24:00 yok
      final sonuc = motor(k).gunDurumu(3, 2026, 8);
      expect(sonuc.durum, GercekDurum.saatAcigi);
      expect(sonuc.mesaj, contains('16:00-24:00'));
    });
  });

  group('12 saat usulü', () {
    test('gündüz + gece tek satırda 24 saati kapatır', () {
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(2, 'p1', kGunduz12);
      k.ata(2, 'p2', kGece12);
      // 02.08.2026 Pazar → hafta sonu, 1 kişi yeterli
      expect(motor(k).gunDurumu(2, 2026, 8).durum, GercekDurum.tamam);
    });

    test('hafta içi dahiliyesiz gün 2. gündüz kişisi ister', () {
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(4, 'p1', kGunduz12); // 04.08.2026 Salı
      k.ata(4, 'p2', kGece12);
      final sonuc = motor(k).gunDurumu(4, 2026, 8);
      expect(sonuc.durum, GercekDurum.kadroEksik);
      expect(sonuc.mesaj, contains('2. kişi'));
    });

    test('resmî tatilde tek gündüz kişisi yeterli', () {
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(4, 'p1', kGunduz12);
      k.ata(4, 'p2', kGece12);
      expect(
        motor(k, tatiller: {'04.08.2026'}).gunDurumu(4, 2026, 8).durum,
        GercekDurum.tamam,
      );
    });

    test('dahiliye varsa hafta içi tek gündüz kişisi yeterli', () {
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(4, 'p1', kGunduz12);
      k.ata(4, 'p2', kGece12);
      k.ata(4, 'p4', kMesai); // dahiliye
      expect(motor(k).gunDurumu(4, 2026, 8).durum, GercekDurum.tamam);
    });

    test('gece boşluğu saat açığı verir', () {
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(2, 'p1', kGunduz12); // sadece gündüz
      final sonuc = motor(k).gunDurumu(2, 2026, 8);
      expect(sonuc.durum, GercekDurum.saatAcigi);
      expect(sonuc.mesaj, contains('20:00-08:00'));
    });
  });

  group('Diğer durumlar', () {
    test('hiç atama yoksa boş gün', () {
      final k = AyKaydi(yil: 2026, ay: 8);
      expect(motor(k).gunDurumu(5, 2026, 8).durum, GercekDurum.bosGun);
    });

    test('sadece izin kodları varsa boş gün', () {
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(5, 'p1', kYillikIzin);
      k.ata(5, 'p2', kHaftaTatili);
      expect(motor(k).gunDurumu(5, 2026, 8).durum, GercekDurum.bosGun);
    });

    test('temizlik biriminde hafta içi 1 kişi yeterli', () {
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(4, 'p1', kGunduz12);
      k.ata(4, 'p2', kGece12);
      expect(
        motor(k, birim: Birim.temizlik).gunDurumu(4, 2026, 8).durum,
        GercekDurum.tamam,
      );
    });

    test('dahiliye kapsamada 18:00\'e kadar sayılır', () {
      // Mesai (08:00-17:30) + akşam/gece dilimleri ile gün kapanır.
      final k = AyKaydi(yil: 2026, ay: 8);
      k.ata(4, 'p1', kMesai); // kapsamada 08-18
      k.ata(4, 'p2', kAksam8); // 16-24
      k.ata(4, 'p3', kGece8); // 00-08
      expect(motor(k).gunDurumu(4, 2026, 8).durum, GercekDurum.tamam);
    });
  });
}
