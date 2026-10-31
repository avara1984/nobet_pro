import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dinlenme_kurali.dart';
import '../core/kapsama_motoru.dart';
import '../core/mesai_hesap.dart' as mh;
import '../core/tarih.dart';
import '../modeller/modeller.dart';
import '../servisler/veri_servisi.dart';

// -----------------------------------------------------------------------------
// DUYURU OKUMA BİLGİSİ
// -----------------------------------------------------------------------------
/// Yöneticinin "kim okudu" görünümü için ham veri.
class DuyuruOkumaBilgisi {
  DuyuruOkumaBilgisi(this.kullanicilar, this.okumalar);

  final List<Kullanici> kullanicilar;

  /// uid → (duyuruId → görüldüğü zaman)
  final Map<String, Map<String, DateTime>> okumalar;

  /// Duyuruyu görmesi beklenen kullanıcılar: onaylı, aktif, Duyurular
  /// ekranına girebilen (sadece-PDF olmayan) ve hedef birim kısıtına uyan.
  List<Kullanici> hedefKitle(Duyuru d) => kullanicilar
      .where((k) =>
          k.aktif &&
          k.onayli &&
          !k.sadecePdf &&
          (d.hedef == null || k.kisitliBirim == null || k.kisitliBirim == d.hedef))
      .toList();

  DateTime? okumaZamani(Kullanici k, Duyuru d) => okumalar[k.uid]?[d.id];
}

// -----------------------------------------------------------------------------
// OTURUM
// -----------------------------------------------------------------------------
class OturumDurumu extends ChangeNotifier {
  Kullanici? _kullanici;

  Kullanici? get kullanici => _kullanici;
  bool get girisYapildi => _kullanici != null;
  Rol get rol => _kullanici?.rol ?? Rol.izleyici;
  String get kurumId => _kullanici?.kurumId ?? 'varsayilan';

  /// Atanmış yönetici profili (Süper Admin / Temizlik Nöbet / Bordro).
  YoneticiProfili? get profil => _kullanici?.yoneticiProfili;

  /// Bordro İşlemleri bölümüne erişebilir mi?
  bool get bordroYetkisi => _kullanici?.bordroYetkisi ?? false;

  /// Yönetim ekranları (Personeller, Ayarlar, Kullanıcılar, Admin Yönetimi,
  /// Yedekleme) yalnızca nöbet tarafını yönetebilenlere açıktır.
  bool get yonetebilir =>
      !(_kullanici?.sadecePdf ?? false) && rol.yonetebilir;

  void ayarla(Kullanici? k) {
    _kullanici = k;
    notifyListeners();
  }

  void temizle() {
    _kullanici = null;
    notifyListeners();
  }
}

// -----------------------------------------------------------------------------
// NÖBET DURUMU
// -----------------------------------------------------------------------------
class NobetDurumu extends ChangeNotifier {
  NobetDurumu({
    required this.servis,
    required this.kurumId,
    required this.rol,
    required this.tercihler,
    required this.uid,
    this.sadecePdf = false,
    this.bordroYetkisi = false,
    Birim? kisitliBirimGiris,
    Birim baslangicBirimi = Birim.guvenlik,
  })  : kisitliBirim = kisitliBirimGiris,
        _birim = kisitliBirimGiris ?? baslangicBirimi,
        // Nöbet Listesi ekranı her rol için "Onaylanan Liste" ile açılır —
        // düzenlemek isteyen (editor/yönetici) versiyon seçiciden asıl
        // Nöbet Listesi'ne geçebilir, bu yalnızca başlangıç görünümü.
        _aktifVersiyon = kVersiyonOnayli {
    final simdi = DateTime.now();
    _yil = simdi.year;
    _ay = simdi.month;
  }

  final VeriServisi servis;
  final String kurumId;
  final Rol rol;

  /// Duyuru "son görüldü" zaman damgasını cihazda saklamak için — bkz.
  /// [okunmamisDuyuruSayisi] / [duyurularGoruldu].
  final SharedPreferences tercihler;

  /// Ortak kullanılan bir cihazda birden fazla personel giriş yapabildiği
  /// için "son görülen duyuru" anahtarı kullanıcıya özel tutulur.
  final String uid;

  /// Eski sistemdeki "bordro" rolü — sadece görüntüleme + PDF, hiçbir
  /// düzenleme aracı kullanılamaz, girişte "Onaylanan Liste" açılır.
  final bool sadecePdf;

  /// Eski sistemdeki "nobet_temizlik" rolü — dolu ise başka birime
  /// geçilemez.
  final Birim? kisitliBirim;

  /// Bordro İşlemleri bölümüne erişebilir mi? Süper Admin ve Bordro
  /// Admini için true. Bordro Admini nöbet tarafında salt okunurdur
  /// ([sadecePdf]) ama bordroda tam yetkilidir — bu yüzden ayrı bayrak.
  final bool bordroYetkisi;

  // --- durum alanları ---
  Birim _birim;
  KurumAyari _ayar = KurumAyari();
  List<Personel> _personeller = [];
  AyKaydi _kayit = AyKaydi(yil: 2026, ay: 1);
  List<Duyuru> _duyurular = [];
  DateTime? _sonGorulenDuyuruZamani;
  Timer? _duyuruZamanlayici;
  bool _duyuruYukleniyor = false;

