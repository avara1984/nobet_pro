import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/tarih.dart';
import '../modeller/bordro_modelleri.dart';
import '../modeller/modeller.dart';
import 'veri_servisi.dart';

/// Firestore tabanlı veri katmanı — tüm cihazlar aynı veriyi görür.
///
/// Depolama düzeni [YerelServis] ile bire birdir: tek `nobet_pro`
/// koleksiyonunda, doküman kimliği yerel anahtarla aynı olan
/// (`kurum_<id>`, `nobet_<id>_<yyyy-MM>[__<versiyon>]`, `bordro_...` vb.)
/// dokümanlar tutulur; içerik `j` alanında JSON metni olarak durur.
/// Bu sayede:
///  - yerel yedek JSON'u değişmeden buluta yüklenebilir (ve tersi),
///  - eski uygulamanın aynı Firebase projesindeki koleksiyonlarıyla
///    (shifts, personnel, admins …) hiçbir çakışma olmaz.
class FirestoreServis implements VeriServisi, YedeklenebilirServis {
  FirestoreServis({FirebaseFirestore? veritabani})
      : _db = veritabani ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _kol =>
      _db.collection('nobet_pro');

  /// Açılışta bulut modunun gerçekten kullanılabilir olduğunu doğrular.
  ///
  /// `get()` varsayılan davranışı sunucuya ulaşamazsa önbelleğe düşmektir;
  /// dolayısıyla:
  ///  - çevrimiçi veya "çevrimdışı ama önbellekte veri var" → başarılı,
  ///  - ilk açılışta çevrimdışı (önbellek boş) → `unavailable` fırlatır,
  ///  - Firestore kuralları `nobet_pro` koleksiyonuna izin vermiyorsa →
  ///    `permission-denied` fırlatır.
  /// Çağıran taraf hata durumunda yerel moda düşer.
  Future<void> saglikKontrolu(String kurumId) =>
      _kol.doc(_kullaniciAnahtari(kurumId)).get();

  // --- anahtarlar (YerelServis ile aynı) -------------------------------------
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

  // --- ortak okuma/yazma -----------------------------------------------------
  Future<String?> _metinOku(String anahtar) async {
    final doc = await _kol.doc(anahtar).get();
    return doc.data()?['j'] as String?;
  }

  /// Kayıt yoksa null; bozuksa [VeriBozukHatasi] (boş sayılmaz).
  Future<Map<String, dynamic>?> _oku(String anahtar) async {
    final metin = await _metinOku(anahtar);
    if (metin == null || metin.isEmpty) return null;
    try {
      return jsonDecode(metin) as Map<String, dynamic>;
    } catch (_) {
      throw VeriBozukHatasi(anahtar);
    }
  }

  /// Kayıt yoksa boş liste; bozuksa [VeriBozukHatasi] (boş sayılmaz).
  Future<List<dynamic>> _okuListe(String anahtar) async =>
      _listeCoz(await _metinOku(anahtar), anahtar);

  List<dynamic> _listeCoz(String? metin, String anahtar) {
    if (metin == null || metin.isEmpty) return [];
    try {
      return List<dynamic>.of(jsonDecode(metin) as List<dynamic>);
    } catch (_) {
      throw VeriBozukHatasi(anahtar);
    }
  }

  /// Firestore doküman sınırı 1 MiB'tir; alan adları ve üst veri payı için
  /// JSON metni bunun altında tutulur.
  static const int _enFazlaBayt = 1000000;

  Map<String, dynamic> _dokuman(String anahtar, Object deger) {
    final metin = jsonEncode(deger);
    final bayt = utf8.encode(metin).length;
    if (bayt > _enFazlaBayt) throw VeriCokBuyukHatasi(anahtar, bayt);
    return {'j': metin, 'g': FieldValue.serverTimestamp()};
  }

  Future<void> _yaz(String anahtar, Object deger) async =>
      _kol.doc(anahtar).set(_dokuman(anahtar, deger));

