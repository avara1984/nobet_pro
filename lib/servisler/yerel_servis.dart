import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/tarih.dart';
import '../modeller/bordro_modelleri.dart';
import '../modeller/modeller.dart';
import 'veri_servisi.dart';

/// Verileri cihazın kendi diskine JSON olarak yazar.
/// Sunucu veya internet gerektirmez.
///
/// [kurumId] parametresi birim ayrımı için de kullanılır
/// (ör. "varsayilan#guvenlik", "varsayilan#temizlik"), böylece
/// Güvenlik ve Temizlik listeleri birbirinden bağımsız saklanır.
class YerelServis implements VeriServisi, YedeklenebilirServis {
  YerelServis(this._tercihler);

  final SharedPreferences _tercihler;

  String _kurumAnahtari(String id) => 'kurum_$id';
  String _personelAnahtari(String id) => 'personeller_$id';
  String _duyuruAnahtari(String id) => 'duyurular_$id';
  String _donemAnahtari(String id, int yil, int ay, [String versiyon = '']) {
    final taban = 'nobet_${id}_${T.donemAnahtari(yil, ay)}';
    return versiyon.isEmpty ? taban : '${taban}__$versiyon';
  }

  String _versiyonAnahtari(String id, int yil, int ay) =>
      'versiyonlar_${id}_${T.donemAnahtari(yil, ay)}';


  String _kullaniciAnahtari(String id) => 'kullanicilar_$id';

  String _bordroAyarAnahtari(int yil) => 'bordro_ayari_$yil';
  String _ucretAnahtari(String birimId) => 'ucretler_$birimId';
  String _bordroAnahtari(String birimId, String personelId, int yil, int ay) =>
      'bordro_${birimId}_${personelId}_${T.donemAnahtari(yil, ay)}';
  String _bordroPdfAnahtari(String birimId, String personelId, int yil, int ay) =>
      'bordro_pdf_${birimId}_${personelId}_${T.donemAnahtari(yil, ay)}';

