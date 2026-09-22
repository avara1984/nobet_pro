import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/para.dart';
import '../core/tarih.dart';
import '../modeller/bordro_modelleri.dart';

/// Bordro PDF'i — dikey A4.
///
/// Yazı tipi `pdf_servis.dart` ile aynı yerel dosyalardan yüklenir
/// (`assets/fonts/Roboto-*.ttf`); yoksa Helvetica'ya düşer ve Türkçe
/// karakterler bozulabilir.
class BordroPdfServis {
  static pw.Font? _normal;
  static pw.Font? _kalin;

  static const String kUyari =
      'UYARI: Bu bordro tahmin amaçlıdır. Resmi bordro KBS sistemindedir. '
      'Her ay KBS ile karşılaştırın.';

  static Future<pw.ThemeData> _tema() async {
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
    return pw.ThemeData.withFont(base: _normal!, bold: _kalin!);
  }

  // ---------------------------------------------------------------------------
  // TEK BORDRO
  // ---------------------------------------------------------------------------
  static Future<Uint8List> olustur({
    required BordroSonucu sonuc,
    required String kurumAdi,
    required String birimEtiketi,
  }) async {
    final tema = await _tema();
    final belge = pw.Document(
      title: 'Bordro ${sonuc.personelAd} ${T.ayYil(sonuc.yil, sonuc.ay)}',
    );

    belge.addPage(
      pw.Page(
        theme: tema,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          1.5 * PdfPageFormat.cm,
          1.0 * PdfPageFormat.cm,
          1.5 * PdfPageFormat.cm,
          1.0 * PdfPageFormat.cm,
        ),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                sonuc.gecisAyi ? 'GEÇİŞ AYI BORDROSU' : 'MAAŞ BORDROSU',
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(kurumAdi,
                      style: const pw.TextStyle(fontSize: 8)),
                ),
                pw.Text(
                  'Dönem: ${T.ayYil(sonuc.yil, sonuc.ay)}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.5, color: PdfColors.grey600),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Adı Soyadı: ${sonuc.personelAd}',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text(birimEtiketi,
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),

            // --- ÇALIŞMA BİLGİLERİ ---
            _baslikSeridi('ÇALIŞMA BİLGİLERİ'),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                _bilgi('Çalışma Günü', '${sonuc.calismaGunu}'),
                _bilgi('SGK Günü', '${sonuc.sgkGunu}'),
                _bilgi('Gece Saati', Para.sade(sonuc.geceSaati)),
                _bilgi('Tatil Çalışma', '${sonuc.tatilGunu} gün'),
                _bilgi('Yol/Yemek', '${sonuc.yolGunu} gün'),
              ],
            ),
            pw.SizedBox(height: 10),

            // --- GELİRLER ---
            _baslikSeridi('GELİRLER'),
            _satir('Günlük Ücret (Md.33)', sonuc.gunlukUcretToplami),
            _satir('Sosyal Yardım (Md.38)', sonuc.sosyalYardim),
            _satir('Hizmet Primi (Md.36)', sonuc.hizmetPrimi),
            _satir('Hizmet Zammı (Md.58)', sonuc.hizmetZammi),
            _satir('Yol Yardımı (Md.40)', sonuc.yolYardimi),
            _satir('Gece Çalışma (Md.23)', sonuc.geceCalismaUcreti),
            _satir('Tatil Çalışma (Md.22)', sonuc.tatilCalismaUcreti),
            if (sonuc.gecisAyi) ...[
              _satir('Ücret Farkı', sonuc.ucretFarki),
              _satir('Hizmet Primi Farkı', sonuc.hizmetPrimiFarki),
              _satir('Sosyal Yardım Farkı', sonuc.sosyalYardimFarki),
              _satir('Yol Yardımı Farkı', sonuc.yolYardimiFarki),
              _satir('Hizmet Zammı Farkı', sonuc.hizmetZammiFarki),
            ],
            pw.Divider(height: 6),
            _satir('BRÜT GELİR', sonuc.brutGelir, kalin: true),

            pw.SizedBox(height: 12),