  /// Liste dokümanında "oku → değiştir → yaz" işlemini tek transaction'da
  /// yapar. İki cihaz aynı anda kaydederse biri diğerinin değişikliğini
  /// ezmez: çakışan transaction yeniden denenir ve güncel listeyi görür.
  /// [degistir] listeyi yerinde değiştirir; false dönerse yazılmaz.
  /// (Transaction sunucu gerektirir; çevrimdışıyken hata verir — sessizce
  /// eski veri üzerine yazmaktansa kullanıcı uyarılır.)
  Future<void> _listeGuncelle(
      String anahtar, bool Function(List<dynamic> liste) degistir) {
    final ref = _kol.doc(anahtar);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final liste = _listeCoz(snap.data()?['j'] as String?, anahtar);
      if (!degistir(liste)) return;
      tx.set(ref, _dokuman(anahtar, liste));
    });
  }

  /// Listede [idAlani] = [id] olan kaydı değiştirir, yoksa sona ekler.
  Future<void> _kayitKaydet(String anahtar, String idAlani, String id,
          Map<String, dynamic> kayit) =>
      _listeGuncelle(anahtar, (liste) {
        final i = liste.indexWhere((e) => e is Map && e[idAlani] == id);
        if (i == -1) {
          liste.add(kayit);
        } else {
          liste[i] = kayit;
        }
        return true;
      });

  /// Listeden [idAlani] = [id] olan kaydı siler. [bosKalabilir] false ise
  /// liste boşalacaksa hiçbir şey yazılmaz.
  Future<void> _kayitSil(String anahtar, String idAlani, String id,
          {bool bosKalabilir = true}) =>
      _listeGuncelle(anahtar, (liste) {
        liste.removeWhere((e) => e is Map && e[idAlani] == id);
        return bosKalabilir || liste.isNotEmpty;
      });

  /// Doküman kimliği [onEk] ile başlayan tüm kayıtlar.
  Future<Map<String, String>> _onEkleOku(String onEk) async {
    final snap = await _kol
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: onEk)
        .where(FieldPath.documentId, isLessThan: '$onEk\uf8ff')
        .get();
    return {
      for (final d in snap.docs)
        if (d.data()['j'] is String) d.id: d.data()['j'] as String,
    };
  }

  // --- KURUM AYARI -----------------------------------------------------------
  @override
  Future<KurumAyari> kurumAyariGetir(String kurumId) async {
    final harita = await _oku(_kurumAnahtari(kurumId));
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
      (await _okuListe(_personelAnahtari(kurumId))).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return Personel.haritadan((m['id'] ?? '') as String, m);
      }).toList();

  @override
  Future<List<Personel>> personelleriGetir(String kurumId) async =>
      (await _tumPersoneller(kurumId))
          .where((p) => p.aktif && p.id.isNotEmpty)
          .toList()
        ..sort((a, b) => a.sira.compareTo(b.sira));

  @override
  Future<void> personelKaydet(String kurumId, Personel personel) =>
      _kayitKaydet(_personelAnahtari(kurumId), 'id', personel.id,
          {'id': personel.id, ...personel.haritasi});

  @override
  Future<void> personelSil(String kurumId, String personelId) =>
      _kayitSil(_personelAnahtari(kurumId), 'id', personelId);

  // --- AY KAYDI --------------------------------------------------------------
  @override
  Future<AyKaydi> ayKaydiGetir(String kurumId, int yil, int ay,
      {String versiyon = ''}) async {
    final harita = await _oku(_donemAnahtari(kurumId, yil, ay, versiyon));
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
      await _listeGuncelle(_versiyonAnahtari(kurumId, kayit.yil, kayit.ay),
          (liste) {
        if (liste.contains(kayit.versiyon)) return false;
        liste
          ..add(kayit.versiyon)
          ..sort((a, b) => a.toString().compareTo(b.toString()));
        return true;
      });
    }
  }

  @override
  Future<List<String>> versiyonlariGetir(
          String kurumId, int yil, int ay) async =>
      kListeVersiyonlari;

  @override
  Future<void> versiyonSil(
          String kurumId, int yil, int ay, String versiyon) async =>
      _kol.doc(_donemAnahtari(kurumId, yil, ay, versiyon)).delete();

  // --- DUYURU ----------------------------------------------------------------
  @override
  Future<List<Duyuru>> duyurulariGetir(String kurumId) async =>
      (await _okuListe(_duyuruAnahtari(kurumId))).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return Duyuru.haritadan((m['id'] ?? '') as String, m);
      }).toList()
        ..sort((a, b) => b.tarih.compareTo(a.tarih));

  @override
  Future<void> duyuruKaydet(String kurumId, Duyuru duyuru) =>
      _kayitKaydet(_duyuruAnahtari(kurumId), 'id', duyuru.id,
          {'id': duyuru.id, ...duyuru.haritasi});

  @override
  Future<void> duyuruSil(String kurumId, String duyuruId) =>
      _kayitSil(_duyuruAnahtari(kurumId), 'id', duyuruId);

  // --- DUYURU OKUMA ----------------------------------------------------------
  String _duyuruOkumaAnahtari(String kurumId, String uid) =>
      'duyuruokuma_${kurumId}_$uid';

  @override
  Future<Map<String, DateTime>> duyuruOkumalariniGetir(
          String kurumId, String uid) async =>
      duyuruOkumaCoz(await _oku(_duyuruOkumaAnahtari(kurumId, uid)));

  @override
  Future<void> duyuruOkumalariniKaydet(
          String kurumId, String uid, Map<String, DateTime> okumalar) =>
      _yaz(_duyuruOkumaAnahtari(kurumId, uid), duyuruOkumaYaz(okumalar));

  @override
  Future<Map<String, Map<String, DateTime>>> tumDuyuruOkumalari(
      String kurumId) async {
    final onEk = 'duyuruokuma_${kurumId}_';
    final ham = await _onEkleOku(onEk);
    final sonuc = <String, Map<String, DateTime>>{};
    for (final e in ham.entries) {
      try {
        sonuc[e.key.substring(onEk.length)] =
            duyuruOkumaCoz(jsonDecode(e.value));
      } catch (_) {}
    }
    return sonuc;
  }

  // --- KULLANICI -------------------------------------------------------------
  Future<List<Kullanici>> _kullanicilariOku(String kurumId) async =>
      (await _okuListe(_kullaniciAnahtari(kurumId)))
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return Kullanici.haritadan((m['uid'] ?? '') as String, m);
          })
          .where((k) => k.uid.isNotEmpty)
          .toList();

  @override
  Future<List<Kullanici>> kullanicilariGetir(String kurumId) async {
    final liste = await _kullanicilariOku(kurumId);
    if (liste.isNotEmpty) return liste;

    // İlk açılış: varsayılan yönetici oluştur. Transaction içinde ve yalnızca
    // liste hâlâ boşsa — iki cihaz aynı anda açılırsa biri diğerinin
    // oluşturduğu (ve belki hemen düzenlediği) yöneticiyi ezmez.
    final varsayilan = Kullanici(
      uid: 'yonetici',
      ad: 'Yönetici',
      eposta: '',
      rol: Rol.yonetici,
      kurumId: kurumId,
    );
    await _listeGuncelle(_kullaniciAnahtari(kurumId), (l) {
      if (l.isNotEmpty) return false;
      l.add({'uid': varsayilan.uid, ...varsayilan.haritasi});
      return true;
    });
    return _kullanicilariOku(kurumId);
  }

  @override
  Future<void> kullaniciKaydet(String kurumId, Kullanici kullanici) =>
      _kayitKaydet(_kullaniciAnahtari(kurumId), 'uid', kullanici.uid,
          {'uid': kullanici.uid, ...kullanici.haritasi});

  @override
  Future<void> kullaniciSil(String kurumId, String uid) =>
      // Son kullanıcı silinemez.
      _kayitSil(_kullaniciAnahtari(kurumId), 'uid', uid, bosKalabilir: false);

  // --- BORDRO ----------------------------------------------------------------
  @override
  Future<BordroAyari> bordroAyariGetir(String kurumId, int yil) async {
    final harita = await _oku(_bordroAyarAnahtari(yil));
    if (harita == null) return BordroAyari(yil: yil);
    return BordroAyari.haritadan(yil, harita);
  }

  @override
  Future<void> bordroAyariKaydet(String kurumId, BordroAyari ayar) =>
      _yaz(_bordroAyarAnahtari(ayar.yil), ayar.haritasi);

  @override
  Future<List<PersonelUcreti>> personelUcretleriGetir(String birimId) async =>
      (await _okuListe(_ucretAnahtari(birimId)))
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return PersonelUcreti.haritadan(
                (m['personelId'] ?? '') as String, m);
          })
          .where((u) => u.personelId.isNotEmpty)
          .toList();

  @override
  Future<void> personelUcretiKaydet(String birimId, PersonelUcreti ucret) =>
      _kayitKaydet(_ucretAnahtari(birimId), 'personelId', ucret.personelId,
          ucret.haritasi);

  @override
  Future<void> personelUcretiSil(String birimId, String personelId) =>
      _kayitSil(_ucretAnahtari(birimId), 'personelId', personelId);

  @override
  Future<BordroSonucu?> bordroGetir(
      String birimId, String personelId, int yil, int ay) async {
    final harita = await _oku(_bordroAnahtari(birimId, personelId, yil, ay));
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
      _kol.doc(_bordroAnahtari(birimId, personelId, yil, ay)).delete();

  @override
  Future<List<BordroSonucu>> bordrolariGetir(String birimId,
      {int? yil, int? ay}) async {
    final kayitlar = await _onEkleOku('bordro_${birimId}_');
    final liste = <BordroSonucu>[];
    for (final metin in kayitlar.values) {
      try {
        final sonuc =
            BordroSonucu.haritadan(jsonDecode(metin) as Map<String, dynamic>);
        if (yil != null && sonuc.yil != yil) continue;
        if (ay != null && sonuc.ay != ay) continue;
        liste.add(sonuc);
      } catch (_) {
        // bozuk kayıt — atla
      }
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
  Future<void> bordroYukle(String birimId, YuklenmisBordro kayit) => _yaz(
        _bordroPdfAnahtari(birimId, kayit.personelId, kayit.yil, kayit.ay),
        kayit.haritasi,
      );

  @override
  Future<YuklenmisBordro?> bordroYuklemesiniGetir(
      String birimId, String personelId, int yil, int ay,
      {bool pdfDahil = true}) async {
    final harita =
        await _oku(_bordroPdfAnahtari(birimId, personelId, yil, ay));
    if (harita == null) return null;
    final kayit = YuklenmisBordro.haritadan(harita);
    return pdfDahil ? kayit : kayit.metaKopya();
  }

  @override
  Future<List<YuklenmisBordro>> birimBordroYuklemeleriniGetir(
      String birimId, {int? yil, int? ay}) async {
    final kayitlar = await _onEkleOku('bordro_pdf_${birimId}_');
    final liste = <YuklenmisBordro>[];
    for (final metin in kayitlar.values) {
      try {
        final kayit = YuklenmisBordro.haritadan(
            jsonDecode(metin) as Map<String, dynamic>).metaKopya();
        if (yil != null && kayit.yil != yil) continue;
        if (ay != null && kayit.ay != ay) continue;
        liste.add(kayit);
      } catch (_) {}
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
      _kol.doc(_bordroPdfAnahtari(birimId, personelId, yil, ay)).delete();

  // --- YEDEK -----------------------------------------------------------------
  /// [YerelServis.tumVeriyiDisaAktar] ile aynı JSON biçimini üretir —
  /// bulut yedeği yerel moda (veya tersine) geri yüklenebilir.
  @override
  Future<String> tumVeriyiDisaAktar() async {
    final hepsi = <String, dynamic>{};
    const onEkler = [
      'kurum_',
      'kullanicilar_',
      'personeller_',
      'versiyonlar_',
      'duyurular_',
      'duyuruokuma_',
      'nobet_',
      'bordro_',
      'bordro_pdf_',
      'ucretler_',
    ];
    for (final onEk in onEkler) {
      hepsi.addAll(await _onEkleOku(onEk));
    }
    return const JsonEncoder.withIndent('  ').convert({
      'surum': 1,
      'tarih': DateTime.now().toIso8601String(),
      'veri': hepsi,
    });
  }

  /// Yedekten geri yükler. Mevcut dokümanların üzerine yazılır.
  @override
  Future<void> yedektenYukle(String json) async {
    final harita = jsonDecode(json) as Map<String, dynamic>;
    final veri = Map<String, dynamic>.from(harita['veri'] as Map);

    // 500 işlem/batch Firestore sınırıdır; güvenli pay bırakılır.
    var grup = _db.batch();
    var sayac = 0;
    for (final girdi in veri.entries) {
      grup.set(_kol.doc(girdi.key), {
        'j': girdi.value.toString(),
        'g': FieldValue.serverTimestamp(),
      });
      if (++sayac % 400 == 0) {
        await grup.commit();
        grup = _db.batch();
      }
    }
    await grup.commit();
  }
}
