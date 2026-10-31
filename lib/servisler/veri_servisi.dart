import '../core/tarih.dart';
import '../modeller/bordro_modelleri.dart';
import '../modeller/modeller.dart';

/// Depodaki bir kayıt okunamadı (JSON bozuk veya beklenen biçimde değil).
///
/// Bozuk kayıt "boş" sayılmaz: aksi hâlde çağıran taraf varsayılan veriyi
/// yazıp gerçek kaydın üzerine basardı. Hata kullanıcıya gösterilir, kayıt
/// olduğu gibi kalır ve elle kurtarılabilir.
class VeriBozukHatasi implements Exception {
  const VeriBozukHatasi(this.anahtar);

  /// Bozuk kaydın depo anahtarı (ör. `kullanicilar_varsayilan`).
  final String anahtar;

  @override
  String toString() =>
      'Kayıt okunamadı (bozuk veri): $anahtar. Üzerine yazılmadı; '
      'yöneticiye başvurun.';
}

/// Bir kayıt, depolama sınırını aşacak kadar büyük.
class VeriCokBuyukHatasi implements Exception {
  const VeriCokBuyukHatasi(this.anahtar, this.bayt);

  final String anahtar;
  final int bayt;

  @override
  String toString() =>
      'Kayıt çok büyük ($bayt bayt), kaydedilemedi: $anahtar.';
}

/// Veri katmanı sözleşmesi. FirestoreServis ve BellekServis bunu uygular.
abstract class VeriServisi {
  Future<KurumAyari> kurumAyariGetir(String kurumId);
  Future<void> kurumAyariKaydet(KurumAyari ayar);

  Future<List<Personel>> personelleriGetir(String kurumId);
  Future<void> personelKaydet(String kurumId, Personel personel);
  Future<void> personelSil(String kurumId, String personelId);

  Future<AyKaydi> ayKaydiGetir(String kurumId, int yil, int ay,
      {String versiyon = ''});
  Future<void> ayKaydiKaydet(String kurumId, AyKaydi kayit);
  Future<List<String>> versiyonlariGetir(String kurumId, int yil, int ay);
  Future<void> versiyonSil(String kurumId, int yil, int ay, String versiyon);

  Future<List<Duyuru>> duyurulariGetir(String kurumId);
  Future<void> duyuruKaydet(String kurumId, Duyuru duyuru);
  Future<void> duyuruSil(String kurumId, String duyuruId);

  /// Bir kullanıcının duyuruları ne zaman gördüğü (duyuruId → zaman).
  /// Her kullanıcı yalnızca kendi kaydını yazar — eşzamanlı yazma çakışması
  /// olmasın diye kayıtlar kullanıcı başına ayrı tutulur.
  Future<Map<String, DateTime>> duyuruOkumalariniGetir(
      String kurumId, String uid);
  Future<void> duyuruOkumalariniKaydet(
      String kurumId, String uid, Map<String, DateTime> okumalar);

  /// Tüm kullanıcıların duyuru okumaları: uid → (duyuruId → zaman).
  Future<Map<String, Map<String, DateTime>>> tumDuyuruOkumalari(
      String kurumId);

  Future<List<Kullanici>> kullanicilariGetir(String kurumId);
  Future<void> kullaniciKaydet(String kurumId, Kullanici kullanici);
  Future<void> kullaniciSil(String kurumId, String uid);

  // --- BORDRO ---------------------------------------------------------------
  /// Yıllık bordro sabitleri. Kayıt yoksa varsayılan döner.
  /// Ayarlar birimden bağımsızdır, [kurumId] doğrudan verilir.
  Future<BordroAyari> bordroAyariGetir(String kurumId, int yil);
  Future<void> bordroAyariKaydet(String kurumId, BordroAyari ayar);

  /// Personel ücretleri birim başına tutulur ([birimId] kullanılır).
  Future<List<PersonelUcreti>> personelUcretleriGetir(String birimId);
  Future<void> personelUcretiKaydet(String birimId, PersonelUcreti ucret);
  Future<void> personelUcretiSil(String birimId, String personelId);