  Map<String, dynamic>? _oku(String anahtar) {
    final metin = _tercihler.getString(anahtar);
    if (metin == null || metin.isEmpty) return null;
    try {
      return jsonDecode(metin) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  List<dynamic> _okuListe(String anahtar) {
    final metin = _tercihler.getString(anahtar);
    if (metin == null || metin.isEmpty) return const [];
    try {
      return jsonDecode(metin) as List<dynamic>;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _yaz(String anahtar, Object deger) =>
      _tercihler.setString(anahtar, jsonEncode(deger));

  // --- KURUM AYARI -----------------------------------------------------------
  @override
  Future<KurumAyari> kurumAyariGetir(String kurumId) async {
    final harita = _oku(_kurumAnahtari(kurumId));
    if (harita == null) {
      final varsayilan = KurumAyari(
        id: kurumId,
        ad: 'T.C. SAĞLIK BAKANLIĞI — AYDIN YENİPAZAR İLÇE DEVLET HASTANESİ',
        altBaslik: 'Nöbet listesi yönetim sistemi',
      );
      await kurumAyariKaydet(varsayilan);
      return varsayilan;
    }
    final ayar = KurumAyari.haritadan(kurumId, harita);
    if (ayar.vardiyalar.isEmpty) {
      ayar.vardiyalar = List.of(kVarsayilanVardiyalar);
    }
    if (ayar.kurallar.isEmpty) {
      ayar.kurallar = List.of(kVarsayilanKurallar);
    }
    return ayar;
  }

  @override
  Future<void> kurumAyariKaydet(KurumAyari ayar) =>
      _yaz(_kurumAnahtari(ayar.id), ayar.haritasi);

  // --- PERSONEL --------------------------------------------------------------
  Future<List<Personel>> _tumPersoneller(String kurumId) async =>
      _okuListe(_personelAnahtari(kurumId)).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return Personel.haritadan((m['id'] ?? '') as String, m);
      }).toList();

  Future<void> _personelleriYaz(String kurumId, List<Personel> liste) => _yaz(
        _personelAnahtari(kurumId),
        liste.map((p) => {'id': p.id, ...p.haritasi}).toList(),
      );

  @override
  Future<List<Personel>> personelleriGetir(String kurumId) async {
    final liste = (await _tumPersoneller(kurumId))
        .where((p) => p.aktif && p.id.isNotEmpty)
        .toList()
      ..sort((a, b) => a.sira.compareTo(b.sira));
    return liste;
  }

  @override
  Future<void> personelKaydet(String kurumId, Personel personel) async {
    final liste = await _tumPersoneller(kurumId);
    final i = liste.indexWhere((p) => p.id == personel.id);
    if (i == -1) {
      liste.add(personel);
    } else {
      liste[i] = personel;
    }
    await _personelleriYaz(kurumId, liste);
  }

  @override
  Future<void> personelSil(String kurumId, String personelId) async {
    final liste = await _tumPersoneller(kurumId);
    liste.removeWhere((p) => p.id == personelId);
    await _personelleriYaz(kurumId, liste);
  }

  // --- AY KAYDI --------------------------------------------------------------
  @override
  Future<AyKaydi> ayKaydiGetir(String kurumId, int yil, int ay,
      {String versiyon = ''}) async {
    final harita = _oku(_donemAnahtari(kurumId, yil, ay, versiyon));
    if (harita == null) {
      return AyKaydi(yil: yil, ay: ay, versiyon: versiyon);
    }
    return AyKaydi.haritadan(yil, ay, harita);
  }

  @override
  Future<void> ayKaydiKaydet(String kurumId, AyKaydi kayit) async {
    await _yaz(
      _donemAnahtari(kurumId, kayit.yil, kayit.ay, kayit.versiyon),
      kayit.haritasi,
    );
    if (kayit.versiyon.isNotEmpty) {
      final liste = _okuListe(_versiyonAnahtari(kurumId, kayit.yil, kayit.ay))
          .map((e) => e.toString())
          .toSet();
      if (liste.add(kayit.versiyon)) {
        await _yaz(_versiyonAnahtari(kurumId, kayit.yil, kayit.ay),
            liste.toList()..sort());
      }
    }
  }

  /// Versiyonlar sabittir; diskte ne varsa değil, tanımlı dört liste döner.
  @override
  Future<List<String>> versiyonlariGetir(
          String kurumId, int yil, int ay) async =>
      kListeVersiyonlari;

  /// Versiyon silinmez, içeriği boşaltılır.
  @override
  Future<void> versiyonSil(
      String kurumId, int yil, int ay, String versiyon) async {
    await _tercihler.remove(_donemAnahtari(kurumId, yil, ay, versiyon));
  }

  // --- DUYURU ----------------------------------------------------------------
  @override
  Future<List<Duyuru>> duyurulariGetir(String kurumId) async {
    final liste = _okuListe(_duyuruAnahtari(kurumId)).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return Duyuru.haritadan((m['id'] ?? '') as String, m);
    }).toList()
      ..sort((a, b) => b.tarih.compareTo(a.tarih));
    return liste;
  }

  Future<void> _duyurulariYaz(String kurumId, List<Duyuru> liste) => _yaz(
        _duyuruAnahtari(kurumId),
        liste.map((d) => {'id': d.id, ...d.haritasi}).toList(),
      );

  @override
  Future<void> duyuruKaydet(String kurumId, Duyuru duyuru) async {
    final liste = await duyurulariGetir(kurumId);
    final i = liste.indexWhere((d) => d.id == duyuru.id);
    if (i == -1) {
      liste.add(duyuru);
    } else {
      liste[i] = duyuru;
    }
    await _duyurulariYaz(kurumId, liste);
  }

  @override
  Future<void> duyuruSil(String kurumId, String duyuruId) async {
    final liste = await duyurulariGetir(kurumId);
    liste.removeWhere((d) => d.id == duyuruId);
    await _duyurulariYaz(kurumId, liste);
  }

