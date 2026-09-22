import '../modeller/modeller.dart';
import 'tarih.dart';

enum Kapsama { tam, eksik, yok }

class KuralIhlali {
  KuralIhlali({
    required this.kuralAdi,
    required this.aralik,
    required this.minPersonel,
    required this.enDusuk,
    required this.eksikDk,
  });

  final String kuralAdi;
  final String aralik;
  final int minPersonel;
  final int enDusuk;
  final int eksikDk;

  String get metin =>
      '$kuralAdi ($aralik): en az $minPersonel gerekli, $enDusuk bulundu '
      '— ${T.sureMetni(eksikDk)} açık';
}

class GunKapsamasi {
  GunKapsamasi({
    required this.gun,
    required this.durum,
    required this.calisanSayisi,
    required this.ihlaller,
  });

  final int gun;
  final Kapsama durum;
  final int calisanSayisi;
  final List<KuralIhlali> ihlaller;

  int get toplamEksikDk =>
      ihlaller.fold(0, (t, i) => t + i.eksikDk);

  String get ipucu {
    if (durum == Kapsama.yok) return 'Bu gün için çalışan personel yok.';
    if (ihlaller.isEmpty) return 'Tüm kapsama kuralları sağlandı.';
    return ihlaller.map((i) => i.metin).join('\n');
  }
}

class _Segment {
  _Segment(this.baslangic, this.bitis, this.sayi);
  final int baslangic;
  final int bitis;
  final int sayi;
}

/// Bir ayın atamalarını dakika bazlı zaman çizgisine açıp
/// kapsama kurallarını denetler.
///
/// Zaman çizgisi: 0. dakika = ayın 1. gününün 00:00'ı.
/// Ertesi güne sarkan vardiyalar (ör. 20:00–08:00) otomatik olarak
/// bir sonraki güne taşınır.
class KapsamaMotoru {
  KapsamaMotoru({
    required this.ayar,
    required this.personeller,
    required this.kayit,
    required this.gunSayisi,
  });

  final KurumAyari ayar;
  final List<Personel> personeller;
  final AyKaydi kayit;
  final int gunSayisi;

  List<_Segment>? _onbellek;

  // ---------------------------------------------------------------------------
  List<_Segment> get _segmentler {
    if (_onbellek != null) return _onbellek!;

    final olaylar = <int, int>{}; // dakika → değişim
    for (var gun = 1; gun <= gunSayisi; gun++) {
      final taban = (gun - 1) * 1440;
      for (final p in personeller) {
        final v = ayar.vardiyaBul(kayit.kod(gun, p.id));
        if (!v.calisiyor || v.sureDk <= 0) continue;
        final bas = taban + v.baslangicDk;
        final bit = bas + v.sureDk;
        olaylar[bas] = (olaylar[bas] ?? 0) + 1;
        olaylar[bit] = (olaylar[bit] ?? 0) - 1;
      }
    }

    final noktalar = olaylar.keys.toList()..sort();
    final sonuc = <_Segment>[];
    var sayi = 0;
    for (var i = 0; i < noktalar.length; i++) {
      sayi += olaylar[noktalar[i]]!;
      if (i + 1 < noktalar.length && sayi > 0) {
        sonuc.add(_Segment(noktalar[i], noktalar[i + 1], sayi));
      }
    }
    _onbellek = sonuc;
    return sonuc;
  }

  void onbellegiTemizle() => _onbellek = null;

  // ---------------------------------------------------------------------------
  /// [a, b) aralığında en düşük personel sayısı ve
  /// [min] altında kalınan toplam dakika.
  (int enDusuk, int eksikDk) _aralikDenetle(int a, int b, int min) {
    if (b <= a) return (0, 0);
    var enDusuk = 1 << 30;
    var eksikDk = 0;
    var imlec = a;

    for (final s in _segmentler) {
      if (s.bitis <= a) continue;
      if (s.baslangic >= b) break;
      final bas = s.baslangic < a ? a : s.baslangic;
      final bit = s.bitis > b ? b : s.bitis;

      if (bas > imlec) {
        // hiç personelin olmadığı boşluk
        enDusuk = 0;
        eksikDk += (bas - imlec) * min;
      }
      if (s.sayi < enDusuk) enDusuk = s.sayi;
      if (s.sayi < min) eksikDk += (bit - bas) * (min - s.sayi);
      imlec = bit;
    }

    if (imlec < b) {
      enDusuk = 0;
      eksikDk += (b - imlec) * min;
    }
    if (enDusuk == 1 << 30) enDusuk = 0;
    return (enDusuk, eksikDk);
  }

  // ---------------------------------------------------------------------------
  int calisanSayisi(int gun) {
    var s = 0;
    for (final p in personeller) {
      if (ayar.vardiyaBul(kayit.kod(gun, p.id)).calisiyor) s++;
    }
    return s;
  }

