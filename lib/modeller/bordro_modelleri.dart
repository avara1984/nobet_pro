/// Bordro (maaş) alt sisteminin veri modelleri.
///
/// `modeller.dart` nöbet tarafının modellerini tutar; bordro ayrı bir alt
/// sistem olduğu için kendi dosyasında durur. Kural aynı: her modelde
/// [haritadan] factory'si + `haritasi` getter'ı bulunur ve yeni bir alan
/// eklerken ikisi birden güncellenir.
library;

// -----------------------------------------------------------------------------
// VERGİ DİLİMİ
// -----------------------------------------------------------------------------
/// Yıllık kümülatif matraha uygulanan tek bir gelir vergisi dilimi.
class VergiDilimi {
  const VergiDilimi({required this.ustSinir, required this.oran});

  /// Bu dilimin bittiği kümülatif matrah tutarı (₺).
  final double ustSinir;

  /// Dilime uygulanan oran (0.15 = %15).
  final double oran;

  factory VergiDilimi.haritadan(Map<String, dynamic> m) => VergiDilimi(
        ustSinir: ((m['ustSinir'] ?? 0) as num).toDouble(),
        oran: ((m['oran'] ?? 0) as num).toDouble(),
      );

  Map<String, dynamic> get haritasi => {
        'ustSinir': ustSinir,
        'oran': oran,
      };
}

// -----------------------------------------------------------------------------
// BORDRO AYARI (yıllık sabitler)
// -----------------------------------------------------------------------------
/// Her yıl güncellenen sabit tutar, oran ve katsayılar.
/// Ayarlar birimden bağımsızdır — Güvenlik ve Temizlik aynı değerleri kullanır.
class BordroAyari {
  BordroAyari({
    required this.yil,
    this.gelirVergisiIstisnasi = 5615.10,
    this.sosyalYardim = 5404.00,
    this.hizmetPrimiOrani = 0.16,
    this.yolYardimiGunluk = 212.10,
    this.sgkCalisan = 0.14,
    this.sgkIssizlik = 0.01,
    this.damgaVergisiOrani = 0.00759,
    this.damgaVergisiIstisnasi = 33030.30,
    this.geceKatsayisi = 0.35,
    this.tatilKatsayisi = 2.0,
    List<VergiDilimi>? vergiDilimleri,
  }) : vergiDilimleri = vergiDilimleri ?? List.of(kVarsayilanVergiDilimleri);

  final int yil;

  /// Gelir vergisi istisnası — asgari ücrete isabet eden kısım (Md. istisna).
  double gelirVergisiIstisnasi;

  /// Sosyal yardım (Md.38) — aylık sabit tutar.
  double sosyalYardim;

  /// Hizmet primi oranı (Md.36) — genelde %16.
  double hizmetPrimiOrani;

  /// Yol yardımı (Md.40) — günlük tutar. Personele özel tutar tanımlıysa
  /// [PersonelUcreti.yolYardimiGunluk] bunun yerine geçer.
  double yolYardimiGunluk;

  /// SGK çalışan payı — genelde %14.
  double sgkCalisan;

  /// SGK işsizlik çalışan payı — genelde %1.
  double sgkIssizlik;

  /// Damga vergisi oranı — genelde %0,759.
  double damgaVergisiOrani;

  /// Damga vergisi istisnası — brüt asgari ücret tutarı.
  double damgaVergisiIstisnasi;

  /// Gece çalışma katsayısı (Md.23) — genelde 0,35.
  double geceKatsayisi;

  /// Resmi tatil çalışma katsayısı (Md.22) — genelde 2,0.
  double tatilKatsayisi;

  /// Kümülatif gelir vergisi dilimleri (artan sırada).
  List<VergiDilimi> vergiDilimleri;

