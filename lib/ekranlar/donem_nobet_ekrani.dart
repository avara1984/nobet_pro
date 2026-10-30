import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/dinlenme_kurali.dart';
import '../core/donem_araligi.dart';
import '../core/haftalik_ozet.dart';
import '../core/kapsama_motoru.dart';
import '../core/tarih.dart';
import '../core/tema.dart';
import '../durum/nobet_durumu.dart';
import '../modeller/modeller.dart';
import '../servisler/pdf_servis.dart';
import 'yayin_uyarisi.dart';

/// "15 - 14 Nöbet" ekranı — ayın 15'inden bir sonraki ayın 14'üne kadar
/// (bordro dönemiyle aynı sınırlar, bkz. `core/donem_araligi.dart`) süren
/// dönemi Nöbet Listesi'ndeki gibi TEK, kesintisiz bir ızgarada gösterir
/// (Haftalık Nöbet'in aksine hafta bloklarına ayrılmaz).
///
/// Haftalık Nöbet ile aynı çok-aylık okuma/yazma yapısını kullanır (iki
/// ayın `AyKaydi`'si aynı anda belleğe alınır, her biri kendi kilidine
/// tabidir) — ekranın içindeki sekmeyle "Onaylanan Liste" veya "Aylık
/// Normal Şablon" arasında geçiş yapılır, üst çubuktaki versiyon
/// seçicisinden bağımsızdır.
///
/// v1 kapsam dışı (bilinçli, Haftalık Nöbet'in ilk sürümündeki gibi):
/// "Liste Yap", Aylık Özet panelleri — gerekirse ayrıca istenebilir.
class DonemNobetEkrani extends StatefulWidget {
  const DonemNobetEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<DonemNobetEkrani> createState() => _DonemNobetEkraniState();
}

class _DonemNobetEkraniState extends State<DonemNobetEkrani> {
  final _yatayBaslik = ScrollController();
  final _yatayGovde = ScrollController();

  static const double _satirY = 27;
  static const double _baslikY = 37;
  static const double _tarihW = 85;
  static const double _gunW = 75;
  static const double _personelW = 85;
  static const double _durumW = 58;

  /// Ekran içindeki sekmeyle seçilen versiyon — üst çubuktaki versiyon
  /// seçicisinden BAĞIMSIZ. Haftalık Nöbet ekranıyla aynı desen.
  String _versiyon = kVersiyonOnayli;

  int? _yuklenenYil;
  int? _yuklenenAy;
  Birim? _yuklenenBirim;
  String? _yuklenenVersiyon;
  bool _yukleniyor = false;

  /// 'yyyy-MM' → o ayın AyKaydi'si. Dönem en fazla 2 farklı aya değer.
  final Map<String, AyKaydi> _kayitlar = {};
  final Map<String, Madde3Motoru> _motorlar = {};
  final Set<String> _kirliAylar = {};

  /// Geri alma yığını: her düzenlemeden önce ilgili ayın TÜM atamalar
  /// haritasının bir kopyası buraya itilir. `NobetDurumu._gecmis` ile aynı
  /// mantık — burada ayrıca hangi ayın (`anahtar`) etkilendiği de saklanır
  /// çünkü ekran aynı anda iki farklı `AyKaydi` üzerinde çalışabiliyor.
  final List<(String anahtar, Map<String, String> onceki)> _gecmis = [];
  static const int _gecmisSiniri = 40;

  @override
  void initState() {
    super.initState();
    _yatayGovde.addListener(() {
      if (_yatayBaslik.hasClients &&
          _yatayBaslik.offset != _yatayGovde.offset) {
        _yatayBaslik.jumpTo(_yatayGovde.offset);
      }
    });
  }

  @override
  void dispose() {
    _yatayBaslik.dispose();
    _yatayGovde.dispose();
    super.dispose();
  }