  GunKapsamasi gunKapsamasi(int gun, int yil, int ay) {
    final tarih = DateTime(yil, ay, gun);
    final taban = (gun - 1) * 1440;
    final ihlaller = <KuralIhlali>[];

    for (final k in ayar.kurallar) {
      if (!k.aktif || !k.gunUygunMu(tarih)) continue;
      final uzunluk = k.bitisDk <= k.baslangicDk
          ? k.bitisDk + 1440 - k.baslangicDk
          : k.bitisDk - k.baslangicDk;
      final a = taban + k.baslangicDk;
      final b = a + uzunluk;

      final (enDusuk, eksikDk) = _aralikDenetle(a, b, k.minPersonel);
      if (eksikDk > 0) {
        ihlaller.add(KuralIhlali(
          kuralAdi: k.ad,
          aralik: k.araligMetni,
          minPersonel: k.minPersonel,
          enDusuk: enDusuk,
          eksikDk: eksikDk,
        ));
      }
    }

    final calisan = calisanSayisi(gun);
    final Kapsama durum;
    if (calisan == 0) {
      durum = Kapsama.yok;
    } else if (ihlaller.isEmpty) {
      durum = Kapsama.tam;
    } else {
      durum = Kapsama.eksik;
    }

    return GunKapsamasi(
      gun: gun,
      durum: durum,
      calisanSayisi: calisan,
      ihlaller: ihlaller,
    );
  }

  List<GunKapsamasi> tumAy(int yil, int ay) =>
      [for (var g = 1; g <= gunSayisi; g++) gunKapsamasi(g, yil, ay)];
}


// =============================================================================
// MADDE 3 — GERÇEK 24 SAAT KAPSAMA KONTROLÜ
// =============================================================================
//
// Eski uygulamadaki _build24hCoverageWidget mantığının birebir karşılığı.
// Genel "min personel" kuralından farklı, sabit ve öncelik sıralı:
//
//   1) Kırmızı — Boş gün: o gün hiç kimse çalışmıyor.
//   2) Kırmızı — Saat açığı: 24 saatlik zaman çizelgesinde (gündüz veya
//      gece bölgesinde) kapsanmayan bir aralık var.
//   3) Turuncu — Kadro eksik: saat bazında kapalı ama kişi sayısı kuralı
//      sağlanmıyor (Güvenlik hafta içi dahiliyesiz: gündüzde 2 kişi
//      gerekir; dahiliye varsa veya hafta sonu/tatilse 1 kişi yeterli;
//      Temizlik'te her zaman 1 kişi yeterli; 8'lik sistem kullanılan
//      günlerde bu kural hiç uygulanmaz).
//   4) Yeşil — Sorun yok.
//
// Dahiliye vardiyası (08:00-17:30), kapsama hesabında 08:00-18:00 arası
// dolu sayılır (17:30 yuvarlanır) — bordro saatinden farklıdır, sadece
// kapsama kontrolünde geçerlidir.

enum GercekDurum { bosGun, saatAcigi, kadroEksik, tamam }

class GercekKapsama {
  GercekKapsama({
    required this.gun,
    required this.durum,
    required this.mesaj,
  });

  final int gun;
  final GercekDurum durum;
  final String mesaj;
}

class Madde3Motoru {
  Madde3Motoru({
    required this.ayar,
    required this.personeller,
    required this.kayit,
    required this.gunSayisi,
    required this.birim,
  });

  final KurumAyari ayar;
  final List<Personel> personeller;
  final AyKaydi kayit;
  final int gunSayisi;
  final Birim birim;

  /// Bir vardiyanın **aynı gün içinde** kapattığı saat aralıkları.
  ///
  /// Kritik nokta: `20:00 - 08:00` ertesi güne taşınmaz, o satırın
  /// `[20,24)` ve `[0,8)` saatlerini kapatır. Nöbet listesi böyle okunur —
  /// her satır kendi başına 24 saati kapatmalıdır. Aksi hâlde 8'lik
  /// sistemden 12'lik sisteme geçilen günlerde (resmî tatil sonrası)
  /// olmayan bir açık raporlanır.
  static List<(int, int)> _saatAraliklari(String kod) {
    switch (kod) {
      case kGunduz12:
        return const [(8, 20)];
      case kGece12:
        return const [(20, 24), (0, 8)];
      case kSabah8:
        return const [(8, 16)];
      case kAksam8:
        return const [(16, 24)];
      case kGece8:
        return const [(0, 8)];
      case kMesai:
        return const [(8, 18)]; // dahiliye kapsama için 18:00'e uzatılır
      default:
        return const [];
    }
  }

  /// O günün 24 saatlik kapsama tablosu (saat başına dolu/boş).
  List<bool> _gunKapsamasi(int gun) {
    final kapali = List<bool>.filled(24, false);
    for (final p in personeller) {
      for (final (bas, bit) in _saatAraliklari(kayit.kod(gun, p.id))) {
        for (var s = bas; s < bit; s++) {
          kapali[s] = true;
        }
      }
    }
    return kapali;
  }