  factory BordroAyari.haritadan(int yil, Map<String, dynamic> m) {
    final dilimler = ((m['vergiDilimleri'] ?? const []) as List)
        .map((e) => VergiDilimi.haritadan(Map<String, dynamic>.from(e as Map)))
        .toList();

    // İki tür bozukluk yakalanır:
    // 1) Para.coz bug'ı: "83.774" → 83.774 (ondalık) gibi küçük değerler.
    // 2) Eski/yanlış tablo: %15 dilimi 190.000 ₺'nin altında bitiyorsa
    //    (örn. önceki yıla ait 83.774 veya 110.000 gibi değerler).
    // Her iki durumda da varsayılan 2026 dilimleri kullanılır.
    final bozuk = dilimler.isNotEmpty &&
        dilimler.any((d) => d.oran == 0.15 && d.ustSinir < 150000);

    return BordroAyari(
      yil: yil,
      gelirVergisiIstisnasi:
          ((m['gelirVergisiIstisnasi'] ?? 5615.10) as num).toDouble(),
      sosyalYardim: ((m['sosyalYardim'] ?? 5404.00) as num).toDouble(),
      hizmetPrimiOrani: ((m['hizmetPrimiOrani'] ?? 0.16) as num).toDouble(),
      yolYardimiGunluk: ((m['yolYardimiGunluk'] ?? 212.10) as num).toDouble(),
      sgkCalisan: ((m['sgkCalisan'] ?? 0.14) as num).toDouble(),
      sgkIssizlik: ((m['sgkIssizlik'] ?? 0.01) as num).toDouble(),
      damgaVergisiOrani:
          ((m['damgaVergisiOrani'] ?? 0.00759) as num).toDouble(),
      damgaVergisiIstisnasi:
          ((m['damgaVergisiIstisnasi'] ?? 33030.30) as num).toDouble(),
      geceKatsayisi: ((m['geceKatsayisi'] ?? 0.35) as num).toDouble(),
      tatilKatsayisi: ((m['tatilKatsayisi'] ?? 2.0) as num).toDouble(),
      vergiDilimleri: (dilimler.isEmpty || bozuk) ? null : dilimler,
    );
  }

  Map<String, dynamic> get haritasi => {
        'yil': yil,
        'gelirVergisiIstisnasi': gelirVergisiIstisnasi,
        'sosyalYardim': sosyalYardim,
        'hizmetPrimiOrani': hizmetPrimiOrani,
        'yolYardimiGunluk': yolYardimiGunluk,
        'sgkCalisan': sgkCalisan,
        'sgkIssizlik': sgkIssizlik,
        'damgaVergisiOrani': damgaVergisiOrani,
        'damgaVergisiIstisnasi': damgaVergisiIstisnasi,
        'geceKatsayisi': geceKatsayisi,
        'tatilKatsayisi': tatilKatsayisi,
        'vergiDilimleri': vergiDilimleri.map((d) => d.haritasi).toList(),
      };
}

/// 2026 ücret geliri tarifesi (GVK Md.103, ücret gelirleri sütunu).
const List<VergiDilimi> kVarsayilanVergiDilimleri = [
  VergiDilimi(ustSinir: 190000, oran: 0.15),
  VergiDilimi(ustSinir: 400000, oran: 0.20),
  VergiDilimi(ustSinir: 1500000, oran: 0.27),
  VergiDilimi(ustSinir: 5300000, oran: 0.35),
  VergiDilimi(ustSinir: 999999999, oran: 0.40),
];

// -----------------------------------------------------------------------------
// PERSONEL ÜCRETİ
// -----------------------------------------------------------------------------
/// Bir personelin bordroya esas ücret bilgileri.
///
/// Ad/soyad ve T.C. no burada tekrarlanmaz — kayıt `Personel.id` ile nöbet
/// tarafındaki personel kaydına bağlıdır, isim oradan okunur. Böylece eski
/// sistemdeki "isim birebir tutmuyor, veri eşleşmedi" sorunu oluşmaz.
class PersonelUcreti {
  PersonelUcreti({
    required this.personelId,
    this.gunlukUcret = 0,
    this.hizmetZammi = 0,
    this.yolYardimiGunluk = 0,
    this.yolYardimiAylik = 0,
    this.sendikaUyesi = true,
  });

  final String personelId;

  /// Günlük ücret (Md.33).
  double gunlukUcret;

  /// Hizmet zammı (Md.58) — kişiye özel aylık sabit.
  double hizmetZammi;