  late int _yil;
  late int _ay;

  /// Önceki ayın kaydı — ayın 1'i resmi tatilse sarkan fazla mesaiyi
  /// hesaplamak için gerekir.
  AyKaydi? _oncekiAyKaydiTam;

  /// Bir sonraki ayın kaydı — ayın son günündeki gece vardiyasının
  /// yarinTatil kontrolü için gerekir (kResmiTatil kodu takibi).
  AyKaydi? _sonrakiAyKaydiTam;

  String _aktifVersiyon;

  /// Geri alma yığını — her değişiklikten önce atamaların kopyası
  final List<Map<String, String>> _gecmis = [];
  static const int _gecmisSiniri = 40;

  bool _yukleniyor = true;
  bool _kaydediliyor = false;
  bool _kirli = false;
  String? _hata;

  KapsamaMotoru? _motor;

  // --- erişimciler ---
  Birim get birim => _birim;
  KurumAyari get ayar => _ayar;
  /// Seçili ayda görevde olan personel (göreve başlama/ayrılma tarihine göre).
  /// Nöbet tabloları, özet ve kapsama hesabı bunu kullanır.
  List<Personel> get personeller =>
      _personeller.where((p) => p.ayAktifMi(_yil, _ay)).toList();

  /// Aya bakılmaksızın tüm aktif personel — Personeller, Raporlar ve Bordro
  /// ekranları (ücret tanımı, yıllık raporlar) bunu kullanır.
  List<Personel> get tumPersoneller => _personeller;
  AyKaydi get kayit => _kayit;
  /// Aktif birime görünen duyurular (hedef == null veya == aktif birim).
  List<Duyuru> get duyurular =>
      _duyurular.where((d) => d.gorunurMu(_birim)).toList();

  /// Filtre uygulanmamış tam liste — Duyurular yönetim ekranında
  /// "hangi birime gidiyor" bilgisini göstermek için kullanılır.
  List<Duyuru> get tumDuyurular => _duyurular;

  /// Aktif birime görünen, henüz "görüldü" işaretlenmemiş duyuru sayısı.
  int get okunmamisDuyuruSayisi {
    final sonGorulen = _sonGorulenDuyuruZamani;
    if (sonGorulen == null) return 0;
    return duyurular.where((d) => d.tarih.isAfter(sonGorulen)).length;
  }

  /// Kullanıcının görebileceği liste versiyonları.
  /// Yalnızca Süper Admin (yonetici rolü) ve Temizlik Nöbet Admini
  /// (kisitliBirim != null) tüm listeleri görür; diğerleri (Bordro Admini
  /// dahil) sadece "Onaylanan Liste"yi görür.
  List<String> get versiyonlar {
    if (sadecePdf) return const [kVersiyonOnayli];
    if (rol == Rol.yonetici || kisitliBirim != null) return kListeVersiyonlari;
    return const [kVersiyonOnayli];
  }
  String get aktifVersiyon => _aktifVersiyon;
  bool get geriAlinabilir => _gecmis.isNotEmpty;
  /// Geriye dönük uyumluluk — artık kullanılmıyor, [onayKilidi] geçerli.
  @Deprecated('onayKilidi kullanın')
  bool get onayli => onayKilidi;

  /// Yayındaki liste tamamen kilitlidir — hücre düzenleme, Liste Yap ve
  /// listeler arası kopyalama dahil hiçbir yazma işlemi yapılamaz.
  /// Kilit yalnızca yayından kaldırılarak açılır (madde 6).
  bool get yayinKilidi => _kayit.yayinda;

  /// "Onaylanan Liste" versiyonunun kendisi PIN korumalıdır — ayrı bir
  /// onay bayrağı gerekmez, versiyon adı yeterlidir (madde 12B).
  bool get onayKilidi => _aktifVersiyon == kVersiyonOnayli;

  /// Herhangi bir düzenleme engeli var mı (madde 6 + 12B birlikte).
  bool get kilitli => yayinKilidi || (onayKilidi && !_oturumlukAcik);
  int get yil => _yil;
  int get ay => _ay;
  bool get yukleniyor => _yukleniyor;
  bool get kaydediliyor => _kaydediliyor;
  bool get kirli => _kirli;
  String? get hata => _hata;
  bool get duzenleyebilir => !sadecePdf && rol.duzenleyebilir;
  bool get yonetebilir => !sadecePdf && rol.yonetebilir;

  /// Personel görünümü: bordro (sadecePdf) değil ama İzleyici/Personel
  /// rolündeki kullanıcı. Bu kullanıcılar her zaman sadece "Onaylanan
  /// Liste"yi görür ve o liste yayında değilse hiçbir veri gösterilmez.
  bool get personelGorunumu => !sadecePdf && rol == Rol.izleyici;

  /// Personel görünümünde veya Bordro Admini (sadecePdf) görünümünde, o ay
  /// için gösterilecek veri var mı? Yönetici/editör için her zaman true —
  /// bu ikisinde "Onaylanan Liste" yayında değilse false döner.
  bool get listeGorunurMu =>
      !(personelGorunumu || sadecePdf) || _kayit.yayinda;

  /// Birim değiştirme kısıtlı mı?
  bool get birimDegistirilebilir => kisitliBirim == null;

  int get gunSayisi => DateTime(_yil, _ay + 1, 0).day;