  Future<BordroSonucu?> bordroGetir(
      String birimId, String personelId, int yil, int ay);
  Future<void> bordroKaydet(String birimId, BordroSonucu sonuc);
  Future<void> bordroSil(String birimId, String personelId, int yil, int ay);

  /// Kayıtlı bordrolar. [yil]/[ay] verilirse yalnızca o döneme ait olanlar.
  Future<List<BordroSonucu>> bordrolariGetir(String birimId, {int? yil, int? ay});

  // --- BORDRO PDF YÜKLEMESİ --------------------------------------------------
  /// PDF bordroyu base64 olarak kaydeder. Mevcut kayıt üzerine yazılır.
  Future<void> bordroYukle(String birimId, YuklenmisBordro kayit);

  /// Belirtilen personel/dönem için yüklü bordroyu döndürür; yoksa null.
  /// [pdfDahil] false ise pdfBase64 alanı boş döner (liste sorgusu için).
  Future<YuklenmisBordro?> bordroYuklemesiniGetir(
      String birimId, String personelId, int yil, int ay,
      {bool pdfDahil = true});

  /// Birime ait yüklenmiş bordroları döndürür (meta-veri; PDF bytes yok).
  Future<List<YuklenmisBordro>> birimBordroYuklemeleriniGetir(
      String birimId, {int? yil, int? ay});

  /// Yüklenmiş bordroyu siler.
  Future<void> bordroYuklemeSil(
      String birimId, String personelId, int yil, int ay);
}

/// Yedekleme ekranının kullandığı ek sözleşme — servis tüm veriyi tek JSON
/// metni olarak dışa aktarabilir ve aynı biçimden geri yükleyebilir.
/// Hem [YerelServis] hem [FirestoreServis] uygular; JSON biçimi ortaktır,
/// bu sayede yerel yedek buluta (veya tersi) taşınabilir.
abstract class YedeklenebilirServis {
  Future<String> tumVeriyiDisaAktar();
  Future<void> yedektenYukle(String json);
}

// -----------------------------------------------------------------------------
// BELLEK SERVİSİ — test/deneme amaçlı, veriler kalıcı değildir
// -----------------------------------------------------------------------------
class BellekServis implements VeriServisi {
  KurumAyari _ayar = KurumAyari(
    ad: 'T.C. SAĞLIK BAKANLIĞI — AYDIN YENİPAZAR İLÇE DEVLET HASTANESİ',
  );

  final List<Personel> _personeller = [
    Personel(id: 'p1', ad: 'Murat Zenciroğlu', sira: 0),
    Personel(id: 'p2', ad: 'Mehmet Sayar', sira: 1),
    Personel(id: 'p3', ad: 'Eser Çerçi', sira: 2),
    Personel(id: 'p4', ad: 'Hakan Aydın', sira: 3),
    Personel(id: 'p5', ad: 'Serkan Yılmaz', sira: 4),
    Personel(
        id: 'p6', ad: 'Derya Kandemir', gorev: GorevTipi.mesai, sira: 5),
  ];

  final Map<String, AyKaydi> _aylar = {};

  final List<Duyuru> _duyurular = [
    Duyuru(
      id: 'd1',
      baslik: 'Nöbet değişim talepleri',
      icerik:
          'Değişim talepleri ayın 25’ine kadar yazılı olarak iletilmelidir.',
      tarih: DateTime.now().subtract(const Duration(days: 3)),
      yazar: 'Yönetim',
    ),
  ];

  @override
  Future<KurumAyari> kurumAyariGetir(String kurumId) async => _ayar;

  @override
  Future<void> kurumAyariKaydet(KurumAyari ayar) async => _ayar = ayar;

  @override
  Future<List<Personel>> personelleriGetir(String kurumId) async =>
      _personeller.where((p) => p.aktif).toList()
        ..sort((a, b) => a.sira.compareTo(b.sira));