  /// Kişiye özel günlük yol yardımı. 0 ise [BordroAyari.yolYardimiGunluk].
  /// [yolYardimiAylik] > 0 ise bu alan kullanılmaz.
  double yolYardimiGunluk;

  /// Sabit aylık yol yardımı (Md.40 Günlük). 0'dan büyükse günlük×gün
  /// hesabı yerine bu tutar doğrudan kullanılır.
  double yolYardimiAylik;

  /// Sendika üyesi ise aylık bir günlük ücret kesilir.
  bool sendikaUyesi;

  factory PersonelUcreti.haritadan(String personelId, Map<String, dynamic> m) =>
      PersonelUcreti(
        personelId: personelId,
        gunlukUcret: ((m['gunlukUcret'] ?? 0) as num).toDouble(),
        hizmetZammi: ((m['hizmetZammi'] ?? 0) as num).toDouble(),
        yolYardimiGunluk: ((m['yolYardimiGunluk'] ?? 0) as num).toDouble(),
        yolYardimiAylik: ((m['yolYardimiAylik'] ?? 0) as num).toDouble(),
        sendikaUyesi: (m['sendikaUyesi'] ?? true) as bool,
      );

  Map<String, dynamic> get haritasi => {
        'personelId': personelId,
        'gunlukUcret': gunlukUcret,
        'hizmetZammi': hizmetZammi,
        'yolYardimiGunluk': yolYardimiGunluk,
        'yolYardimiAylik': yolYardimiAylik,
        'sendikaUyesi': sendikaUyesi,
      };
}

// -----------------------------------------------------------------------------
// BORDRO SONUCU
// -----------------------------------------------------------------------------
/// Hesaplanmış tek aylık bordro. Kaydedildiğinde diske bu hâliyle yazılır,
/// böylece sonradan ayar değişse bile geçmiş bordrolar aynı kalır.
class BordroSonucu {
  BordroSonucu({
    required this.personelId,
    required this.personelAd,
    required this.yil,
    required this.ay,
    required this.calismaGunu,
    required this.sgkGunu,
    required this.geceSaati,
    required this.tatilGunu,
    required this.yolGunu,
    required this.gunlukUcretToplami,
    required this.sosyalYardim,
    required this.hizmetPrimi,
    required this.hizmetZammi,
    required this.yolYardimi,
    required this.geceCalismaUcreti,
    required this.tatilCalismaUcreti,
    required this.brutGelir,
    required this.sgkMatrahi,
    required this.sgkCalisanKesintisi,
    required this.sgkIssizlikKesintisi,
    required this.aylikVergiMatrahi,
    required this.oncekiYillikMatrah,
    required this.yillikMatrah,
    required this.gelirVergisi,
    required this.gelirVergisiIstisnasi,
    required this.netGelirVergisi,
    required this.damgaVergisi,
    required this.sendikaKesintisi,
    required this.toplamKesinti,
    required this.odenecekTutar,
    this.gecisAyi = false,
    this.ucretFarki = 0,
    this.hizmetPrimiFarki = 0,
    this.sosyalYardimFarki = 0,
    this.yolYardimiFarki = 0,
    this.hizmetZammiFarki = 0,
    this.sendikaFarki = 0,
    this.hesaplama,
  });

  // --- kimlik / dönem ---
  final String personelId;

  /// Hesaplama anındaki ad — personel sonradan silinse de geçmiş okunabilsin.
  final String personelAd;
  final int yil;
  final int ay;

  // --- girdiler ---
  final int calismaGunu;
  final int sgkGunu;
  final double geceSaati;
  final int tatilGunu;
  final int yolGunu;

  // --- gelir kalemleri ---
  final double gunlukUcretToplami; // Md.33
  final double sosyalYardim; // Md.38
  final double hizmetPrimi; // Md.36
  final double hizmetZammi; // Md.58
  final double yolYardimi; // Md.40
  final double geceCalismaUcreti; // Md.23
  final double tatilCalismaUcreti; // Md.22
  final double brutGelir;

