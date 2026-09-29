import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/kapsama_motoru.dart';
import '../core/tarih.dart';
import '../modeller/modeller.dart';

/// Nöbet listesi PDF'i — yatay A4.
///
/// Gerekli dosyalar:
///   assets/fonts/Roboto-Regular.ttf   (Türkçe karakterler için)
///   assets/fonts/Roboto-Bold.ttf
///   assets/amblem.jpg                 (hastane amblemi — PDF başlığındaki logo)
///   assets/logo.png                   (amblem yoksa yedek)
class PdfServis {
  static pw.Font? _normal;
  static pw.Font? _kalin;
  static Uint8List? _logo;
  static bool _logoArandi = false;

  static const String kSabitNot =
      'ACİL DURUMLARDA BİR SONRAKİ GÜNÜN NÖBETÇİSİ İCAPÇIDIR.';

  /// Personel adını başlık hücresinde iki satıra böler: soyadı (son
  /// kelime) ikinci satırda, geri kalan ad(lar) ilk satırda — "Burak Can
  /// İnci" → "Burak Can" / "İnci".
  static String _adIkiSatir(String ad) {
    final i = ad.lastIndexOf(' ');
    return i < 0 ? ad : '${ad.substring(0, i)}\n${ad.substring(i + 1)}';
  }