  // --- KULLANICI -------------------------------------------------------------
  /// Diskten okur, seed etmez. Kaydet/sil bunu kullanır;
  /// böylece kullanicilariGetir ile karşılıklı çağrı oluşmaz.
  List<Kullanici> _kullanicilariOku(String kurumId) =>
      _okuListe(_kullaniciAnahtari(kurumId))
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return Kullanici.haritadan((m['uid'] ?? '') as String, m);
          })
          .where((k) => k.uid.isNotEmpty)
          .toList();

  Future<void> _kullanicilariYaz(String kurumId, List<Kullanici> liste) =>
      _yaz(
        _kullaniciAnahtari(kurumId),
        liste.map((k) => {'uid': k.uid, ...k.haritasi}).toList(),
      );

  @override
  Future<List<Kullanici>> kullanicilariGetir(String kurumId) async {
    final liste = _kullanicilariOku(kurumId);
    if (liste.isNotEmpty) return liste;

    // İlk açılış: varsayılan yönetici oluştur
    final varsayilan = Kullanici(
      uid: 'yonetici',
      ad: 'Yönetici',
      eposta: '',
      rol: Rol.yonetici,
      kurumId: kurumId,
    );
    await _kullanicilariYaz(kurumId, [varsayilan]);
    return [varsayilan];
  }

  @override
  Future<void> kullaniciKaydet(String kurumId, Kullanici kullanici) async {
    final liste = _kullanicilariOku(kurumId);
    final i = liste.indexWhere((k) => k.uid == kullanici.uid);
    if (i == -1) {
      liste.add(kullanici);
    } else {
      liste[i] = kullanici;
    }
    await _kullanicilariYaz(kurumId, liste);
  }

  @override
  Future<void> kullaniciSil(String kurumId, String uid) async {
    final liste = _kullanicilariOku(kurumId);
    liste.removeWhere((k) => k.uid == uid);
    if (liste.isEmpty) return; // son kullanıcı silinemez
    await _kullanicilariYaz(kurumId, liste);
  }

  @override
  Future<void> kullaniciRolGuncelle(String uid, Rol rol) async {}

  // --- BORDRO ----------------------------------------------------------------
  @override
  Future<BordroAyari> bordroAyariGetir(String kurumId, int yil) async {
    final harita = _oku(_bordroAyarAnahtari(yil));
    if (harita == null) return BordroAyari(yil: yil);
    return BordroAyari.haritadan(yil, harita);
  }

  @override
  Future<void> bordroAyariKaydet(String kurumId, BordroAyari ayar) =>
      _yaz(_bordroAyarAnahtari(ayar.yil), ayar.haritasi);

  @override
  Future<List<PersonelUcreti>> personelUcretleriGetir(String birimId) async =>
      _okuListe(_ucretAnahtari(birimId))
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return PersonelUcreti.haritadan(
                (m['personelId'] ?? '') as String, m);
          })
          .where((u) => u.personelId.isNotEmpty)
          .toList();

  Future<void> _ucretleriYaz(String birimId, List<PersonelUcreti> liste) =>
      _yaz(_ucretAnahtari(birimId), liste.map((u) => u.haritasi).toList());

  @override
  Future<void> personelUcretiKaydet(
      String birimId, PersonelUcreti ucret) async {
    final liste = await personelUcretleriGetir(birimId);
    final i = liste.indexWhere((u) => u.personelId == ucret.personelId);
    if (i == -1) {
      liste.add(ucret);
    } else {
      liste[i] = ucret;
    }
    await _ucretleriYaz(birimId, liste);
  }

  @override
  Future<void> personelUcretiSil(String birimId, String personelId) async {
    final liste = await personelUcretleriGetir(birimId);
    liste.removeWhere((u) => u.personelId == personelId);
    await _ucretleriYaz(birimId, liste);
  }

  @override
  Future<BordroSonucu?> bordroGetir(
      String birimId, String personelId, int yil, int ay) async {
    final harita = _oku(_bordroAnahtari(birimId, personelId, yil, ay));
    if (harita == null) return null;
    return BordroSonucu.haritadan(harita);
  }

  @override
  Future<void> bordroKaydet(String birimId, BordroSonucu sonuc) => _yaz(
        _bordroAnahtari(birimId, sonuc.personelId, sonuc.yil, sonuc.ay),
        sonuc.haritasi,
      );

  @override
  Future<void> bordroSil(
          String birimId, String personelId, int yil, int ay) async =>
      _tercihler.remove(_bordroAnahtari(birimId, personelId, yil, ay));

  /// Diskteki `bordro_<birimId>_...` anahtarlarını tarayarak okur.
  @override
  Future<List<BordroSonucu>> bordrolariGetir(String birimId,
      {int? yil, int? ay}) async {
    final onEk = 'bordro_${birimId}_';
    final liste = <BordroSonucu>[];
    for (final anahtar in _tercihler.getKeys()) {
      if (!anahtar.startsWith(onEk)) continue;
      final harita = _oku(anahtar);
      if (harita == null) continue;
      final sonuc = BordroSonucu.haritadan(harita);
      if (yil != null && sonuc.yil != yil) continue;
      if (ay != null && sonuc.ay != ay) continue;
      liste.add(sonuc);
    }
    liste.sort((a, b) {
      final yilFarki = b.yil.compareTo(a.yil);
      if (yilFarki != 0) return yilFarki;
      final ayFarki = b.ay.compareTo(a.ay);
      if (ayFarki != 0) return ayFarki;
      return a.personelAd.compareTo(b.personelAd);
    });
    return liste;
  }

  // --- BORDRO PDF YÜKLEMESİ --------------------------------------------------
  @override
  Future<void> bordroYukle(String birimId, YuklenmisBordro kayit) async =>
      _tercihler.setString(
          _bordroPdfAnahtari(birimId, kayit.personelId, kayit.yil, kayit.ay),
          jsonEncode(kayit.haritasi));

  @override
  Future<YuklenmisBordro?> bordroYuklemesiniGetir(
      String birimId, String personelId, int yil, int ay,
      {bool pdfDahil = true}) async {
    final harita =
        _oku(_bordroPdfAnahtari(birimId, personelId, yil, ay));
    if (harita == null) return null;
    final kayit = YuklenmisBordro.haritadan(harita);
    return pdfDahil ? kayit : kayit.metaKopya();
  }

  @override
  Future<List<YuklenmisBordro>> birimBordroYuklemeleriniGetir(
      String birimId, {int? yil, int? ay}) async {
    final onEk = 'bordro_pdf_${birimId}_';
    final liste = <YuklenmisBordro>[];
    for (final anahtar in _tercihler.getKeys()) {
      if (!anahtar.startsWith(onEk)) continue;
      final harita = _oku(anahtar);
      if (harita == null) continue;
      final kayit = YuklenmisBordro.haritadan(harita).metaKopya();
      if (yil != null && kayit.yil != yil) continue;
      if (ay != null && kayit.ay != ay) continue;
      liste.add(kayit);
    }
    liste.sort((a, b) {
      final yf = b.yil.compareTo(a.yil);
      if (yf != 0) return yf;
      final af = b.ay.compareTo(a.ay);
      if (af != 0) return af;
      return a.personelAd.compareTo(b.personelAd);
    });
    return liste;
  }

  @override
  Future<void> bordroYuklemeSil(
          String birimId, String personelId, int yil, int ay) async =>
      _tercihler
          .remove(_bordroPdfAnahtari(birimId, personelId, yil, ay));

  // --- YEDEK -----------------------------------------------------------------
  /// Diskteki tüm nöbet verisini tek JSON metni olarak döndürür.
  @override
  Future<String> tumVeriyiDisaAktar() async {
    final hepsi = <String, dynamic>{};
    for (final anahtar in _tercihler.getKeys()) {
      if (anahtar.startsWith('kurum_') ||
          anahtar.startsWith('kullanicilar_') ||
          anahtar.startsWith('personeller_') ||
          anahtar.startsWith('versiyonlar_') ||
          anahtar.startsWith('duyurular_') ||
          anahtar.startsWith('nobet_') ||
          anahtar.startsWith('bordro_') ||
          anahtar.startsWith('bordro_pdf_') ||
          anahtar.startsWith('ucretler_')) {
        hepsi[anahtar] = _tercihler.getString(anahtar);
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      'surum': 1,
      'tarih': DateTime.now().toIso8601String(),
      'veri': hepsi,
    });
  }

  /// Yedekten geri yükler. Mevcut veriler üzerine yazılır.
  @override
  Future<void> yedektenYukle(String json) async {
    final harita = jsonDecode(json) as Map<String, dynamic>;
    final veri = Map<String, dynamic>.from(harita['veri'] as Map);
    for (final girdi in veri.entries) {
      await _tercihler.setString(girdi.key, girdi.value.toString());
    }
  }
}