  void _bilgi(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), width: 380));

  Future<void> _yukleGerekirse(NobetDurumu d) async {
    if (_yuklenenYil == d.yil &&
        _yuklenenAy == d.ay &&
        _yuklenenBirim == d.birim &&
        _yuklenenVersiyon == _versiyon) {
      return;
    }
    _yuklenenYil = d.yil;
    _yuklenenAy = d.ay;
    _yuklenenBirim = d.birim;
    _yuklenenVersiyon = _versiyon;

    setState(() => _yukleniyor = true);

    final aylar = {donemBaslangicAyi(d.yil, d.ay), donemBitisAyi(d.yil, d.ay)};

    _kayitlar.clear();
    _motorlar.clear();
    _kirliAylar.clear();
    _gecmis.clear();
    for (final (yil, ay) in aylar) {
      final kayit = await d.servis
          .ayKaydiGetir(d.birimId, yil, ay, versiyon: _versiyon);
      _kayitlar[T.donemAnahtari(yil, ay)] = kayit;
    }

    if (!mounted) return;
    setState(() => _yukleniyor = false);
  }

  AyKaydi? _kayitIcin(DateTime tarih) =>
      _kayitlar[T.donemAnahtari(tarih.year, tarih.month)];

  Madde3Motoru _motorIcin(NobetDurumu d, DateTime tarih) {
    final anahtar = T.donemAnahtari(tarih.year, tarih.month);
    final onbellek = _motorlar[anahtar];
    if (onbellek != null) return onbellek;
    final kayit = _kayitlar[anahtar]!;
    final gunSayisi = DateTime(tarih.year, tarih.month + 1, 0).day;
    final motor = Madde3Motoru(
      ayar: d.ayar,
      personeller: d.personeller,
      kayit: kayit,
      gunSayisi: gunSayisi,
      birim: d.birim,
    );
    _motorlar[anahtar] = motor;
    return motor;
  }

  void _ayKirletVeMotoruAt(DateTime tarih) {
    final anahtar = T.donemAnahtari(tarih.year, tarih.month);
    _kirliAylar.add(anahtar);
    _motorlar.remove(anahtar);
  }

  /// Bir hücreyi değiştirmeden ÖNCE çağrılır — ilgili ayın o anki tüm
  /// atamalar haritasının bir kopyasını yığına iter.
  void _oncekiHaliniKaydet(DateTime tarih) {
    final anahtar = T.donemAnahtari(tarih.year, tarih.month);
    final kayit = _kayitlar[anahtar];
    if (kayit == null) return;
    _gecmis.add((anahtar, Map<String, String>.from(kayit.atamalar)));
    if (_gecmis.length > _gecmisSiniri) _gecmis.removeAt(0);
  }

  bool get _geriAlinabilir => _gecmis.isNotEmpty;

  void _geriAl() {
    if (_gecmis.isEmpty) return;
    final (anahtar, onceki) = _gecmis.removeLast();
    final kayit = _kayitlar[anahtar];
    if (kayit == null) return;
    kayit.atamalar
      ..clear()
      ..addAll(onceki);
    _kirliAylar.add(anahtar);
    _motorlar.remove(anahtar);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();

    if (d.sadecePdf) {
      return const Center(
        child: Text('Bu ekrana erişim yetkiniz yok.',
            style: TextStyle(color: R.gri)),
      );
    }

    if (_yuklenenYil != d.yil ||
        _yuklenenAy != d.ay ||
        _yuklenenBirim != d.birim ||
        _yuklenenVersiyon != _versiyon) {
      _yukleGerekirse(d);
    }

    return Padding(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _versiyonSekmeleri(),
          SizedBox(height: widget.genis ? 6 : 4),
          Expanded(child: _icerik(d)),
        ],
      ),
    );
  }

  /// Ekranın hangi versiyona bağlı çalıştığını gösteren kısa başlık.
  String get _ekranBaslik => switch (_versiyon) {
        kVersiyonOnayli => 'Onaylanan Listeye Göre 15 - 14 Nöbet',
        kVersiyonSablon => 'Aylık Normal Şablona Göre 14 - 15 Nöbet',
        _ => '15 - 14 Nöbet',
      };

  /// Ekranın en üstündeki, "Onaylanan Liste" / "Aylık Normal Şablon"
  /// arasında geçiş yapan sekme çifti — Haftalık Nöbet ekranıyla aynı
  /// görsel dil.
  Widget _versiyonSekmeleri() {
    Widget dugme(String v, String etiket) {
      final aktif = _versiyon == v;
      return InkWell(
        onTap: aktif ? null : () => setState(() => _versiyon = v),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: aktif ? R.mavi : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(etiket,
              style: TextStyle(
                fontSize: 12,
                fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
                color: aktif ? Colors.white : R.gri,
              )),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Tema.kenar(context)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          dugme(kVersiyonOnayli, 'Onaylanan Listeye Göre 15 - 14 Nöbet'),
          dugme(kVersiyonSablon, 'Aylık Normal Şablona Göre 14 - 15 Nöbet'),
        ],
      ),
    );
  }

  Widget _icerik(NobetDurumu d) {
    if (_yukleniyor || _kayitlar.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (d.personeller.isEmpty) {
      return const Center(
        child: Text('Kayıtlı personel yok',
            style: TextStyle(fontSize: 15, color: R.gri)),
      );
    }

    // Personel (izleyici) görünümünde, dönemi oluşturan İKİ ayın "Onaylanan
    // Liste"si de yayında değilse gösterilmez.
    if (d.personelGorunumu) {
      final hepsiYayinda =
          _kayitlar.values.every((k) => k.yayinda) && _kayitlar.isNotEmpty;
      if (!hepsiYayinda) return _yayinlanmadiEkrani();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _baslikCubugu(d),
        SizedBox(height: widget.genis ? 6 : 4),
        Expanded(child: _tablo(d)),
        const SizedBox(height: 10),
        _altCubuk(),
      ],
    );
  }

  Widget _yayinlanmadiEkrani() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: R.gri),
              SizedBox(height: 20),
              Text(
                'Bu Dönemin Nöbet Listesi Henüz Yayınlanmamıştır.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              SizedBox(height: 6),
              Text(
                'Liste Onaylandığında Buradan Görebilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(color: R.gri, fontSize: 13),
              ),
            ],
          ),
        ),
      );

  static const _kutuZemin = Color(0xFFE3F2FA);
  static const _kutuKenar = Color(0xFFA9DCEF);

  static final ButtonStyle _kompaktCerceve = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    side: const BorderSide(color: Color(0xFF00C853), width: 1.5),
  );

  static final ButtonStyle _kompaktDolgu = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    side: const BorderSide(color: Color(0xFF00C853), width: 1.5),
  );

  /// Bir personelin dönem genelindeki (iki ayı da kapsayan) toplam
  /// çalışma saati — `haftalikToplamSaat` tarih listesi konusunda tarafsız
  /// olduğu için burada da aynen kullanılabiliyor.
  double _kisiToplamSaat(NobetDurumu d, String personelId) =>
      haftalikToplamSaat(
        haftaGunleri: donemGunleri(d.yil, d.ay),
        ayar: d.ayar,
        personelId: personelId,
        kayitBul: (t) => _kayitIcin(t) ?? AyKaydi(yil: t.year, ay: t.month),
      );

  /// Dönemin HEDEF normal çalışma saati — `NobetDurumu.aylikHedefSaat` ile
  /// aynı hesap (Pazar/resmi tatil hariç her gün 7.5 saat, yarım günler
  /// 3.5), yalnızca takvim ayı yerine 15-14 dönemi üzerinden. Personel
  /// sayısından bağımsız TEK bir kurum hedefidir — Aylık Özet'teki
  /// "X Ayı Çalışma: N Saat" ile aynı anlam.
  double _toplamCalismaSaati(NobetDurumu d) {
    var toplam = 0.0;
    for (final tarih in donemGunleri(d.yil, d.ay)) {
      if (tarih.weekday == DateTime.sunday) continue;
      if (d.ayar.resmiTatilMi(tarih)) continue;
      toplam += d.ayar.yarimGunMu(tarih) ? 3.5 : 7.5;
    }
    return toplam;
  }

  Widget _baslikCubugu(NobetDurumu d) {
    final baslik = Row(
      children: [
        const Icon(Icons.date_range_outlined, size: 20, color: R.maviKoyu),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$_ekranBaslik  (${donemBasligi(d.yil, d.ay)})',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final butonlar = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (d.personelGorunumu)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_outlined, size: 15, color: R.gri),
                SizedBox(width: 6),
                Text('Sadece görüntüleme',
                    style: TextStyle(fontSize: 12, color: R.gri)),
              ],
            ),
          )
        else
          FilledButton.icon(
            style: _kompaktDolgu,
            onPressed: _kirliAylar.isEmpty ? null : () => _kaydet(d),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: Text(_kirliAylar.isEmpty ? 'Kaydet' : 'Kaydet *'),
          ),
        if (d.personelGorunumu)
          Tooltip(
            message: 'PDF indirme yetkiniz yok.',
            child: OutlinedButton.icon(
              style: _kompaktCerceve,
              onPressed: null,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('PDF İndir'),
            ),
          )
        else
          OutlinedButton.icon(
            style: _kompaktCerceve,
            onPressed: () => _pdf(d),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('PDF İndir'),
          ),
        if (!d.personelGorunumu)
          OutlinedButton.icon(
            style: _kompaktCerceve,
            onPressed: _geriAlinabilir && d.duzenleyebilir
                ? () {
                    _geriAl();
                    _bilgi('İşlem geri alındı.');
                  }
                : null,
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Geri Al'),
          ),
        OutlinedButton.icon(
          style: _kompaktCerceve,
          onPressed: () => _onizlemeGoster(d),
          icon: const Icon(Icons.visibility_outlined, size: 16),
          label: const Text('Önizle'),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF00C853), width: 1.5),
          ),
          child: Text(
            'Toplam Çalışma: ${_toplamCalismaSaati(d).toStringAsFixed(1)} Saat',
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: R.maviKoyu),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: _kutuZemin,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kutuKenar),
      ),
      child: widget.genis
          ? Row(
              children: [
                Expanded(child: baslik),
                const SizedBox(width: 12),
                butonlar,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                baslik,
                const SizedBox(height: 8),
                butonlar,
              ],
            ),
    );
  }

  Widget _altCubuk() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tema.kenar(context)),
      ),
      child: const Text(
        'Yukarıdaki sekmeden "Onaylanan Liste" veya "Aylık Normal Şablon" '
        'seçilebilir; ekran ayın 15\'inden bir sonraki ayın 14\'üne kadarki '
        'dönemi gösterir. Kayıtlar ilgili ayın kendi listesine yazılır. '
        'Kilitli (yayında) aylardaki hücreler değiştirilemez.',
        style: TextStyle(fontSize: 11.5, color: R.gri, height: 1.4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _tablo(NobetDurumu d,
      {ScrollController? baslikCtrl, ScrollController? govdeCtrl}) {
    final personeller = d.personeller;
    final kayanW = _gunW + personeller.length * _personelW + _durumW;
    final gunler = donemGunleri(d.yil, d.ay);
    final bCtrl = baslikCtrl ?? _yatayBaslik;
    final gCtrl = govdeCtrl ?? _yatayGovde;

    if (personeller.isEmpty) {
      return const Center(
        child: Text('Kayıtlı personel yok', style: TextStyle(color: R.gri)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cizgi(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: _baslikY,
            child: Row(
              children: [
                _baslikHucre('Tarih', _tarihW),
                Expanded(
                  child: SingleChildScrollView(
                    controller: bCtrl,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: kayanW,
                      child: Row(
                        children: [
                          _baslikHucre('Günler', _gunW),
                          for (final p in personeller)
                            _personelBaslikHucre(p, _personelW),
                          _baslikHucre('Durum', _durumW,
                              kenarRengi: Colors.black),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1.5, color: _cizgi(context)),
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      for (final tarih in gunler) _tarihHucresi(d, tarih),
                      _ozetTarihHucresi(),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: gCtrl,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: kayanW,
                        child: Column(
                          children: [
                            for (final tarih in gunler)
                              _gunSatiri(d, tarih, personeller),
                            _toplamSatiri(d, personeller),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tablo iç çizgileri — belirgin, sabit kontrastlı (Tema.kenar bu yoğun
  /// ızgarada neredeyse görünmüyordu).
  Color _cizgi(BuildContext c) {
    final koyu = Theme.of(c).brightness == Brightness.dark;
    return koyu ? Colors.white30 : const Color(0xFFB9C0CC);
  }

  /// Dönemin iki ayı arasındaki sınır (14→15 geçişi) kalın kırmızı bir
  /// çizgiyle vurgulanır — Haftalık Nöbet'teki hafta sınırıyla aynı dil.
  Color _ayGecisSiniri(BuildContext c) {
    final koyu = Theme.of(c).brightness == Brightness.dark;
    return koyu ? R.kirmizi.withValues(alpha: .7) : R.kirmizi;
  }

  bool _ayGecisBasiMi(DateTime tarih) => tarih.day == 1;

  Widget _tarihHucresi(NobetDurumu d, DateTime tarih) {
    final tatil = d.ayar.resmiTatilMi(tarih);
    final ustSinir = _ayGecisBasiMi(tarih);
    return _metinHucre(
      T.tarih(tarih),
      _tarihW,
      kalin: true,
      vurgu: T.haftaSonu(tarih),
      tatil: tatil,
      yarimGun: !tatil && d.ayar.yarimGunMu(tarih),
      ayGecisi: ustSinir,
      ikon:
          tatil ? Icons.star : (d.ayar.yarimGunMu(tarih) ? Icons.star_half : null),
    );
  }

  Widget _gunSatiri(NobetDurumu d, DateTime tarih, List<Personel> personeller) {
    final haftaSonuMu = T.haftaSonu(tarih);
    final tatil = d.ayar.resmiTatilMi(tarih);
    final yarim = !tatil && d.ayar.yarimGunMu(tarih);
    final ustSinir = _ayGecisBasiMi(tarih);
    return SizedBox(
      height: _satirY,
      child: Row(
        children: [
          _metinHucre(T.gunAdi(tarih), _gunW,
              kalin: true,
              vurgu: haftaSonuMu,
              tatil: tatil,
              yarimGun: yarim,
              ayGecisi: ustSinir),
          for (final p in personeller)
            _vardiyaHucre(d, tarih, p,
                vurgu: haftaSonuMu,
                tatil: tatil,
                yarimGun: yarim,
                ayGecisi: ustSinir),
          _durumHucre(d, tarih,
              vurgu: haftaSonuMu, tatil: tatil, yarimGun: yarim, ayGecisi: ustSinir),
        ],
      ),
    );
  }

  /// Sol sabit sütunun en altındaki boş hücre — sağdaki [_toplamSatiri] ile
  /// aynı hizada durur ("Toplam" etiketi o satırın Günler hücresinde).
  Widget _ozetTarihHucresi() => Container(
        width: _tarihW,
        height: _satirY,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: R.mavi.withValues(alpha: .14),
          border: Border(
            right: BorderSide(color: _cizgi(context)),
            top: BorderSide(color: _ayGecisSiniri(context), width: 2),
          ),
        ),
      );

  /// Dönemin sonunda, her personel sütununun altında toplam çalışma
  /// saatini gösteren tek satır — resimde işaretlenen "personelin toplam
  /// çalışma saatleri herkesin altında olacak" isteği.
  Widget _toplamSatiri(NobetDurumu d, List<Personel> personeller) {
    final sinir = BorderSide(color: _ayGecisSiniri(context), width: 2);
    return Container(
      height: _satirY,
      decoration: BoxDecoration(
        color: R.mavi.withValues(alpha: .14),
        border: Border(top: sinir),
      ),
      child: Row(
        children: [
          Container(
            width: _gunW,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: _cizgi(context))),
            ),
            child: const Text('Toplam',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: R.kirmizi)),
          ),
          for (final p in personeller)
            Container(
              width: _personelW,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: _cizgi(context))),
              ),
              child: Text(
                _kisiToplamSaat(d, p.id).toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: R.kirmizi),
              ),
            ),
          Container(
            width: _durumW,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Colors.black, width: 1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _baslikHucre(String metin, double w, {Color? kenarRengi}) => Container(
        width: w,
        height: _baslikY,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Tema.tabloBaslik(context),
          border:
              Border(right: BorderSide(color: kenarRengi ?? _cizgi(context))),
        ),
        child: Text(metin,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  (String, String) _adSoyadAyir(String tamAd) {
    final t = tamAd.trim();
    final i = t.lastIndexOf(' ');
    if (i == -1) return (t, '');
    return (t.substring(0, i), t.substring(i + 1));
  }

  Widget _personelBaslikHucre(Personel p, double w) {
    final (ad, soyad) = _adSoyadAyir(p.ad);
    const stil =
        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.1);
    return Container(
      width: w,
      height: _baslikY,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Tema.tabloBaslik(context),
        border: Border(right: BorderSide(color: _cizgi(context))),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: stil),
          if (soyad.isNotEmpty)
            Text(soyad,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: stil),
        ],
      ),
    );
  }

  Color? _satirZemini(bool vurgu, {bool tatil = false, bool yarimGun = false}) {
    final koyu = Theme.of(context).brightness == Brightness.dark;
    if (tatil) {
      return koyu ? R.kirmizi.withValues(alpha: .16) : const Color(0xFFFDE7E7);
    }
    if (yarimGun) {
      return koyu ? R.turuncu.withValues(alpha: .15) : const Color(0xFFFFF2DC);
    }
    if (vurgu) {
      return koyu
          ? Colors.white.withValues(alpha: .06)
          : const Color(0xFFE9EBF0);
    }
    return null;
  }

  Widget _metinHucre(String metin, double w,
      {bool kalin = false,
      bool vurgu = false,
      bool tatil = false,
      bool yarimGun = false,
      bool ayGecisi = false,
      IconData? ikon}) {
    final yazi = Text(metin,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12, fontWeight: kalin ? FontWeight.w600 : FontWeight.w400));

    return Container(
      width: w,
      height: _satirY,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _satirZemini(vurgu, tatil: tatil, yarimGun: yarimGun),
        border: Border(
          right: BorderSide(color: _cizgi(context)),
          bottom: BorderSide(color: _cizgi(context)),
          top: ayGecisi
              ? BorderSide(color: _ayGecisSiniri(context), width: 2)
              : BorderSide.none,
        ),
      ),
      child: ikon == null
          ? yazi
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: yazi),
                const SizedBox(width: 3),
                Icon(ikon, size: 11, color: tatil ? R.kirmizi : R.turuncu),
              ],
            ),
    );
  }

  Widget _vardiyaHucre(NobetDurumu d, DateTime tarih, Personel p,
      {bool vurgu = false,
      bool tatil = false,
      bool yarimGun = false,
      bool ayGecisi = false}) {
    final kayit = _kayitIcin(tarih);
    final kod = kayit?.kod(tarih.day, p.id) ?? '';
    final kilitli = kayit?.yayinda ?? false;
    final duzenlenebilir = d.duzenleyebilir && !kilitli;

    final gorunen = kod.isEmpty ? kNobetIzni : d.ayar.vardiyaBul(kod).etiket;
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final boya = vardiyaBoyasi(kod.isEmpty ? kNobetIzni : kod, koyu: koyu);

    return InkWell(
      onTap: duzenlenebilir ? () => _vardiyaSec(d, tarih, p) : null,
      onLongPress: duzenlenebilir
          ? () {
              _oncekiHaliniKaydet(tarih);
              kayit!.ata(tarih.day, p.id, '');
              _ayKirletVeMotoruAt(tarih);
              setState(() {});
            }
          : null,
      child: Container(
        width: _personelW,
        height: _satirY,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _satirZemini(vurgu, tatil: tatil, yarimGun: yarimGun),
          border: Border(
            right: BorderSide(color: _cizgi(context)),
            bottom: BorderSide(color: _cizgi(context)),
            top: ayGecisi
                ? BorderSide(color: _ayGecisSiniri(context), width: 2)
                : BorderSide.none,
          ),
        ),
        child: boya.rozet
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                decoration: BoxDecoration(
                  color: boya.zemin,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  gorunen,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: boya.yazi),
                ),
              )
            : Text(
                gorunen,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                  color: boya.yazi,
                ),
              ),
      ),
    );
  }

  Widget _durumHucre(NobetDurumu d, DateTime tarih,
      {bool vurgu = false,
      bool tatil = false,
      bool yarimGun = false,
      bool ayGecisi = false}) {
    final motor = _motorIcin(d, tarih);
    final k = motor.gunDurumu(tarih.day, tarih.year, tarih.month);
    final (ikon, renk) = switch (k.durum) {
      GercekDurum.tamam => (Icons.check, R.yesil),
      GercekDurum.kadroEksik => (Icons.warning_amber_rounded, R.turuncu),
      GercekDurum.saatAcigi => (Icons.error_outline, R.kirmizi),
      GercekDurum.bosGun => (Icons.close, R.kirmizi),
    };
    return Container(
      width: _durumW,
      height: _satirY,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _satirZemini(vurgu, tatil: tatil, yarimGun: yarimGun),
        border: Border(
          right: const BorderSide(color: Colors.black, width: 1),
          bottom: BorderSide(color: _cizgi(context)),
          top: ayGecisi
              ? BorderSide(color: _ayGecisSiniri(context), width: 2)
              : BorderSide.none,
        ),
      ),
      child: Tooltip(
        message: k.mesaj,
        child: Icon(ikon, color: renk, size: 20),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EYLEMLER
  // ---------------------------------------------------------------------------

  String? _oncekiKod(DateTime tarih, String personelId) {
    final onceki = tarih.subtract(const Duration(days: 1));
    final kayit = _kayitIcin(onceki);
    return kayit?.kod(onceki.day, personelId);
  }

  Future<void> _vardiyaSec(NobetDurumu d, DateTime tarih, Personel p) async {
    final kayit = _kayitIcin(tarih);
    if (kayit == null) return;
    if (kayit.yayinda) {
      _bilgi('Bu ayın listesi YAYINDA olduğu için değişiklik yapılamaz.');
      return;
    }
    // Ekran hangi versiyonda çalışıyorsa (üst çubuktaki seçiciden bağımsız)
    // PIN kontrolü ona göre yapılır.
    if (_versiyon == kVersiyonOnayli &&
        !d.onaylananListeAcikMi &&
        !await _kilidiAc(d)) {
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('${p.ad} — ${T.tarih(tarih)} ${T.gunAdi(tarih)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              const Divider(height: 12),
              for (final v in d.ayar.vardiyalar)
                ListTile(
                  dense: true,
                  leading: Builder(builder: (ctx2) {
                    final boya = vardiyaBoyasi(v.kod,
                        koyu: Theme.of(ctx2).brightness == Brightness.dark);
                    return Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: boya.rozet ? boya.zemin : Colors.transparent,
                        border: Border.all(color: Tema.kenar(ctx2)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                  title: Text(v.etiket),
                  subtitle: v.calisiyor
                      ? Text('${v.kod} · ${T.sureMetni(v.sureDk)}')
                      : Text(v.kod),
                  trailing: kayit.kod(tarih.day, p.id) == v.kod
                      ? const Icon(Icons.check, color: R.yesil, size: 18)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);

                    if (v.kod == kYillikIzin || v.kod == kIdariIzin) {
                      final tatilGunu = tarih.weekday == DateTime.sunday ||
                          d.ayar.resmiTatilMi(tarih);
                      if (tatilGunu && mounted) {
                        await _tatilYIUyarisi(v.kod);
                        if (!mounted) return;
                      }
                    }

                    final uyari = dinlenmeIhlaliMetni(
                      personelAdi: p.ad,
                      oncekiKod: _oncekiKod(tarih, p.id),
                      yeniKod: v.kod,
                    );
                    if (uyari == null) {
                      _oncekiHaliniKaydet(tarih);
                      kayit.ata(tarih.day, p.id, v.kod);
                      _ayKirletVeMotoruAt(tarih);
                      setState(() {});
                      return;
                    }
                    final devam = await _ihlalOnayi(uyari);
                    if (devam == true) {
                      _oncekiHaliniKaydet(tarih);
                      kayit.ata(tarih.day, p.id, v.kod);
                      _ayKirletVeMotoruAt(tarih);
                      setState(() {});
                    }
                  },
                ),
              ListTile(
                dense: true,
                leading:
                    const Icon(Icons.backspace_outlined, size: 20, color: R.gri),
                title: const Text('Hücreyi temizle'),
                onTap: () {
                  _oncekiHaliniKaydet(tarih);
                  kayit.ata(tarih.day, p.id, '');
                  _ayKirletVeMotoruAt(tarih);
                  setState(() {});
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _kilidiAc(NobetDurumu d) async {
    final c = TextEditingController();
    final girilen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline, color: R.turuncu, size: 30),
        title: const Text('Onaylanan Liste'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Bu liste PIN korumalıdır. Değişiklik yapmak için 4 haneli '
              'kodu girin.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: c,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 10),
              decoration: const InputDecoration(counterText: ''),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Aç')),
        ],
      ),
    );

    if (girilen == null) return false;
    if (d.onayKoduDogruMu(girilen)) {
      d.kilidiAc();
      return true;
    }
    if (mounted) _bilgi('Şifre yanlış, tekrar deneyin.');
    return false;
  }

  Future<void> _tatilYIUyarisi(String kod) {
    final izinAdi = kod == kYillikIzin ? 'YILLIK İZİN' : 'İDARİ İZİN';
    final kisaAd = kod == kYillikIzin ? 'Y.İ.' : 'İ.İ.';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline, color: R.kirmizi, size: 30),
        title: Text('RESMİ TATİLLERDE $izinAdi SAYILMAZ'),
        content: Text(
          'Bu gün Pazar veya resmi tatil olduğu için $kisaAd olarak '
          'işaretlense bile ${kod == kYillikIzin ? 'yıllık izin hakkından' : 'çalışma saatinden'} '
          'düşülmez — zaten tatil günüdür. Kayıt yine de yapılacaktır.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }

  Future<bool?> _ihlalOnayi(String mesaj) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon:
            const Icon(Icons.warning_amber_rounded, color: R.kirmizi, size: 32),
        title: const Text('DİKKAT: NÖBET İHLALİ'),
        content: Text(mesaj, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: R.kirmizi),
            child: const Text('Yine de yaz (riskli)'),
          ),
        ],
      ),
    );
  }

  Future<void> _kaydet(NobetDurumu d) async {
    if (_kirliAylar.isEmpty) return;
    setState(() => _yukleniyor = true);
    final kaydeden = context.read<OturumDurumu>().kullanici?.ad ?? '';
    final aktifAnahtar = T.donemAnahtari(d.yil, d.ay);
    var aktifAyKaydedildi = false;
    for (final anahtar in _kirliAylar.toList()) {
      final kayit = _kayitlar[anahtar];
      if (kayit == null) continue;
      kayit.guncelleme = DateTime.now();
      if (kaydeden.isNotEmpty) kayit.guncelleyen = kaydeden;
      await d.servis.ayKaydiKaydet(d.birimId, kayit);
      if (anahtar == aktifAnahtar) aktifAyKaydedildi = true;
    }
    _kirliAylar.clear();
    // Nöbet Listesi ekranı da Onaylanan Liste'yi gösteriyorsa aynı ayın
    // güncel hâlini görsün diye.
    if (aktifAyKaydedildi && d.aktifVersiyon == _versiyon) {
      await d.yenidenYukle();
    }
    if (!mounted) return;
    setState(() => _yukleniyor = false);
    _bilgi('15 - 14 Nöbet listesi kaydedildi.');
  }

  /// Ekranın kendi (henüz kaydedilmemiş olabilecek) `_kayitlar` haritasından
  /// okur — Haftalık PDF'teki gibi Önizleme'de görülen hâli birebir yansıtır.
  Future<void> _pdf(NobetDurumu d) async {
    if (!await d.onizlemeyeIzinVar()) {
      if (mounted) await yayinlanmadiUyarisiGoster(context);
      return;
    }
    if (!mounted) return;
    try {
      final gunler = donemGunleri(d.yil, d.ay);
      await PdfServis.onizleDonem(
        ayar: d.ayar,
        personeller: d.personeller,
        birim: d.birim,
        yil: d.yil,
        ay: d.ay,
        gunler: gunler,
        kodBul: (tarih, personelId) =>
            _kayitIcin(tarih)?.kod(tarih.day, personelId) ?? '',
        durumBul: (tarih) =>
            _motorIcin(d, tarih).gunDurumu(tarih.day, tarih.year, tarih.month),
        toplamSaatBul: (personelId) => _kisiToplamSaat(d, personelId),
      );
    } catch (e) {
      if (mounted) _bilgi('PDF oluşturulamadı: $e');
    }
  }

  Future<void> _onizlemeGoster(NobetDurumu d) async {
    if (!await d.onizlemeyeIzinVar()) {
      if (mounted) await yayinlanmadiUyarisiGoster(context);
      return;
    }
    if (!mounted) return;
    final baslikCtrl = ScrollController();
    final govdeCtrl = ScrollController();
    void senkronize() {
      if (baslikCtrl.hasClients && baslikCtrl.offset != govdeCtrl.offset) {
        baslikCtrl.jumpTo(govdeCtrl.offset);
      }
    }

    govdeCtrl.addListener(senkronize);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Tema.kart(context),
            foregroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black,
            elevation: 0,
            title: Text(
              '${d.ayar.ad} — ${donemBasligi(d.yil, d.ay)} · 15 - 14 Nöbet',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                tooltip: 'Kapat',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(10),
            child: LayoutBuilder(
              builder: (ctx, kisit) {
                final dogalGenislik =
                    _tarihW + _gunW + d.personeller.length * _personelW + _durumW;
                final genislik = dogalGenislik < kisit.maxWidth
                    ? dogalGenislik
                    : kisit.maxWidth;
                return Center(
                  child: SizedBox(
                    width: genislik,
                    child:
                        _tablo(d, baslikCtrl: baslikCtrl, govdeCtrl: govdeCtrl),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    govdeCtrl.removeListener(senkronize);
    baslikCtrl.dispose();
    govdeCtrl.dispose();
  }
}