            // --- KESİNTİLER ---
            _baslikSeridi('KESİNTİLER'),
            _satir('SGK Çalışan', sonuc.sgkCalisanKesintisi),
            _satir('SGK İşsizlik', sonuc.sgkIssizlikKesintisi),
            _satir('Gelir Vergisi', sonuc.gelirVergisi),
            _kucukSatir(
                'İstisna: ${Para.tl(sonuc.gelirVergisiIstisnasi)} · '
                'Yıllık matrah: ${Para.tl(sonuc.yillikMatrah)}'),
            _satir('Damga Vergisi', sonuc.damgaVergisi),
            _satir('Sendika Kesintisi', sonuc.sendikaKesintisi),
            pw.Divider(height: 6),
            _satir('TOPLAM KESİNTİ', sonuc.toplamKesinti, kalin: true),

            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue900,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('ÖDENECEK TUTAR',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 12)),
                  pw.Text('${Para.tl(sonuc.odenecekTutar)} TL',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
            ),

            pw.Spacer(),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(5),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.orange, width: 0.5),
              ),
              child: pw.Text(kUyari,
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.orange900)),
            ),
          ],
        ),
      ),
    );

    return belge.save();
  }

  static pw.Widget _baslikSeridi(String metin) => pw.Container(
        width: double.infinity,
        color: PdfColors.grey300,
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: pw.Center(
          child: pw.Text(metin,
              style:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        ),
      );

  static pw.Widget _bilgi(String etiket, String deger) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(etiket,
                style:
                    const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            pw.Text(deger,
                style:
                    pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ],
        ),
      );

  static pw.Widget _satir(String etiket, double deger, {bool kalin = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(etiket,
                style: pw.TextStyle(
                  fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal,
                  fontSize: 9,
                )),
            pw.Text(Para.tl(deger),
                style: pw.TextStyle(
                  fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal,
                  fontSize: 9,
                )),
          ],
        ),
      );

  static pw.Widget _kucukSatir(String metin) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Text(metin,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
      );

  // ---------------------------------------------------------------------------
  // TOPLU BORDRO
  // ---------------------------------------------------------------------------
  /// Birden çok bordroyu tek tabloda özetler (yıllık toplu döküm).
  static Future<Uint8List> topluOlustur({
    required List<BordroSonucu> kayitlar,
    required int yil,
    required String kurumAdi,
    required String birimEtiketi,
  }) async {
    final tema = await _tema();
    final belge = pw.Document(title: 'Toplu Bordro $yil');

    pw.Widget hucre(String metin,
            {bool kalin = false, bool saga = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          child: pw.Text(
            metin,
            textAlign: saga ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontWeight: kalin ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: 8,
            ),
          ),
        );

    final toplamBrut = kayitlar.fold(0.0, (t, k) => t + k.brutGelir);
    final toplamKesinti = kayitlar.fold(0.0, (t, k) => t + k.toplamKesinti);
    final toplamNet = kayitlar.fold(0.0, (t, k) => t + k.odenecekTutar);

    belge.addPage(
      pw.MultiPage(
        theme: tema,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          1.5 * PdfPageFormat.cm,
          1.0 * PdfPageFormat.cm,
          1.5 * PdfPageFormat.cm,
          1.0 * PdfPageFormat.cm,
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}',
              style:
                  pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
        ),
        build: (ctx) => [
          pw.Center(
            child: pw.Text('TOPLU MAAŞ BORDROSU — $yil',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 14)),
          ),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text('$kurumAdi · $birimEtiketi · '
                '${kayitlar.length} kayıt',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey700)),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2),
              4: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  hucre('PERSONEL', kalin: true),
                  hucre('AY', kalin: true),
                  hucre('BRÜT', kalin: true, saga: true),
                  hucre('KESİNTİ', kalin: true, saga: true),
                  hucre('NET', kalin: true, saga: true),
                ],
              ),
              for (final k in kayitlar)
                pw.TableRow(children: [
                  hucre(k.personelAd),
                  hucre(T.aylar[k.ay - 1]),
                  hucre(Para.tl(k.brutGelir), saga: true),
                  hucre(Para.tl(k.toplamKesinti), saga: true),
                  hucre(Para.tl(k.odenecekTutar), kalin: true, saga: true),
                ]),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  hucre('TOPLAM', kalin: true),
                  hucre(''),
                  hucre(Para.tl(toplamBrut), kalin: true, saga: true),
                  hucre(Para.tl(toplamKesinti), kalin: true, saga: true),
                  hucre(Para.tl(toplamNet), kalin: true, saga: true),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(kUyari,
              style: const pw.TextStyle(
                  fontSize: 7, color: PdfColors.orange900)),
        ],
      ),
    );

    return belge.save();
  }

  // ---------------------------------------------------------------------------
  static Future<void> onizle({
    required BordroSonucu sonuc,
    required String kurumAdi,
    required String birimEtiketi,
  }) async {
    final bayt = await olustur(
      sonuc: sonuc,
      kurumAdi: kurumAdi,
      birimEtiketi: birimEtiketi,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bayt,
      name: 'Bordro_${sonuc.personelAd}_'
          '${T.donemAnahtari(sonuc.yil, sonuc.ay)}.pdf',
    );
  }

  static Future<void> topluOnizle({
    required List<BordroSonucu> kayitlar,
    required int yil,
    required String kurumAdi,
    required String birimEtiketi,
  }) async {
    final bayt = await topluOlustur(
      kayitlar: kayitlar,
      yil: yil,
      kurumAdi: kurumAdi,
      birimEtiketi: birimEtiketi,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bayt,
      name: 'Toplu_Bordro_$yil.pdf',
    );
  }
}
