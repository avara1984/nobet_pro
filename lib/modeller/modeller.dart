import '../core/tarih.dart';

// -----------------------------------------------------------------------------
// BİRİM
// -----------------------------------------------------------------------------
enum Birim { guvenlik, temizlik }

extension BirimX on Birim {
  String get etiket => switch (this) {
        Birim.guvenlik => 'Güvenlik',
        Birim.temizlik => 'Temizlik',
      };

  String get uzunEtiket => switch (this) {
        Birim.guvenlik => 'Güvenlik Personeli Nöbet Listesi',
        Birim.temizlik => 'Temizlik Personeli Nöbet Listesi',
      };

  static Birim coz(String? deger) => Birim.values.firstWhere(
        (b) => b.name == deger,
        orElse: () => Birim.guvenlik,
      );
}

// -----------------------------------------------------------------------------
// ROL
// -----------------------------------------------------------------------------
enum Rol { yonetici, editor, izleyici }

extension RolX on Rol {
  String get etiket => switch (this) {
        Rol.yonetici => 'Yönetici',
        Rol.editor => 'Liste Sorumlusu',
        Rol.izleyici => 'Personel',
      };

  bool get duzenleyebilir => this != Rol.izleyici;
  bool get yonetebilir => this == Rol.yonetici;

  static Rol coz(String? deger) => Rol.values.firstWhere(
        (r) => r.name == deger,
        orElse: () => Rol.izleyici,
      );
}

Birim? _birimCoz(String? deger) {
  if (deger == null || deger.isEmpty) return null;
  return Birim.values.firstWhere((b) => b.name == deger,
      orElse: () => Birim.guvenlik);
}

// -----------------------------------------------------------------------------
// YÖNETİCİ PROFİLİ
// -----------------------------------------------------------------------------
/// Eski uygulamanın "Admin Yönetimi" ekranındaki üç admin rolünün karşılığı.
///
/// Profil, [Kullanici] üzerindeki `rol` / `sadecePdf` / `kisitliBirim`
/// alanlarını **belirler** — bu üç alan profilden türetilir, elle ayrı ayrı
/// ayarlanmaz. Böylece "yönetici ama sadece PDF" gibi çelişkili birleşimler
/// oluşmaz. Profili olmayan (null) kullanıcılar normal kullanıcılardır ve
/// eski davranışlarını korur.
enum YoneticiProfili { superAdmin, temizlikNobet, bordro }

extension YoneticiProfiliX on YoneticiProfili {
  String get etiket => switch (this) {
        YoneticiProfili.superAdmin => 'Süper Admin',
        YoneticiProfili.temizlikNobet => 'Temizlik Nöbet Admini',
        YoneticiProfili.bordro => 'Bordro Admini',
      };

  String get aciklama => switch (this) {
        YoneticiProfili.superAdmin =>
          'Her şeye erişir: iki birim, tüm listeler, personel/kullanıcı '
              'yönetimi, ayarlar, yedekleme ve bordro.',
        YoneticiProfili.temizlikNobet =>
          'Yalnızca Temizlik biriminin nöbet listesini hazırlar. Bordro ve '
              'yönetim ekranlarına giremez.',
        YoneticiProfili.bordro =>
          'Nöbet listelerini yalnızca görüntüler (Onaylanan Liste, salt '
              'okunur); bordro işlemlerinin tamamını yapar.',
      };

  /// Profilin ima ettiği temel rol.
  Rol get rol => switch (this) {
        YoneticiProfili.superAdmin => Rol.yonetici,
        YoneticiProfili.temizlikNobet => Rol.editor,
        YoneticiProfili.bordro => Rol.editor,
      };

  /// Nöbet tarafı salt okunur mu (girişte Onaylanan Liste açılır).
  bool get sadecePdf => this == YoneticiProfili.bordro;

  /// Yalnızca bu birime girebilir; null ise kısıt yok.
  Birim? get kisitliBirim =>
      this == YoneticiProfili.temizlikNobet ? Birim.temizlik : null;

  /// Bordro İşlemleri bölümüne erişebilir mi?
  bool get bordroYetkisi =>
      this == YoneticiProfili.superAdmin || this == YoneticiProfili.bordro;

  static YoneticiProfili? coz(String? deger) {
    if (deger == null || deger.isEmpty) return null;
    for (final p in YoneticiProfili.values) {
      if (p.name == deger) return p;
    }
    return null;
  }
}

// -----------------------------------------------------------------------------
// KULLANICI
// -----------------------------------------------------------------------------
class Kullanici {
  /// Yönetici profili verildiğinde `rol`, `sadecePdf` ve `kisitliBirim`
  /// profilden türetilir; ayrıca verilmelerine gerek yoktur.
  factory Kullanici.yonetici({
    required String uid,
    required String ad,
    required String kurumId,
    required YoneticiProfili profil,
    String eposta = '',
    bool aktif = true,
    String pin = '',
    String kimlik = '',
    String kullaniciAdi = '',
    String sifreHash = '',
    bool onayli = true,
  }) =>
      Kullanici(
        uid: uid,
        ad: ad,
        eposta: eposta,
        rol: profil.rol,
        kurumId: kurumId,
        aktif: aktif,
        pin: pin,
        sadecePdf: profil.sadecePdf,
        kisitliBirim: profil.kisitliBirim,
        yoneticiProfili: profil,
        kimlik: kimlik,
        kullaniciAdi: kullaniciAdi,
        sifreHash: sifreHash,
        onayli: onayli,
      );

