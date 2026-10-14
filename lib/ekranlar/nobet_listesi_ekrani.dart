import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/kapsama_motoru.dart';
import '../core/tarih.dart';
import '../core/tema.dart';
import '../durum/nobet_durumu.dart';
import '../modeller/modeller.dart';
import '../servisler/pdf_servis.dart';
import 'yayin_uyarisi.dart';

class NobetListesiEkrani extends StatefulWidget {
  const NobetListesiEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<NobetListesiEkrani> createState() => _NobetListesiEkraniState();
}

class _NobetListesiEkraniState extends State<NobetListesiEkrani> {
  final _yatayBaslik = ScrollController();
  final _yatayGovde = ScrollController();

  static const double _satirY = 27;
  static const double _baslikY = 37;
  static const double _tarihW = 85;
  static const double _gunW = 75;
  static const double _personelW = 90;
  static const double _durumW = 58;
  static const double _ozetPanelMinW = 280;

  // Android'de Önizleme popup'ı için daraltılmış ölçüler — telefon
  // ekranına daha çok sütun sığsın diye. Masaüstünde kullanılmaz.
  static const double _satirYDar = 22;
  static const double _baslikYDar = 32;
  static const double _tarihWDar = 60;
  static const double _gunWDar = 55;
  static const double _personelWDar = 64;
  static const double _durumWDar = 40;