  // --- kesintiler ---
  final double sgkMatrahi;
  final double sgkCalisanKesintisi;
  final double sgkIssizlikKesintisi;
  final double aylikVergiMatrahi;
  final double oncekiYillikMatrah;
  final double yillikMatrah;
  final double gelirVergisi;
  final double gelirVergisiIstisnasi;
  final double netGelirVergisi;
  final double damgaVergisi;
  final double sendikaKesintisi;
  final double toplamKesinti;
  final double odenecekTutar;

  // --- geçiş ayı farkları (bordrodan elle girilir) ---
  final bool gecisAyi;
  final double ucretFarki;

  /// Ücret farkının hizmet primi karşılığı — otomatik (%16 × ücret farkı).
  final double hizmetPrimiFarki;
  final double sosyalYardimFarki;
  final double yolYardimiFarki;
  final double hizmetZammiFarki;

  /// Sendika kesintisi farkı — kesinti tarafına eklenir.
  final double sendikaFarki;

  /// Kaydedilme zamanı.
  final DateTime? hesaplama;

  /// Geçiş ayı fark satırlarının gelir toplamı (sendika farkı kesintidir).
  double get farkToplami => gecisAyi
      ? ucretFarki +
          hizmetPrimiFarki +
          sosyalYardimFarki +
          yolYardimiFarki +
          hizmetZammiFarki
      : 0;

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory BordroSonucu.haritadan(Map<String, dynamic> m) => BordroSonucu(
        personelId: (m['personelId'] ?? '') as String,
        personelAd: (m['personelAd'] ?? '') as String,
        yil: _i(m['yil']),
        ay: _i(m['ay']),
        calismaGunu: _i(m['calismaGunu']),
        sgkGunu: _i(m['sgkGunu']),
        geceSaati: _d(m['geceSaati']),
        tatilGunu: _i(m['tatilGunu']),
        yolGunu: _i(m['yolGunu']),
        gunlukUcretToplami: _d(m['gunlukUcretToplami']),
        sosyalYardim: _d(m['sosyalYardim']),
        hizmetPrimi: _d(m['hizmetPrimi']),
        hizmetZammi: _d(m['hizmetZammi']),
        yolYardimi: _d(m['yolYardimi']),
        geceCalismaUcreti: _d(m['geceCalismaUcreti']),
        tatilCalismaUcreti: _d(m['tatilCalismaUcreti']),
        brutGelir: _d(m['brutGelir']),
        sgkMatrahi: _d(m['sgkMatrahi']),
        sgkCalisanKesintisi: _d(m['sgkCalisanKesintisi']),
        sgkIssizlikKesintisi: _d(m['sgkIssizlikKesintisi']),
        aylikVergiMatrahi: _d(m['aylikVergiMatrahi']),
        oncekiYillikMatrah: _d(m['oncekiYillikMatrah']),
        yillikMatrah: _d(m['yillikMatrah']),
        gelirVergisi: _d(m['gelirVergisi']),
        gelirVergisiIstisnasi: _d(m['gelirVergisiIstisnasi']),
        netGelirVergisi: _d(m['netGelirVergisi']),
        damgaVergisi: _d(m['damgaVergisi']),
        sendikaKesintisi: _d(m['sendikaKesintisi']),
        toplamKesinti: _d(m['toplamKesinti']),
        odenecekTutar: _d(m['odenecekTutar']),
        gecisAyi: (m['gecisAyi'] ?? false) as bool,
        ucretFarki: _d(m['ucretFarki']),
        hizmetPrimiFarki: _d(m['hizmetPrimiFarki']),
        sosyalYardimFarki: _d(m['sosyalYardimFarki']),
        yolYardimiFarki: _d(m['yolYardimiFarki']),
        hizmetZammiFarki: _d(m['hizmetZammiFarki']),
        sendikaFarki: _d(m['sendikaFarki']),
        hesaplama: m['hesaplama'] == null
            ? null
            : DateTime.tryParse(m['hesaplama'].toString()),
      );

