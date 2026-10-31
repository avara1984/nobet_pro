import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/kapsama_motoru.dart';
import '../core/tarih.dart';
import '../core/tema.dart';
import '../durum/nobet_durumu.dart';
import '../modeller/modeller.dart';

class AylikOzetEkrani extends StatefulWidget {
  const AylikOzetEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<AylikOzetEkrani> createState() => _AylikOzetEkraniState();
}

class _AylikOzetEkraniState extends State<AylikOzetEkrani> {
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
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    final genis = widget.genis;

    if (!d.listeGorunurMu) {
      return Center(
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
    }

    _yillikIzinYukleGerekirse(d);

    return SingleChildScrollView(
      padding: genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${T.ayYil(d.yil, d.ay)} — ${d.birim.etiket} Personel Özeti',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          const Text(
            'Saatler mola düşülmüş bordro değerleridir. Resmi tatilde '
            'çalışılan gündüz vardiyaları normal mesaiden düşülüp fazla '
            'mesai günü olarak sayılır.',
            style: TextStyle(fontSize: 12, color: R.gri, height: 1.5),
          ),
          const SizedBox(height: 6),
          _hedefPaneli(context, d, genis),
          const SizedBox(height: 6),
          FutureBuilder<Map<String, int>>(
            future: _yillikIzinGelecek,
            builder: (ctx, anlik) =>
                _ozetTablosu(context, d, anlik.data ?? const {}),
          ),
          const SizedBox(height: 6),
          const Text('Kapsama Denetimi',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          _kapsamaPaneli(context, d),
          const SizedBox(height: 8),
          const Text('Vardiya Tanımları',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          _lejant(context, d),
        ],
      ),
    );
  }

  /// Sütun başlığı: vardiya saat aralığı kısaltılmadan, başlangıç ve bitiş
  /// alt alta yazılır ('08:00 - 17:30' → '08:00' / '17:30'). N.İ./Y.İ.
  /// kısaltma yerine tam adıyla gösterilir; diğer izin türleri olduğu gibi
  /// kalır.
  String _vardiyaBasligi(VardiyaTanimi v) {
    if (v.kod == kNobetIzni) return 'Nöbet\nİzni';
    if (v.kod == kYillikIzin) return 'Yıllık\nİzin';
    final parcalar = v.kod.split(' - ');
    return parcalar.length == 2 ? '${parcalar[0]}\n${parcalar[1]}' : v.kod;
  }

  /// Özet tablosunun başlık hücresi — çok satırlı başlıklarda satırlar
  /// birbirine göre ortalanır.
  static const double _baslikY = 38;

  /// Sütun aralığı hücrelerin kendi iç dolgusuyla verilir (columnSpacing 0):
  /// vardiya başlıkları hücrenin tamamını boyayabilsin diye.
  static const double _hucreDolgu = 10;

  /// Personel sütununun sol boşluğu (tablonun eski yatay kenar boşluğu).
  static const double _kenarBosluk = 24;

  Widget _baslik(String metin) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: _hucreDolgu),
        child: Text(metin, textAlign: TextAlign.center),
      );

  /// Vardiya saati başlığı: hücrenin tamamı nöbet tablolarındaki açık
  /// kırmızı başlık rengiyle boyanır.
  Widget _vardiyaBaslik(BuildContext context, String metin) => Container(
        height: _baslikY,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: _hucreDolgu),
        color: Tema.nobetTabloBaslik(context),
        child: Text(metin, textAlign: TextAlign.center),
      );

  DataCell _hucre(Widget child) => DataCell(Padding(
        padding: const EdgeInsets.symmetric(horizontal: _hucreDolgu),
        child: child,
      ));

  // ---------------------------------------------------------------------------
  Widget _ozetTablosu(
      BuildContext context, NobetDurumu d, Map<String, int> yillikIzin) {
    final calisan =
        d.ayar.vardiyalar.where((v) => v.calisiyor).toList();
    // H.T./R.T./İ.İ. bu özet tablosunda gösterilmiyor — ekranda gereksiz
    // yer kaplıyorlardı; nöbet listesindeki kod olarak kullanımları etkilenmez.
    const gizliIzinKodlari = {kHaftaTatili, kResmiTatil, kIdariIzin};
    final izinler = d.ayar.vardiyalar
        .where((v) =>
            !v.calisiyor &&
            v.kod.isNotEmpty &&
            !gizliIzinKodlari.contains(v.kod))
        .toList();
    final ozetler = d.ozetler;
    final hedef = d.aylikHedefSaat;

    if (ozetler.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text('Kayıtlı personel yok.',
              style: TextStyle(color: R.gri)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tema.kenar(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(Tema.tabloBaslik(context)),
          columnSpacing: 0,
          horizontalMargin: 0,
          headingRowHeight: _baslikY,
          dataRowMinHeight: 34,
          dataRowMaxHeight: 40,
          border: TableBorder.symmetric(
            inside: BorderSide(color: Tema.kenar(context)),
          ),
          columns: [
            DataColumn(
                label: Padding(
                  padding: const EdgeInsets.only(left: _kenarBosluk),
                  child: _baslik('Personel'),
                ),
                headingRowAlignment: MainAxisAlignment.center),
            for (final v in calisan)
              DataColumn(
                label: Tooltip(
                  message: '${v.etiket}  ·  ${v.saat.toStringAsFixed(1)} saat',
                  child: _vardiyaBaslik(context, _vardiyaBasligi(v)),
                ),
                numeric: true,
                headingRowAlignment: MainAxisAlignment.center,
              ),
            for (final v in izinler)
              DataColumn(
                label: Tooltip(
                  message: v.kod == kNobetIzni
                      ? 'İzin türü değil — bu ay nöbete yazılmayan gün sayısı'
                      : v.etiket,
                  child: _vardiyaBaslik(context, _vardiyaBasligi(v)),
                ),
                numeric: true,
                headingRowAlignment: MainAxisAlignment.center,
              ),
            DataColumn(
                label: _vardiyaBaslik(context, 'Toplam\nSaat'),
                numeric: true,
                headingRowAlignment: MainAxisAlignment.center),
            DataColumn(
                label: _vardiyaBaslik(context, 'Gece\nSaati'),
                numeric: true,
                headingRowAlignment: MainAxisAlignment.center),
            DataColumn(
                label: _vardiyaBaslik(context, 'Normal\nMesai'),
                numeric: true,
                headingRowAlignment: MainAxisAlignment.center),
            DataColumn(
                label: _vardiyaBaslik(context, 'Fazla\nMesai'),
                numeric: true,
                headingRowAlignment: MainAxisAlignment.center),
            DataColumn(
                label: _vardiyaBaslik(context, 'Yıllık\nİzin'),
                numeric: true,
                headingRowAlignment: MainAxisAlignment.center),
          ],
          rows: [
            for (final o in ozetler)
              DataRow(cells: [
                DataCell(Padding(
                  padding: const EdgeInsets.only(
                      left: _kenarBosluk, right: _hucreDolgu),
                  child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor:
                          o.personel.mesaiMi ? R.turuncu : R.mavi,
                      child: Text(o.personel.basHarfler,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10)),
                    ),
                    const SizedBox(width: 8),
                    Text(o.personel.ad,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ))),
                for (final v in calisan) _sayiHucre(o.adet(v.kod)),
                for (final v in izinler) _sayiHucre(o.adet(v.kod)),
                _hucre(Center(
                  child: Text(
                    o.toplamSaat.toStringAsFixed(1),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: o.toplamSaat + 0.01 < hedef
                          ? R.kirmizi
                          : (o.toplamSaat > hedef + 0.01
                              ? R.turuncu
                              : R.yesil),
                    ),
                  ),
                )),
                _hucre(Center(
                  child: Text(
                    o.geceSaati == 0 ? '–' : o.geceSaati.toStringAsFixed(1),
                    style: TextStyle(
                        color: o.geceSaati > 0 ? R.maviKoyu : R.gri),
                  ),
                )),
                _hucre(Center(child: Text(o.normalMesai.toStringAsFixed(1)))),
                _hucre(Center(
                  child: Text(
                    o.fazlaMesaiGunu == 0
                        ? '–'
                        : o.fazlaMesaiGunu.toStringAsFixed(0),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: o.fazlaMesaiGunu > 0 ? R.turuncu : R.gri,
                    ),
                  ),
                )),
                () {
                  final kullanilan = yillikIzin[o.personel.id] ??
                      o.yillikIzinKullanilan; // veri gelene kadar geçici
                  final kalan = o.personel.yillikIzinKotasi - kullanilan;
                  return _hucre(Tooltip(
                    message: 'Hak: ${o.personel.yillikIzinKotasi} gün · '
                        '${T.aylar[d.ay - 1]} sonuna kadar (Ocak\'tan '
                        'itibaren) kullanılan: $kullanilan gün',
                    child: Center(
                      child: Text(
                        '$kalan',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: kalan < 5 ? R.kirmizi : R.yesil,
                        ),
                      ),
                    ),
                  ));
                }(),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _hedefPaneli(BuildContext context, NobetDurumu d, bool genis) {
    final hedef = d.aylikHedefSaat;
    var calismaGunu = 0;
    for (var g = 1; g <= d.gunSayisi; g++) {
      final t = DateTime(d.yil, d.ay, g);
      if (t.weekday == DateTime.sunday) continue;
      if (d.ayar.resmiTatilMi(t)) continue;
      calismaGunu++;
    }

    final baslik = Text(
      '${T.ayYil(d.yil, d.ay)} Aylık Çalışma Saati Hedefi: '
      '${hedef.toStringAsFixed(1)} Saat',
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    );

    const aciklamaStili = TextStyle(fontSize: 11.5, color: R.gri, height: 1.4);
    final aciklama = Text(
      '$calismaGunu çalışma günü · Pazar ve tam gün resmi tatiller '
      'düşüldü, arife günleri 3.5 saat sayıldı',
      style: aciklamaStili,
    );

    final lejant = Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _lejantNokta('Hedefin Altında', R.kirmizi),
        _lejantNokta('Hedefte', R.yesil),
        _lejantNokta('Hedefin Üstünde', R.turuncu),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tema.kenar(context)),
      ),
      child: genis
          ? Row(
              children: [
                const Icon(Icons.timelapse_outlined,
                    color: R.maviKoyu, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [baslik, const SizedBox(height: 3), aciklama],
                  ),
                ),
                const SizedBox(width: 16),
                lejant,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.timelapse_outlined,
                        color: R.maviKoyu, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: baslik),
                  ],
                ),
                const SizedBox(height: 6),
                aciklama,
                const SizedBox(height: 12),
                lejant,
              ],
            ),
    );
  }

  Widget _lejantNokta(String metin, Color renk) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(metin, style: const TextStyle(fontSize: 11, color: R.gri)),
        ],
      );

  DataCell _sayiHucre(int deger) => _hucre(
        Center(
          child: Text(deger == 0 ? '–' : '$deger',
              style: TextStyle(color: deger == 0 ? R.gri : null)),
        ),
      );

  // ---------------------------------------------------------------------------
  Widget _kapsamaPaneli(BuildContext context, NobetDurumu d) {
    final tumu = d.madde3.tumAy(d.yil, d.ay);
    final tam = tumu.where((k) => k.durum == GercekDurum.tamam).length;
    final kadroEksik =
        tumu.where((k) => k.durum == GercekDurum.kadroEksik).toList();
    final saatAcigi =
        tumu.where((k) => k.durum == GercekDurum.saatAcigi).toList();
    final bosGun = tumu.where((k) => k.durum == GercekDurum.bosGun).toList();
    final sorunlu = [...bosGun, ...saatAcigi, ...kadroEksik]
      ..sort((a, b) => a.gun.compareTo(b.gun));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tema.kenar(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _rozet('Kurallara Uygun', '$tam gün', R.yesil),
              _rozet('Kadro Eksik', '${kadroEksik.length} gün', R.turuncu),
              _rozet('Saat Açığı', '${saatAcigi.length} gün', R.kirmizi),
              _rozet('Boş Gün', '${bosGun.length} gün', R.kirmizi),
            ],
          ),
          if (sorunlu.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: Tema.kenar(context)),
            const SizedBox(height: 8),
            for (final k in sorunlu)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      k.durum == GercekDurum.kadroEksik
                          ? Icons.warning_amber_rounded
                          : Icons.error_outline,
                      size: 17,
                      color: k.durum == GercekDurum.kadroEksik
                          ? R.turuncu
                          : R.kirmizi,
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: Text(
                        T.tarih(DateTime(d.yil, d.ay, k.gun)),
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(k.mesaj,
                          style:
                              const TextStyle(fontSize: 12.5, height: 1.4)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _rozet(String baslik, String deger, Color renk) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$baslik: ',
              style: const TextStyle(fontSize: 12.5, color: R.gri)),
          Text(deger,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      );

  // ---------------------------------------------------------------------------
  Widget _lejant(BuildContext context, NobetDurumu d) => Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          for (final v in d.ayar.vardiyalar)
            if (v.kod.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Tema.kart(context),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Tema.kenar(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nöbet tablosundaki hücreyle aynı renk.
                    Builder(builder: (ctx) {
                      final boya = vardiyaBoyasi(v.kod,
                          koyu: Theme.of(ctx).brightness == Brightness.dark);
                      return Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: boya.rozet ? boya.zemin : Colors.transparent,
                          border: Border.all(color: Tema.kenar(ctx)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                    const SizedBox(width: 8),
                    Text(v.etiket, style: const TextStyle(fontSize: 12.5)),
                    if (v.saat > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${v.saat.toStringAsFixed(1)} sa'
                        '${v.geceSaati > 0 ? ' · ${v.geceSaati.toStringAsFixed(1)} gece' : ''}',
                        style: const TextStyle(fontSize: 11, color: R.gri),
                      ),
                    ],
                  ],
                ),
              ),
        ],
      );
}