  @override
  Future<void> personelKaydet(String kurumId, Personel personel) async {
    final i = _personeller.indexWhere((p) => p.id == personel.id);
    if (i == -1) {
      _personeller.add(personel);
    } else {
      _personeller[i] = personel;
    }
  }

  @override
  Future<void> personelSil(String kurumId, String personelId) async =>
      _personeller.removeWhere((p) => p.id == personelId);

  @override
  Future<AyKaydi> ayKaydiGetir(String kurumId, int yil, int ay,
          {String versiyon = ''}) async =>
      _aylar['${T.donemAnahtari(yil, ay)}|$versiyon'] ??
      AyKaydi(yil: yil, ay: ay, versiyon: versiyon);

  @override
  Future<void> ayKaydiKaydet(String kurumId, AyKaydi kayit) async => _aylar[
      '${T.donemAnahtari(kayit.yil, kayit.ay)}|${kayit.versiyon}'] = kayit;

  @override
  Future<List<String>> versiyonlariGetir(
          String kurumId, int yil, int ay) async =>
      kListeVersiyonlari;

  @override
  Future<void> versiyonSil(
      String kurumId, int yil, int ay, String versiyon) async {}

  @override
  Future<List<Duyuru>> duyurulariGetir(String kurumId) async =>
      List.of(_duyurular)..sort((a, b) => b.tarih.compareTo(a.tarih));

  @override
  Future<void> duyuruKaydet(String kurumId, Duyuru duyuru) async {
    final i = _duyurular.indexWhere((d) => d.id == duyuru.id);
    if (i == -1) {
      _duyurular.add(duyuru);
    } else {
      _duyurular[i] = duyuru;
    }
  }

  @override
  Future<void> duyuruSil(String kurumId, String duyuruId) async =>
      _duyurular.removeWhere((d) => d.id == duyuruId);

  final Map<String, Map<String, DateTime>> _duyuruOkumalari = {};

  @override
  Future<Map<String, DateTime>> duyuruOkumalariniGetir(
          String kurumId, String uid) async =>
      Map.of(_duyuruOkumalari[uid] ?? const {});

  @override
  Future<void> duyuruOkumalariniKaydet(
          String kurumId, String uid, Map<String, DateTime> okumalar) async =>
      _duyuruOkumalari[uid] = Map.of(okumalar);

  @override
  Future<Map<String, Map<String, DateTime>>> tumDuyuruOkumalari(
          String kurumId) async =>
      {for (final e in _duyuruOkumalari.entries) e.key: Map.of(e.value)};

  @override
  Future<List<Kullanici>> kullanicilariGetir(String kurumId) async => [
        Kullanici(
          uid: 'demo',
          ad: 'Demo Yönetici',
          eposta: 'demo@ornek.gov.tr',
          rol: Rol.yonetici,
          kurumId: kurumId,
        ),
      ];

  @override
  Future<void> kullaniciKaydet(String kurumId, Kullanici kullanici) async {}

  @override
  Future<void> kullaniciSil(String kurumId, String uid) async {}

  // --- BORDRO ---------------------------------------------------------------
  final Map<int, BordroAyari> _bordroAyarlari = {};
  final Map<String, List<PersonelUcreti>> _ucretler = {};
  final Map<String, BordroSonucu> _bordrolar = {};

  static String _bordroAnahtari(
          String birimId, String personelId, int yil, int ay) =>
      '$birimId|$personelId|${T.donemAnahtari(yil, ay)}';

  @override
  Future<BordroAyari> bordroAyariGetir(String kurumId, int yil) async =>
      _bordroAyarlari[yil] ?? BordroAyari(yil: yil);

  @override
  Future<void> bordroAyariKaydet(String kurumId, BordroAyari ayar) async =>
      _bordroAyarlari[ayar.yil] = ayar;

  @override
  Future<List<PersonelUcreti>> personelUcretleriGetir(String birimId) async =>
      List.of(_ucretler[birimId] ?? const []);