  Map<String, dynamic> get haritasi => {
        'personelId': personelId,
        'personelAd': personelAd,
        'yil': yil,
        'ay': ay,
        'calismaGunu': calismaGunu,
        'sgkGunu': sgkGunu,
        'geceSaati': geceSaati,
        'tatilGunu': tatilGunu,
        'yolGunu': yolGunu,
        'gunlukUcretToplami': gunlukUcretToplami,
        'sosyalYardim': sosyalYardim,
        'hizmetPrimi': hizmetPrimi,
        'hizmetZammi': hizmetZammi,
        'yolYardimi': yolYardimi,
        'geceCalismaUcreti': geceCalismaUcreti,
        'tatilCalismaUcreti': tatilCalismaUcreti,
        'brutGelir': brutGelir,
        'sgkMatrahi': sgkMatrahi,
        'sgkCalisanKesintisi': sgkCalisanKesintisi,
        'sgkIssizlikKesintisi': sgkIssizlikKesintisi,
        'aylikVergiMatrahi': aylikVergiMatrahi,
        'oncekiYillikMatrah': oncekiYillikMatrah,
        'yillikMatrah': yillikMatrah,
        'gelirVergisi': gelirVergisi,
        'gelirVergisiIstisnasi': gelirVergisiIstisnasi,
        'netGelirVergisi': netGelirVergisi,
        'damgaVergisi': damgaVergisi,
        'sendikaKesintisi': sendikaKesintisi,
        'toplamKesinti': toplamKesinti,
        'odenecekTutar': odenecekTutar,
        'gecisAyi': gecisAyi,
        'ucretFarki': ucretFarki,
        'hizmetPrimiFarki': hizmetPrimiFarki,
        'sosyalYardimFarki': sosyalYardimFarki,
        'yolYardimiFarki': yolYardimiFarki,
        'hizmetZammiFarki': hizmetZammiFarki,
        'sendikaFarki': sendikaFarki,
        'hesaplama': (hesaplama ?? DateTime.now()).toIso8601String(),
      };
}

// -----------------------------------------------------------------------------
// YÜKLENEN BORDRO — admin tarafından yüklenen PDF bordro kaydı
// -----------------------------------------------------------------------------
/// Bir personele ait belirli aya ait PDF bordronun meta verisi.
/// PDF içeriği [pdfBase64] alanında base64 kodlu olarak saklanır.
class YuklenmisBordro {
  YuklenmisBordro({
    required this.personelId,
    required this.personelAd,
    required this.yil,
    required this.ay,
    required this.dosyaAdi,
    required this.yuklemeTarihi,
    this.pdfBase64 = '',
  });

  final String personelId;
  final String personelAd;
  final int yil;
  final int ay;
  final String dosyaAdi;
  final DateTime yuklemeTarihi;
  /// PDF içeriği base64 kodlu. Sadece yükleme/indirme sırasında doldurulur;
  /// liste sorgularında boş bırakılabilir (meta-veri sorgusu).
  final String pdfBase64;

  factory YuklenmisBordro.haritadan(Map<String, dynamic> m) => YuklenmisBordro(
        personelId: m['personelId'] as String? ?? '',
        personelAd: m['personelAd'] as String? ?? '',
        yil: (m['yil'] as num?)?.toInt() ?? 0,
        ay: (m['ay'] as num?)?.toInt() ?? 0,
        dosyaAdi: m['dosyaAdi'] as String? ?? '',
        yuklemeTarihi: m['yuklemeTarihi'] != null
            ? DateTime.parse(m['yuklemeTarihi'] as String)
            : DateTime.now(),
        pdfBase64: m['pdfBase64'] as String? ?? '',
      );

  Map<String, dynamic> get haritasi => {
        'personelId': personelId,
        'personelAd': personelAd,
        'yil': yil,
        'ay': ay,
        'dosyaAdi': dosyaAdi,
        'yuklemeTarihi': yuklemeTarihi.toIso8601String(),
        'pdfBase64': pdfBase64,
      };

  /// PDF içeriği olmayan meta-veri kopyası (liste sorgularında kullanılır).
  YuklenmisBordro metaKopya() => YuklenmisBordro(
        personelId: personelId,
        personelAd: personelAd,
        yil: yil,
        ay: ay,
        dosyaAdi: dosyaAdi,
        yuklemeTarihi: yuklemeTarihi,
      );
}