  Kullanici({
    required this.uid,
    required this.ad,
    required this.eposta,
    required this.rol,
    required this.kurumId,
    this.aktif = true,
    this.pin = '',
    this.sadecePdf = false,
    this.kisitliBirim,
    this.yoneticiProfili,
    this.kimlik = '',
    this.kullaniciAdi = '',
    this.sifreHash = '',
    this.onayli = true,
  });

  final String uid;
  final String ad;
  final String eposta;
  final Rol rol;
  final String kurumId;
  final bool aktif;

  /// T.C. Kimlik Numarası — giriş ekranında kimlik olarak kullanılır.
  /// Boşsa bu kullanıcı TC ile giriş yapamaz (eski/PIN'li kayıtlar).
  final String kimlik;

  /// İsteğe bağlı kullanıcı adı (nick name) — T.C. Kimlik No yerine bununla
  /// da giriş yapılabilir. Boşsa yalnızca [kimlik] ile giriş yapılır.
  final String kullaniciAdi;

  /// Giriş şifresinin SHA-256 özeti (düz metin saklanmaz). Boşsa şifre yok.
  final String sifreHash;

  /// Yönetici onayından geçti mi? Üye ol ile kendi kaydolan personel için
  /// başta false olur; yönetici onaylayınca true. Yöneticiler ve eski
  /// kayıtlar için varsayılan true.
  final bool onayli;

  /// Atanmışsa kullanıcı bir yöneticidir ve yetkileri profilden gelir.
  /// null ise normal kullanıcıdır ([rol] geçerlidir).
  final YoneticiProfili? yoneticiProfili;

  /// İsteğe bağlı 4 haneli giriş kodu. Boşsa kod sorulmaz.
  final String pin;

  /// Eski sistemdeki "bordro" rolünün karşılığı: girişte otomatik
  /// "Onaylanan Liste" açılır, hiçbir düzenleme aracı kullanılamaz,
  /// sadece görüntüleme + PDF indirme yapılabilir.
  final bool sadecePdf;

  /// Eski sistemdeki "nobet_temizlik" rolünün karşılığı: dolu ise
  /// kullanıcı sadece bu birime girebilir, diğer birime geçemez.
  /// null ise her iki birime de erişir.
  final Birim? kisitliBirim;

  bool get pinliMi => pin.length == 4;

  /// Bordro İşlemleri bölümüne erişebilir mi?
  ///
  /// Profil atanmışsa profil belirler. Profil yoksa (eski kayıtlar) eski
  /// davranış korunur: nöbet tarafını yönetebilen yöneticiler bordroya da
  /// erişir.
  bool get bordroYetkisi =>
      yoneticiProfili?.bordroYetkisi ?? (!sadecePdf && rol.yonetebilir);

  String get rolEtiketiUzun {
    if (yoneticiProfili != null) return yoneticiProfili!.etiket;
    if (sadecePdf) return '${rol.etiket} · Sadece PDF';
    if (kisitliBirim != null) return '${rol.etiket} · Sadece ${kisitliBirim!.etiket}';
    return rol.etiket;
  }

  String get basHarfler {
    final p = ad.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return '?';
    if (p.length == 1) return p.first.substring(0, 1);
    return '${p.first.substring(0, 1)}${p.last.substring(0, 1)}';
  }

  /// [yoneticiProfili] verilirse rol/sadecePdf/kisitliBirim ondan türetilir.
  /// [profilSil] true ise kullanıcı normal kullanıcıya çevrilir.
  Kullanici kopyala({
    String? ad,
    Rol? rol,
    String? pin,
    bool? aktif,
    bool? sadecePdf,
    Birim? kisitliBirim,
    bool kisitliBirimSil = false,
    YoneticiProfili? yoneticiProfili,
    bool profilSil = false,
    String? kimlik,
    String? kullaniciAdi,
    String? sifreHash,
    bool? onayli,
  }) {
    final profil =
        profilSil ? null : (yoneticiProfili ?? this.yoneticiProfili);
    if (profil != null) {
      return Kullanici(
        uid: uid,
        ad: ad ?? this.ad,
        eposta: eposta,
        rol: profil.rol,
        kurumId: kurumId,
        aktif: aktif ?? this.aktif,
        pin: pin ?? this.pin,
        sadecePdf: profil.sadecePdf,
        kisitliBirim: profil.kisitliBirim,
        yoneticiProfili: profil,
        kimlik: kimlik ?? this.kimlik,
        kullaniciAdi: kullaniciAdi ?? this.kullaniciAdi,
        sifreHash: sifreHash ?? this.sifreHash,
        onayli: onayli ?? this.onayli,
      );
    }
    return Kullanici(
      uid: uid,
      ad: ad ?? this.ad,
      eposta: eposta,
      rol: rol ?? this.rol,
      kurumId: kurumId,
      aktif: aktif ?? this.aktif,
      pin: pin ?? this.pin,
      sadecePdf: sadecePdf ?? this.sadecePdf,
      kisitliBirim:
          kisitliBirimSil ? null : (kisitliBirim ?? this.kisitliBirim),
      yoneticiProfili: null,
      kimlik: kimlik ?? this.kimlik,
      kullaniciAdi: kullaniciAdi ?? this.kullaniciAdi,
      sifreHash: sifreHash ?? this.sifreHash,
      onayli: onayli ?? this.onayli,
    );
  }