  @override
  Future<void> personelUcretiKaydet(
      String birimId, PersonelUcreti ucret) async {
    final liste = _ucretler.putIfAbsent(birimId, () => []);
    final i = liste.indexWhere((u) => u.personelId == ucret.personelId);
    if (i == -1) {
      liste.add(ucret);
    } else {
      liste[i] = ucret;
    }
  }

  @override
  Future<void> personelUcretiSil(String birimId, String personelId) async =>
      _ucretler[birimId]?.removeWhere((u) => u.personelId == personelId);

  @override
  Future<BordroSonucu?> bordroGetir(
          String birimId, String personelId, int yil, int ay) async =>
      _bordrolar[_bordroAnahtari(birimId, personelId, yil, ay)];

  @override
  Future<void> bordroKaydet(String birimId, BordroSonucu sonuc) async =>
      _bordrolar[_bordroAnahtari(
          birimId, sonuc.personelId, sonuc.yil, sonuc.ay)] = sonuc;

  @override
  Future<void> bordroSil(
          String birimId, String personelId, int yil, int ay) async =>
      _bordrolar.remove(_bordroAnahtari(birimId, personelId, yil, ay));

  @override
  Future<List<BordroSonucu>> bordrolariGetir(String birimId,
          {int? yil, int? ay}) async =>
      _bordrolar.entries
          .where((e) => e.key.startsWith('$birimId|'))
          .map((e) => e.value)
          .where((b) => (yil == null || b.yil == yil) &&
              (ay == null || b.ay == ay))
          .toList()
        ..sort(_bordroSirala);

  final Map<String, YuklenmisBordro> _yuklenmisBordrolar = {};

  @override
  Future<void> bordroYukle(String birimId, YuklenmisBordro kayit) async =>
      _yuklenmisBordrolar['$birimId|${kayit.personelId}|${kayit.yil}-${kayit.ay}'] =
          kayit;

  @override
  Future<YuklenmisBordro?> bordroYuklemesiniGetir(
          String birimId, String personelId, int yil, int ay,
          {bool pdfDahil = true}) async =>
      _yuklenmisBordrolar['$birimId|$personelId|$yil-$ay'];

  @override
  Future<List<YuklenmisBordro>> birimBordroYuklemeleriniGetir(
          String birimId, {int? yil, int? ay}) async =>
      _yuklenmisBordrolar.entries
          .where((e) => e.key.startsWith('$birimId|'))
          .map((e) => e.value.metaKopya())
          .where((b) => (yil == null || b.yil == yil) &&
              (ay == null || b.ay == ay))
          .toList()
        ..sort((a, b) {
          final yf = b.yil.compareTo(a.yil);
          if (yf != 0) return yf;
          final af = b.ay.compareTo(a.ay);
          if (af != 0) return af;
          return a.personelAd.compareTo(b.personelAd);
        });

  @override
  Future<void> bordroYuklemeSil(
          String birimId, String personelId, int yil, int ay) async =>
      _yuklenmisBordrolar.remove('$birimId|$personelId|$yil-$ay');
}

/// Yeni dönem önce, aynı dönemde isme göre — geçmiş listesi için ortak sıra.
int _bordroSirala(BordroSonucu a, BordroSonucu b) {
  final yilFarki = b.yil.compareTo(a.yil);
  if (yilFarki != 0) return yilFarki;
  final ayFarki = b.ay.compareTo(a.ay);
  if (ayFarki != 0) return ayFarki;
  return a.personelAd.compareTo(b.personelAd);
}

/// Depodaki okuma kaydını (`{duyuruId: ISO zaman}`) çözer.
Map<String, DateTime> duyuruOkumaCoz(Object? ham) {
  final sonuc = <String, DateTime>{};
  if (ham is Map) {
    for (final e in ham.entries) {
      final zaman = DateTime.tryParse('${e.value}');
      if (zaman != null) sonuc['${e.key}'] = zaman;
    }
  }
  return sonuc;
}

Map<String, String> duyuruOkumaYaz(Map<String, DateTime> okumalar) =>
    {for (final e in okumalar.entries) e.key: e.value.toIso8601String()};
