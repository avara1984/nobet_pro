import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/dinlenme_kurali.dart';
import '../core/hafta_araligi.dart';
import '../core/haftalik_ozet.dart';
import '../core/kapsama_motoru.dart';
import '../core/liste_doldur.dart' as ld;
import '../core/tarih.dart';
import '../core/tema.dart';
import '../durum/nobet_durumu.dart';
import '../modeller/modeller.dart';
import '../servisler/pdf_servis.dart';

/// Aylık ızgaranın Pazartesi–Pazar haftalara bölünmüş hâli. Seçilen ay
/// için bir önceki ayın son Pazartesi'sinden bir sonraki ayın ilk
/// Pazar'ına kadar (tam haftalara dolgulu) gösterir; aynı verinin
/// (AyKaydi) üzerinde çalışır — Nöbet Listesi ekranıyla aynı kaynak.
class HaftalikNobetEkrani extends StatefulWidget {
  const HaftalikNobetEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<HaftalikNobetEkrani> createState() => _HaftalikNobetEkraniState();
}

class _HaftalikNobetEkraniState extends State<HaftalikNobetEkrani> {
  final _yatayBaslik = ScrollController();
  final _yatayGovde = ScrollController();

  static const double _satirY = 27;
  static const double _baslikY = 37;
  static const double _tarihW = 85;
  static const double _gunW = 75;
  static const double _personelW = 90;
  static const double _durumW = 58;

  /// Ekran içindeki sekmeyle seçilen versiyon — üst çubuktaki versiyon
  /// seçicisinden BAĞIMSIZ. "Onaylanan Liste" ve "Aylık Normal Şablon"
  /// arasında ekran hiç değişmeden geçiş yapılabilir.
  String _versiyon = kVersiyonOnayli;

  int? _yuklenenYil;
  int? _yuklenenAy;
  Birim? _yuklenenBirim;
  String? _yuklenenVersiyon;
  bool _yukleniyor = false;

  /// 'yyyy-MM' → o ayın AyKaydi'si. Seçilen ay ve komşu iki ay (toplam
  /// en fazla 3 farklı ay — dolgu haftaları başka bir aya taşmadığı
  /// sürece) burada tutulur.
  final Map<String, AyKaydi> _kayitlar = {};
  final Map<String, Madde3Motoru> _motorlar = {};
  final Set<String> _kirliAylar = {};

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

  /// Ekranın hangi versiyona bağlı çalıştığını gösteren kısa başlık.
  String get _ekranBaslik => switch (_versiyon) {
        kVersiyonOnayli => 'Onaylanan Listeye Göre Haftalık Nöbet',
        kVersiyonSablon => 'Aylık Normal Şablona Göre Haftalık Nöbet',
        _ => 'Haftalık Nöbet',
      };