  factory Kullanici.haritadan(String uid, Map<String, dynamic> m) {
    final profil = YoneticiProfiliX.coz(m['yoneticiProfili'] as String?);
    return Kullanici(
      uid: uid,
      ad: (m['ad'] ?? '') as String,
      eposta: (m['eposta'] ?? '') as String,
      // Profil varsa rol/bayraklar ondan türetilir — diskteki değerler
      // profille çelişse bile profil kazanır.
      rol: profil?.rol ?? RolX.coz(m['rol'] as String?),
      kurumId: (m['kurumId'] ?? 'varsayilan') as String,
      aktif: (m['aktif'] ?? true) as bool,
      pin: (m['pin'] ?? '') as String,
      sadecePdf: profil?.sadecePdf ?? (m['sadecePdf'] ?? false) as bool,
      kisitliBirim:
          profil != null ? profil.kisitliBirim : _birimCoz(m['kisitliBirim'] as String?),
      yoneticiProfili: profil,
      kimlik: (m['kimlik'] ?? '') as String,
      kullaniciAdi: (m['kullaniciAdi'] ?? '') as String,
      sifreHash: (m['sifreHash'] ?? '') as String,
      // Alan yoksa eski kayıt: onaylı kabul edilir (girişi engellenmesin).
      onayli: (m['onayli'] ?? true) as bool,
    );
  }

  Map<String, dynamic> get haritasi => {
        'ad': ad,
        'eposta': eposta,
        'rol': rol.name,
        'kurumId': kurumId,
        'aktif': aktif,
        'pin': pin,
        'sadecePdf': sadecePdf,
        'kisitliBirim': kisitliBirim?.name ?? '',
        'yoneticiProfili': yoneticiProfili?.name ?? '',
        'kimlik': kimlik,
        'kullaniciAdi': kullaniciAdi,
        'sifreHash': sifreHash,
        'onayli': onayli,
      };
}

// -----------------------------------------------------------------------------
// PERSONEL
// -----------------------------------------------------------------------------
/// nobetci  → 8 günlük döngüye girer
/// mesai    → döngüye girmez (dahiliye). Hafta sonu H.T., resmi tatil R.T.,
///            diğer günler 08:00 - 17:30
enum GorevTipi { nobetci, mesai }

class Personel {
  Personel({
    required this.id,
    required this.ad,
    this.sicil = '',
    this.tcNo = '',
    this.gorev = GorevTipi.nobetci,
    this.aktif = true,
    this.sira = 0,
    this.yillikIzinKotasi = 30,
    this.dongBaslangici = 0,
    this.gorevBaslangic,
    this.gorevBitis,
  });

  final String id;
  String ad;
  String sicil;

  /// Göreve başlama / ayrılma tarihi (isteğe bağlı). Boşsa kişi her ayın
  /// listesinde görünür; dolu ise yalnızca görevde olduğu aylarda — böylece
  /// sonradan gelen biri eski ayların, ayrılan biri sonraki ayların
  /// listesine karışmaz. Tarih bileşeni (saat yok).
  DateTime? gorevBaslangic;
  DateTime? gorevBitis;

  /// Kişi, verilen ayın herhangi bir gününde görevde mi?
  bool ayAktifMi(int yil, int ay) {
    final ayBasi = DateTime(yil, ay, 1);
    final aySonu = DateTime(yil, ay + 1, 0);
    final bas = gorevBaslangic;
    final bit = gorevBitis;
    if (bas != null && bas.isAfter(aySonu)) return false;
    if (bit != null && bit.isBefore(ayBasi)) return false;
    return true;
  }

  /// T.C. Kimlik Numarası (11 hane). Boş bırakılabilir.
  String tcNo;

  GorevTipi gorev;
  bool aktif;
  int sira;

  /// Yıllık izin hakkı (gün). Kıdeme göre 20 veya 30 olur.
  int yillikIzinKotasi;

  /// Ayın 1'inde döngünün kaçıncı basamağında olduğu (0..dongUzunlugu-1).
  /// 8 günlük döngüde: 0-1 gündüz, 2-3 izin, 4-5 gece, 6-7 izin.
  int dongBaslangici;

  bool get mesaiMi => gorev == GorevTipi.mesai;

  String get basHarfler {
    final p = ad.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return '?';
    if (p.length == 1) return p.first.substring(0, 1);
    return '${p.first.substring(0, 1)}${p.last.substring(0, 1)}';
  }