  // Araç çubuğu butonları için daraltılmış dolgu — tema varsayılanı
  // (yatay 18 / dikey 16) yedi öğeyi tek satıra sığdırmıyor, "Önizleme"
  // alt satıra kayıyordu.
  static final ButtonStyle _kompaktDolgu = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  static final ButtonStyle _kompaktCerceve = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: R.mavi,
    backgroundColor: R.mavi.withValues(alpha: .02),
    side: BorderSide(color: R.mavi),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
  );

  Future<Map<String, int>>? _yillikIzinGelecek;
  int? _yuklenenYil;
  int? _yuklenenAy;
  Birim? _yuklenenBirim;

  void _yillikIzinYukleGerekirse(NobetDurumu d) {
    if (_yuklenenYil == d.yil &&
        _yuklenenAy == d.ay &&
        _yuklenenBirim == d.birim) {
      return;
    }
    _yuklenenYil = d.yil;
    _yuklenenAy = d.ay;
    _yuklenenBirim = d.birim;
    _yillikIzinGelecek = d.yillikIzinKullanimi();
  }

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

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          final d = context.read<NobetDurumu>();
          if (!d.duzenleyebilir || d.kaydediliyor) return;
          final oturum = context.read<OturumDurumu>();
          d.kaydet(kaydeden: oturum.kullanici?.ad ?? '').then((ok) {
            if (mounted) _bilgi(ok ? 'Liste kaydedildi.' : 'Kaydedilemedi.');
          });
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sekmeler(),
            Expanded(child: _liste()),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _sekmeler() {
    final d = context.watch<NobetDurumu>();
    return Container(
      color: Tema.kart(context),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Dar ekranda (telefon) üç öğe sığmazsa sol grup yatay kayar —
          // sağdaki yayın ikonu her zaman görünür kalır.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _sekmeEtiketi('Nöbet Listesi'),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: _kompaktCerceve,
                    onPressed: () => _onizlemeGoster(d),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('Önizle'),
                  ),
                  if (!d.sadecePdf && !d.personelGorunumu) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: _kompaktCerceve,
                      onPressed: d.duzenleyebilir ? () => _aylikNot(d) : null,
                      icon: const Icon(Icons.sticky_note_2_outlined, size: 16),
                      label: const Text('Aylık Not'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Yayın butonu yalnızca "Onaylanan Liste" versiyonunda gösterilir.
          if (d.aktifVersiyon == kVersiyonOnayli)
            Tooltip(
              message: d.kayit.yayinda ? 'Yayında' : 'Yayında Değil',
              child: InkWell(
                onTap: d.yonetebilir
                    ? () async {
                        final simdiYayinda = !d.kayit.yayinda;
                        final oturum = context.read<OturumDurumu>();
                        await d.yayinDurumuDegistir(
                            kaydeden: oturum.kullanici?.ad ?? '');
                        if (mounted) {
                          _bilgi(simdiYayinda
                              ? 'Liste yayına alındı ve kilitlendi.'
                              : 'Liste yayından kaldırıldı, düzenlemeye açık.');
                        }
                      }
                    : () =>
                        _bilgi('Yayın durumunu yalnızca yönetici değiştirir.'),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Icon(
                    d.kayit.yayinda
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16.5,
                    color: d.kayit.yayinda ? R.yesil : R.gri,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sekmeEtiketi(String baslik) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: R.mavi, width: 2.5)),
      ),
      child: Text(baslik,
          style: const TextStyle(
            fontSize: 13.5,
            color: R.mavi,
            fontWeight: FontWeight.w700,
          )),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _liste() {
    final d = context.watch<NobetDurumu>();

    if (!d.listeGorunurMu) {
      return _yayinlanmadiEkrani();
    }

    if (widget.genis) _yillikIzinYukleGerekirse(d);

    // Başlık satırı (Tarih/Günler/personel/Durum) tablonun kendi içinde
    // sabit tutulur; günler ve altındaki "AYLIK ÖZET" tablosu tek bir dikey
    // kaydırma alanında, başlığın ALTINDA kayar — böylece liste ne kadar
    // aşağı kaydırılırsa kaydırılsın başlık her zaman görünür kalır.
    return Padding(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 2, 20, 20)
          : const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _araCubugu(),
          SizedBox(height: widget.genis ? 2 : 4),
          Expanded(
            child: widget.genis
                ? _tabloVeOzetPaneli(d, altIcerik: _aylikOzetTablosu(d))
                : _tablo(altIcerik: _aylikOzetTablosu(d)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AYLIK ÖZET TABLOSU (ekranda, eski uygulamadaki gibi Nöbet Listesi'nin
  // altında) — PDF çıktısındaki (`PdfServis._ozetTablosu`) aynı sütun
  // düzeninin ekran karşılığı. "YOL" sütunu, o ay içindeki fiilen çalışılan
  // nöbet günü sayısıdır (aynı satırdaki altı vardiya sütununun toplamı) —
  // Yıllık İzin'in yerini alır.
  static const Map<String, String> _ozetSutunlari = {
    kGunduz12: '08:00\n20:00',
    kGece12: '20:00\n08:00',
    kSabah8: '08:00\n16:00',
    kAksam8: '16:00\n24:00',
    kGece8: '24:00\n08:00',
    kMesai: '08:00\n17:30',
  };

  Widget _aylikOzetTablosu(NobetDurumu d) {
    final ozetler = d.ozetler;
    if (ozetler.isEmpty) return const SizedBox.shrink();

    // Güvenlik ve Temizlik birimlerinin personel sayısı (dolayısıyla bu
    // tabloyu barındıran gün tablosunun genişliği) farklı olduğu için iki
    // birim ayrı, sabit sütun düzenine sahiptir — Güvenlik'te boşta kalan
    // yeri doldurmak üzere "Nöbet İzni" ve "Hafta Tatili" sütunları geri
    // eklenir, Temizlik zaten sığdığı için onlarsız kalır.
    final guvenlikMi = d.birim == Birim.guvenlik;

    // Sütun genişlikleri (yatay ölçü) ve hücre yüksekliği (padding'e bağlı,
    // aşağıdaki `EdgeInsets.symmetric(vertical: ...)` ile ayarlanır).
    const adW = 144.0;
    // Her sütun grubu artık ayrı bir sabitle ayarlanır (hepsi birden tek
    // bir "dataW" değerini paylaşmıyor) — istenirse birbirinden bağımsız
    // daraltılıp genişletilebilir.
    const vardiyaW = 37.0; // "08:00\n20:00" gibi vardiya saati sütunları
    const izinW = 44.0; // Nöbet İzni / Hafta Tatili — sadece Güvenlik'te
    const yolW = 30.0;
    const gunduzW = 52.0;
    const geceW = 32.0;
    const normalMesaiW = 52.0;
    const fazlaMesaiW = 43.0;
    const satirDikeyBosluk = 4.0; // hücre yüksekliğini belirler

    // Flutter'ın Table widget'ı kullanılıyor (önceki sürümdeki gibi her
    // hücreye ayrı ayrı sağ/alt Border eklemek yerine) — tek bir TableBorder
    // TÜM ızgarayı çizdiği için satır/sütun çizgileri arasında piksel
    // kayması olmaz.
    Widget baslik(String metin, {double boyut = 9.5}) => Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
              vertical: satirDikeyBosluk, horizontal: 2),
          color: Tema.tabloBaslik(context),
          child: Text(metin,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: boyut, fontWeight: FontWeight.w700)),
        );

    Widget hucre(String metin,
            {Color? renk, bool kalin = false, double boyut = 10}) =>
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
              vertical: satirDikeyBosluk, horizontal: 2),
          child: Text(metin,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: boyut,
                color: renk,
                fontWeight: kalin ? FontWeight.w700 : FontWeight.w500,
              )),
        );

    // Temizlik'te "Nöbet İzni" ve "Hafta Tatili" sütunları burada
    // gösterilmez (yer kazanmak için); Güvenlik'te geri eklenir. PDF
    // çıktısında (bkz. `PdfServis`/`BordroPdfServis`) ikisi de her zaman yer
    // alır — bu, yalnızca ekrandaki görünümü etkiler.
    final izinSutunSayisi = guvenlikMi ? 2 : 0;
    final vardiyaSutunSayisi = _ozetSutunlari.length;
    final satirGenisligi = adW +
        vardiyaSutunSayisi * vardiyaW +
        izinSutunSayisi * izinW +
        yolW +
        gunduzW +
        geceW +
        normalMesaiW +
        fazlaMesaiW;
    final sutunGenislikleri = <int, TableColumnWidth>{
      0: const FixedColumnWidth(adW),
      for (var i = 1; i <= vardiyaSutunSayisi; i++)
        i: const FixedColumnWidth(vardiyaW),
      for (var i = 0; i < izinSutunSayisi; i++)
        vardiyaSutunSayisi + 1 + i: const FixedColumnWidth(izinW),
      vardiyaSutunSayisi + izinSutunSayisi + 1: const FixedColumnWidth(yolW),
      vardiyaSutunSayisi + izinSutunSayisi + 2:
          const FixedColumnWidth(gunduzW),
      vardiyaSutunSayisi + izinSutunSayisi + 3: const FixedColumnWidth(geceW),
      vardiyaSutunSayisi + izinSutunSayisi + 4:
          const FixedColumnWidth(normalMesaiW),
      vardiyaSutunSayisi + izinSutunSayisi + 5:
          const FixedColumnWidth(fazlaMesaiW),
    };

    return Container(
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cizgi(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: R.mavi.withValues(alpha: .12),
              border: Border(bottom: BorderSide(color: _cizgi(context))),
            ),
            child: const Row(
              children: [
                Icon(Icons.summarize_outlined, size: 16, color: R.maviKoyu),
                SizedBox(width: 6),
                Text('AYLIK ÖZET',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: satirGenisligi,
              child: Table(
                // Dış kenarların tamamı da Table'ın kendi TableBorder'ına
                // dahil edilir — dış Container'ın kenarlığına güvenmek,
                // yuvarlama farkı yüzünden sağ kenarda kısa kesilen bir
                // çizgiye yol açıyordu.
                border: TableBorder(
                  top: BorderSide(color: _cizgi(context)),
                  left: BorderSide(color: _cizgi(context)),
                  right: BorderSide(color: _cizgi(context)),
                  bottom: BorderSide(color: _cizgi(context)),
                  horizontalInside: BorderSide(color: _cizgi(context)),
                  verticalInside: BorderSide(color: _cizgi(context)),
                ),
                columnWidths: sutunGenislikleri,
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      baslik('ADI SOYADI', boyut: 11.5),
                      for (final baslikMetni in _ozetSutunlari.values)
                        baslik(baslikMetni, boyut: 10),
                      if (guvenlikMi) ...[
                        baslik('NÖBET\nİZNİ', boyut: 10),
                        baslik('HAFTA\nTATİLİ', boyut: 10),
                      ],
                      baslik('YOL'),
                      baslik('GÜNDÜZ', boyut: 10),
                      baslik('GECE', boyut: 10),
                      baslik('NORMAL\nMESAİ'),
                      baslik('FAZLA\nMESAİ'),
                    ],
                  ),
                  for (final o in ozetler)
                    () {
                      final yol = _ozetSutunlari.keys
                          .fold<int>(0, (t, kod) => t + o.adet(kod));
                      final gunduz = o.toplamSaat - o.geceSaati;
                      return TableRow(
                        children: [
                          Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                                vertical: satirDikeyBosluk, horizontal: 6),
                            child: Text(o.personel.ad,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5, fontWeight: FontWeight.w700)),
                          ),
                          for (final kod in _ozetSutunlari.keys)
                            hucre('${o.adet(kod)}', boyut: 11),
                          if (guvenlikMi) ...[
                            hucre('${o.adet(kNobetIzni)}', boyut: 11),
                            hucre('${o.adet(kHaftaTatili)}', boyut: 11),
                          ],
                          hucre('$yol', kalin: true, renk: R.mavi),
                          hucre(_ondalikliSayi(gunduz), boyut: 11),
                          hucre(_ondalikliSayi(o.geceSaati), boyut: 11),
                          hucre(_ondalikliSayi(o.normalMesai),
                              kalin: true, renk: R.yesil),
                          hucre('${_ondalikliSayi(o.fazlaMesaiGunu)} GÜN',
                              kalin: true, renk: R.kirmizi),
                        ],
                      );
                    }(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Türkçe ondalık ayracı (nokta değil virgül).
  String _ondalikliSayi(double d) {
    final metin =
        d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
    return metin.replaceAll('.', ',');
  }

  /// Tablo, gerçek içerik genişliği kadar yer kaplar (fazladan boşluk
  /// bırakmaz); kalan yatay alanın tamamı Aylık Özet paneline verilir.
  /// Ekran, tablo + panelin minimum genişliğini karşılamayacak kadar dar
  /// kalırsa tablo eski (kayan/Expanded) davranışına döner ve panel sabit
  /// minimum genişlikte kalır.
  Widget _tabloVeOzetPaneli(NobetDurumu d, {Widget? altIcerik}) {
    final tabloGenisligi =
        _tarihW + _gunW + d.personeller.length * _personelW + _durumW;
    const aralik = 14.0;

    return LayoutBuilder(
      builder: (context, kisit) {
        final sigiyorMu =
            tabloGenisligi + aralik + _ozetPanelMinW <= kisit.maxWidth;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sigiyorMu
                ? SizedBox(
                    width: tabloGenisligi,
                    child: _tablo(altIcerik: altIcerik))
                : Expanded(child: _tablo(altIcerik: altIcerik)),
            const SizedBox(width: aralik),
            sigiyorMu
                ? Expanded(child: _aylikOzetPaneli(d))
                : SizedBox(width: _ozetPanelMinW, child: _aylikOzetPaneli(d)),
          ],
        );
      },
    );
  }

  /// Personel görünümünde, seçilen ayın "Onaylanan Liste"si henüz
  /// yayında değilse gösterilir.
  Widget _yayinlanmadiEkrani() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: R.gri),
              const SizedBox(height: 20),
              const Text(
                'Bu Ayın Nöbet Listesi Henüz Yayınlanmamıştır.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Liste Onaylandığında Buradan Görebilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(color: R.gri, fontSize: 13),
              ),
            ],
          ),
        ),
      );

  Widget _araCubugu() {
    final d = context.watch<NobetDurumu>();
    final oturum = context.watch<OturumDurumu>();

    if (d.sadecePdf) {
      return Row(
        children: [
          _versiyonSecici(d),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: _kompaktCerceve,
            onPressed: () => _pdf(d),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
            label: const Text('PDF İndir'),
          ),
          const Spacer(),
          const Icon(Icons.visibility_outlined, size: 15, color: R.gri),
          const SizedBox(width: 6),
          const Text('Sadece görüntüleme',
              style: TextStyle(fontSize: 12, color: R.gri)),
        ],
      );
    }

    if (d.personelGorunumu) {
      return Row(
        children: [
          _versiyonSecici(d),
          const SizedBox(width: 8),
          Tooltip(
            message: 'PDF indirme yetkiniz yok.',
            child: OutlinedButton.icon(
              style: _kompaktCerceve,
              onPressed: null,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
              label: const Text('PDF İndir'),
            ),
          ),
          const Spacer(),
          const Icon(Icons.visibility_outlined, size: 15, color: R.gri),
          const SizedBox(width: 6),
          const Text('Sadece görüntüleme',
              style: TextStyle(fontSize: 12, color: R.gri)),
        ],
      );
    }

    final ogeler = <Widget>[
      _versiyonSecici(d),
      FilledButton.icon(
        style: _kompaktDolgu,
        onPressed: d.kaydediliyor || !d.duzenleyebilir
            ? null
            : () async {
                final ok = await d.kaydet(kaydeden: oturum.kullanici?.ad ?? '');
                if (mounted) {
                  _bilgi(ok ? 'Liste kaydedildi.' : 'Kaydedilemedi.');
                }
              },
        icon: d.kaydediliyor
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_outlined, size: 16),
        label: Text(d.kirli ? 'Kaydet *' : 'Kaydet'),
      ),
      OutlinedButton.icon(
        style: _kompaktCerceve,
        onPressed: () => _pdf(d),
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
        label: const Text('PDF İndir'),
      ),
      OutlinedButton.icon(
        style: _kompaktCerceve,
        onPressed: d.duzenleyebilir ? () => _listeYap(d) : null,
        icon: const Icon(Icons.auto_awesome_outlined, size: 16),
        label: const Text('Liste Yap'),
      ),
      OutlinedButton.icon(
        style: _kompaktCerceve,
        onPressed: d.geriAlinabilir && d.duzenleyebilir
            ? () {
                d.geriAl();
                _bilgi('İşlem geri alındı.');
              }
            : null,
        icon: const Icon(Icons.undo, size: 16),
        label: const Text('Geri Al'),
      ),
    ];

    // Telefon: butonlar tek satırda yatay kayar — çok satıra yığılıp liste
    // alanını daraltmasın. Masaüstü: Wrap + "son kayıt" bilgisi.
    if (!widget.genis) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < ogeler.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              ogeler[i],
            ],
          ],
        ),
      );
    }

    return Wrap(spacing: 6, runSpacing: 6, children: ogeler);
  }

  // ---------------------------------------------------------------------------
  Widget _tablo({
    ScrollController? baslikCtrl,
    ScrollController? govdeCtrl,
    bool saltOkunur = false,
    bool dar = false,
    Widget? altIcerik,
  }) {
    final d = context.watch<NobetDurumu>();
    final personeller = d.personeller;
    final tarihW = dar ? _tarihWDar : _tarihW;
    final gunW = dar ? _gunWDar : _gunW;
    final personelW = dar ? _personelWDar : _personelW;
    final durumW = dar ? _durumWDar : _durumW;
    final baslikY = dar ? _baslikYDar : _baslikY;
    final satirY = dar ? _satirYDar : _satirY;
    final kayanW = gunW + personeller.length * personelW + durumW;
    final bCtrl = baslikCtrl ?? _yatayBaslik;
    final gCtrl = govdeCtrl ?? _yatayGovde;

    if (personeller.isEmpty) {
      return _bosDurum('Kayıtlı personel yok',
          'Personeller bölümünden personel ekleyerek başlayın.');
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
            height: baslikY,
            child: Row(
              children: [
                _baslikHucre('Tarih', tarihW, dar: dar),
                Expanded(
                  child: SingleChildScrollView(
                    controller: bCtrl,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: kayanW,
                      child: Row(
                        children: [
                          _baslikHucre('Günler', gunW, dar: dar),
                          for (final p in personeller)
                            _personelBaslikHucre(p, personelW, dar: dar),
                          _baslikHucre('Durum', durumW, dar: dar),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          for (var g = 1; g <= d.gunSayisi; g++)
                        () {
                          final t = DateTime(d.yil, d.ay, g);
                          final tatil = d.ayar.resmiTatilMi(t);
                          final bugun = DateTime.now();
                          final bugunMu = d.yil == bugun.year &&
                              d.ay == bugun.month &&
                              g == bugun.day;
                          return _metinHucre(
                            T.tarih(t),
                            tarihW,
                            kalin: true,
                            vurgu: T.haftaSonu(t),
                            tatil: tatil,
                            yarimGun: !tatil && d.ayar.yarimGunMu(t),
                            bugunMu: bugunMu,
                            dar: dar,
                            // Tatil günü yıldızla da işaretlenir — renk
                            // körlüğünde de ayırt edilebilsin.
                            ikon: tatil
                                ? Icons.star
                                : (d.ayar.yarimGunMu(t)
                                    ? Icons.star_half
                                    : null),
                          );
                        }(),
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
                                for (var g = 1; g <= d.gunSayisi; g++)
                                  () {
                                    final t = DateTime(d.yil, d.ay, g);
                                    final haftaSonuMu = T.haftaSonu(t);
                                    final tatil = d.ayar.resmiTatilMi(t);
                                    final yarim =
                                        !tatil && d.ayar.yarimGunMu(t);
                                    final bugun = DateTime.now();
                                    final bugunMu = d.yil == bugun.year &&
                                        d.ay == bugun.month &&
                                        g == bugun.day;
                                    return SizedBox(
                                      height: satirY,
                                      child: Row(
                                        children: [
                                          _metinHucre(
                                            T.gunAdi(t),
                                            gunW,
                                            kalin: true,
                                            vurgu: haftaSonuMu,
                                            tatil: tatil,
                                            yarimGun: yarim,
                                            bugunMu: bugunMu,
                                            dar: dar,
                                          ),
                                          for (final p in personeller)
                                            _vardiyaHucre(d, g, p,
                                                vurgu: haftaSonuMu,
                                                tatil: tatil,
                                                yarimGun: yarim,
                                                bugunMu: bugunMu,
                                                saltOkunur: saltOkunur,
                                                dar: dar),
                                          _durumHucre(d, g,
                                              vurgu: haftaSonuMu,
                                              tatil: tatil,
                                              yarimGun: yarim,
                                              bugunMu: bugunMu,
                                              dar: dar),
                                        ],
                                      ),
                                    );
                                  }(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (altIcerik != null) ...[
                    const SizedBox(height: 18),
                    altIcerik,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _baslikHucre(String metin, double w,
          {String? altMetin, bool dar = false}) =>
      Container(
        width: w,
        height: dar ? _baslikYDar : _baslikY,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: dar ? 3 : 6),
        decoration: BoxDecoration(
          color: _baslikZemini(context),
          border: Border(right: BorderSide(color: _cizgi(context))),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(metin,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: dar ? 10.5 : 12.5,
                    fontWeight: FontWeight.w700)),
            if (altMetin != null)
              Text(altMetin,
                  style: TextStyle(fontSize: dar ? 8 : 10, color: R.gri)),
          ],
        ),
      );

  /// Personel adını "Ad" ve "SOYAD" iki ayrı satırda gösterir (yan yana
  /// yazıldığında dar sütunlarda kesilen uzun soyadları okunur kılmak için).
  (String, String) _adSoyadAyir(String tamAd) {
    final t = tamAd.trim();
    final i = t.lastIndexOf(' ');
    if (i == -1) return (t, '');
    return (t.substring(0, i), t.substring(i + 1));
  }

  Widget _personelBaslikHucre(Personel p, double w, {bool dar = false}) {
    final (ad, soyad) = _adSoyadAyir(p.ad);
    final stil = TextStyle(
        fontSize: dar ? 9.5 : 11.5, fontWeight: FontWeight.w700, height: 1.1);
    return Container(
      width: w,
      height: dar ? _baslikYDar : _baslikY,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: dar ? 2 : 4),
      decoration: BoxDecoration(
        color: _baslikZemini(context),
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

  /// Tablo iç çizgileri — [Tema.kenar] bu yoğun ızgarada (özellikle hafta
  /// sonu/tatil zeminiyle üst üste binince) neredeyse görünmüyordu; burada
  /// belirgin, sabit kontrastlı bir çizgi rengi kullanılıyor.
  Color _cizgi(BuildContext c) {
    final koyu = Theme.of(c).brightness == Brightness.dark;
    return koyu ? Colors.white30 : const Color(0xFFB9C0CC);
  }

  /// Satır zemini. Öncelik sırası: resmî/dinî tatil → yarım gün (arife) →
  /// hafta sonu → normal. Tatiller ayrı renkle işaretlenir ki 8'lik sisteme
  /// geçilen günler listede bir bakışta görünsün.
  Color? _satirZemini(bool vurgu,
      {bool tatil = false, bool yarimGun = false, bool bugunMu = false}) {
    final koyu = Theme.of(context).brightness == Brightness.dark;
    if (bugunMu) {
      return koyu
          ? R.mavi.withValues(alpha: .22)
          : const Color(0xFFDCEEFF);
    }
    if (tatil) {
      return koyu
          ? R.kirmizi.withValues(alpha: .16)
          : const Color(0xFFFDE7E7);
    }
    if (yarimGun) {
      return koyu
          ? R.turuncu.withValues(alpha: .15)
          : const Color(0xFFFFF2DC);
    }
    if (vurgu) {
      return koyu
          ? Colors.white.withValues(alpha: .10)
          : const Color(0xFFD9DCE3);
    }
    return null;
  }

  /// Tarih/Günler/Personel/Durum başlık satırının zemin rengi — açık kırmızı.
  Color _baslikZemini(BuildContext context) {
    final koyu = Theme.of(context).brightness == Brightness.dark;
    return koyu
        ? R.kirmizi.withValues(alpha: .12)
        : const Color(0xFFFDEEEE);
  }

  Widget _metinHucre(String metin, double w,
      {bool kalin = false,
      bool vurgu = false,
      bool tatil = false,
      bool yarimGun = false,
      bool bugunMu = false,
      bool dar = false,
      IconData? ikon}) {
    final yazi = Text(metin,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: dar ? 10 : 12,
            fontWeight: kalin ? FontWeight.w600 : FontWeight.w400));

    return Container(
      width: w,
      height: dar ? _satirYDar : _satirY,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _satirZemini(vurgu,
            tatil: tatil, yarimGun: yarimGun, bugunMu: bugunMu),
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
                    size: dar ? 9 : 11,
                    color: tatil ? R.kirmizi : R.turuncu),
              ],
            ),
    );
  }

  Widget _vardiyaHucre(NobetDurumu d, int gun, Personel p,
      {bool vurgu = false,
      bool tatil = false,
      bool yarimGun = false,
      bool bugunMu = false,
      bool saltOkunur = false,
      bool dar = false}) {
    final kod = d.kod(gun, p.id);
    final duzenlenebilir = !saltOkunur && d.duzenleyebilir;

    // Boş hücre "N.İ." (nöbet izni) sayılır — yeni ay bu sayede baştan
    // N.İ. dolu görünür, kullanıcı üzerine vardiya seçerek çalışır.
    final gorunen = kod.isEmpty ? kNobetIzni : d.ayar.vardiyaBul(kod).etiket;
    final koyu = Theme.of(context).brightness == Brightness.dark;
    final boya = vardiyaBoyasi(kod.isEmpty ? kNobetIzni : kod, koyu: koyu);
    final yaziBoyu = dar ? 9.5 : 11.5;

    return InkWell(
      onTap: duzenlenebilir ? () => _vardiyaSec(d, gun, p) : null,
      onLongPress: duzenlenebilir ? () => d.kodAta(gun, p.id, '') : null,
      child: Container(
        width: dar ? _personelWDar : _personelW,
        height: dar ? _satirYDar : _satirY,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _satirZemini(vurgu,
              tatil: tatil, yarimGun: yarimGun, bugunMu: bugunMu),
          border: Border(
            right: BorderSide(color: _cizgi(context)),
            bottom: BorderSide(color: _cizgi(context)),
          ),
        ),
        child: boya.rozet
            ? Container(
                padding: EdgeInsets.symmetric(
                    horizontal: dar ? 5 : 7, vertical: dar ? 2 : 3.5),
                decoration: BoxDecoration(
                  color: boya.zemin,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  gorunen,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: yaziBoyu,
                    fontWeight: FontWeight.w700,
                    color: boya.yazi,
                  ),
                ),
              )
            : Text(
                gorunen,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: yaziBoyu,
                  fontWeight: FontWeight.w500,
                  color: boya.yazi,
                ),
              ),
      ),
    );
  }

  Widget _durumHucre(NobetDurumu d, int gun,
      {bool vurgu = false,
      bool tatil = false,
      bool yarimGun = false,
      bool bugunMu = false,
      bool dar = false}) {
    final k = d.madde3.gunDurumu(gun, d.yil, d.ay);
    final (ikon, renk) = switch (k.durum) {
      GercekDurum.tamam => (Icons.check, R.yesil),
      GercekDurum.kadroEksik => (Icons.warning_amber_rounded, R.turuncu),
      GercekDurum.saatAcigi => (Icons.error_outline, R.kirmizi),
      GercekDurum.bosGun => (Icons.close, R.kirmizi),
    };
    return Container(
      width: dar ? _durumWDar : _durumW,
      height: dar ? _satirYDar : _satirY,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _satirZemini(vurgu,
            tatil: tatil, yarimGun: yarimGun, bugunMu: bugunMu),
        border: Border(bottom: BorderSide(color: _cizgi(context))),
      ),
      child: Tooltip(
        message: k.mesaj,
        child: Icon(ikon, color: renk, size: dar ? 16 : 20),
      ),
    );
  }

  static const _ozetRenkleri = [R.mavi, R.turuncu, R.yesil, R.kirmizi, R.maviKoyu];

  Widget _aylikOzetPaneli(NobetDurumu d) {
    final ozetler = d.ozetler;
    final hedef = d.aylikHedefSaat;

    return Container(
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tema.kenar(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: R.mavi.withValues(alpha: .12),
            ),
            child: Row(
              children: [
                const Icon(Icons.summarize_outlined,
                    size: 15, color: R.maviKoyu),
                const SizedBox(width: 5),
                const Text('Aylık Özet',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${T.aylar[d.ay - 1]} Ayı Çalışma: '
                    '${hedef.toStringAsFixed(1)} Saat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: R.maviKoyu),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ozetler.isEmpty
                ? const Center(
                    child: Text('Kayıtlı personel yok',
                        style: TextStyle(fontSize: 12, color: R.gri)))
                : FutureBuilder<Map<String, int>>(
                    future: _yillikIzinGelecek,
                    builder: (ctx, anlik) {
                      final yillikIzin = anlik.data ?? const {};
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                        itemCount: ozetler.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 5),
                        itemBuilder: (_, i) => _ozetKarti(
                          ozetler[i],
                          hedef,
                          yillikIzin,
                          _ozetRenkleri[i % _ozetRenkleri.length],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _ozetKarti(PersonelOzeti o, double hedef,
      Map<String, int> yillikIzin, Color renk) {
    final kullanilan = yillikIzin[o.personel.id] ?? o.yillikIzinKullanilan;
    final kalan = o.personel.yillikIzinKotasi - kullanilan;
    final gunduz = o.toplamSaat - o.geceSaati;
    final durumRengi = o.toplamSaat + 0.01 < hedef
        ? R.kirmizi
        : (o.toplamSaat > hedef + 0.01 ? R.turuncu : R.yesil);

    Widget degerIcerigi(IconData? ikon, String etiket, String v,
            {Color? renkV}) =>
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (ikon != null) ...[
              Icon(ikon, size: 13, color: R.gri),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '$etiket: ',
                      style: const TextStyle(fontSize: 12, color: R.gri)),
                  TextSpan(
                      text: v,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: renkV)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );

    Widget solSutun() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            degerIcerigi(Icons.wb_sunny_outlined, 'Gündüz',
                gunduz.toStringAsFixed(1)),
            const SizedBox(height: 1),
            degerIcerigi(Icons.nightlight_round, 'Gece',
                o.geceSaati.toStringAsFixed(1)),
          ],
        );

    Widget sagSutun() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            degerIcerigi(
                null, 'Normal Mesai', o.normalMesai.toStringAsFixed(1)),
            const SizedBox(height: 1),
            degerIcerigi(
                null,
                'Fazla Mesai',
                o.fazlaMesaiGunu == 0
                    ? '– Gün'
                    : '${o.fazlaMesaiGunu.toStringAsFixed(0)} Gün',
                renkV: o.fazlaMesaiGunu > 0 ? R.kirmizi : null),
          ],
        );

    return Container(
      decoration: BoxDecoration(
        color: renk.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: renk, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(o.personel.ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: renk)),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: R.yesil.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: R.yesil.withValues(alpha: .4)),
                ),
                child: Text('Kalan Yıllık İzin: $kalan',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: R.yesil)),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: solSutun()),
              Expanded(child: sagSutun()),
            ],
          ),
          const SizedBox(height: 1),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: durumRengi.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('TOPLAM: ${o.toplamSaat.toStringAsFixed(1)} SAAT',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: durumRengi)),
          ),
        ],
      ),
    );
  }

  Widget _bosDurum(String baslik, String aciklama) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_outlined, size: 40, color: R.gri),
            const SizedBox(height: 12),
            Text(baslik,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(aciklama,
                textAlign: TextAlign.center,
                style: const TextStyle(color: R.gri)),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // EYLEMLER
  // ---------------------------------------------------------------------------
  Future<void> _vardiyaSec(NobetDurumu d, int gun, Personel p) async {
    if (d.yayinKilidi) {
      _bilgi('Bu liste YAYINDA olduğu için değişiklik yapılamaz. Önce '
          'göz simgesine basıp yayından kaldırın.');
      return;
    }
    if (d.onayKilidi && !await _kilidiAc(d)) return;
    if (!mounted) return;
    final tarih = DateTime(d.yil, d.ay, gun);
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
                  // Tablodaki hücreyle aynı renk — seçim listesinde de
                  // vardiya türü bir bakışta tanınsın.
                  leading: Builder(builder: (ctx2) {
                    final boya = vardiyaBoyasi(v.kod,
                        koyu:
                            Theme.of(ctx2).brightness == Brightness.dark);
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
                  trailing: d.kod(gun, p.id) == v.kod
                      ? const Icon(Icons.check, color: R.yesil, size: 18)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);

                    // Resmi tatilde Y.İ. veya İ.İ. — engellemez, bilgilendirir.
                    if (v.kod == kYillikIzin || v.kod == kIdariIzin) {
                      final t = DateTime(d.yil, d.ay, gun);
                      final tatilGunu =
                          t.weekday == DateTime.sunday || d.ayar.resmiTatilMi(t);
                      if (tatilGunu && mounted) {
                        await _tatilYIUyarisi(v.kod);
                        if (!mounted) return;
                      }
                    }

                    final uyari = d.dinlenmeIhlali(gun, p.id, v.kod);
                    if (uyari == null) {
                      d.kodAta(gun, p.id, v.kod);
                      return;
                    }
                    final devam = await _ihlalOnayi(uyari);
                    if (devam == true) d.kodAta(gun, p.id, v.kod);
                  },
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.backspace_outlined,
                    size: 20, color: R.gri),
                title: const Text('Hücreyi temizle'),
                onTap: () {
                  d.kodAta(gun, p.id, '');
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

  /// "Onaylanan Liste" üzerinde düzenleme yapılmadan önce PIN sorar.
  /// Doğru girilirse kilit bu oturumluk açık kalır (madde 12B).
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
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

  Widget _versiyonSecici(NobetDurumu d) {
    IconData ikon(String v) => switch (v) {
          kVersiyonSablon => Icons.description_outlined,
          kVersiyonOnayli => Icons.verified_outlined,
          kVersiyonTaslak => Icons.edit_note,
          _ => Icons.list_alt,
        };

    if (d.sadecePdf || d.personelGorunumu) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: R.mavi.withValues(alpha: .10),
          border: Border.all(color: const Color(0xFF00C853), width: 1.5),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ikon(d.aktifVersiyon), size: 14, color: R.kirmizi),
            const SizedBox(width: 5),
            Text(d.kayit.versiyonAdi,
                style: const TextStyle(fontSize: 12.5, color: R.kirmizi)),
            const SizedBox(width: 4),
            const Icon(Icons.lock, size: 12, color: R.kirmizi),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      tooltip: 'Liste seç',
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 320),
      onSelected: (v) async {
        if (v.startsWith('#kopya#')) {
          await _versiyonaKopyala(d, v.substring(7));
        } else if (v.startsWith('#bosalt#')) {
          await _versiyonBosalt(d, v.substring(8));
        } else {
          await d.versiyonDegistir(v);
        }
      },
      itemBuilder: (_) => [
        for (final v in d.versiyonlar)
          PopupMenuItem(
            value: v,
            child: Row(
              children: [
                Icon(
                  v == d.aktifVersiyon
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: v == d.aktifVersiyon ? R.mavi : R.gri,
                ),
                const SizedBox(width: 10),
                Icon(ikon(v), size: 16, color: R.gri),
                const SizedBox(width: 8),
                Text(versiyonAdi(v)),
              ],
            ),
          ),
        if (d.duzenleyebilir) ...[
          const PopupMenuDivider(),
          for (final v in d.versiyonlar)
            if (v != d.aktifVersiyon)
              PopupMenuItem(
                value: '#kopya#$v',
                child: Row(children: [
                  const Icon(Icons.copy_all_outlined, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '→ ${versiyonAdi(v)} listesine kopyala',
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
        ],
        if (d.yonetebilir) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: '#bosalt#${d.aktifVersiyon}',
            child: Row(children: [
              const Icon(Icons.delete_sweep_outlined,
                  size: 16, color: R.kirmizi),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '"${versiyonAdi(d.aktifVersiyon)}" bu ayını boşalt',
                  style: const TextStyle(color: R.kirmizi, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: d.aktifVersiyon == kVersiyonOnayli
              ? R.mavi.withValues(alpha: .10)
              : null,
          border: Border.all(
            color: const Color(0xFF00C853),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ikon(d.aktifVersiyon),
                size: 14,
                color: d.aktifVersiyon == kVersiyonOnayli ? R.kirmizi : null),
            const SizedBox(width: 5),
            Text(d.kayit.versiyonAdi,
                style: TextStyle(
                    fontSize: 12.5,
                    color: d.aktifVersiyon == kVersiyonOnayli
                        ? R.kirmizi
                        : null)),
            if (d.kilitli) ...[
              const SizedBox(width: 4),
              Icon(Icons.lock,
                  size: 12,
                  color: d.aktifVersiyon == kVersiyonOnayli
                      ? R.kirmizi
                      : R.yesil),
            ],
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _versiyonaKopyala(NobetDurumu d, String hedef) async {
    if (hedef == kVersiyonOnayli && !d.onaylananListeAcikMi) {
      if (!await _kilidiAc(d)) return;
      if (!mounted) return;
    }

    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Listeye kopyala'),
        content: Text(
          '${T.ayYil(d.yil, d.ay)} — "${d.kayit.versiyonAdi}" listesi '
          '"${versiyonAdi(hedef)}" listesinin üzerine yazılacak. Hedef '
          'liste yayındaysa işlem reddedilir.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Kopyala')),
        ],
      ),
    );
    if (onay != true) return;
    final oturum = context.read<OturumDurumu>();
    final mesaj =
        await d.versiyonaKopyala(hedef, kaydeden: oturum.kullanici?.ad ?? '');
    if (mounted) _bilgi(mesaj);
  }

  Future<void> _versiyonBosalt(NobetDurumu d, String versiyon) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: R.kirmizi, size: 30),
        title: const Text('Listeyi boşalt'),
        content: Text(
          '${T.ayYil(d.yil, d.ay)} — "${versiyonAdi(versiyon)}" listesinin '
          'bu aya ait tüm nöbetleri silinecek. Diğer aylar etkilenmez.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: R.kirmizi),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Boşalt')),
        ],
      ),
    );
    if (onay != true) return;
    await d.versiyonBosalt(versiyon);
    if (mounted) _bilgi('Liste boşaltıldı.');
  }

  /// Resmi tatil/pazar gününde Y.İ. veya İ.İ. seçildiğinde çıkan
  /// bilgilendirme. Engellemez — sadece bilgilendirir (madde 12A.3,
  /// ek bulgu 5 ile İ.İ. için de tutarlı hale getirildi).
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _ihlalOnayi(String mesaj) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: R.kirmizi, size: 32),
        title: const Text('DİKKAT: NÖBET İHLALİ'),
        content: Text(mesaj, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: R.kirmizi),
            child: const Text('Yine de yaz (riskli)'),
          ),
        ],
      ),
    );
  }

  Future<void> _listeYap(NobetDurumu d) async {
    if (d.yayinKilidi) {
      _bilgi('Bu liste YAYINDA olduğu için Liste Yap kullanılamaz. Önce '
          'göz simgesine basıp yayından kaldırın.');
      return;
    }
    if (d.onayKilidi && !await _kilidiAc(d)) return;
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
                        '${cekirdek + 1}. günden ayın sonuna kadar aynı döngü '
                        'tekrarlanır. İlk $cekirdek güne dokunulmaz.',
                    ikon: Icons.playlist_add_check,
                  ),
                  const SizedBox(height: 10),
                  _secenekKarti(
                    baslik: 'Geçen aydan devam et',
                    aciklama:
                        'Geçen ayın "Aylık Normal Şablon" listesinin son '
                        '$cekirdek günü çekirdek alınır ve bu ayın TAMAMI '
                        'yeniden kurulur. Şablon boşsa geçen ayın Nöbet '
                        'Listesi kullanılır.',
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
                            'mesai yazılır. Geri Al ile işlemi geri '
                            'alabilirsiniz.',
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

    if (secim == 'buay') {
      final mesaj = d.listeyiBuAydanDoldur(cekirdek: cekirdek);
      if (mounted) _bilgi(mesaj);
    } else {
      final mesaj = await d.listeyiGecenAydanDoldur(cekirdek: cekirdek);
      if (mounted) _bilgi(mesaj);
    }
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

  Future<void> _aylikNot(NobetDurumu d) async {
    final c = TextEditingController(text: d.kayit.aylikNot);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${T.ayYil(d.yil, d.ay)} — Aylık Not'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: c,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'PDF çıktısının altında yer alacak açıklama…',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              d.aylikNotKaydet(c.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  /// O ayın tam nöbet listesini tam ekran, salt-önizleme amaçlı bir
  /// popup'ta gösterir. Sağ üstteki X ile kapanır.
  ///
  /// Kendi ScrollController'larını kullanır — arkadaki asıl tablo hâlâ
  /// bağlı olduğu için aynı controller'ı burada tekrar kullanmak Flutter'ın
  /// "bir controller aynı anda tek kaydırma alanına bağlanabilir"
  /// kısıtını ihlal eder.
  Future<void> _onizlemeGoster(NobetDurumu d) async {
    if (!await d.onizlemeyeIzinVar()) {
      if (mounted) await yayinlanmadiUyarisiGoster(context);
      return;
    }
    if (!mounted) return;
    final baslikCtrl = ScrollController();
    final govdeCtrl = ScrollController();
    void senkronize() {
      if (baslikCtrl.hasClients &&
          baslikCtrl.offset != govdeCtrl.offset) {
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
              '${d.ayar.ad} — ${T.ayYil(d.yil, d.ay)} · ${d.kayit.versiyonAdi}',
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
            // Tablo, içerik genişliğini aşan ekranlarda sola yapışmasın
            // diye yatayda ortalanır; dar ekranda tüm alanı kullanır.
            // Android'de telefon ekranına daha çok sütun sığsın diye
            // daraltılmış ölçüler kullanılır (dar: true).
            child: Builder(builder: (ctx) {
              final dar =
                  Theme.of(ctx).platform == TargetPlatform.android;
              final maxW = dar
                  ? _tarihWDar +
                      _gunWDar +
                      d.personeller.length * _personelWDar +
                      _durumWDar +
                      2
                  : _tarihW +
                      _gunW +
                      d.personeller.length * _personelW +
                      _durumW +
                      2; // +2: sol/sağ çerçeve çizgileri
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxW),
                  child: _tablo(
                    baslikCtrl: baslikCtrl,
                    govdeCtrl: govdeCtrl,
                    saltOkunur: true,
                    dar: dar,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );

    govdeCtrl.removeListener(senkronize);
    baslikCtrl.dispose();
    govdeCtrl.dispose();
  }

  Future<void> _pdf(NobetDurumu d) async {
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
}