  /// Personel, nöbet ve duyuru verileri birim başına ayrı tutulur.
  /// Kurum ayarları (vardiyalar, kurallar, tatiller) iki birimde ortaktır.
  String get _birimId => '$kurumId#${_birim.name}';

  /// [_birimId]'nin dışarıya açık hâli — bordro ekranları `servis` üzerinden
  /// doğrudan okuma/yazma yaparken aynı birim anahtarını kullanır.
  String get birimId => _birimId;

  KapsamaMotoru get motor {
    _motor ??= KapsamaMotoru(
      ayar: _ayar,
      personeller: personeller,
      kayit: _kayit,
      gunSayisi: gunSayisi,
    );
    return _motor!;
  }

  Madde3Motoru? _madde3;

  /// Eski uygulamadaki 24 saat kapsama kontrolünün (madde 3) birebir
  /// karşılığı. Durum sütunu ve panolar bunu kullanır.
  Madde3Motoru get madde3 {
    _madde3 ??= Madde3Motoru(
      ayar: _ayar,
      personeller: personeller,
      kayit: _kayit,
      gunSayisi: gunSayisi,
      birim: _birim,
    );
    return _madde3!;
  }

  void _motoruTazele() {
    _motor = null;
    _madde3 = null;
  }

  // ---------------------------------------------------------------------------
  // YÜKLEME
  // ---------------------------------------------------------------------------
  Future<void> baslat() async {
    _yukleniyor = true;
    _hata = null;
    if (sadecePdf) _aktifVersiyon = kVersiyonOnayli;
    notifyListeners();
    try {
      _ayar = await servis.kurumAyariGetir(kurumId);
      await _birimVerisiYukle();
      _duyurular = await servis.duyurulariGetir(kurumId);
      await _sonGorulenDuyuruyuYukle();
      _duyuruZamanlayiciBaslat();
    } catch (e) {
      _hata = 'Veriler yüklenemedi: $e';
    } finally {
      _yukleniyor = false;
      notifyListeners();
    }
  }

  static String _duyuruTercihAnahtari(String uid) => 'son_gorulen_duyuru_$uid';

  Future<void> _sonGorulenDuyuruyuYukle() async {
    final kayitli = tercihler.getString(_duyuruTercihAnahtari(uid));
    final parsed = kayitli == null ? null : DateTime.tryParse(kayitli);
    if (parsed != null) {
      _sonGorulenDuyuruZamani = parsed;
      return;
    }
    // İlk giriş — geçmişteki tüm duyurular "okunmamış" olarak yığılmasın.
    _sonGorulenDuyuruZamani = DateTime.now();
    await tercihler.setString(
        _duyuruTercihAnahtari(uid), _sonGorulenDuyuruZamani!.toIso8601String());
  }

  /// Önizleme ve PDF İndir kapısı: Süper Admin her zaman geçer; diğer herkes
  /// yalnızca seçili ayın "Onaylanan Liste"si yayındaysa. (Liste yayında
  /// değilken editörler önizleme veya PDF ile listeyi alamamalı.)
  Future<bool> onizlemeyeIzinVar() async {
    if (yonetebilir) return true;
    if (_aktifVersiyon == kVersiyonOnayli) return _kayit.yayinda;
    try {
      final k = await servis.ayKaydiGetir(_birimId, _yil, _ay,
          versiyon: kVersiyonOnayli);
      return k.yayinda;
    } catch (_) {
      return false;
    }
  }

  /// Duyurular ekranı açıldığında çağrılır — o ana kadarki tüm duyuruları
  /// "görüldü" işaretler.
  Future<void> duyurularGoruldu() async {
    _sonGorulenDuyuruZamani = DateTime.now();
    await tercihler.setString(
        _duyuruTercihAnahtari(uid), _sonGorulenDuyuruZamani!.toIso8601String());
    notifyListeners();
    await _duyuruOkumaIsaretle();
  }

  /// Duyurular ekranının gösterdiği tüm duyuruları bu kullanıcı adına
  /// "görüldü" yazar (daha önce yazılmış olanların zamanı korunur). Yönetici
  /// "kim okudu" ekranını bununla besler; hata olursa sessiz geçilir.
  Future<void> _duyuruOkumaIsaretle() async {
    try {
      final mevcut = await servis.duyuruOkumalariniGetir(kurumId, uid);
      final simdi = DateTime.now();
      var degisti = false;
      for (final dy in _duyurular) {
        if (!mevcut.containsKey(dy.id)) {
          mevcut[dy.id] = simdi;
          degisti = true;
        }
      }
      if (degisti) await servis.duyuruOkumalariniKaydet(kurumId, uid, mevcut);
    } catch (_) {}
  }

  /// Yönetici için: kullanıcılar ve kimin hangi duyuruyu ne zaman gördüğü.
  /// Çağıran kullanıcının kendi okuması da önce yazılır (ekranı açmış sayılır).
  Future<DuyuruOkumaBilgisi> duyuruOkumaBilgisi() async {
    await _duyuruOkumaIsaretle();
    final kullanicilar = await servis.kullanicilariGetir(kurumId);
    final okumalar = await servis.tumDuyuruOkumalari(kurumId);
    return DuyuruOkumaBilgisi(kullanicilar, okumalar);
  }