  /// Gizlenmiş TC: 12345678901 → 123*****901
  String get tcMaskeli =>
      tcNo.length == 11 ? '${tcNo.substring(0, 3)}*****${tcNo.substring(8)}' : '';

  /// 11 hane, hepsi rakam, ilk hane 0 değil.
  static bool tcGecerliMi(String deger) {
    if (deger.length != 11) return false;
    if (!RegExp(r'^[0-9]+$').hasMatch(deger)) return false;
    if (deger[0] == '0') return false;
    return true;
  }

  factory Personel.haritadan(String id, Map<String, dynamic> m) => Personel(
        id: id,
        ad: (m['ad'] ?? '') as String,
        sicil: (m['sicil'] ?? '') as String,
        tcNo: (m['tcNo'] ?? '') as String,
        gorev: (m['gorev'] == 'mesai') ? GorevTipi.mesai : GorevTipi.nobetci,
        aktif: (m['aktif'] ?? true) as bool,
        sira: (m['sira'] ?? 0) as int,
        yillikIzinKotasi: (m['yillikIzinKotasi'] ?? 30) as int,
        dongBaslangici: (m['dongBaslangici'] ?? 0) as int,
        gorevBaslangic: _tarihCoz(m['gorevBaslangic'] as String?),
        gorevBitis: _tarihCoz(m['gorevBitis'] as String?),
      );

  static DateTime? _tarihCoz(String? metin) {
    if (metin == null || metin.isEmpty) return null;
    final t = DateTime.tryParse(metin);
    return t == null ? null : DateTime(t.year, t.month, t.day);
  }

  static String? _tarihYaz(DateTime? t) => t == null
      ? null
      : '${t.year}-${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> get haritasi => {
        'ad': ad,
        'sicil': sicil,
        'tcNo': tcNo,
        'gorev': gorev.name,
        'aktif': aktif,
        'sira': sira,
        'yillikIzinKotasi': yillikIzinKotasi,
        'dongBaslangici': dongBaslangici,
        if (gorevBaslangic != null) 'gorevBaslangic': _tarihYaz(gorevBaslangic),
        if (gorevBitis != null) 'gorevBitis': _tarihYaz(gorevBitis),
      };

  Personel kopya() => Personel(
      id: id,
      ad: ad,
      sicil: sicil,
      tcNo: tcNo,
      gorev: gorev,
      aktif: aktif,
      sira: sira,
      yillikIzinKotasi: yillikIzinKotasi,
      dongBaslangici: dongBaslangici,
      gorevBaslangic: gorevBaslangic,
      gorevBitis: gorevBitis);
}

// -----------------------------------------------------------------------------
// VARDİYA TANIMI
// -----------------------------------------------------------------------------
/// [toplamSaat] ve [geceSaati] bordro değerleridir; vardiya süresinden
/// bağımsız olarak elle tanımlanır (mola düşülmüş haldedir).
/// Örnek: 08:00 - 20:00 aralığı 12 saat sürer ama 11.0 saat sayılır.
class VardiyaTanimi {
  const VardiyaTanimi({
    required this.kod,
    required this.etiket,
    this.kisa = '',
    this.baslangicDk = 0,
    this.bitisDk = 0,
    this.calisiyor = true,
    this.renk = 0xFF1D4ED8,
    this.izinSayilir = false,
    this.toplamSaat = 0,
    this.geceSaati = 0,
    this.yarimGunSaati = -1,
  });

  /// Depolama anahtarı. Mevcut uygulamayla birebir aynı metinler kullanılır.
  final String kod;

  /// Tabloda görünen metin
  final String etiket;

  /// Özet tablosunda görünen kısa metin
  final String kisa;

  final int baslangicDk;
  final int bitisDk;
  final bool calisiyor;
  final int renk;
  final bool izinSayilir;

  /// Bordroya yazılan toplam saat
  final double toplamSaat;

  /// Bunun kaçı gece saati
  final double geceSaati;

  /// Arife (yarım gün) durumunda geçerli saat. -1 ise toplamSaat kullanılır.
  final double yarimGunSaati;

  /// Takvimsel süre (kapsama denetimi için)
  int get sureDk {
    if (baslangicDk == 0 && bitisDk == 0) return 0;
    final bit = bitisDk <= baslangicDk ? bitisDk + 1440 : bitisDk;
    return bit - baslangicDk;
  }

  /// Bordro saati. Elle tanımlanmadıysa takvimsel süreden hesaplanır.
  double get saat => toplamSaat > 0 ? toplamSaat : sureDk / 60.0;

  bool get erteseGuneSarkar =>
      sureDk > 0 && bitisDk <= baslangicDk && baslangicDk > 0;

  /// Gece vardiyası mı (bordroda gece saati var mı)
  bool get geceVardiyasi => geceSaati > 0;

  String get gorunenKisa => kisa.isEmpty ? kod : kisa;