  static Future<void> _hazirla() async {
    if (_normal == null) {
      try {
        _normal = pw.Font.ttf(
            await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
        _kalin =
            pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
      } catch (_) {
        _normal = pw.Font.helvetica();
        _kalin = pw.Font.helveticaBold();
      }
    }
    if (!_logoArandi) {
      _logoArandi = true;
      // Önce gerçek hastane amblemi, bulunamazsa uygulama logosu.
      for (final yol in const ['assets/amblem.jpg', 'assets/logo.png']) {
        try {
          final veri = await rootBundle.load(yol);
          _logo = veri.buffer.asUint8List();
          break;
        } catch (_) {
          _logo = null;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  static Future<Uint8List> olustur({
    required KurumAyari ayar,
    required List<Personel> personeller,
    required AyKaydi kayit,
    required int gunSayisi,
    required List<PersonelOzeti> ozetler,
    required Birim birim,
    required double hedefSaat,
  }) async {
    await _hazirla();
    final tema = pw.ThemeData.withFont(base: _normal!, bold: _kalin!);
    final belge = pw.Document(
        title: '${birim.etiket} ${T.ayYil(kayit.yil, kayit.ay)} Nöbet Listesi');

    belge.addPage(
      pw.MultiPage(
        theme: tema,
        // Dikey A4 — yatayda çıktı gereğinden geniş kalıyordu.
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          1.5 * PdfPageFormat.cm,
          0.7 * PdfPageFormat.cm,
          1.5 * PdfPageFormat.cm,
          0.5 * PdfPageFormat.cm,
        ),
        build: (ctx) => [
          _baslik(ayar, kayit, birim),
          pw.SizedBox(height: 8),
          _anaTablo(ayar, personeller, kayit, gunSayisi),
          pw.SizedBox(height: 10),
          _ozetBasligi(kayit),
          pw.SizedBox(height: 3),
          _ozetTablosu(ozetler),
          pw.SizedBox(height: 14),
          _notVeImza(kayit),
        ],
      ),
    );

    return belge.save();
  }

  // Satır zemini — öncelik: resmî tatil → yarım gün (arife) → hafta sonu.
  // Ekrandaki renk şemasıyla aynı sıra (bkz. nobet_listesi_ekrani.dart).
  static const _tatilZemin = PdfColor(1.0, 0xC2 / 0xFF, 0xB3 / 0xFF); // #FFC2B3
  static const _yarimGunZemin = PdfColor(1.0, 0xF7 / 0xFF, 0xB8 / 0xFF); // #FFF7B8

  static PdfColor _satirZemini(KurumAyari ayar, DateTime tarih) {
    if (ayar.resmiTatilMi(tarih)) return _tatilZemin;
    if (ayar.yarimGunMu(tarih)) return _yarimGunZemin;
    return T.haftaSonu(tarih) ? PdfColors.grey300 : PdfColors.white;
  }

  // ---------------------------------------------------------------------------
  static pw.Widget _baslik(KurumAyari ayar, AyKaydi kayit, Birim birim) {
    final ayYil = T.ayYil(kayit.yil, kayit.ay).toUpperCase();
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (_logo != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Image(pw.MemoryImage(_logo!),
                width: 66, height: 66, fit: pw.BoxFit.contain),
          ),
        pw.SizedBox(width: 14),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              ayar.ad,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${birim.etiket.toUpperCase()} PERSONELİ $ayYil NÖBET LİSTESİ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  static pw.Widget _anaTablo(
      KurumAyari ayar,
      List<Personel> personeller,
      AyKaydi kayit,
      int gunSayisi,
      ) {
    pw.Widget h(String metin) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
      child: pw.Center(
        child: pw.Text(metin,
            textAlign: pw.TextAlign.center,
            style:
            pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
      ),
    );

    pw.Widget c(String metin, {PdfColor? renk, bool kalin = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
          child: pw.Center(
            child: pw.Text(
              metin,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 8,
                color: renk ?? PdfColors.black,
                fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        );

    final genislikler = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(58),
      1: const pw.FixedColumnWidth(50),
    };
    for (var i = 0; i < personeller.length; i++) {
      genislikler[i + 2] = const pw.FlexColumnWidth(1);
    }

    final satirlar = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          h('TARİH'),
          h('GÜNLER'),
          ...personeller.map((p) => h(_adIkiSatir(p.ad))),
        ],
      ),
    ];

    for (var g = 1; g <= gunSayisi; g++) {
      final tarih = DateTime(kayit.yil, kayit.ay, g);
      final zemin = _satirZemini(ayar, tarih);
      const yazi = PdfColors.black; // metin kontrastı her zaman sabit

      satirlar.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: zemin),
        children: [
          c('${T.iki(g)}.${T.iki(kayit.ay)}.${kayit.yil}',
              renk: yazi, kalin: true),
          c(T.gunAdi(tarih), renk: yazi, kalin: true),
          // Tüm hücreler aynı ton ve kalınlıkta — N.İ./H.T. gibi kodlar da
          // vardiya saatleriyle aynı siyah ve kalın görünür.
          // Boş hücre ekranda olduğu gibi çıktıda da N.İ. sayılır.
          ...personeller.map((p) {
            final kod = kayit.kod(g, p.id);
            return c(
              kod.isEmpty ? kNobetIzni : kod,
              renk: PdfColors.black,
              kalin: true,
            );
          }),
        ],
      ));
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: genislikler,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: satirlar,
    );
  }

  // ---------------------------------------------------------------------------
  static pw.Widget _notVeImza(AyKaydi kayit) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 7,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: 'NOT: ',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.TextSpan(
                      text: kSabitNot, style: const pw.TextStyle(fontSize: 8)),
                ]),
              ),
              if (kayit.aylikNot.trim().isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 6),
                  child: pw.Text(kayit.aylikNot.trim(),
                      style: const pw.TextStyle(fontSize: 8)),
                ),
            ],
          ),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('ONAYLAYAN',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  static pw.Widget _ozetBasligi(AyKaydi kayit) => pw.Text(
    'AYLIK ÖZET',
    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
  );

  static pw.Widget _ozetTablosu(List<PersonelOzeti> ozetler) {
    pw.Widget h(String metin) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1, horizontal: 1),
      child: pw.Center(
        child: pw.Text(metin,
            textAlign: pw.TextAlign.center,
            style:
            pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
      ),
    );

    pw.Widget c(String metin, {bool kalin = false, PdfColor? renk}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1, horizontal: 1),
          child: pw.Center(
            child: pw.Text(
              metin,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: renk ?? PdfColors.black,
                fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        );

    // Türkçe ondalık ayracı (nokta değil virgül) — ek bulgu 22.
    String f(double d) {
      final metin =
      d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
      return metin.replaceAll('.', ',');
    }

    final satirlar = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          h('ADI SOYADI'),
          h('08:00\n20:00'),
          h('20:00\n08:00'),
          h('08:00\n16:00'),
          h('16:00\n24:00'),
          h('24:00\n08:00'),
          h('08:00\n17:30'),
          h('NÖBET\nİZNİ'),
          h('HAFTA\nTATİLİ'),
          h('YOL'),
          h('GÜNDÜZ'),
          h('GECE'),
          h('FAZLA\nMESAİ'),
        ],
      ),
    ];

    // "YOL" = o ay içinde fiilen nöbete girilen gün sayısı (aşağıdaki altı
    // vardiya sütununun toplamı) — eskiden burada gösterilen Yıllık İzin'in
    // yerini alır.
    const yolKodlari = [kGunduz12, kGece12, kSabah8, kAksam8, kGece8, kMesai];

    for (final o in ozetler) {
      final gunduz = o.toplamSaat - o.geceSaati;
      final yol = yolKodlari.fold<int>(0, (t, kod) => t + o.adet(kod));
      satirlar.add(pw.TableRow(children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1, horizontal: 3),
          child: pw.Text(o.personel.ad,
              style: pw.TextStyle(
                  fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
        ),
        c('${o.adet(kGunduz12)}'),
        c('${o.adet(kGece12)}'),
        c('${o.adet(kSabah8)}'),
        c('${o.adet(kAksam8)}'),
        c('${o.adet(kGece8)}'),
        c('${o.adet(kMesai)}'),
        c('${o.adet(kNobetIzni)}'),
        c('${o.adet(kHaftaTatili)}'),
        c('$yol'),
        c(f(gunduz)),
        c(f(o.geceSaati)),
        c('${f(o.fazlaMesaiGunu)} GÜN', kalin: true, renk: PdfColors.red800),
      ]));
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(90),
        1: pw.FixedColumnWidth(28),
        2: pw.FixedColumnWidth(28),
        3: pw.FixedColumnWidth(28),
        4: pw.FixedColumnWidth(28),
        5: pw.FixedColumnWidth(28),
        6: pw.FixedColumnWidth(28),
        7: pw.FixedColumnWidth(28),
        8: pw.FixedColumnWidth(28),
        9: pw.FixedColumnWidth(28),
        10: pw.FixedColumnWidth(32),
        11: pw.FixedColumnWidth(28),
        12: pw.FixedColumnWidth(34),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: satirlar,
    );
  }

  // ---------------------------------------------------------------------------
  static Future<void> onizle({
    required KurumAyari ayar,
    required List<Personel> personeller,
    required AyKaydi kayit,
    required int gunSayisi,
    required List<PersonelOzeti> ozetler,
    required Birim birim,
    required double hedefSaat,
  }) async {
    final bayt = await olustur(
      ayar: ayar,
      personeller: personeller,
      kayit: kayit,
      gunSayisi: gunSayisi,
      ozetler: ozetler,
      birim: birim,
      hedefSaat: hedefSaat,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bayt,
      name: 'Nobet_${birim.name}_'
          '${T.donemAnahtari(kayit.yil, kayit.ay)}.pdf',
    );
  }

  // ---------------------------------------------------------------------------
  // HAFTALIK NÖBET PDF'İ
  // ---------------------------------------------------------------------------
  /// Haftalık Nöbet ekranındaki TÜM ızgarayı (birden fazla ay, haftalık
  /// toplam satırları dahil) tek sayfaya sığdırarak üretir. Personel
  /// sütunları, sayfanın gerçek kullanılabilir genişliğine göre BAŞTAN
  /// hesaplanan sabit genişliktedir (bkz. [_haftalikTablo]) — böylece
  /// tabloya asla sayfa sınırının dışına taşacak bir doğal genişlik
  /// verilmez ve [pw.FittedBox] sadece (çok haftalı aylarda) dikey
  /// taşmayı ölçekleyerek tek sayfaya sığdırır.
  ///
  /// Veri, ekranın kendi durumundan (`_kayitlar`, per-ay `Madde3Motoru`)
  /// gelir; bu servis sadece render eder — [kodBul]/[durumBul]/
  /// [haftaToplamBul] callback'leri ekranın o anki (kaydedilmiş veya
  /// henüz kaydedilmemiş) hâlini birebir yansıtır.
  static Future<Uint8List> olusturHaftalik({
    required KurumAyari ayar,
    required List<Personel> personeller,
    required Birim birim,
    required int yil,
    required int ay,
    required List<List<DateTime>> haftalar,
    required String Function(DateTime tarih, String personelId) kodBul,
    required GercekKapsama Function(DateTime tarih) durumBul,
    required double Function(List<DateTime> hafta, String personelId)
    haftaToplamBul,
  }) async {
    await _hazirla();
    final tema = pw.ThemeData.withFont(base: _normal!, bold: _kalin!);
    final belge = pw.Document(
        title:
        '${birim.etiket} ${T.ayYil(yil, ay)} Haftalık Nöbet Listesi');

    final ilk = haftalar.first.first;
    final son = haftalar.last.last;

    // Dikey A4 — yatay (landscape) sayfa aylık listede de aynı sorunu
    // yaratmıştı (bkz. `olustur()` yorumundaki not): birçok yazıcı/görüntü-
    // leyici çıktıyı otomatik yatay olarak tanımayıp dikey kağıda göre
    // kırpıyor. Sütun genişlikleri sayfanın gerçek kullanılabilir
    // genişliğine göre hesaplandığı için (bkz. [_haftalikTablo]) dikeye
    // geçmek başka bir değişiklik gerektirmiyor.
    const yatayMargin = 1 * PdfPageFormat.cm;
    const sayfaFormati = PdfPageFormat.a4;
    final kullanilabilirGenislik =
        sayfaFormati.width - (2 * yatayMargin);

    belge.addPage(
      pw.Page(
        theme: tema,
        pageFormat: sayfaFormati,
        margin: const pw.EdgeInsets.fromLTRB(
          yatayMargin,
          0.5 * PdfPageFormat.cm,
          yatayMargin,
          0.5 * PdfPageFormat.cm,
        ),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _haftalikBaslik(ayar, birim, yil, ay, ilk, son),
            pw.SizedBox(height: 5),
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.topCenter,
                child: _haftalikTablo(
                  ayar: ayar,
                  personeller: personeller,
                  haftalar: haftalar,
                  kodBul: kodBul,
                  durumBul: durumBul,
                  haftaToplamBul: haftaToplamBul,
                  sayfaGenisligi: kullanilabilirGenislik,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return belge.save();
  }

  static pw.Widget _haftalikBaslik(KurumAyari ayar, Birim birim, int yil,
      int ay, DateTime ilk, DateTime son) {
    final ayYil = T.ayYil(yil, ay).toUpperCase();
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (_logo != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Image(pw.MemoryImage(_logo!),
                width: 42, height: 42, fit: pw.BoxFit.contain),
          ),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              ayar.ad,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${birim.etiket.toUpperCase()} PERSONELİ $ayYil HAFTALIK '
                  'NÖBET LİSTESİ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 1),
            pw.Text('${T.tarih(ilk)} - ${T.tarih(son)}',
                style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _haftalikTablo({
    required KurumAyari ayar,
    required List<Personel> personeller,
    required List<List<DateTime>> haftalar,
    required String Function(DateTime tarih, String personelId) kodBul,
    required GercekKapsama Function(DateTime tarih) durumBul,
    required double Function(List<DateTime> hafta, String personelId)
    haftaToplamBul,
    required double sayfaGenisligi,
  }) {
    pw.Widget h(String metin) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: pw.Center(
        child: pw.Text(metin,
            textAlign: pw.TextAlign.center,
            style:
            pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
      ),
    );

    pw.Widget c(String metin, {PdfColor? renk, bool kalin = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: pw.Center(
            child: pw.Text(
              metin,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 9,
                color: renk ?? PdfColors.black,
                fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        );

    // NOT: FlexColumnWidth burada kullanılamaz — bu tablo pw.FittedBox
    // içinde ölçeklendiği için önce SINIRSIZ genişlikte "doğal boyutu"
    // hesaplanıyor; flex sütunlar, kendilerini paylaştıracak sınırlı bir
    // genişlik olmadan 0'a çöküyor (personel sütunları PDF'te boş
    // çıkıyordu). Bu yüzden her sütun sabit genişlikte VE genişlikler
    // sayfanın gerçek kullanılabilir genişliğine göre hesaplanıyor —
    // tablo hiçbir zaman sayfadan taşacak bir doğal genişliğe sahip
    // olmuyor, dolayısıyla sağ kenardan kesilme de yaşanmıyor.
    const tarihW = 62.0;
    const gunW = 52.0;
    final personelSayisi = personeller.length;
    final kalanGenislik = sayfaGenisligi - tarihW - gunW;
    // En az 34pt — çok kalabalık kadrolarda okunaklılık alt sınırı;
    // bu durumda tablo sayfadan biraz taşabilir ama FittedBox onu da
    // ölçekleyip tek sayfaya sığdırır (ikinci bir güvenlik ağı).
    final personelW = personelSayisi == 0
        ? 0.0
        : (kalanGenislik / personelSayisi).clamp(34.0, 90.0);

    final genislikler = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(tarihW),
      1: const pw.FixedColumnWidth(gunW),
    };
    for (var i = 0; i < personeller.length; i++) {
      genislikler[i + 2] = pw.FixedColumnWidth(personelW);
    }

    final satirlar = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          h('TARİH'),
          h('GÜNLER'),
          ...personeller.map((p) => h(_adIkiSatir(p.ad))),
        ],
      ),
    ];

    for (final hafta in haftalar) {
      for (final tarih in hafta) {
        final zemin = _satirZemini(ayar, tarih);

        satirlar.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: zemin),
          children: [
            c('${T.iki(tarih.day)}.${T.iki(tarih.month)}.${tarih.year}',
                kalin: true),
            c(T.gunAdi(tarih), kalin: true),
            ...personeller.map((p) {
              final kod = kodBul(tarih, p.id);
              return c(kod.isEmpty ? kNobetIzni : kod, kalin: true);
            }),
          ],
        ));
      }

      // Haftalık toplam satırı — hafta bloğu bittiğinde eklenir.
      satirlar.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blue50),
        children: [
          c(''),
          c('TOPLAM', renk: PdfColors.red800, kalin: true),
          ...personeller.map((p) => c(
            _ondalikliSayi(haftaToplamBul(hafta, p.id)),
            renk: PdfColors.red800,
            kalin: true,
          )),
        ],
      ));
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: genislikler,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: satirlar,
    );
  }

  /// Türkçe ondalık ayracı (nokta değil virgül).
  static String _ondalikliSayi(double d) {
    final metin =
    d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
    return metin.replaceAll('.', ',');
  }

  static Future<void> onizleHaftalik({
    required KurumAyari ayar,
    required List<Personel> personeller,
    required Birim birim,
    required int yil,
    required int ay,
    required List<List<DateTime>> haftalar,
    required String Function(DateTime tarih, String personelId) kodBul,
    required GercekKapsama Function(DateTime tarih) durumBul,
    required double Function(List<DateTime> hafta, String personelId)
    haftaToplamBul,
  }) async {
    final bayt = await olusturHaftalik(
      ayar: ayar,
      personeller: personeller,
      birim: birim,
      yil: yil,
      ay: ay,
      haftalar: haftalar,
      kodBul: kodBul,
      durumBul: durumBul,
      haftaToplamBul: haftaToplamBul,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bayt,
      name: 'Haftalik_Nobet_${birim.name}_${T.donemAnahtari(yil, ay)}.pdf',
    );
  }

  // ---------------------------------------------------------------------------
  // "15 - 14 NÖBET" PDF'İ
  // ---------------------------------------------------------------------------
  /// Haftalık PDF'in aynı tek-sayfa/dinamik-sütun-genişliği mantığını
  /// kullanır ama hafta bloklarına ayırmaz — Nöbet Listesi'ndeki gibi tek,
  /// kesintisiz bir gün listesi üretir; en altta tek bir TOPLAM satırı olur.
  static Future<Uint8List> olusturDonem({
    required KurumAyari ayar,
    required List<Personel> personeller,
    required Birim birim,
    required int yil,
    required int ay,
    required List<DateTime> gunler,
    required String Function(DateTime tarih, String personelId) kodBul,
    required GercekKapsama Function(DateTime tarih) durumBul,
    required double Function(String personelId) toplamSaatBul,
  }) async {
    await _hazirla();
    final tema = pw.ThemeData.withFont(base: _normal!, bold: _kalin!);
    final belge = pw.Document(
        title: '${birim.etiket} 15 - 14 Nöbet Listesi');

    const yatayMargin = 1 * PdfPageFormat.cm;
    const sayfaFormati = PdfPageFormat.a4;
    final kullanilabilirGenislik = sayfaFormati.width - (2 * yatayMargin);

    belge.addPage(
      pw.Page(
        theme: tema,
        pageFormat: sayfaFormati,
        margin: const pw.EdgeInsets.fromLTRB(
          yatayMargin,
          0.7 * PdfPageFormat.cm,
          yatayMargin,
          0.6 * PdfPageFormat.cm,
        ),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _donemBaslik(ayar, birim, gunler.first, gunler.last),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.topCenter,
                child: _donemTablo(
                  ayar: ayar,
                  personeller: personeller,
                  gunler: gunler,
                  kodBul: kodBul,
                  durumBul: durumBul,
                  toplamSaatBul: toplamSaatBul,
                  sayfaGenisligi: kullanilabilirGenislik,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return belge.save();
  }

  static pw.Widget _donemBaslik(
      KurumAyari ayar, Birim birim, DateTime ilk, DateTime son) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (_logo != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Image(pw.MemoryImage(_logo!),
                width: 42, height: 42, fit: pw.BoxFit.contain),
          ),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              ayar.ad,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${birim.etiket.toUpperCase()} PERSONELİ 15 - 14 NÖBET LİSTESİ',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            ),
            pw.SizedBox(height: 1),
            pw.Text('${T.tarih(ilk)} - ${T.tarih(son)}',
                style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _donemTablo({
    required KurumAyari ayar,
    required List<Personel> personeller,
    required List<DateTime> gunler,
    required String Function(DateTime tarih, String personelId) kodBul,
    required GercekKapsama Function(DateTime tarih) durumBul,
    required double Function(String personelId) toplamSaatBul,
    required double sayfaGenisligi,
  }) {
    pw.Widget h(String metin) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: pw.Center(
        child: pw.Text(metin,
            textAlign: pw.TextAlign.center,
            style:
            pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
      ),
    );

    pw.Widget c(String metin, {PdfColor? renk, bool kalin = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: pw.Center(
            child: pw.Text(
              metin,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 9,
                color: renk ?? PdfColors.black,
                fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        );

    const tarihW = 62.0;
    const gunW = 52.0;
    final personelSayisi = personeller.length;
    final kalanGenislik = sayfaGenisligi - tarihW - gunW;
    final personelW = personelSayisi == 0
        ? 0.0
        : (kalanGenislik / personelSayisi).clamp(34.0, 90.0);

    final genislikler = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(tarihW),
      1: const pw.FixedColumnWidth(gunW),
    };
    for (var i = 0; i < personeller.length; i++) {
      genislikler[i + 2] = pw.FixedColumnWidth(personelW);
    }

    final satirlar = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          h('TARİH'),
          h('GÜNLER'),
          ...personeller.map((p) => h(_adIkiSatir(p.ad))),
        ],
      ),
    ];

    for (final tarih in gunler) {
      final zemin = _satirZemini(ayar, tarih);

      satirlar.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: zemin),
        children: [
          c('${T.iki(tarih.day)}.${T.iki(tarih.month)}.${tarih.year}',
              kalin: true),
          c(T.gunAdi(tarih), kalin: true),
          ...personeller.map((p) {
            final kod = kodBul(tarih, p.id);
            return c(kod.isEmpty ? kNobetIzni : kod, kalin: true);
          }),
        ],
      ));
    }

    satirlar.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.blue50),
      children: [
        c(''),
        c('TOPLAM', renk: PdfColors.red800, kalin: true),
        ...personeller.map((p) => c(
          _ondalikliSayi(toplamSaatBul(p.id)),
          renk: PdfColors.red800,
          kalin: true,
        )),
      ],
    ));

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: genislikler,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: satirlar,
    );
  }

  static Future<void> onizleDonem({
    required KurumAyari ayar,
    required List<Personel> personeller,
    required Birim birim,
    required int yil,
    required int ay,
    required List<DateTime> gunler,
    required String Function(DateTime tarih, String personelId) kodBul,
    required GercekKapsama Function(DateTime tarih) durumBul,
    required double Function(String personelId) toplamSaatBul,
  }) async {
    final bayt = await olusturDonem(
      ayar: ayar,
      personeller: personeller,
      birim: birim,
      yil: yil,
      ay: ay,
      gunler: gunler,
      kodBul: kodBul,
      durumBul: durumBul,
      toplamSaatBul: toplamSaatBul,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bayt,
      name: '15_14_Nobet_${birim.name}_${T.donemAnahtari(yil, ay)}.pdf',
    );
  }
}