  void _duyuruZamanlayiciBaslat() {
    _duyuruZamanlayici?.cancel();
    _duyuruZamanlayici =
        Timer.periodic(const Duration(minutes: 5), (_) => duyurulariYenile());
  }

  /// Duyuruları yeniden çeker — periyodik zamanlayıcı ve (Android'de)
  /// ön plandayken gelen FCM mesajları tarafından çağrılır.
  Future<void> duyurulariYenile() async {
    if (_duyuruYukleniyor) return;
    _duyuruYukleniyor = true;
    try {
      _duyurular = await servis.duyurulariGetir(kurumId);
      notifyListeners();
    } catch (_) {
      // Sessiz geç — _oncekiAyiOku/_sonrakiAyiOku ile aynı desen.
    } finally {
      _duyuruYukleniyor = false;
    }
  }

  @override
  void dispose() {
    _duyuruZamanlayici?.cancel();
    super.dispose();
  }

  Future<void> _birimVerisiYukle() async {
    _personeller = await servis.personelleriGetir(_birimId);
    if (!versiyonlar.contains(_aktifVersiyon)) {
      _aktifVersiyon = kVersiyonNobet;
    }
    _gecmis.clear();
    _kayit = await servis.ayKaydiGetir(_birimId, _yil, _ay,
        versiyon: _aktifVersiyon);
    await _oncekiAyiOku();
    await _sonrakiAyiOku();
    _kirli = false;
    _motoruTazele();
  }

  Future<void> _oncekiAyiOku() async {
    try {
      final oAy = _ay == 1 ? 12 : _ay - 1;
      final oYil = _ay == 1 ? _yil - 1 : _yil;
      _oncekiAyKaydiTam = await servis.ayKaydiGetir(_birimId, oYil, oAy,
          versiyon: kVersiyonOnayli);
    } catch (_) {
      _oncekiAyKaydiTam = null;
    }
  }

  Future<void> _sonrakiAyiOku() async {
    try {
      final sAy = _ay == 12 ? 1 : _ay + 1;
      final sYil = _ay == 12 ? _yil + 1 : _yil;
      _sonrakiAyKaydiTam = await servis.ayKaydiGetir(_birimId, sYil, sAy,
          versiyon: kVersiyonOnayli);
    } catch (_) {
      _sonrakiAyKaydiTam = null;
    }
  }

  Future<void> birimDegistir(Birim yeni) async {
    if (yeni == _birim) return;
    if (kisitliBirim != null) return; // nobet_temizlik benzeri kısıt
    _birim = yeni;
    _yukleniyor = true;
    notifyListeners();
    try {
      await _birimVerisiYukle();
      _duyurular = await servis.duyurulariGetir(kurumId);
    } catch (e) {
      _hata = 'Birim yüklenemedi: $e';
    } finally {
      _yukleniyor = false;
      notifyListeners();
    }
  }

  Future<void> donemDegistir(int yil, int ay) async {
    if (yil == _yil && ay == _ay) return;
    _yil = yil;
    _ay = ay;
    _yukleniyor = true;
    notifyListeners();
    try {
      _gecmis.clear();
      _oturumlukAcik = false;
      _kayit = await servis.ayKaydiGetir(_birimId, yil, ay,
          versiyon: _aktifVersiyon);
      await _oncekiAyiOku();
      await _sonrakiAyiOku();
      _kirli = false;
      _motoruTazele();
    } catch (e) {
      _hata = 'Dönem yüklenemedi: $e';
    } finally {
      _yukleniyor = false;
      notifyListeners();
    }
  }