  factory VardiyaTanimi.haritadan(Map<String, dynamic> m) => VardiyaTanimi(
        kod: (m['kod'] ?? '') as String,
        etiket: (m['etiket'] ?? '') as String,
        kisa: (m['kisa'] ?? '') as String,
        baslangicDk: (m['baslangicDk'] ?? 0) as int,
        bitisDk: (m['bitisDk'] ?? 0) as int,
        calisiyor: (m['calisiyor'] ?? true) as bool,
        renk: (m['renk'] ?? 0xFF1D4ED8) as int,
        izinSayilir: (m['izinSayilir'] ?? false) as bool,
        toplamSaat: ((m['toplamSaat'] ?? 0) as num).toDouble(),
        geceSaati: ((m['geceSaati'] ?? 0) as num).toDouble(),
        yarimGunSaati: ((m['yarimGunSaati'] ?? -1) as num).toDouble(),
      );

  Map<String, dynamic> get haritasi => {
        'kod': kod,
        'etiket': etiket,
        'kisa': kisa,
        'baslangicDk': baslangicDk,
        'bitisDk': bitisDk,
        'calisiyor': calisiyor,
        'renk': renk,
        'izinSayilir': izinSayilir,
        'toplamSaat': toplamSaat,
        'geceSaati': geceSaati,
        'yarimGunSaati': yarimGunSaati,
      };

  VardiyaTanimi kopyala({
    String? kod,
    String? etiket,
    String? kisa,
    int? baslangicDk,
    int? bitisDk,
    bool? calisiyor,
    int? renk,
    bool? izinSayilir,
    double? toplamSaat,
    double? geceSaati,
    double? yarimGunSaati,
  }) =>
      VardiyaTanimi(
        kod: kod ?? this.kod,
        etiket: etiket ?? this.etiket,
        kisa: kisa ?? this.kisa,
        baslangicDk: baslangicDk ?? this.baslangicDk,
        bitisDk: bitisDk ?? this.bitisDk,
        calisiyor: calisiyor ?? this.calisiyor,
        renk: renk ?? this.renk,
        izinSayilir: izinSayilir ?? this.izinSayilir,
        toplamSaat: toplamSaat ?? this.toplamSaat,
        geceSaati: geceSaati ?? this.geceSaati,
        yarimGunSaati: yarimGunSaati ?? this.yarimGunSaati,
      );
}

const VardiyaTanimi kBosVardiya =
    VardiyaTanimi(kod: '', etiket: '—', calisiyor: false, renk: 0xFF9CA3AF);

// Kodlar mevcut uygulamadaki metinlerle birebir aynıdır.
const String kGunduz12 = '08:00 - 20:00';
const String kGece12 = '20:00 - 08:00';
const String kSabah8 = '08:00 - 16:00';
const String kAksam8 = '16:00 - 24:00';
const String kGece8 = '24:00 - 08:00';
const String kMesai = '08:00 - 17:30';
const String kNobetIzni = 'N.İ.';
const String kYillikIzin = 'Y.İ.';
const String kHaftaTatili = 'H.T.';
const String kResmiTatil = 'R.T.';
const String kIdariIzin = 'İ.İ.';

const List<VardiyaTanimi> kVarsayilanVardiyalar = [
  VardiyaTanimi(
      kod: kGunduz12,
      etiket: kGunduz12,
      kisa: '08-20',
      baslangicDk: 480,
      bitisDk: 1200,
      toplamSaat: 11.0,
      renk: 0xFFB45309),
  VardiyaTanimi(
      kod: kGece12,
      etiket: kGece12,
      kisa: '20-08',
      baslangicDk: 1200,
      bitisDk: 480,
      toplamSaat: 11.0,
      geceSaati: 11.0,
      renk: 0xFF3730A3),
  VardiyaTanimi(
      kod: kSabah8,
      etiket: kSabah8,
      kisa: '08-16',
      baslangicDk: 480,
      bitisDk: 960,
      toplamSaat: 7.5,
      renk: 0xFFC2410C),
  VardiyaTanimi(
      kod: kAksam8,
      etiket: kAksam8,
      kisa: '16-24',
      baslangicDk: 960,
      bitisDk: 1440,
      toplamSaat: 7.5,
      geceSaati: 3.5,
      renk: 0xFF4338CA),
  VardiyaTanimi(
      kod: kGece8,
      etiket: kGece8,
      kisa: '24-08',
      baslangicDk: 0,
      bitisDk: 480,
      toplamSaat: 7.5,
      geceSaati: 7.5,
      renk: 0xFF312E81),
  VardiyaTanimi(
      kod: kMesai,
      etiket: kMesai,
      kisa: 'Mesai',
      baslangicDk: 480,
      bitisDk: 1050,
      toplamSaat: 9.0,
      renk: 0xFF1D4ED8),
  VardiyaTanimi(
      kod: kNobetIzni,
      etiket: kNobetIzni,
      kisa: 'N.İ.',
      calisiyor: false,
      izinSayilir: true,
      renk: 0xFF9CA3AF),
  VardiyaTanimi(
      kod: kYillikIzin,
      etiket: kYillikIzin,
      kisa: 'Y.İ.',
      calisiyor: false,
      izinSayilir: true,
      toplamSaat: 7.5,
      renk: 0xFFBE185D),
  VardiyaTanimi(
      kod: kHaftaTatili,
      etiket: kHaftaTatili,
      kisa: 'H.T.',
      calisiyor: false,
      izinSayilir: true,
      renk: 0xFF9CA3AF),
  VardiyaTanimi(
      kod: kResmiTatil,
      etiket: kResmiTatil,
      kisa: 'R.T.',
      calisiyor: false,
      izinSayilir: true,
      renk: 0xFF15803D),
  VardiyaTanimi(
      kod: kIdariIzin,
      etiket: kIdariIzin,
      kisa: 'İ.İ.',
      calisiyor: false,
      izinSayilir: true,
      toplamSaat: 9.0,
      yarimGunSaati: 3.5,
      renk: 0xFF0F766E),
];