  static bool _aralikKapali(List<bool> kapali, int bas, int bit) {
    for (var s = bas; s < bit; s++) {
      if (!kapali[s]) return false;
    }
    return true;
  }

  /// O gün en az bir kişi çalışıyor mu?
  bool _gunBosMu(int gun) {
    for (final p in personeller) {
      if (ayar.vardiyaBul(kayit.kod(gun, p.id)).calisiyor) return false;
    }
    return true;
  }

  /// O gün 8'lik sistem (sabah/akşam/gece) kullanılıyor mu?
  /// Kullanılıyorsa "gündüz 2 kişi" kuralı uygulanmaz.
  bool _sekizlikSistemGunu(int gun) {
    for (final p in personeller) {
      if (p.mesaiMi) continue;
      final kod = kayit.kod(gun, p.id);
      if (kod == kSabah8 || kod == kAksam8 || kod == kGece8) return true;
    }
    return false;
  }

  bool _dahiliyeVarMi(int gun) {
    for (final p in personeller) {
      if (p.mesaiMi) return true;
      if (kayit.kod(gun, p.id) == kMesai) return true;
    }
    return false;
  }

  int _gunduzKisiSayisi(int gun) {
    var n = 0;
    for (final p in personeller) {
      if (p.mesaiMi) continue;
      if (kayit.kod(gun, p.id) == kGunduz12) n++;
    }
    return n;
  }

  GercekKapsama gunDurumu(int gun, int yil, int ay) {
    if (_gunBosMu(gun)) {
      return GercekKapsama(
        gun: gun,
        durum: GercekDurum.bosGun,
        mesaj: 'BOŞ GÜN: Hiç nöbetçi atanmamış.',
      );
    }

    final kapali = _gunKapsamasi(gun);
    final sekizlik = _sekizlikSistemGunu(gun);
    final tarih = DateTime(yil, ay, gun);
    final haftaSonuTatil = T.haftaSonu(tarih) || ayar.resmiTatilMi(tarih);
    final dahiliyeVar = _dahiliyeVarMi(gun);

    // --- Kadro (kişi sayısı) kuralı: yalnızca 12'lik sistemde geçerli ---
    // 8'lik sistemde gün üç vardiyaya bölündüğü için "gündüz 2 kişi"
    // aranmaz (madde 3, referans uygulamayla birebir).
    final eksikler = <String>[];
    var kadroEksigi = false;

    if (!sekizlik) {
      final gerekli = birim == Birim.temizlik
          ? 1
          : (dahiliyeVar || haftaSonuTatil ? 1 : 2);
      final mevcut = _gunduzKisiSayisi(gun);
      if (mevcut < gerekli) {
        kadroEksigi = true;
        eksikler.add(gerekli == 2 && mevcut == 1
            ? 'Gündüz 2. kişi (08:00-20:00)'
            : 'Gündüz kişi sayısı yetersiz (gerekli: $gerekli, mevcut: $mevcut)');
      }
    }

    // --- Saat açığı: gündüz [08,20) ve gece [20,24)+[00,08) ---
    final gunduzBos = !_aralikKapali(kapali, 8, 20);
    final geceBos =
        !_aralikKapali(kapali, 20, 24) || !_aralikKapali(kapali, 0, 8);

    var saatAcigi = false;
    if (gunduzBos) {
      saatAcigi = true;
      if (sekizlik) {
        if (!_aralikKapali(kapali, 8, 16)) eksikler.add('08:00-16:00');
        if (!_aralikKapali(kapali, 16, 20) &&
            !_aralikKapali(kapali, 16, 24)) {
          eksikler.add('16:00-24:00');
        }
      } else {
        eksikler.add('08:00-20:00');
      }
    }
    if (geceBos) {
      saatAcigi = true;
      if (sekizlik) {
        if (!_aralikKapali(kapali, 16, 24) &&
            !eksikler.contains('16:00-24:00')) {
          eksikler.add('16:00-24:00');
        }
        if (!_aralikKapali(kapali, 0, 8)) eksikler.add('24:00-08:00');
      } else {
        eksikler.add('20:00-08:00');
      }
    }

    if (saatAcigi) {
      return GercekKapsama(
        gun: gun,
        durum: GercekDurum.saatAcigi,
        mesaj: 'AĞIR EKSİK: ${eksikler.join(', ')} kapsanmıyor.',
      );
    }
    if (kadroEksigi) {
      return GercekKapsama(
        gun: gun,
        durum: GercekDurum.kadroEksik,
        mesaj: eksikler.join(', '),
      );
    }

    return GercekKapsama(
      gun: gun,
      durum: GercekDurum.tamam,
      mesaj: sekizlik
          ? '8\'lik sistem: 24 saat kapalı.'
          : 'Kapsama kuralları sağlanıyor.',
    );
  }

  List<GercekKapsama> tumAy(int yil, int ay) =>
      [for (var g = 1; g <= gunSayisi; g++) gunDurumu(g, yil, ay)];
}