  /// `donemDegistir`'in aksine yıl/ay değişmese bile HER ZAMAN diskten/
  /// buluttan yeniden okur. Haftalık Nöbet ekranı gibi bu nesnenin
  /// dışından (aynı `servis` üzerinden doğrudan) aktif aya yazan
  /// ekranlardan sonra bellekteki `_kayit`in bayatlamasını önlemek içindir.
  ///
  /// `_oturumlukAcik` bilinçli olarak sıfırlanmaz — PIN kilidi oturum
  /// geneli bir bayraktır, burada sıfırlamak her kayıttan sonra gereksiz
  /// yeniden PIN sorulmasına yol açardı.
  Future<void> yenidenYukle() async {
    _yukleniyor = true;
    notifyListeners();
    try {
      _gecmis.clear();
      _kayit = await servis.ayKaydiGetir(_birimId, _yil, _ay,
          versiyon: _aktifVersiyon);
      await _oncekiAyiOku();
      await _sonrakiAyiOku();
      _kirli = false;
      _motoruTazele();
    } catch (e) {
      _hata = 'Dönem yenilenemedi: $e';
    } finally {
      _yukleniyor = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // HÜCRELER
  // ---------------------------------------------------------------------------
  // --- VERSİYONLAR ------------------------------------------------------------
  Future<void> versiyonDegistir(String versiyon) async {
    if (versiyon == _aktifVersiyon) return;
    _yukleniyor = true;
    notifyListeners();
    try {
      _aktifVersiyon = versiyon;
      _gecmis.clear();
      _oturumlukAcik = false;
      _kayit = await servis.ayKaydiGetir(_birimId, _yil, _ay,
          versiyon: versiyon);
      _kirli = false;
      _motoruTazele();
    } catch (e) {
      _hata = 'Versiyon açılamadı: $e';
    } finally {
      _yukleniyor = false;
      notifyListeners();
    }
  }

  /// Bu ayın mevcut listesini başka bir versiyona kopyalar.
  Future<String> versiyonaKopyala(String hedef, {String kaydeden = ''}) async {
    if (!duzenleyebilir) return 'Bu işlem için yetkiniz yok.';
    if (hedef == _aktifVersiyon) return 'Kaynak ve hedef aynı liste.';
    if (!kListeVersiyonlari.contains(hedef)) return 'Geçersiz liste.';

    // Hedef versiyonun kendi kilidini de kontrol et — eski sistemdeki
    // "Farklı Kaydet PIN/yayın kilidini atlıyor" açığı burada kapatılıyor.
    final hedefKayit =
        await servis.ayKaydiGetir(_birimId, _yil, _ay, versiyon: hedef);
    if (hedefKayit.yayinda) {
      return '"${versiyonAdi(hedef)}" listesi YAYINDA olduğu için üzerine '
          'yazılamaz. Önce yayından kaldırın.';
    }
    if (hedef == kVersiyonOnayli && !_oturumlukAcik) {
      return '"${versiyonAdi(hedef)}" listesi PIN korumalı. Önce PIN '
          'doğrulaması yapmanız gerekiyor.';
    }

    final yeni = _kayit.kopyala(hedef);
    if (kaydeden.isNotEmpty) yeni.guncelleyen = kaydeden;
    await servis.ayKaydiKaydet(_birimId, yeni);
    notifyListeners();
    return '${T.ayYil(_yil, _ay)} listesi "${versiyonAdi(hedef)}" '
        'listesine kopyalandı.';
  }

  /// Versiyonun bu aya ait içeriğini boşaltır. Versiyon silinmez.
  Future<void> versiyonBosalt(String versiyon) async {
    if (!yonetebilir) return;
    await servis.versiyonSil(_birimId, _yil, _ay, versiyon);
    if (_aktifVersiyon == versiyon) {
      _kayit = await servis.ayKaydiGetir(_birimId, _yil, _ay,
          versiyon: versiyon);
      _gecmis.clear();
      _kirli = false;
      _motoruTazele();
    }
    notifyListeners();
  }

  // --- ONAY -------------------------------------------------------------------
  /// Varsayılan PIN her zaman '0000'dir — Ayarlar'dan özel bir kod
  /// tanımlanmadıysa bile "Onaylanan Liste" PIN ile korunur (madde 12B).
  static const String kVarsayilanOnayKodu = '0000';

  String get _gecerliOnayKodu =>
      _ayar.onayKodu.length == 4 ? _ayar.onayKodu : kVarsayilanOnayKodu;

  bool onayKoduDogruMu(String girilen) => girilen == _gecerliOnayKodu;

  /// Bu oturumluk "Onaylanan Liste" kilidini açık tutar — sayfa
  /// yenilenene/ay veya versiyon değişene kadar tekrar PIN sorulmaz.
  bool _oturumlukAcik = false;

  /// "Onaylanan Liste" bu oturum için PIN ile açıldı mı? Listeler arası
  /// kopyalama akışı bunu kontrol eder.
  bool get onaylananListeAcikMi => _oturumlukAcik;

  void kilidiAc() {
    _oturumlukAcik = true;
    notifyListeners();
  }

  // --- GERİ ALMA --------------------------------------------------------------
  void _gecmiseYaz() {
    _gecmis.add(Map<String, String>.from(_kayit.atamalar));
    if (_gecmis.length > _gecmisSiniri) _gecmis.removeAt(0);
  }

  bool geriAl() {
    if (_gecmis.isEmpty) return false;
    final onceki = _gecmis.removeLast();
    _kayit.atamalar
      ..clear()
      ..addAll(onceki);
    _kirli = true;
    _motoruTazele();
    notifyListeners();
    return true;
  }

  String kod(int gun, String personelId) => _kayit.kod(gun, personelId);

  VardiyaTanimi vardiya(int gun, String personelId) =>
      _ayar.vardiyaBul(_kayit.kod(gun, personelId));

  void kodAta(int gun, String personelId, String kod) {
    if (!duzenleyebilir || yayinKilidi) return;
    _gecmiseYaz();
    _kayit.ata(gun, personelId, kod);
    _kirli = true;
    _motoruTazele();
    notifyListeners();
  }

  /// Gece vardiyasından çıkan personel ertesi gün gündüz vardiyasına
  /// yazılamaz. İhlal varsa uyarı metni, yoksa null döner.
  ///
  /// Kuralın kendisi [dinlenmeIhlaliMetni] içinde (core/dinlenme_kurali.dart)
  /// — Haftalık Nöbet ekranı da aynı fonksiyonu, ay sınırında doğru
  /// `AyKaydi`'den okuduğu `oncekiKod` ile çağırır.
  String? dinlenmeIhlali(int gun, String personelId, String yeniKod) {
    if (gun <= 1) return null;
    final onceki = _kayit.kod(gun - 1, personelId);
    final p = _personeller.firstWhere(
      (x) => x.id == personelId,
      orElse: () => Personel(id: '', ad: 'Personel'),
    );
    return dinlenmeIhlaliMetni(
      personelAdi: p.ad,
      oncekiKod: onceki,
      yeniKod: yeniKod,
    );
  }

  // ---------------------------------------------------------------------------
  // OTOMATİK LİSTE — 8 günlük döngü
  // ---------------------------------------------------------------------------
  /// Şablon olarak kullanılan versiyonun adı.
  static const String kSablonVersiyonu = kVersiyonSablon;

  String _mesaiKodu(DateTime tarih) {
    if (T.haftaSonu(tarih)) return kHaftaTatili;
    if (_ayar.resmiTatilMi(tarih)) return kResmiTatil;
    return kMesai;
  }

  /// Şablonda 08:00 - 17:30 yazan kişiler dahiliye (mesai) sayılır.
  /// Personel kaydında mesai işareti varsa o da geçerlidir.
  Set<String> _mesaiKisileri(AyKaydi kaynak, int gunSayisiKaynak) {
    final kume = <String>{
      for (final p in personeller)
        if (p.mesaiMi) p.id
    };
    for (var g = 1; g <= gunSayisiKaynak; g++) {
      for (final p in personeller) {
        if (kaynak.kod(g, p.id) == kMesai) kume.add(p.id);
      }
    }
    return kume;
  }

  /// Ortak doldurma motoru.
  ///
  /// [kaynak] çekirdeğin okunduğu ay kaydı,
  /// [kaynakBaslangic] çekirdeğin kaynaktaki ilk günü,
  /// [ilkYazilanGun] bu ayda yazmaya başlanacak gün.
  void _cekirdektenDoldur({
    required AyKaydi kaynak,
    required int kaynakBaslangic,
    required int cekirdek,
    required int ilkYazilanGun,
    required int kaynakGunSayisi,
  }) {
    final mesailer = _mesaiKisileri(kaynak, kaynakGunSayisi);

    for (var gun = ilkYazilanGun; gun <= gunSayisi; gun++) {
      final tarih = DateTime(_yil, _ay, gun);
      final kaynakGun = kaynakBaslangic + ((gun - ilkYazilanGun) % cekirdek);

      for (final p in personeller) {
        if (mesailer.contains(p.id)) {
          _kayit.ata(gun, p.id, _mesaiKodu(tarih));
          continue;
        }
        final k = kaynak.kod(kaynakGun, p.id);
        // N.İ. ve boş hücreler nöbet izni olarak yazılır
        _kayit.ata(gun, p.id, (k.isEmpty || k == kNobetIzni) ? kNobetIzni : k);
      }
    }

    _kirli = true;
    _motoruTazele();
    notifyListeners();
  }

  /// Bu ayın ilk [cekirdek] gününü çekirdek alıp ayın kalanını doldurur.
  /// Elle girdiğiniz ilk günler olduğu gibi kalır.
  String listeyiBuAydanDoldur({int cekirdek = 0}) {
    if (!duzenleyebilir) return 'Bu işlem için yetkiniz yok.';
    if (yayinKilidi) {
      return 'Bu liste YAYINDA olduğu için değişiklik yapılamaz. Önce '
          'göz simgesine basıp yayından kaldırın.';
    }
    if (onayKilidi) {
      return 'Bu liste onaylanmış. Önce kilidi açmanız gerekiyor.';
    }
    final n = cekirdek > 0 ? cekirdek : _ayar.dongUzunlugu;
    if (n < 2) return 'Döngü uzunluğu geçersiz.';
    if (gunSayisi <= n) return 'Ay, çekirdek gün sayısından kısa.';

    var doluHucre = 0;
    for (var g = 1; g <= n; g++) {
      for (final p in personeller) {
        if (_kayit.kod(g, p.id).isNotEmpty) doluHucre++;
      }
    }
    if (doluHucre == 0) {
      return 'Ayın ilk $n günü boş. Önce bu günleri elle doldurun.';
    }

    _gecmiseYaz();
    _cekirdektenDoldur(
      kaynak: _kayit,
      kaynakBaslangic: 1,
      cekirdek: n,
      ilkYazilanGun: n + 1,
      kaynakGunSayisi: n,
    );
    return 'Ayın ilk $n günü çekirdek alındı, ${n + 1}. günden ayın sonuna '
        'kadar döngü uygulandı.';
  }

  /// Geçen ayın son [cekirdek] gününü çekirdek alıp ayın tamamını kurar.
  /// Önce geçen ayın "Aylık Normal Şablon" versiyonuna bakar, yoksa
  /// geçen ayın asıl listesini kullanır.
  Future<String> listeyiGecenAydanDoldur({int cekirdek = 0}) async {
    if (!duzenleyebilir) return 'Bu işlem için yetkiniz yok.';
    if (yayinKilidi) {
      return 'Bu liste YAYINDA olduğu için değişiklik yapılamaz. Önce '
          'göz simgesine basıp yayından kaldırın.';
    }
    if (onayKilidi) {
      return 'Bu liste onaylanmış. Önce kilidi açmanız gerekiyor.';
    }
    final n = cekirdek > 0 ? cekirdek : _ayar.dongUzunlugu;
    if (n < 2) return 'Döngü uzunluğu geçersiz.';

    final oncekiAy = _ay == 1 ? 12 : _ay - 1;
    final oncekiYil = _ay == 1 ? _yil - 1 : _yil;
    final oncekiGunSayisi = DateTime(oncekiYil, oncekiAy + 1, 0).day;

    AyKaydi kaynak;
    var kaynakAdi = 'asıl liste';
    try {
      kaynak = await servis.ayKaydiGetir(_birimId, oncekiYil, oncekiAy,
          versiyon: kSablonVersiyonu);
      if (kaynak.atamalar.isEmpty) {
        kaynak = await servis.ayKaydiGetir(_birimId, oncekiYil, oncekiAy);
      } else {
        kaynakAdi = kSablonVersiyonu;
      }
    } catch (e) {
      return 'Geçen ay okunamadı: $e';
    }

    if (kaynak.atamalar.isEmpty) {
      return '${T.ayYil(oncekiYil, oncekiAy)} ayında veri yok. '
          'Bu ayın ilk $n gününü elle doldurup "Bu aydan devam et" '
          'seçeneğini kullanın.';
    }

    _gecmiseYaz();
    _cekirdektenDoldur(
      kaynak: kaynak,
      kaynakBaslangic: oncekiGunSayisi - n + 1,
      cekirdek: n,
      ilkYazilanGun: 1,
      kaynakGunSayisi: oncekiGunSayisi,
    );
    return '${T.ayYil(oncekiYil, oncekiAy)} ayının son $n günü '
        '($kaynakAdi) çekirdek alındı, ${T.ayYil(_yil, _ay)} '
        'ayının tamamı yeniden kuruldu.';
  }

  // ---------------------------------------------------------------------------
  /// Ayın zorunlu çalışma saati hedefi.
  /// Pazar günleri ve tam gün resmi tatiller düşülür,
  /// arife (yarım gün) 3.5 saat, normal iş günü 7.5 saat sayılır.
  double get aylikHedefSaat {
    var toplam = 0.0;
    for (var g = 1; g <= gunSayisi; g++) {
      final t = DateTime(_yil, _ay, g);
      if (t.weekday == DateTime.sunday) continue;
      if (_ayar.resmiTatilMi(t)) continue;
      toplam += _ayar.yarimGunMu(t) ? 3.5 : 7.5;
    }
    return toplam;
  }

  /// Bir günün bordro değerleri (madde 2). Hesaplama mantığı
  /// core/mesai_hesap.dart'ta — yıllık rapor da aynı fonksiyonu kullanır.
  mh.MesaiSonucu saatBilgisi(int gun, String personelId) {
    // Ayın son günündeki gece vardiyasının yarinTatil kontrolü için
    // bir sonraki ayın 1'inin koduna bak (KurumAyari'ye eklenmemiş olabilir).
    final yarinKodResmiTatil = gun == gunSayisi &&
        (_sonrakiAyKaydiTam?.kod(1, personelId) ?? '') == kResmiTatil;
    return mh.gunSonucu(
      ayar: _ayar,
      kayit: _kayit,
      gun: gun,
      yil: _yil,
      ay: _ay,
      gunSayisi: gunSayisi,
      personelId: personelId,
      yarinKodResmiTatil: yarinKodResmiTatil,
    );
  }

  // ---------------------------------------------------------------------------
  // KAYDETME
  // ---------------------------------------------------------------------------
  Future<bool> kaydet({String kaydeden = ''}) async {
    if (!duzenleyebilir) return false;
    _kaydediliyor = true;
    notifyListeners();
    try {
      _kayit.guncelleme = DateTime.now();
      if (kaydeden.isNotEmpty) _kayit.guncelleyen = kaydeden;
      await servis.ayKaydiKaydet(_birimId, _kayit);
      _kirli = false;
      return true;
    } catch (e) {
      _hata = 'Kaydedilemedi: $e';
      return false;
    } finally {
      _kaydediliyor = false;
      notifyListeners();
    }
  }

  /// Yayına alma/kaldırma — onay diyaloğu olmadan tek tıkla (madde 6).
  /// Yayına ALINIRKEN, kaydedilmemiş değişiklik varsa önce sessizce
  /// kaydedilir (akıllı otomatik kaydetme).
  Future<void> yayinDurumuDegistir({String kaydeden = ''}) async {
    if (!yonetebilir) return;
    if (!_kayit.yayinda && _kirli) {
      await kaydet(kaydeden: kaydeden);
    }
    _kayit.yayinda = !_kayit.yayinda;
    notifyListeners();
    await servis.ayKaydiKaydet(_birimId, _kayit);
  }

  Future<void> aylikNotKaydet(String not) async {
    if (!duzenleyebilir) return;
    _kayit.aylikNot = not;
    notifyListeners();
    await servis.ayKaydiKaydet(_birimId, _kayit);
  }

  // --- personel ---------------------------------------------------------------
  Future<void> personelKaydet(Personel p) async {
    if (!yonetebilir) return;
    await servis.personelKaydet(_birimId, p);
    _personeller = await servis.personelleriGetir(_birimId);
    _motoruTazele();
    notifyListeners();
  }

  Future<void> personelSil(String id) async {
    if (!yonetebilir) return;
    await servis.personelSil(_birimId, id);
    _personeller = await servis.personelleriGetir(_birimId);
    _motoruTazele();
    notifyListeners();
  }

  // --- duyuru -----------------------------------------------------------------
  /// Duyurular kurum genelinde ortak saklanır (birime özel değil),
  /// [Duyuru.hedef] alanı hangi birim(ler)e görüneceğini belirler
  /// (madde 12F).
  Future<void> duyuruKaydet(Duyuru d) async {
    if (!duzenleyebilir) return;
    await servis.duyuruKaydet(kurumId, d);
    _duyurular = await servis.duyurulariGetir(kurumId);
    notifyListeners();
  }

  Future<void> duyuruSil(String id) async {
    if (!duzenleyebilir) return;
    await servis.duyuruSil(kurumId, id);
    _duyurular = await servis.duyurulariGetir(kurumId);
    notifyListeners();
  }

  // --- ayarlar ----------------------------------------------------------------
  Future<void> ayarKaydet(KurumAyari yeni) async {
    if (!yonetebilir) return;
    _ayar = yeni;
    _motoruTazele();
    notifyListeners();
    await servis.kurumAyariKaydet(yeni);
  }

  // ---------------------------------------------------------------------------
  // İSTATİSTİK
  // ---------------------------------------------------------------------------
  /// Fiilen çalışma atanmış gün sayısı.
  ///
  /// Boş hücre "N.İ." (nöbet izni) sayıldığı için burada aranan şey
  /// hücrelerin dolu olması değil, o gün en az bir kişinin çalışıyor
  /// olmasıdır — aksi hâlde hiç dokunulmamış bir ay "tamamen dolu"
  /// görünürdü.
  int get doldurulanGun {
    if (personeller.isEmpty) return 0;
    var s = 0;
    for (var g = 1; g <= gunSayisi; g++) {
      final calisanVar = personeller.any((p) {
        final kod = _kayit.kod(g, p.id);
        return kod.isNotEmpty && _ayar.vardiyaBul(kod).calisiyor;
      });
      if (calisanVar) s++;
    }
    return s;
  }

  int get sorunluGun => madde3
      .tumAy(_yil, _ay)
      .where((k) => k.durum != GercekDurum.tamam)
      .length;

  /// Ayın tamamı için personel bazlı bordro özeti
  List<PersonelOzeti> get ozetler {
    return [
      for (final p in personeller) ...[
        () {
          final sayac = <String, int>{};
          var toplam = 0.0, gece = 0.0, normal = 0.0;
          var fazla = mh.oncekiAydanSarkanFazlaMesai(
            ayar: _ayar,
            oncekiAyKayit: _oncekiAyKaydiTam,
            personelId: p.id,
            yil: _yil,
            ay: _ay,
          );
          var izin = 0;
          for (var g = 1; g <= gunSayisi; g++) {
            final k = _kayit.kod(g, p.id);
            // Boş hücre ekranda/PDF'te N.İ. olarak gösterilir — Aylık
            // Özet'teki sayımın da aynı kuralı izlemesi gerekir, aksi
            // hâlde otomatik boş bırakılan N.İ. günleri sayılmaz.
            final kSayim = k.isEmpty ? kNobetIzni : k;
            sayac[kSayim] = (sayac[kSayim] ?? 0) + 1;
            final s = saatBilgisi(g, p.id);
            toplam += s.toplam;
            gece += s.gece;
            normal += s.normal;
            fazla += s.fazlaGun;
            izin += s.yillikIzin;
          }
          return PersonelOzeti(
            personel: p,
            vardiyaSayilari: sayac,
            toplamSaat: toplam,
            geceSaati: gece,
            normalMesai: normal,
            fazlaMesaiGunu: fazla,
            yillikIzinKullanilan: izin,
          );
        }()
      ]
    ];
  }

  /// Bir personelin, görüntülenen yılın Ocak'tan bulunulan aya kadar
  /// (bulunulan ay TAMAMI dahil — o ayın henüz gelmemiş günleri de
  /// sayılır, sadece bulunulan aydan SONRAKİ aylar hariç tutulur; üst
  /// çubukta hangi ay görüntüleniyor olursa olsun gerçek takvim tarihine
  /// göre) toplam yıllık izin kullanımı — HER ZAMAN "Onaylanan Liste"den
  /// okunur, hangi versiyon görüntüleniyor olursa olsun.
  Future<Map<String, int>> yillikIzinKullanimi() async {
    final sonuc = <String, int>{for (final p in personeller) p.id: 0};
    final bugun = DateTime.now();
    if (_yil > bugun.year) return sonuc; // tamamı ileri tarihli
    final sonAy = _yil == bugun.year ? bugun.month : 12;
    for (var ay = 1; ay <= sonAy; ay++) {
      final AyKaydi kayit;
      try {
        kayit = ay == _ay && _aktifVersiyon == kVersiyonOnayli
            ? _kayit
            : await servis.ayKaydiGetir(_birimId, _yil, ay,
                versiyon: kVersiyonOnayli);
      } catch (_) {
        continue;
      }
      final gunSayisiAy = DateTime(_yil, ay + 1, 0).day;
      for (final p in personeller) {
        var toplam = sonuc[p.id] ?? 0;
        for (var g = 1; g <= gunSayisiAy; g++) {
          toplam += mh
              .gunSonucu(
                ayar: _ayar,
                kayit: kayit,
                gun: g,
                yil: _yil,
                ay: ay,
                gunSayisi: gunSayisiAy,
                personelId: p.id,
              )
              .yillikIzin;
        }
        sonuc[p.id] = toplam;
      }
    }
    return sonuc;
  }
}