// -----------------------------------------------------------------------------
// KAPSAMA KURALI
// -----------------------------------------------------------------------------
class KapsamaKurali {
  const KapsamaKurali({
    required this.ad,
    required this.baslangicDk,
    required this.bitisDk,
    this.minPersonel = 1,
    this.gunler = const <int>{},
    this.aktif = true,
  });

  final String ad;
  final int baslangicDk;
  final int bitisDk;
  final int minPersonel;
  final Set<int> gunler;
  final bool aktif;

  bool gunUygunMu(DateTime tarih) =>
      gunler.isEmpty || gunler.contains(tarih.weekday);

  String get araligMetni =>
      '${T.dakikaSaat(baslangicDk)} – ${T.dakikaSaat(bitisDk)}';

  factory KapsamaKurali.haritadan(Map<String, dynamic> m) => KapsamaKurali(
        ad: (m['ad'] ?? '') as String,
        baslangicDk: (m['baslangicDk'] ?? 0) as int,
        bitisDk: (m['bitisDk'] ?? 0) as int,
        minPersonel: (m['minPersonel'] ?? 1) as int,
        gunler: ((m['gunler'] ?? const []) as List).map((e) => e as int).toSet(),
        aktif: (m['aktif'] ?? true) as bool,
      );

  Map<String, dynamic> get haritasi => {
        'ad': ad,
        'baslangicDk': baslangicDk,
        'bitisDk': bitisDk,
        'minPersonel': minPersonel,
        'gunler': gunler.toList(),
        'aktif': aktif,
      };

  KapsamaKurali kopyala({
    String? ad,
    int? baslangicDk,
    int? bitisDk,
    int? minPersonel,
    Set<int>? gunler,
    bool? aktif,
  }) =>
      KapsamaKurali(
        ad: ad ?? this.ad,
        baslangicDk: baslangicDk ?? this.baslangicDk,
        bitisDk: bitisDk ?? this.bitisDk,
        minPersonel: minPersonel ?? this.minPersonel,
        gunler: gunler ?? this.gunler,
        aktif: aktif ?? this.aktif,
      );
}

const List<KapsamaKurali> kVarsayilanKurallar = [
  KapsamaKurali(ad: 'Gündüz', baslangicDk: 480, bitisDk: 1200, minPersonel: 1),
  KapsamaKurali(ad: 'Gece', baslangicDk: 1200, bitisDk: 480, minPersonel: 1),
];

// Kullanıcı henüz resmi tatil eklemediyse bu listeler varsayılan olarak
// kullanılır — referans uygulamanın Firebase'deki fallback listeleriyle aynı.
const Set<String> _kTurkVarsayilanTatiller = {
  // 2025
  '01.01.2025', '28.03.2025', '29.03.2025', '30.03.2025',
  '23.04.2025', '01.05.2025', '19.05.2025',
  '04.06.2025', '05.06.2025', '06.06.2025', '07.06.2025', '08.06.2025',
  '15.07.2025', '30.08.2025', '29.10.2025',
  // 2026
  '01.01.2026', '20.03.2026', '21.03.2026', '22.03.2026',
  '23.04.2026', '01.05.2026', '19.05.2026',
  '27.05.2026', '28.05.2026', '29.05.2026', '30.05.2026',
  '15.07.2026', '30.08.2026', '29.10.2026',
  // 2027
  '01.01.2027', '09.03.2027', '10.03.2027', '11.03.2027',
  '23.04.2027', '01.05.2027', '19.05.2027',
  '16.05.2027', '17.05.2027', '18.05.2027',
  '15.07.2027', '30.08.2027', '29.10.2027',
  // 2028
  '01.01.2028', '26.02.2028', '27.02.2028', '28.02.2028',
  '23.04.2028', '01.05.2028', '19.05.2028',
  '04.06.2028', '05.06.2028', '06.06.2028', '07.06.2028',
  '15.07.2028', '30.08.2028', '29.10.2028',
};

const Set<String> _kTurkVarsayilanArifeler = {
  '19.03.2026', '26.05.2026', '28.10.2026',
  '08.03.2027', '15.05.2027', '28.10.2027',
  '25.02.2028', '03.06.2028', '28.10.2028',
};