  /// Ekranın en üstündeki, "Onaylanan Liste" / "Aylık Normal Şablon"
  /// arasında geçiş yapan sekme çifti — yan menüde tek bir "Haftalık
  /// Nöbet" girişi var, seçim burada, ekranın içinde yapılıyor.
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
          dugme(kVersiyonOnayli, 'Onaylanan Listeye Göre Haftalık Nöbet'),
          dugme(kVersiyonSablon, 'Aylık Normal Şablona Göre Haftalık Nöbet'),
        ],
      ),
    );
  }

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

    final haftalar = haftalikGunler(d.yil, d.ay);
    final aylar = <(int, int)>{};
    for (final hafta in haftalar) {
      for (final g in hafta) {
        aylar.add((g.year, g.month));
      }
    }

    _kayitlar.clear();
    _motorlar.clear();
    _kirliAylar.clear();
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

    // Personel (izleyici) görünümünde, seçilen ayın "Onaylanan Liste"si
    // henüz yayında değilse gösterilmez — aylık ekranla aynı kural.
    if (d.personelGorunumu) {
      final aktifKayit = _kayitlar[T.donemAnahtari(d.yil, d.ay)];
      if (aktifKayit == null || !aktifKayit.yayinda) {
        return _yayinlanmadiEkrani();
      }
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
                'Bu Ayın Nöbet Listesi Henüz Yayınlanmamıştır.',
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

  Widget _baslikCubugu(NobetDurumu d) {
    final haftalar = haftalikGunler(d.yil, d.ay);
    final ilk = haftalar.first.first;
    final son = haftalar.last.last;

    final baslik = Row(
      children: [
        const Icon(Icons.view_week_outlined, size: 20, color: R.maviKoyu),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${T.ayYil(d.yil, d.ay)} — $_ekranBaslik  '
            '(${T.tarih(ilk)} – ${T.tarih(son)})',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    // Personel (izleyici) görünümünde yalnızca "Önizleme" var — PDF indirme
    // aylık ekrandaki gibi yetkisiz, Liste Yap/Kaydet ise düzenleme aracı
    // olduğu için hiç gösterilmez.
    final butonlar = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!d.personelGorunumu)
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
        if (d.personelGorunumu)
          Tooltip(
            message: 'PDF indirme yetkiniz yok.',
            child: OutlinedButton.icon(
              style: _kompaktCerceve,
              onPressed: null,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Haftalık PDF İndir'),
            ),
          )
        else
          OutlinedButton.icon(
            style: _kompaktCerceve,
            onPressed: () => _pdfHaftalik(d),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Haftalık PDF İndir'),
          ),
        if (!d.personelGorunumu)
          OutlinedButton.icon(
            style: _kompaktCerceve,
            onPressed: d.duzenleyebilir ? () => _listeYap(d) : null,
            icon: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: const Text('Liste Yap'),
          ),
        OutlinedButton.icon(
          style: _kompaktCerceve,
          onPressed: () => _onizlemeGoster(d),
          icon: const Icon(Icons.visibility_outlined, size: 16),
          label: const Text('Önizleme'),
        ),
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
          OutlinedButton.icon(
            style: _kompaktCerceve,
            onPressed: _kirliAylar.isEmpty
                ? null
                : () {
                    _yuklenenYil = -1;
                    _yukleGerekirse(d);
                  },
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Geri Al'),
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
        'Önceki/sonraki aydan taşan günler de düzenlenebilir; kayıtlar '
        'ilgili ayın kendi listesine yazılır. Kilitli (yayında/onaylı) '
        'aylardaki hücreler değiştirilemez.',
        style: TextStyle(fontSize: 11.5, color: R.gri, height: 1.4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _tablo(NobetDurumu d,
      {ScrollController? baslikCtrl, ScrollController? govdeCtrl}) {
    final personeller = d.personeller;
    final kayanW = _gunW + personeller.length * _personelW + _durumW;
    final haftalar = haftalikGunler(d.yil, d.ay);
    final bCtrl = baslikCtrl ?? _yatayBaslik;
    final gCtrl = govdeCtrl ?? _yatayGovde;

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
                      for (final hafta in haftalar) ...[
                        for (final tarih in hafta)
                          _tarihHucresi(d, tarih),
                        _ozetTarihHucresi(),
                      ],
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
                            for (final hafta in haftalar) ...[
                              for (final tarih in hafta)
                                _gunSatiri(d, tarih, personeller),
                              _haftaOzetSatiri(d, hafta, personeller),
                            ],
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

  /// Tablo iç çizgileri — [Tema.kenar] bu yoğun ızgarada neredeyse
  /// görünmüyordu (özellikle hafta sonu/tatil zeminiyle üst üste
  /// binince). Burada belirgin, sabit kontrastlı bir çizgi rengi
  /// kullanılıyor.
  Color _cizgi(BuildContext c) {
    final koyu = Theme.of(c).brightness == Brightness.dark;
    return koyu ? Colors.white30 : const Color(0xFFB9C0CC);
  }

  /// Hafta bloklarını ayıran kalın çizgi — "Haftalık Toplam" satırının
  /// altı ve üstü, bir haftanın bittiğini/yenisinin başladığını net
  /// gösterir.
  Color _haftaSiniri(BuildContext c) {
    final koyu = Theme.of(c).brightness == Brightness.dark;
    return koyu ? R.kirmizi.withValues(alpha: .7) : R.kirmizi;
  }

  Widget _tarihHucresi(NobetDurumu d, DateTime tarih) {
    final tatil = d.ayar.resmiTatilMi(tarih);
    final baskaAy = tarih.month != d.ay;
    return _metinHucre(
      T.tarih(tarih),
      _tarihW,
      kalin: true,
      vurgu: T.haftaSonu(tarih),
      tatil: tatil,
      yarimGun: !tatil && d.ayar.yarimGunMu(tarih),
      soluk: baskaAy,
      ikon: tatil
          ? Icons.star
          : (d.ayar.yarimGunMu(tarih) ? Icons.star_half : null),
    );
  }

  Widget _ozetTarihHucresi() => Container(
        width: _tarihW,
        height: _satirY,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: R.mavi.withValues(alpha: .14),
          border: Border(
            right: BorderSide(color: _cizgi(context)),
            top: BorderSide(color: _haftaSiniri(context), width: 2),
            bottom: BorderSide(color: _haftaSiniri(context), width: 2),
          ),
        ),
        child: const Text('Haftalık',
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: R.kirmizi)),
      );

  Widget _gunSatiri(
      NobetDurumu d, DateTime tarih, List<Personel> personeller) {
    final haftaSonuMu = T.haftaSonu(tarih);
    final tatil = d.ayar.resmiTatilMi(tarih);
    final yarim = !tatil && d.ayar.yarimGunMu(tarih);
    final baskaAy = tarih.month != d.ay;
    return SizedBox(
      height: _satirY,
      child: Row(
        children: [
          _metinHucre(T.gunAdi(tarih), _gunW,
              kalin: true,
              vurgu: haftaSonuMu,
              tatil: tatil,
              yarimGun: yarim,
              soluk: baskaAy),
          for (final p in personeller)
            _vardiyaHucre(d, tarih, p,
                vurgu: haftaSonuMu,
                tatil: tatil,
                yarimGun: yarim,
                soluk: baskaAy),
          _durumHucre(d, tarih,
              vurgu: haftaSonuMu, tatil: tatil, yarimGun: yarim, soluk: baskaAy),
        ],
      ),
    );
  }

  Widget _haftaOzetSatiri(
      NobetDurumu d, List<DateTime> hafta, List<Personel> personeller) {
    final sinir = BorderSide(color: _haftaSiniri(context), width: 2);
    return Container(
      height: _satirY,
      decoration: BoxDecoration(
        color: R.mavi.withValues(alpha: .14),
        border: Border(top: sinir, bottom: sinir),
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
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
          for (final p in personeller)
            Container(
              width: _personelW,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: _cizgi(context))),
              ),
              child: Text(
                haftalikToplamSaat(
                  haftaGunleri: hafta,
                  ayar: d.ayar,
                  personelId: p.id,
                  kayitBul: (t) => _kayitIcin(t) ?? AyKaydi(yil: t.year, ay: t.month),
                ).toStringAsFixed(1),
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
    const stil = TextStyle(
        fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.1);
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
      bool soluk = false,
      IconData? ikon}) {
    final yazi = Text(metin,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 12,
            fontWeight: kalin ? FontWeight.w600 : FontWeight.w400,
            color: soluk ? R.gri : null));

    return Container(
      width: w,
      height: _satirY,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _satirZemini(vurgu, tatil: tatil, yarimGun: yarimGun),
        border: Border(
          right: BorderSide(color: _cizgi(context)),
          bottom: BorderSide(color: _cizgi(context)),
        ),
      ),
      child: ikon == null
          ? yazi
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: yazi),
                const SizedBox(width: 3),
                Icon(ikon,
                    size: 11,
                    color: (tatil ? R.kirmizi : R.turuncu)
                        .withValues(alpha: soluk ? .5 : 1)),
              ],
            ),
    );
  }

  Widget _vardiyaHucre(NobetDurumu d, DateTime tarih, Personel p,
      {bool vurgu = false,
      bool tatil = false,
      bool yarimGun = false,
      bool soluk = false}) {
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
          ),
        ),
        child: Opacity(
          opacity: soluk ? .55 : 1,
          child: boya.rozet
              ? Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3.5),
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
      ),
    );
  }

  Widget _durumHucre(NobetDurumu d, DateTime tarih,
      {bool vurgu = false,
      bool tatil = false,
      bool yarimGun = false,
      bool soluk = false}) {
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
        ),
      ),
      child: Tooltip(
        message: k.mesaj,
        child: Icon(ikon, color: renk.withValues(alpha: soluk ? .5 : 1), size: 20),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EYLEMLER
  // ---------------------------------------------------------------------------

  /// Bir önceki günün vardiya kodunu, o günün ait olduğu (yüklüyse)
  /// AyKaydi'den okur. Aylık ekrandaki `gun<=1` kısıtının aksine burada
  /// ızgaranın taşan günleri sayesinde ay sınırında da doğru önceki gün
  /// bulunabiliyor; sadece ızgaranın en baştaki günü (önceki gün hiç
  /// yüklü değilse) kontrol atlanır.
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
                      kayit.ata(tarih.day, p.id, v.kod);
                      _ayKirletVeMotoruAt(tarih);
                      setState(() {});
                      return;
                    }
                    final devam = await _ihlalOnayi(uyari);
                    if (devam == true) {
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
    // Nöbet Listesi ekranı da aynı versiyonu gösteriyorsa aynı ayın
    // güncel hâlini görsün diye.
    if (aktifAyKaydedildi && d.aktifVersiyon == _versiyon) {
      await d.yenidenYukle();
    }
    if (!mounted) return;
    setState(() => _yukleniyor = false);
    _bilgi('Haftalık liste kaydedildi.');
  }

  /// PDF her zaman aktif ayın (Nöbet Listesi ekranındakiyle birebir aynı
  /// biçimdeki) çıktısını üretir — bu yüzden aktif ayda kaydedilmemiş
  /// haftalık değişiklik varsa önce kaydetmesi istenir.
  Future<void> _pdf(NobetDurumu d) async {
    final aktifAnahtar = T.donemAnahtari(d.yil, d.ay);
    if (_kirliAylar.contains(aktifAnahtar)) {
      _bilgi('Bu ayda kaydedilmemiş değişiklikler var. PDF, en son '
          'kaydedilen hâli kullanır — önce Kaydet\'e basın.');
      return;
    }
    try {
      await PdfServis.onizle(
        ayar: d.ayar,
        personeller: d.personeller,
        kayit: d.kayit,
        gunSayisi: d.gunSayisi,
        ozetler: d.ozetler,
        birim: d.birim,
        hedefSaat: d.aylikHedefSaat,
      );
    } catch (e) {
      if (mounted) _bilgi('PDF oluşturulamadı: $e');
    }
  }

  /// Haftalık ızgaranın TAMAMINI (birden fazla ay + haftalık toplam
  /// satırları) tek sayfaya sığdırarak indirir. Aylık PDF'in aksine
  /// `d.kayit` yerine doğrudan ekranın kendi `_kayitlar` haritasından
  /// okur — bu yüzden henüz kaydedilmemiş değişiklikler de (Önizleme'de
  /// görüldüğü gibi) çıktıya yansır.
  Future<void> _pdfHaftalik(NobetDurumu d) async {
    try {
      await PdfServis.onizleHaftalik(
        ayar: d.ayar,
        personeller: d.personeller,
        birim: d.birim,
        yil: d.yil,
        ay: d.ay,
        haftalar: haftalikGunler(d.yil, d.ay),
        kodBul: (tarih, personelId) =>
            _kayitIcin(tarih)?.kod(tarih.day, personelId) ?? '',
        durumBul: (tarih) =>
            _motorIcin(d, tarih).gunDurumu(tarih.day, tarih.year, tarih.month),
        haftaToplamBul: (hafta, personelId) => haftalikToplamSaat(
          haftaGunleri: hafta,
          ayar: d.ayar,
          personelId: personelId,
          kayitBul: (t) => _kayitIcin(t) ?? AyKaydi(yil: t.year, ay: t.month),
        ),
      );
    } catch (e) {
      if (mounted) _bilgi('Haftalık PDF oluşturulamadı: $e');
    }
  }

  /// Haftalık ızgaranın tam ekran, kendi ScrollController'larıyla
  /// önizlemesi — arkadaki asıl tablo hâlâ bağlı olduğu için aynı
  /// controller'lar burada tekrar kullanılamaz.
  Future<void> _onizlemeGoster(NobetDurumu d) async {
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
            foregroundColor:
                Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
            elevation: 0,
            title: Text(
              '${d.ayar.ad} — ${T.ayYil(d.yil, d.ay)} · $_ekranBaslik',
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
            // Personel sayısı az olan birimlerde tablonun doğal genişliği
            // ekrandan dar kalabiliyor; `_tablo` içindeki Expanded'lar onu
            // varsayılan olarak sola yaslıyor. Doğal genişliği hesaplayıp
            // ekrandan darsa ortalıyoruz — genişse (yatay kaydırma
            // gerektiğinde) davranış değişmiyor.
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

  Future<void> _listeYap(NobetDurumu d) async {
    final aktifAnahtar = T.donemAnahtari(d.yil, d.ay);
    final aktifKayit = _kayitlar[aktifAnahtar];
    if (aktifKayit == null) return;
    if (aktifKayit.yayinda) {
      _bilgi('Bu ayın listesi YAYINDA olduğu için Liste Yap kullanılamaz. '
          'Önce Nöbet Listesi ekranından yayından kaldırın.');
      return;
    }
    if (_versiyon == kVersiyonOnayli &&
        !d.onaylananListeAcikMi &&
        !await _kilidiAc(d)) {
      return;
    }
    if (!mounted) return;
    var cekirdek = d.ayar.dongUzunlugu;

    final secim = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: const Text('Liste Yap'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Çekirdek gün sayısı:',
                          style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Çekirdek gün sayısını azalt',
                        onPressed: () => yenile(
                            () => cekirdek = cekirdek > 2 ? cekirdek - 1 : 2),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$cekirdek',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      IconButton(
                        tooltip: 'Çekirdek gün sayısını artır',
                        onPressed: () => yenile(() => cekirdek++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const Expanded(
                        child: Text(
                          'Nöbet döngüsü kaç günde bir tekrar ediyorsa o sayı.',
                          style: TextStyle(fontSize: 11.5, color: R.gri),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 22),
                  _secenekKarti(
                    baslik: 'Bu aydan devam et',
                    aciklama:
                        'Ayın ilk $cekirdek gününü elle girdiyseniz, '
                        '${cekirdek + 1}. günden ayın sonuna ve ızgarada '
                        'görünen sonraki ayın taşan (Pazar\'a kadarki) '
                        'günlerine kadar aynı döngü tekrarlanır.',
                    ikon: Icons.playlist_add_check,
                  ),
                  const SizedBox(height: 10),
                  _secenekKarti(
                    baslik: 'Geçen aydan devam et',
                    aciklama:
                        'Geçen ayın "Aylık Normal Şablon" listesinin son '
                        '$cekirdek günü çekirdek alınır; ayın 1\'inden '
                        'itibaren bu ayın TAMAMI ve ızgarada görünen '
                        'sonraki ayın taşan günleri yeniden kurulur. Şablon '
                        'boşsa geçen ayın Nöbet Listesi kullanılır.',
                    ikon: Icons.history,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: R.turuncu.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: R.turuncu),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mesai (dahiliye) personeli döngüye girmez; '
                            'hafta sonu H.T., resmi tatil R.T., diğer günler '
                            'mesai yazılır. Sonraki ayın listesi zaten '
                            'YAYINDAysa o ayın günlerine dokunulmaz.',
                            style: TextStyle(fontSize: 11.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç')),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'gecenay'),
              child: const Text('Geçen aydan'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'buay'),
              child: const Text('Bu aydan'),
            ),
          ],
        ),
      ),
    );

    if (secim == null) return;
    if (!mounted) return;

    final mesaj = secim == 'buay'
        ? _buAydanDoldur(d, cekirdek: cekirdek)
        : await _gecenAydanDoldur(d, cekirdek: cekirdek);
    if (mounted) _bilgi(mesaj);
  }

  Widget _secenekKarti({
    required String baslik,
    required String aciklama,
    required IconData ikon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Tema.kenar(context)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 20, color: R.maviKoyu),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Text(aciklama,
                    style: const TextStyle(
                        fontSize: 11.5, color: R.gri, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sonraki ayın ızgarada görünen taşan günlerini (1'den, o ayın içindeki
  /// haftalık ilk Pazar'ına kadar) döndürür — sonraki ay zaten YAYINDA ise
  /// veya haftalık ızgara o aya hiç taşmıyorsa null döner (o bölüm atlanır).
  (String anahtar, AyKaydi kayit, int gunSayisi)? _tasanSonrakiAy(
      NobetDurumu d) {
    final sonrakiYil = d.ay == 12 ? d.yil + 1 : d.yil;
    final sonrakiAy = d.ay == 12 ? 1 : d.ay + 1;
    final anahtar = T.donemAnahtari(sonrakiYil, sonrakiAy);
    final kayit = _kayitlar[anahtar];
    if (kayit == null || kayit.yayinda) return null;
    final tasanGunSayisi = haftalikBitis(d.yil, d.ay).day;
    if (tasanGunSayisi <= 0) return null;
    return (anahtar, kayit, tasanGunSayisi);
  }

  /// Bu ayın ilk [cekirdek] gününü çekirdek alıp ayın kalanını ve
  /// ızgarada görünen sonraki ayın taşan günlerini doldurur.
  String _buAydanDoldur(NobetDurumu d, {int cekirdek = 0}) {
    final aktifAnahtar = T.donemAnahtari(d.yil, d.ay);
    final aktifKayit = _kayitlar[aktifAnahtar]!;
    final n = cekirdek > 0 ? cekirdek : d.ayar.dongUzunlugu;
    if (n < 2) return 'Döngü uzunluğu geçersiz.';
    final gunSayisiAktif = DateTime(d.yil, d.ay + 1, 0).day;
    if (gunSayisiAktif <= n) return 'Ay, çekirdek gün sayısından kısa.';

    var doluHucre = 0;
    for (var g = 1; g <= n; g++) {
      for (final p in d.personeller) {
        if (aktifKayit.kod(g, p.id).isNotEmpty) doluHucre++;
      }
    }
    if (doluHucre == 0) {
      return 'Ayın ilk $n günü boş. Önce bu günleri elle doldurun.';
    }

    final sonraki = _tasanSonrakiAy(d);

    ld.cekirdektenDoldur(
      ayar: d.ayar,
      personeller: d.personeller,
      kaynak: aktifKayit,
      kaynakBaslangic: 1,
      kaynakGunSayisi: n,
      cekirdek: n,
      ilkMutlakGun: n + 1,
      sonMutlakGun: gunSayisiAktif + (sonraki?.$3 ?? 0),
      hedefCoz: (mutlakGun) => mutlakGun <= gunSayisiAktif
          ? (aktifKayit, DateTime(d.yil, d.ay, mutlakGun))
          : (sonraki!.$2, DateTime(sonraki.$2.yil, sonraki.$2.ay,
              mutlakGun - gunSayisiAktif)),
    );

    _kirliAylar.add(aktifAnahtar);
    _motorlar.remove(aktifAnahtar);
    if (sonraki != null) {
      _kirliAylar.add(sonraki.$1);
      _motorlar.remove(sonraki.$1);
    }
    setState(() {});

    return 'Ayın ilk $n günü çekirdek alındı, ${n + 1}. günden ay sonuna'
        '${sonraki != null ? ' ve sonraki ayın taşan günlerine' : ''} '
        'kadar döngü uygulandı.';
  }

  /// Geçen ayın son [cekirdek] gününü çekirdek alıp bu ayın tamamını ve
  /// ızgarada görünen sonraki ayın taşan günlerini kurar. Önce geçen ayın
  /// "Aylık Normal Şablon" versiyonuna bakar, yoksa geçen ayın asıl
  /// listesini kullanır.
  Future<String> _gecenAydanDoldur(NobetDurumu d, {int cekirdek = 0}) async {
    final n = cekirdek > 0 ? cekirdek : d.ayar.dongUzunlugu;
    if (n < 2) return 'Döngü uzunluğu geçersiz.';

    final oncekiAy = d.ay == 1 ? 12 : d.ay - 1;
    final oncekiYil = d.ay == 1 ? d.yil - 1 : d.yil;
    final oncekiGunSayisi = DateTime(oncekiYil, oncekiAy + 1, 0).day;

    AyKaydi kaynak;
    var kaynakAdi = 'asıl liste';
    try {
      kaynak = await d.servis.ayKaydiGetir(d.birimId, oncekiYil, oncekiAy,
          versiyon: kVersiyonSablon);
      if (kaynak.atamalar.isEmpty) {
        kaynak = await d.servis.ayKaydiGetir(d.birimId, oncekiYil, oncekiAy);
      } else {
        kaynakAdi = kVersiyonSablon;
      }
    } catch (e) {
      return 'Geçen ay okunamadı: $e';
    }

    if (kaynak.atamalar.isEmpty) {
      return '${T.ayYil(oncekiYil, oncekiAy)} ayında veri yok. Bu ayın ilk '
          '$n gününü elle doldurup "Bu aydan devam et" seçeneğini kullanın.';
    }

    final aktifAnahtar = T.donemAnahtari(d.yil, d.ay);
    final aktifKayit = _kayitlar[aktifAnahtar];
    if (aktifKayit == null) return 'Bu ayın verisi yüklü değil.';
    final gunSayisiAktif = DateTime(d.yil, d.ay + 1, 0).day;
    final sonraki = _tasanSonrakiAy(d);

    ld.cekirdektenDoldur(
      ayar: d.ayar,
      personeller: d.personeller,
      kaynak: kaynak,
      kaynakBaslangic: oncekiGunSayisi - n + 1,
      kaynakGunSayisi: oncekiGunSayisi,
      cekirdek: n,
      ilkMutlakGun: 1,
      sonMutlakGun: gunSayisiAktif + (sonraki?.$3 ?? 0),
      hedefCoz: (mutlakGun) => mutlakGun <= gunSayisiAktif
          ? (aktifKayit, DateTime(d.yil, d.ay, mutlakGun))
          : (sonraki!.$2, DateTime(sonraki.$2.yil, sonraki.$2.ay,
              mutlakGun - gunSayisiAktif)),
    );

    _kirliAylar.add(aktifAnahtar);
    _motorlar.remove(aktifAnahtar);
    if (sonraki != null) {
      _kirliAylar.add(sonraki.$1);
      _motorlar.remove(sonraki.$1);
    }
    setState(() {});

    return '${T.ayYil(oncekiYil, oncekiAy)} ayının son $n günü ($kaynakAdi) '
        'çekirdek alındı; ${T.ayYil(d.yil, d.ay)} ayının tamamı'
        '${sonraki != null ? ' ve sonraki ayın taşan günleri' : ''} '
        'yeniden kuruldu.';
  }
}