// -----------------------------------------------------------------------------
// KURUM AYARI
// -----------------------------------------------------------------------------
class KurumAyari {
  KurumAyari({
    this.id = 'varsayilan',
    this.ad = 'T.C. SAĞLIK BAKANLIĞI — HASTANE ADI',
    this.altBaslik = 'Nöbet listesi yönetim sistemi',
    this.gunBaslangicDk = 480,
    this.dongUzunlugu = 8,
    this.onayKodu = '',
    List<VardiyaTanimi>? vardiyalar,
    List<KapsamaKurali>? kurallar,
    Set<String>? resmiTatiller,
    Set<String>? yarimGunler,
  })  : vardiyalar = vardiyalar ?? List.of(kVarsayilanVardiyalar),
        kurallar = kurallar ?? List.of(kVarsayilanKurallar),
        resmiTatiller = resmiTatiller ?? <String>{},
        yarimGunler = yarimGunler ?? <String>{};

  final String id;
  String ad;
  String altBaslik;
  int gunBaslangicDk;

  /// Nöbet döngüsünün gün sayısı (varsayılan 8: 2 gündüz, 2 izin, 2 gece, 2 izin)
  int dongUzunlugu;

  /// Onaylı listeyi değiştirmek için istenen 4 haneli kod.
  /// Boşsa onaylı listeler de serbestçe düzenlenir.
  String onayKodu;

  List<VardiyaTanimi> vardiyalar;
  List<KapsamaKurali> kurallar;

  /// 'gg.aa.yyyy' biçiminde tam gün resmi tatiller
  Set<String> resmiTatiller;

  /// 'gg.aa.yyyy' biçiminde yarım gün (arife) tarihleri
  Set<String> yarimGunler;

  VardiyaTanimi vardiyaBul(String kod) => vardiyalar.firstWhere(
        (v) => v.kod == kod,
        orElse: () => kBosVardiya,
      );

  /// `resmiTatiller` boşsa (kullanıcı henüz elle eklememiş) Türkiye için
  /// bilinen 2025–2028 resmi tatil listesini varsayılan olarak kullanır.
  bool resmiTatilMi(DateTime t) {
    final liste = resmiTatiller.isEmpty ? _kTurkVarsayilanTatiller : resmiTatiller;
    return liste.contains(T.tarih(t));
  }

  bool yarimGunMu(DateTime t) {
    final liste = yarimGunler.isEmpty ? _kTurkVarsayilanArifeler : yarimGunler;
    return liste.contains(T.tarih(t));
  }

  factory KurumAyari.haritadan(String id, Map<String, dynamic> m) => KurumAyari(
        id: id,
        ad: (m['ad'] ?? '') as String,
        altBaslik: (m['altBaslik'] ?? '') as String,
        gunBaslangicDk: (m['gunBaslangicDk'] ?? 480) as int,
        dongUzunlugu: (m['dongUzunlugu'] ?? 8) as int,
        onayKodu: (m['onayKodu'] ?? '') as String,
        vardiyalar: ((m['vardiyalar'] ?? const []) as List)
            .map((e) =>
                VardiyaTanimi.haritadan(Map<String, dynamic>.from(e as Map)))
            .toList(),
        kurallar: ((m['kurallar'] ?? const []) as List)
            .map((e) =>
                KapsamaKurali.haritadan(Map<String, dynamic>.from(e as Map)))
            .toList(),
        resmiTatiller: ((m['resmiTatiller'] ?? const []) as List)
            .map((e) => e.toString())
            .toSet(),
        yarimGunler: ((m['yarimGunler'] ?? const []) as List)
            .map((e) => e.toString())
            .toSet(),
      );

  Map<String, dynamic> get haritasi => {
        'ad': ad,
        'altBaslik': altBaslik,
        'gunBaslangicDk': gunBaslangicDk,
        'dongUzunlugu': dongUzunlugu,
        'onayKodu': onayKodu,
        'vardiyalar': vardiyalar.map((v) => v.haritasi).toList(),
        'kurallar': kurallar.map((k) => k.haritasi).toList(),
        'resmiTatiller': resmiTatiller.toList(),
        'yarimGunler': yarimGunler.toList(),
      };
}

// -----------------------------------------------------------------------------
// LİSTE VERSİYONLARI
// -----------------------------------------------------------------------------
/// Asıl liste. Depoda boş metinle tutulur (eski kayıtlarla uyumlu kalsın diye).
const String kVersiyonNobet = '';
const String kVersiyonSablon = 'Aylık Normal Şablon';
const String kVersiyonOnayli = 'Onaylanan Liste';
const String kVersiyonTaslak = 'Taslak';

const List<String> kListeVersiyonlari = [
  kVersiyonNobet,
  kVersiyonSablon,
  kVersiyonOnayli,
  kVersiyonTaslak,
];

String versiyonAdi(String versiyon) =>
    versiyon.isEmpty ? 'Nöbet Listesi' : versiyon;

/// Rolüne göre görebileceği versiyonlar
List<String> rolVersiyonlari(Rol rol) => switch (rol) {
      Rol.yonetici => kListeVersiyonlari,
      Rol.editor => const [kVersiyonNobet, kVersiyonSablon, kVersiyonOnayli],
      Rol.izleyici => const [kVersiyonOnayli],
    };

// -----------------------------------------------------------------------------
// AY KAYDI
// -----------------------------------------------------------------------------
class AyKaydi {
  AyKaydi({
    required this.yil,
    required this.ay,
    Map<String, String>? atamalar,
    this.aylikNot = '',
    this.yayinda = false,
    this.guncelleme,
    this.guncelleyen = '',
    this.versiyon = '',
    this.onayli = false,
  }) : atamalar = atamalar ?? {};

  final int yil;
  final int ay;

  /// anahtar: '<gun>_<personelId>'  →  vardiya kodu
  final Map<String, String> atamalar;

  String aylikNot;
  bool yayinda;
  DateTime? guncelleme;
  String guncelleyen;

  /// Boş ise asıl liste. Dolu ise adlandırılmış bir alternatif liste.
  final String versiyon;

  /// Onaylanmış liste. Değiştirmek için onay kodu gerekir.
  bool onayli;

  String get versiyonAdi => versiyon.isEmpty ? 'Nöbet Listesi' : versiyon;

  /// Aynı içeriği başka bir versiyon adıyla kopyalar
  AyKaydi kopyala(String yeniVersiyon) => AyKaydi(
        yil: yil,
        ay: ay,
        atamalar: Map<String, String>.from(atamalar),
        aylikNot: aylikNot,
        yayinda: false,
        guncelleme: DateTime.now(),
        guncelleyen: guncelleyen,
        versiyon: yeniVersiyon,
        onayli: false,
      );

  static String anahtar(int gun, String personelId) => '${gun}_$personelId';

  String kod(int gun, String personelId) =>
      atamalar[anahtar(gun, personelId)] ?? '';

  void ata(int gun, String personelId, String kod) {
    if (kod.isEmpty) {
      atamalar.remove(anahtar(gun, personelId));
    } else {
      atamalar[anahtar(gun, personelId)] = kod;
    }
  }

  factory AyKaydi.haritadan(int yil, int ay, Map<String, dynamic> m) => AyKaydi(
        yil: yil,
        ay: ay,
        atamalar: Map<String, String>.from(
            (m['atamalar'] ?? const <String, String>{}) as Map),
        aylikNot: (m['aylikNot'] ?? '') as String,
        yayinda: (m['yayinda'] ?? false) as bool,
        guncelleme: m['guncelleme'] == null
            ? null
            : DateTime.tryParse(m['guncelleme'].toString()),
        guncelleyen: (m['guncelleyen'] ?? '') as String,
        versiyon: (m['versiyon'] ?? '') as String,
        onayli: (m['onayli'] ?? false) as bool,
      );

  Map<String, dynamic> get haritasi => {
        'yil': yil,
        'ay': ay,
        'atamalar': atamalar,
        'aylikNot': aylikNot,
        'yayinda': yayinda,
        'guncelleme': (guncelleme ?? DateTime.now()).toIso8601String(),
        'guncelleyen': guncelleyen,
        'versiyon': versiyon,
        'onayli': onayli,
      };
}

// -----------------------------------------------------------------------------
// PERSONEL AY ÖZETİ
// -----------------------------------------------------------------------------
class PersonelOzeti {
  PersonelOzeti({
    required this.personel,
    required this.vardiyaSayilari,
    required this.toplamSaat,
    required this.geceSaati,
    required this.normalMesai,
    required this.fazlaMesaiGunu,
    required this.yillikIzinKullanilan,
  });

  final Personel personel;

  /// vardiya kodu → adet
  final Map<String, int> vardiyaSayilari;

  final double toplamSaat;
  final double geceSaati;
  final double normalMesai;
  final double fazlaMesaiGunu;

  /// Bu ay içinde yıllık izinden düşen gün sayısı.
  /// Pazara veya resmi tatile denk gelen Y.İ. günleri sayılmaz.
  final int yillikIzinKullanilan;

  int adet(String kod) => vardiyaSayilari[kod] ?? 0;
}

// -----------------------------------------------------------------------------
// DUYURU
// -----------------------------------------------------------------------------
/// Duyurunun hangi birim(ler)e gösterileceği. null = her iki birime.
class Duyuru {
  Duyuru({
    required this.id,
    required this.baslik,
    required this.icerik,
    required this.tarih,
    this.yazar = '',
    this.hedef,
  });

  final String id;
  String baslik;
  String icerik;
  DateTime tarih;
  String yazar;

  /// null ise "hepsi" — her iki birimde de görünür.
  Birim? hedef;

  bool gorunurMu(Birim birim) => hedef == null || hedef == birim;

  String get hedefEtiketi => hedef == null ? 'Hepsi' : hedef!.etiket;

  factory Duyuru.haritadan(String id, Map<String, dynamic> m) => Duyuru(
        id: id,
        baslik: (m['baslik'] ?? '') as String,
        icerik: (m['icerik'] ?? '') as String,
        tarih: DateTime.tryParse(m['tarih']?.toString() ?? '') ?? DateTime.now(),
        yazar: (m['yazar'] ?? '') as String,
        hedef: _birimCoz(m['hedef'] as String?),
      );

  Map<String, dynamic> get haritasi => {
        'baslik': baslik,
        'icerik': icerik,
        'tarih': tarih.toIso8601String(),
        'yazar': yazar,
        'hedef': hedef?.name ?? '',
      };
}
