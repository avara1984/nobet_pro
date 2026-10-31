import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../core/bordro_hesap.dart';
import '../core/para.dart';
import '../core/tarih.dart';
import '../core/tema.dart';
import '../durum/nobet_durumu.dart';
import '../modeller/bordro_modelleri.dart';
import '../modeller/modeller.dart';
import '../servisler/bordro_pdf_servis.dart';

// =============================================================================
// ORTAK YARDIMCILAR
// =============================================================================
void _bilgi(BuildContext context, String mesaj, {bool hata = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(mesaj),
      width: 420,
      backgroundColor: hata ? R.kirmizi : null,
    ));
}

/// Sayı girişi için ortak alan — Türkçe virgüllü yazımı da kabul eder.
Widget _sayiAlani(TextEditingController c, String etiket, {String? ipucu}) =>
    TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
      decoration: InputDecoration(
        labelText: etiket,
        helperText: ipucu,
        helperMaxLines: 2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: const OutlineInputBorder(),
      ),
    );

Widget _kartCerceve(BuildContext context,
        {required Widget child, EdgeInsets? ic}) =>
    Container(
      width: double.infinity,
      padding: ic ?? const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tema.kenar(context)),
      ),
      child: child,
    );

Widget _bolumBasligi(String metin, {String? aciklama}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(metin,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (aciklama != null) ...[
          const SizedBox(height: 4),
          Text(aciklama,
              style:
                  const TextStyle(fontSize: 12, color: R.gri, height: 1.5)),
        ],
      ],
    );

/// Tahmin uyarısı — eski uygulamadaki KBS notunun karşılığı.
Widget _uyariSeridi() => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: R.turuncu.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: R.turuncu.withValues(alpha: .5)),
      ),
      child: const Row(children: [
        Icon(Icons.warning_amber_rounded, size: 18, color: R.turuncu),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Bu bordro tahmin amaçlıdır. Resmi bordro KBS sistemindedir; '
            'her ay KBS ile karşılaştırın.',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
          ),
        ),
      ]),
    );

/// Bordro yetkisi olmayan kullanıcılar için ortak engel.
Widget _yetkiYok() => const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: R.gri),
            SizedBox(height: 14),
            Text('Bu bölüme yalnızca Süper Admin ve Bordro Admini erişebilir.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );

Widget _bosDurum(String baslik, String aciklama, IconData ikon) => Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ikon, size: 42, color: R.gri),
            const SizedBox(height: 12),
            Text(baslik,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(aciklama,
                textAlign: TextAlign.center,
                style: const TextStyle(color: R.gri, height: 1.5)),
          ],
        ),
      ),
    );

// =============================================================================
// BORDRO HESAPLA
// =============================================================================
class BordroHesaplaEkrani extends StatefulWidget {
  const BordroHesaplaEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<BordroHesaplaEkrani> createState() => _BordroHesaplaEkraniState();
}

class _BordroHesaplaEkraniState extends State<BordroHesaplaEkrani> {
  final _calismaGunuC = TextEditingController();
  final _sgkGunuC = TextEditingController(text: '30');
  final _geceSaatiC = TextEditingController(text: '0');
  final _tatilGunuC = TextEditingController(text: '0');
  final _yolGunuC = TextEditingController(text: '0');
  final _oncekiMatrahC = TextEditingController(text: '0');

  bool _gecisAyi = false;
  final _ucretFarkiC = TextEditingController(text: '0');
  final _sosyalFarkiC = TextEditingController(text: '0');
  final _yolFarkiC = TextEditingController(text: '0');
  final _hizmetZammiFarkiC = TextEditingController(text: '0');
  final _sendikaFarkiC = TextEditingController(text: '0');

  String? _personelId;
  String _versiyon = kVersiyonOnayli;
  BordroAyari? _ayar;
  List<PersonelUcreti> _ucretler = const [];
  BordroSonucu? _sonuc;
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    for (final c in [
      _calismaGunuC,
      _sgkGunuC,
      _geceSaatiC,
      _tatilGunuC,
      _yolGunuC,
      _oncekiMatrahC,
      _ucretFarkiC,
      _sosyalFarkiC,
      _yolFarkiC,
      _hizmetZammiFarkiC,
      _sendikaFarkiC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final d = context.read<NobetDurumu>();
    setState(() => _mesgul = true);
    try {
      _ayar = await d.servis.bordroAyariGetir(d.kurumId, d.yil);
      _ucretler = await d.servis.personelUcretleriGetir(d.birimId);
      _calismaGunuC.text = '${d.gunSayisi}';
    } catch (e) {
      if (mounted) _bilgi(context, 'Bordro verileri okunamadı: $e', hata: true);
    }
    if (mounted) setState(() => _mesgul = false);
  }

  PersonelUcreti? get _seciliUcret {
    if (_personelId == null) return null;
    for (final u in _ucretler) {
      if (u.personelId == _personelId) return u;
    }
    return null;
  }

  /// Nöbet listesinden gece saati, tatil günü ve yol gününü otomatik doldurur.
  Future<void> _nobettenCek() async {
    final d = context.read<NobetDurumu>();
    if (_personelId == null) return;
    setState(() => _mesgul = true);
    try {
      final oncekiAy = d.ay == 1 ? 12 : d.ay - 1;
      final oncekiYil = d.ay == 1 ? d.yil - 1 : d.yil;
      final sonrakiAy = d.ay == 12 ? 1 : d.ay + 1;
      final sonrakiYil = d.ay == 12 ? d.yil + 1 : d.yil;

      final kayit = await d.servis
          .ayKaydiGetir(d.birimId, d.yil, d.ay, versiyon: _versiyon);
      final onceki = await d.servis
          .ayKaydiGetir(d.birimId, oncekiYil, oncekiAy, versiyon: _versiyon);
      final sonraki = await d.servis
          .ayKaydiGetir(d.birimId, sonrakiYil, sonrakiAy, versiyon: _versiyon);

      final girdi = nobettenGirdi(
        ayar: d.ayar,
        kayit: kayit,
        oncekiAyKaydi: onceki,
        sonrakiAyKaydi: sonraki,
        personelId: _personelId!,
        yil: d.yil,
        ay: d.ay,
      );

      final oncekiMatrah = await _oncekiYillikMatrah(d);

      if (!mounted) return;
      setState(() {
        _calismaGunuC.text = '${d.gunSayisi}';
        _geceSaatiC.text = Para.sade(girdi.geceSaati);
        _tatilGunuC.text = '${girdi.tatilGunu}';
        _yolGunuC.text = '${girdi.yolGunu}';
        _oncekiMatrahC.text = Para.tl(oncekiMatrah);
        _mesgul = false;
      });

      if (girdi.doluGun == 0) {
        _bilgi(
          context,
          '"${versiyonAdi(_versiyon)}" listesinde ${T.ayYil(d.yil, d.ay)} '
          'için bu personele ait dolu gün yok. Başka bir liste versiyonu '
          'seçmeyi deneyin.',
          hata: true,
        );
      } else {
        _bilgi(
          context,
          '${girdi.doluGun} gün okundu · Gece ${Para.sade(girdi.geceSaati)} sa · '
          'Tatil ${girdi.tatilGunu} gün · Yol ${girdi.yolGunu} gün',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _mesgul = false);
        _bilgi(context, 'Nöbet verisi okunamadı: $e', hata: true);
      }
    }
  }

  /// Aynı yıl içinde bu aydan önceki en son kayıtlı bordronun yıllık matrahı.
  Future<double> _oncekiYillikMatrah(NobetDurumu d) async {
    for (var a = d.ay - 1; a >= 1; a--) {
      final onceki =
          await d.servis.bordroGetir(d.birimId, _personelId!, d.yil, a);
      if (onceki != null) return onceki.yillikMatrah;
    }
    return 0;
  }

  void _hesapla() {
    final d = context.read<NobetDurumu>();
    final ucret = _seciliUcret;
    if (ucret == null || _ayar == null) {
      _bilgi(context, 'Önce personel seçin.', hata: true);
      return;
    }
    if (ucret.gunlukUcret <= 0) {
      _bilgi(
        context,
        'Bu personelin günlük ücreti tanımlı değil. '
        'Bordro İşlemleri › Personel Ücretleri bölümünden girin.',
        hata: true,
      );
      return;
    }

    Personel? personel;
    for (final p in d.tumPersoneller) {
      if (p.id == _personelId) personel = p;
    }
    if (personel == null) {
      _bilgi(context, 'Personel bulunamadı.', hata: true);
      return;
    }

    setState(() {
      _sonuc = bordroHesapla(
        personel: personel!,
        ucret: ucret,
        ayar: _ayar!,
        yil: d.yil,
        ay: d.ay,
        calismaGunu: Para.cozVeya(_calismaGunuC.text, d.gunSayisi.toDouble())
            .round(),
        sgkGunu: Para.cozVeya(_sgkGunuC.text, 30).round(),
        geceSaati: Para.cozVeya(_geceSaatiC.text),
        tatilGunu: Para.cozVeya(_tatilGunuC.text).round(),
        yolGunu: Para.cozVeya(_yolGunuC.text).round(),
        oncekiYillikMatrah: Para.cozVeya(_oncekiMatrahC.text),
        gecisAyi: _gecisAyi,
        ucretFarki: Para.cozVeya(_ucretFarkiC.text),
        sosyalYardimFarki: Para.cozVeya(_sosyalFarkiC.text),
        yolYardimiFarki: Para.cozVeya(_yolFarkiC.text),
        hizmetZammiFarki: Para.cozVeya(_hizmetZammiFarkiC.text),
        sendikaFarki: Para.cozVeya(_sendikaFarkiC.text),
      );
    });
  }

  Future<void> _kaydet() async {
    if (_sonuc == null) return;
    final d = context.read<NobetDurumu>();
    try {
      await d.servis.bordroKaydet(d.birimId, _sonuc!);
      if (mounted) _bilgi(context, 'Bordro kaydedildi.');
    } catch (e) {
      if (mounted) _bilgi(context, 'Kaydedilemedi: $e', hata: true);
    }
  }

  Future<void> _pdf() async {
    if (_sonuc == null) return;
    final d = context.read<NobetDurumu>();
    try {
      await BordroPdfServis.onizle(
        sonuc: _sonuc!,
        kurumAdi: d.ayar.ad,
        birimEtiketi: d.birim.uzunEtiket,
      );
    } catch (e) {
      if (mounted) _bilgi(context, 'PDF oluşturulamadı: $e', hata: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    if (!d.bordroYetkisi) return _yetkiYok();

    return SingleChildScrollView(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bolumBasligi(
            'Bordro Hesapla — ${T.ayYil(d.yil, d.ay)} · ${d.birim.etiket}',
            aciklama: 'Dönem ve birim üst çubuktan seçilir. Gece saati, '
                'tatil çalışması ve yol günü nöbet listesinden otomatik '
                'okunabilir.',
          ),
          const SizedBox(height: 8),
          _girisKarti(d),
          const SizedBox(height: 8),
          _uyariSeridi(),
          const SizedBox(height: 8),
          if (_sonuc != null) _sonucKarti(_sonuc!),
        ],
      ),
    );
  }

  Widget _girisKarti(NobetDurumu d) {
    final ucretsizler = <String>{
      for (final u in _ucretler)
        if (u.gunlukUcret > 0) u.personelId,
    };

    final personelSecici = DropdownButtonFormField<String>(
      initialValue: _personelId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Personel',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: [
        for (final p in d.tumPersoneller)
          DropdownMenuItem(
            value: p.id,
            child: Row(
              children: [
                Expanded(child: Text(p.ad, overflow: TextOverflow.ellipsis)),
                if (!ucretsizler.contains(p.id))
                  const Icon(Icons.error_outline, size: 15, color: R.turuncu),
              ],
            ),
          ),
      ],
      onChanged: (v) => setState(() {
        _personelId = v;
        _sonuc = null;
      }),
    );

    final versiyonSecici = DropdownButtonFormField<String>(
      initialValue: _versiyon,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Nöbet Liste Versiyonu',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: [
        for (final v in kListeVersiyonlari)
          DropdownMenuItem(value: v, child: Text(versiyonAdi(v))),
      ],
      onChanged: (v) => setState(() => _versiyon = v ?? kVersiyonOnayli),
    );

    final sayilar = Column(
      children: [
        Row(children: [
          Expanded(child: _sayiAlani(_calismaGunuC, 'Çalışma Günü')),
          const SizedBox(width: 8),
          Expanded(child: _sayiAlani(_sgkGunuC, 'SGK Günü')),
          const SizedBox(width: 8),
          Expanded(child: _sayiAlani(_geceSaatiC, 'Gece Saati')),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _sayiAlani(_tatilGunuC, 'Tatil Çalışma Günü')),
          const SizedBox(width: 8),
          Expanded(child: _sayiAlani(_yolGunuC, 'Yol/Yemek Günü')),
          const SizedBox(width: 8),
          Expanded(
              child: _sayiAlani(_oncekiMatrahC, 'Önceki Yıllık Matrah (₺)')),
        ]),
      ],
    );

    return _kartCerceve(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Bordro Bilgileri',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 8),
          if (widget.genis)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(children: [
                    personelSecici,
                    const SizedBox(height: 6),
                    versiyonSecici,
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: sayilar),
              ],
            )
          else
            Column(children: [
              personelSecici,
              const SizedBox(height: 6),
              versiyonSecici,
              const SizedBox(height: 6),
              sayilar,
            ]),
          const SizedBox(height: 2),
          CheckboxListTile(
            value: _gecisAyi,
            onChanged: (v) => setState(() => _gecisAyi = v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Geçiş Ayı (Zamlı Geçiş)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Bordrodaki fark tutarlarını girin. Hizmet primi farkı '
                'ücret farkının oranı kadar otomatik eklenir.',
                style: TextStyle(fontSize: 11.5)),
          ),
          if (_gecisAyi) ...[
            Row(children: [
              Expanded(child: _sayiAlani(_ucretFarkiC, 'Ücret Farkı (₺)')),
              const SizedBox(width: 8),
              Expanded(
                  child: _sayiAlani(_sosyalFarkiC, 'Sosyal Yrd. Farkı (₺)')),
              const SizedBox(width: 8),
              Expanded(child: _sayiAlani(_yolFarkiC, 'Yol Yrd. Farkı (₺)')),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                  child: _sayiAlani(
                      _hizmetZammiFarkiC, 'Hizmet Zammı Farkı (₺)')),
              const SizedBox(width: 8),
              Expanded(child: _sayiAlani(_sendikaFarkiC, 'Sendika Farkı (₺)')),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()),
            ]),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _personelId == null || _mesgul ? null : _nobettenCek,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Nöbet Listesinden Çek'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _mesgul ? null : _hesapla,
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: const Text('HESAPLA'),
              ),
            ),
          ]),
          if (_mesgul)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _sonucKarti(BordroSonucu r) {
    final gelirler = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('GELİRLER',
            style: TextStyle(fontWeight: FontWeight.w700, color: R.yesil)),
        const SizedBox(height: 4),
        _satir('Günlük Ücret (Md.33)', r.gunlukUcretToplami),
        _satir('Sosyal Yardım (Md.38)', r.sosyalYardim),
        _satir('Hizmet Primi (Md.36)', r.hizmetPrimi),
        _satir('Hizmet Zammı (Md.58)', r.hizmetZammi),
        _satir('Yol Yardımı (Md.40)', r.yolYardimi),
        _satir('Gece Çalışma (Md.23)', r.geceCalismaUcreti),
        _satir('Tatil Çalışma (Md.22)', r.tatilCalismaUcreti),
        if (r.gecisAyi) ...[
          _satir('Ücret Farkı', r.ucretFarki, renk: R.mavi),
          _satir('Hizmet Primi Farkı', r.hizmetPrimiFarki, renk: R.mavi),
          _satir('Sosyal Yardım Farkı', r.sosyalYardimFarki, renk: R.mavi),
          _satir('Yol Yardımı Farkı', r.yolYardimiFarki, renk: R.mavi),
          _satir('Hizmet Zammı Farkı', r.hizmetZammiFarki, renk: R.mavi),
        ],
        const Divider(),
        _satir('BRÜT GELİR', r.brutGelir, kalin: true, renk: R.yesil),
      ],
    );

    final kesintiler = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('KESİNTİLER',
            style: TextStyle(fontWeight: FontWeight.w700, color: R.kirmizi)),
        const SizedBox(height: 4),
        _satir('SGK Çalışan', r.sgkCalisanKesintisi),
        _satir('SGK İşsizlik', r.sgkIssizlikKesintisi),
        _satir('Gelir Vergisi', r.gelirVergisi),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'İstisna ${Para.tl(r.gelirVergisiIstisnasi)} · '
            'yıllık matrah ${Para.tl(r.yillikMatrah)}',
            style: const TextStyle(fontSize: 10.5, color: R.gri),
          ),
        ),
        _satir('Damga Vergisi', r.damgaVergisi),
        _satir('Sendika Kesintisi', r.sendikaKesintisi),
        const Divider(),
        _satir('TOPLAM KESİNTİ', r.toplamKesinti,
            kalin: true, renk: R.kirmizi),
      ],
    );

    return _kartCerceve(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, color: R.maviKoyu),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${r.personelAd} — ${T.ayYil(r.yil, r.ay)}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            if (r.gecisAyi)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: R.mavi.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Geçiş ayı',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: R.maviKoyu)),
              ),
          ]),
          const Divider(height: 18),
          if (widget.genis)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: gelirler),
                const SizedBox(width: 26),
                Expanded(child: kesintiler),
              ],
            )
          else
            Column(children: [
              gelirler,
              const SizedBox(height: 14),
              kesintiler,
            ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: R.maviKoyu,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ÖDENECEK TUTAR',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                Text(Para.tlSimge(r.odenecekTutar),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _kaydet,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Kaydet'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _pdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF İndir'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _satir(String etiket, double deger,
          {bool kalin = false, Color? renk}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(etiket,
                  style: TextStyle(
                    fontSize: 13,
                    color: renk,
                    fontWeight: kalin ? FontWeight.w700 : FontWeight.w400,
                  )),
            ),
            Text(Para.tl(deger),
                style: TextStyle(
                  fontSize: 13,
                  color: renk,
                  fontWeight: kalin ? FontWeight.w700 : FontWeight.w500,
                )),
          ],
        ),
      );
}

// =============================================================================
// KAYITLI BORDROLAR
// =============================================================================
class BordroKayitlariEkrani extends StatefulWidget {
  const BordroKayitlariEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<BordroKayitlariEkrani> createState() => _BordroKayitlariEkraniState();
}

class _BordroKayitlariEkraniState extends State<BordroKayitlariEkrani> {
  int? _yilSuzgeci;
  int? _aySuzgeci;
  List<BordroSonucu> _liste = const [];
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final d = context.read<NobetDurumu>();
    setState(() => _mesgul = true);
    try {
      _liste = await d.servis
          .bordrolariGetir(d.birimId, yil: _yilSuzgeci, ay: _aySuzgeci);
    } catch (e) {
      _liste = const [];
      if (mounted) _bilgi(context, 'Bordrolar okunamadı: $e', hata: true);
    }
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _sil(BordroSonucu r) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: R.kirmizi, size: 30),
        title: const Text('Bordroyu sil'),
        content: Text(
          '${r.personelAd} — ${T.ayYil(r.yil, r.ay)} bordrosu silinecek. '
          'Bu işlem geri alınamaz.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: R.kirmizi),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (onay != true) return;

    if (!mounted) return;
    final d = context.read<NobetDurumu>();
    await d.servis.bordroSil(d.birimId, r.personelId, r.yil, r.ay);
    await _yukle();
    if (mounted) _bilgi(context, 'Bordro silindi.');
  }

  Future<void> _detay(BordroSonucu r) async {
    final d = context.read<NobetDurumu>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r.personelAd} — ${T.ayYil(r.yil, r.ay)}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dSatir('Çalışma günü', '${r.calismaGunu}'),
                _dSatir('Gece saati', Para.sade(r.geceSaati)),
                _dSatir('Tatil çalışma', '${r.tatilGunu} gün'),
                _dSatir('Yol/yemek', '${r.yolGunu} gün'),
                const Divider(),
                _dSatir('Günlük Ücret (Md.33)', Para.tl(r.gunlukUcretToplami)),
                _dSatir('Sosyal Yardım (Md.38)', Para.tl(r.sosyalYardim)),
                _dSatir('Hizmet Primi (Md.36)', Para.tl(r.hizmetPrimi)),
                _dSatir('Hizmet Zammı (Md.58)', Para.tl(r.hizmetZammi)),
                _dSatir('Yol Yardımı (Md.40)', Para.tl(r.yolYardimi)),
                _dSatir('Gece Çalışma (Md.23)', Para.tl(r.geceCalismaUcreti)),
                _dSatir('Tatil Çalışma (Md.22)', Para.tl(r.tatilCalismaUcreti)),
                if (r.gecisAyi)
                  _dSatir('Geçiş ayı farkları', Para.tl(r.farkToplami)),
                _dSatir('BRÜT GELİR', Para.tl(r.brutGelir), kalin: true),
                const Divider(),
                _dSatir('SGK Çalışan', Para.tl(r.sgkCalisanKesintisi)),
                _dSatir('SGK İşsizlik', Para.tl(r.sgkIssizlikKesintisi)),
                _dSatir('Gelir Vergisi', Para.tl(r.gelirVergisi)),
                _dSatir('Damga Vergisi', Para.tl(r.damgaVergisi)),
                _dSatir('Sendika', Para.tl(r.sendikaKesintisi)),
                _dSatir('TOPLAM KESİNTİ', Para.tl(r.toplamKesinti),
                    kalin: true),
                const Divider(),
                _dSatir('ÖDENECEK', Para.tlSimge(r.odenecekTutar),
                    kalin: true),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await BordroPdfServis.onizle(
                sonuc: r,
                kurumAdi: d.ayar.ad,
                birimEtiketi: d.birim.uzunEtiket,
              );
            },
            icon: const Icon(Icons.picture_as_pdf_outlined,
                size: 18, color: R.kirmizi),
            label: const Text('PDF'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat')),
        ],
      ),
    );
  }

  Widget _dSatir(String etiket, String deger, {bool kalin = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(etiket,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          kalin ? FontWeight.w700 : FontWeight.w400)),
            ),
            Text(deger,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: kalin ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    if (!d.bordroYetkisi) return _yetkiYok();

    final buYil = DateTime.now().year;

    return Padding(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bolumBasligi('Kayıtlı Bordrolar — ${d.birim.etiket}',
              aciklama: 'Hesaplanıp kaydedilmiş bordrolar. Kayıtlar '
                  'hesaplandıkları hâliyle saklanır; ayarları sonradan '
                  'değiştirmek eski bordroları etkilemez.'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _yilSuzgeci,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Yıl',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tümü')),
                  for (var i = 0; i < 6; i++)
                    DropdownMenuItem(
                        value: buYil - 3 + i, child: Text('${buYil - 3 + i}')),
                ],
                onChanged: (v) {
                  setState(() => _yilSuzgeci = v);
                  _yukle();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: _aySuzgeci,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Ay',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tümü')),
                  for (var a = 1; a <= 12; a++)
                    DropdownMenuItem(value: a, child: Text(T.aylar[a - 1])),
                ],
                onChanged: (v) {
                  setState(() => _aySuzgeci = v);
                  _yukle();
                },
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Yenile',
              onPressed: _yukle,
              icon: const Icon(Icons.refresh),
            ),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: _mesgul
                ? const Center(child: CircularProgressIndicator())
                : _liste.isEmpty
                    ? _bosDurum(
                        'Kayıtlı bordro yok',
                        'Bordro Hesapla bölümünde bir bordro hesaplayıp '
                            '"Kaydet" deyin.',
                        Icons.receipt_long_outlined)
                    : ListView.separated(
                        itemCount: _liste.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (ctx, i) {
                          final r = _liste[i];
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Tema.kenar(context)),
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 0),
                              leading: CircleAvatar(
                                radius: 15,
                                backgroundColor:
                                    r.gecisAyi ? R.turuncu : R.maviKoyu,
                                child: Text(T.aylarKisa[r.ay - 1],
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 10)),
                              ),
                              title: Text(r.personelAd,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5)),
                              subtitle: Text(
                                '${T.ayYil(r.yil, r.ay)} · Net: '
                                '${Para.tlSimge(r.odenecekTutar)}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Detay',
                                    icon: const Icon(Icons.visibility_outlined,
                                        size: 20, color: R.mavi),
                                    onPressed: () => _detay(r),
                                  ),
                                  IconButton(
                                    tooltip: 'Sil',
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20, color: R.kirmizi),
                                    onPressed: () => _sil(r),
                                  ),
                                ],
                              ),
                              onTap: () => _detay(r),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PERSONEL ÜCRETLERİ
// =============================================================================
class PersonelUcretleriEkrani extends StatefulWidget {
  const PersonelUcretleriEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<PersonelUcretleriEkrani> createState() =>
      _PersonelUcretleriEkraniState();
}

class _PersonelUcretleriEkraniState extends State<PersonelUcretleriEkrani> {
  Map<String, PersonelUcreti> _ucretler = {};
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final d = context.read<NobetDurumu>();
    setState(() => _mesgul = true);
    try {
      final liste = await d.servis.personelUcretleriGetir(d.birimId);
      _ucretler = {for (final u in liste) u.personelId: u};
    } catch (e) {
      if (mounted) _bilgi(context, 'Ücretler okunamadı: $e', hata: true);
    }
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _duzenle(Personel p) async {
    final mevcut = _ucretler[p.id];
    final gunlukC = TextEditingController(
        text: mevcut == null || mevcut.gunlukUcret == 0
            ? ''
            : Para.tl(mevcut.gunlukUcret, basamak: 5));
    final zamC = TextEditingController(
        text: mevcut == null || mevcut.hizmetZammi == 0
            ? ''
            : Para.tl(mevcut.hizmetZammi, basamak: 2));
    final yolC = TextEditingController(
        text: mevcut == null || mevcut.yolYardimiGunluk == 0
            ? ''
            : Para.tl(mevcut.yolYardimiGunluk, basamak: 3));
    final yolAylikC = TextEditingController(
        text: mevcut == null || mevcut.yolYardimiAylik == 0
            ? ''
            : Para.tl(mevcut.yolYardimiAylik, basamak: 2));
    var sendika = mevcut?.sendikaUyesi ?? true;

    final kaydet = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: Text(p.ad),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    p.tcNo.isEmpty
                        ? 'T.C. no tanımlı değil'
                        : 'T.C. ${p.tcMaskeli}',
                    style: const TextStyle(fontSize: 12, color: R.gri),
                  ),
                  const SizedBox(height: 14),
                  _sayiAlani(gunlukC, 'Günlük Ücret (₺)',
                      ipucu: 'Md.33 — bordrodaki günlük yevmiye'),
                  const SizedBox(height: 12),
                  _sayiAlani(zamC, 'Hizmet Zammı (₺)',
                      ipucu: 'Md.58 — kişiye özel aylık sabit'),
                  const SizedBox(height: 12),
                  _sayiAlani(yolC, 'Günlük Yol Yardımı (₺)',
                      ipucu: 'Boş bırakılırsa genel ayardaki tutar kullanılır'),
                  const SizedBox(height: 12),
                  _sayiAlani(yolAylikC, 'Sabit Aylık Yol Yardımı (₺)',
                      ipucu:
                          'Dolu ise günlük×gün yerine bu sabit tutar kullanılır'),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    value: sendika,
                    onChanged: (v) => yenile(() => sendika = v ?? true),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Sendika üyesi',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: const Text(
                        'Üye ise aylık bir günlük ücret kesilir',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Kaydet')),
          ],
        ),
      ),
    );

    if (kaydet != true || !mounted) return;

    final d = context.read<NobetDurumu>();
    await d.servis.personelUcretiKaydet(
      d.birimId,
      PersonelUcreti(
        personelId: p.id,
        gunlukUcret: Para.cozVeya(gunlukC.text),
        hizmetZammi: Para.cozVeya(zamC.text),
        yolYardimiGunluk: Para.cozVeya(yolC.text),
        yolYardimiAylik: Para.cozVeya(yolAylikC.text),
        sendikaUyesi: sendika,
      ),
    );
    await _yukle();
    if (mounted) _bilgi(context, '${p.ad} ücret bilgisi kaydedildi.');
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    if (!d.bordroYetkisi) return _yetkiYok();

    final eksik = d.tumPersoneller
        .where((p) => (_ucretler[p.id]?.gunlukUcret ?? 0) <= 0)
        .length;

    return Padding(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bolumBasligi('Personel Ücretleri — ${d.birim.etiket}',
              aciklama: 'Ücretler nöbet listesindeki personel kayıtlarına '
                  'bağlıdır; ayrıca isim girmeye gerek yoktur. Personel '
                  'eklemek için Personeller bölümünü kullanın.'),
          const SizedBox(height: 6),
          if (eksik > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: R.turuncu.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 17, color: R.turuncu),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$eksik personelin günlük ücreti tanımlı değil — '
                      'bordroları hesaplanamaz.',
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ),
          Expanded(
            child: _mesgul
                ? const Center(child: CircularProgressIndicator())
                : d.tumPersoneller.isEmpty
                    ? _bosDurum(
                        'Kayıtlı personel yok',
                        'Önce Personeller bölümünden personel ekleyin.',
                        Icons.groups_outlined)
                    : ListView.separated(
                        itemCount: d.tumPersoneller.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (ctx, i) {
                          final p = d.tumPersoneller[i];
                          final u = _ucretler[p.id];
                          final tanimli = (u?.gunlukUcret ?? 0) > 0;
                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: tanimli
                                    ? Tema.kenar(context)
                                    : R.turuncu.withValues(alpha: .5),
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 0),
                              leading: CircleAvatar(
                                radius: 15,
                                backgroundColor:
                                    tanimli ? R.maviKoyu : R.gri,
                                child: Text(p.basHarfler,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11)),
                              ),
                              title: Text(p.ad,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5)),
                              subtitle: Text(
                                tanimli
                                    ? [
                                        'Günlük ${Para.tl(u!.gunlukUcret)} ₺',
                                        if (u.hizmetZammi > 0)
                                          'H.Zammı ${Para.tl(u.hizmetZammi)} ₺',
                                        if (u.yolYardimiAylik > 0)
                                          'Yol (Sabit) ${Para.tl(u.yolYardimiAylik)} ₺'
                                        else if (u.yolYardimiGunluk > 0)
                                          'Yol/gün ${Para.tl(u.yolYardimiGunluk, basamak: 3)} ₺',
                                        if (u.sendikaUyesi) 'Sendika üyesi',
                                      ].join(' · ')
                                    : 'Ücret bilgisi girilmedi',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: tanimli ? null : R.turuncu),
                              ),
                              trailing: IconButton(
                                tooltip: 'Ücret bilgisini düzenle',
                                icon: const Icon(Icons.edit_outlined,
                                    size: 20, color: R.mavi),
                                onPressed: () => _duzenle(p),
                              ),
                              onTap: () => _duzenle(p),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BORDRO AYARLARI
// =============================================================================
class BordroAyarlariEkrani extends StatefulWidget {
  const BordroAyarlariEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<BordroAyarlariEkrani> createState() => _BordroAyarlariEkraniState();
}

class _BordroAyarlariEkraniState extends State<BordroAyarlariEkrani> {
  late int _yil;
  bool _mesgul = false;

  final _istisnaC = TextEditingController();
  final _sosyalC = TextEditingController();
  final _yolC = TextEditingController();
  final _primC = TextEditingController();
  final _sgkC = TextEditingController();
  final _issizlikC = TextEditingController();
  final _damgaC = TextEditingController();
  final _damgaIstisnaC = TextEditingController();
  final _geceC = TextEditingController();
  final _tatilC = TextEditingController();

  List<TextEditingController> _dilimSinirC = [];
  List<TextEditingController> _dilimOranC = [];

  @override
  void initState() {
    super.initState();
    _yil = context.read<NobetDurumu>().yil;
    _yukle();
  }

  Future<void> _yukle() async {
    final d = context.read<NobetDurumu>();
    setState(() => _mesgul = true);
    try {
      final a = await d.servis.bordroAyariGetir(d.kurumId, _yil);
      _istisnaC.text = Para.tl(a.gelirVergisiIstisnasi);
      _sosyalC.text = Para.tl(a.sosyalYardim);
      _yolC.text = Para.tl(a.yolYardimiGunluk);
      _primC.text = Para.tl(a.hizmetPrimiOrani * 100);
      _sgkC.text = Para.tl(a.sgkCalisan * 100);
      _issizlikC.text = Para.tl(a.sgkIssizlik * 100);
      _damgaC.text = Para.tl(a.damgaVergisiOrani * 100, basamak: 3);
      _damgaIstisnaC.text = Para.tl(a.damgaVergisiIstisnasi);
      _geceC.text = Para.tl(a.geceKatsayisi);
      _tatilC.text = Para.tl(a.tatilKatsayisi);

      for (final c in [..._dilimSinirC, ..._dilimOranC]) {
        c.dispose();
      }
      _dilimSinirC = [
        for (final b in a.vergiDilimleri)
          TextEditingController(text: Para.tl(b.ustSinir, basamak: 0)),
      ];
      _dilimOranC = [
        for (final b in a.vergiDilimleri)
          TextEditingController(text: Para.tl(b.oran * 100)),
      ];
    } catch (e) {
      if (mounted) _bilgi(context, 'Ayarlar okunamadı: $e', hata: true);
    }
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _kaydet() async {
    final d = context.read<NobetDurumu>();
    final dilimler = <VergiDilimi>[
      for (var i = 0; i < _dilimSinirC.length; i++)
        VergiDilimi(
          ustSinir: Para.cozVeya(_dilimSinirC[i].text),
          oran: Para.cozVeya(_dilimOranC[i].text) / 100,
        ),
    ]..sort((a, b) => a.ustSinir.compareTo(b.ustSinir));

    final ayar = BordroAyari(
      yil: _yil,
      gelirVergisiIstisnasi: Para.cozVeya(_istisnaC.text),
      sosyalYardim: Para.cozVeya(_sosyalC.text),
      yolYardimiGunluk: Para.cozVeya(_yolC.text),
      hizmetPrimiOrani: Para.cozVeya(_primC.text) / 100,
      sgkCalisan: Para.cozVeya(_sgkC.text) / 100,
      sgkIssizlik: Para.cozVeya(_issizlikC.text) / 100,
      damgaVergisiOrani: Para.cozVeya(_damgaC.text) / 100,
      damgaVergisiIstisnasi: Para.cozVeya(_damgaIstisnaC.text),
      geceKatsayisi: Para.cozVeya(_geceC.text),
      tatilKatsayisi: Para.cozVeya(_tatilC.text),
      vergiDilimleri: dilimler.isEmpty ? null : dilimler,
    );

    try {
      await d.servis.bordroAyariKaydet(d.kurumId, ayar);
      if (mounted) _bilgi(context, '$_yil yılı bordro ayarları kaydedildi.');
    } catch (e) {
      if (mounted) _bilgi(context, 'Kaydedilemedi: $e', hata: true);
    }
  }

  void _dilimEkle() {
    setState(() {
      _dilimSinirC.add(TextEditingController(text: '0'));
      _dilimOranC.add(TextEditingController(text: '0'));
    });
  }

  void _dilimSil(int i) {
    setState(() {
      _dilimSinirC.removeAt(i).dispose();
      _dilimOranC.removeAt(i).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    if (!d.bordroYetkisi) return _yetkiYok();
    if (_mesgul) return const Center(child: CircularProgressIndicator());

    final buYil = DateTime.now().year;

    final sabitler = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('SABİT TUTARLAR',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        _sayiAlani(_istisnaC, 'Gelir Vergisi İstisnası (₺)',
            ipucu: 'Asgari ücrete isabet eden kısım'),
        const SizedBox(height: 6),
        _sayiAlani(_sosyalC, 'Sosyal Yardım — Md.38 (₺)',
            ipucu: 'Aylık sabit tutar'),
        const SizedBox(height: 6),
        _sayiAlani(_yolC, 'Yol Yardımı — günlük (₺)',
            ipucu: 'Personele özel tutar tanımlıysa o kullanılır'),
        const SizedBox(height: 6),
        _sayiAlani(_damgaIstisnaC, 'Damga Vergisi İstisnası (₺)',
            ipucu: 'Brüt asgari ücret'),
      ],
    );

    final oranlar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('ORANLAR VE KATSAYILAR',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        _sayiAlani(_primC, 'Hizmet Primi — Md.36 (%)', ipucu: 'Genelde %16'),
        const SizedBox(height: 6),
        _sayiAlani(_sgkC, 'SGK Çalışan (%)', ipucu: 'Genelde %14'),
        const SizedBox(height: 6),
        _sayiAlani(_issizlikC, 'SGK İşsizlik (%)', ipucu: 'Genelde %1'),
        const SizedBox(height: 6),
        _sayiAlani(_damgaC, 'Damga Vergisi (%)', ipucu: 'Genelde %0,759'),
        const SizedBox(height: 6),
        _sayiAlani(_geceC, 'Gece Çalışma Katsayısı — Md.23',
            ipucu: 'Genelde 0,35'),
        const SizedBox(height: 6),
        _sayiAlani(_tatilC, 'Tatil Çalışma Katsayısı — Md.22',
            ipucu: 'Genelde 2,0'),
      ],
    );

    final dilimler = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Expanded(
            child: Text('GELİR VERGİSİ DİLİMLERİ',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          IconButton(
            tooltip: 'Dilim ekle',
            onPressed: _dilimEkle,
            icon: const Icon(Icons.add_circle_outline, size: 20),
          ),
        ]),
        const Text('Kümülatif yıllık matraha uygulanır — üst sınır artan '
            'sırada olmalıdır.',
            style: TextStyle(fontSize: 11.5, color: R.gri, height: 1.4)),
        const SizedBox(height: 6),
        for (var i = 0; i < _dilimSinirC.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                  child: _sayiAlani(_dilimSinirC[i], '${i + 1}. dilim (₺)')),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: _sayiAlani(_dilimOranC[i], 'Oran %'),
              ),
              IconButton(
                tooltip: 'Dilimi sil',
                onPressed:
                    _dilimSinirC.length > 1 ? () => _dilimSil(i) : null,
                icon: const Icon(Icons.remove_circle_outline,
                    size: 20, color: R.kirmizi),
              ),
            ]),
          ),
      ],
    );

    return SingleChildScrollView(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bolumBasligi('Bordro Ayarları',
              aciklama: 'Her yıl güncellenen sabit tutar, oran ve '
                  'katsayılar. Ayarlar iki birim için ortaktır ve '
                  'kaydedilmiş eski bordroları etkilemez.'),
          const SizedBox(height: 8),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<int>(
              initialValue: _yil,
              decoration: const InputDecoration(
                labelText: 'Ayar yılı',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: [
                for (var i = 0; i < 6; i++)
                  DropdownMenuItem(
                      value: buYil - 2 + i, child: Text('${buYil - 2 + i}')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _yil = v);
                _yukle();
              },
            ),
          ),
          const SizedBox(height: 10),
          if (widget.genis)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: sabitler),
                const SizedBox(width: 10),
                Expanded(child: oranlar),
                const SizedBox(width: 10),
                Expanded(child: dilimler),
              ],
            )
          else
            Column(children: [
              sabitler,
              const SizedBox(height: 10),
              oranlar,
              const SizedBox(height: 10),
              dilimler,
            ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _kaydet,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text('$_yil AYARLARINI KAYDET'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _istisnaC,
      _sosyalC,
      _yolC,
      _primC,
      _sgkC,
      _issizlikC,
      _damgaC,
      _damgaIstisnaC,
      _geceC,
      _tatilC,
      ..._dilimSinirC,
      ..._dilimOranC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}

// =============================================================================
// BORDRO RAPORLARI
// =============================================================================
class BordroRaporlariEkrani extends StatefulWidget {
  const BordroRaporlariEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<BordroRaporlariEkrani> createState() => _BordroRaporlariEkraniState();
}

class _BordroRaporlariEkraniState extends State<BordroRaporlariEkrani> {
  late int _yil;
  String? _personelId;
  List<BordroSonucu> _yilVerisi = const [];
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _yil = context.read<NobetDurumu>().yil;
  }

  Future<void> _yukle() async {
    if (_personelId == null) {
      setState(() => _yilVerisi = const []);
      return;
    }
    final d = context.read<NobetDurumu>();
    setState(() => _mesgul = true);
    try {
      final hepsi = await d.servis.bordrolariGetir(d.birimId, yil: _yil);
      _yilVerisi = hepsi.where((b) => b.personelId == _personelId).toList()
        ..sort((a, b) => a.ay.compareTo(b.ay));
    } catch (e) {
      _yilVerisi = const [];
      if (mounted) _bilgi(context, 'Rapor okunamadı: $e', hata: true);
    }
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _topluPdf() async {
    final d = context.read<NobetDurumu>();
    setState(() => _mesgul = true);
    try {
      final hepsi = await d.servis.bordrolariGetir(d.birimId, yil: _yil);
      if (hepsi.isEmpty) {
        if (mounted) {
          setState(() => _mesgul = false);
          _bilgi(context, '$_yil yılı için kayıtlı bordro yok.', hata: true);
        }
        return;
      }
      hepsi.sort((a, b) {
        final isim = a.personelAd.compareTo(b.personelAd);
        return isim != 0 ? isim : a.ay.compareTo(b.ay);
      });
      await BordroPdfServis.topluOnizle(
        kayitlar: hepsi,
        yil: _yil,
        kurumAdi: d.ayar.ad,
        birimEtiketi: d.birim.uzunEtiket,
      );
    } catch (e) {
      if (mounted) _bilgi(context, 'Toplu bordro hatası: $e', hata: true);
    }
    if (mounted) setState(() => _mesgul = false);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    if (!d.bordroYetkisi) return _yetkiYok();

    final buYil = DateTime.now().year;

    return SingleChildScrollView(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bolumBasligi('Bordro Raporları — ${d.birim.etiket}',
              aciklama: 'Bir personelin yıl içindeki bordro seyri ve '
                  'birimin tamamı için toplu döküm.'),
          const SizedBox(height: 8),
          _kartCerceve(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<int>(
                      initialValue: _yil,
                      decoration: const InputDecoration(
                          labelText: 'Yıl',
                          border: OutlineInputBorder(),
                          isDense: true),
                      items: [
                        for (var i = 0; i < 6; i++)
                          DropdownMenuItem(
                              value: buYil - 3 + i,
                              child: Text('${buYil - 3 + i}')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _yil = v);
                        _yukle();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _personelId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Personel',
                          border: OutlineInputBorder(),
                          isDense: true),
                      items: [
                        for (final p in d.tumPersoneller)
                          DropdownMenuItem(
                              value: p.id,
                              child:
                                  Text(p.ad, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        setState(() => _personelId = v);
                        _yukle();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _mesgul ? null : _topluPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: Text('$_yil toplu bordro PDF (tüm personel)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_mesgul)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_personelId == null)
            _bosDurum('Personel seçin',
                'Yıllık bordro seyrini görmek için bir personel seçin.',
                Icons.person_search_outlined)
          else if (_yilVerisi.isEmpty)
            _bosDurum('Kayıt yok',
                '$_yil yılı için bu personele ait kayıtlı bordro bulunamadı.',
                Icons.event_busy_outlined)
          else ...[
            _grafik(),
            const SizedBox(height: 8),
            _yilTablosu(),
          ],
        ],
      ),
    );
  }

  Widget _grafik() {
    final enBuyuk = _yilVerisi
        .map((b) => b.odenecekTutar)
        .reduce((a, b) => a > b ? a : b);

    return _kartCerceve(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Aylık net maaş',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in _yilVerisi)
                  Expanded(
                    child: Tooltip(
                      message: '${T.aylar[b.ay - 1]}: '
                          '${Para.tlSimge(b.odenecekTutar)}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              Para.tl(b.odenecekTutar / 1000, basamak: 0),
                              style: const TextStyle(
                                  fontSize: 9, color: R.gri),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              height: enBuyuk <= 0
                                  ? 4
                                  : 4 + 118 * (b.odenecekTutar / enBuyuk),
                              decoration: BoxDecoration(
                                color: R.mavi,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(T.aylarKisa[b.ay - 1],
                                style: const TextStyle(
                                    fontSize: 9.5, color: R.gri)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text('Değerler bin ₺ cinsindendir.',
              style: TextStyle(fontSize: 10.5, color: R.gri)),
        ],
      ),
    );
  }

  Widget _yilTablosu() {
    var toplamBrut = 0.0, toplamKesinti = 0.0, toplamNet = 0.0;
    for (final b in _yilVerisi) {
      toplamBrut += b.brutGelir;
      toplamKesinti += b.toplamKesinti;
      toplamNet += b.odenecekTutar;
    }

    Widget satir(String ay, String brut, String kesinti, String net,
            {bool kalin = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: Row(children: [
            Expanded(
              flex: 2,
              child: Text(ay,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          kalin ? FontWeight.w700 : FontWeight.w400)),
            ),
            Expanded(
              flex: 3,
              child: Text(brut,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          kalin ? FontWeight.w700 : FontWeight.w400)),
            ),
            Expanded(
              flex: 3,
              child: Text(kesinti,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: R.kirmizi,
                      fontWeight:
                          kalin ? FontWeight.w700 : FontWeight.w400)),
            ),
            Expanded(
              flex: 3,
              child: Text(net,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: kalin ? R.maviKoyu : null,
                      fontWeight:
                          kalin ? FontWeight.w700 : FontWeight.w600)),
            ),
          ]),
        );

    return _kartCerceve(
      context,
      ic: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$_yil yıllık özet',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            color: Tema.tabloBaslik(context),
            child: satir('Ay', 'Brüt', 'Kesinti', 'Net', kalin: true),
          ),
          for (final b in _yilVerisi)
            satir(T.aylar[b.ay - 1], Para.tl(b.brutGelir),
                Para.tl(b.toplamKesinti), Para.tl(b.odenecekTutar)),
          const Divider(),
          Container(
            color: R.mavi.withValues(alpha: .08),
            child: satir('TOPLAM', Para.tl(toplamBrut),
                Para.tl(toplamKesinti), Para.tl(toplamNet), kalin: true),
          ),
          const SizedBox(height: 8),
          Text(
            '${_yilVerisi.length} aylık kayıt · ortalama net '
            '${Para.tlSimge(toplamNet / _yilVerisi.length)}',
            style: const TextStyle(
                fontSize: 11.5, color: R.gri, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BORDRO PDF YÜKLEME
// =============================================================================
class BordroYuklemeEkrani extends StatefulWidget {
  const BordroYuklemeEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<BordroYuklemeEkrani> createState() => _BordroYuklemeEkraniState();
}

class _BordroYuklemeEkraniState extends State<BordroYuklemeEkrani> {
  static const int _maxBoyutKb = 700;

  List<Personel> _personeller = [];
  List<YuklenmisBordro> _yukluListe = [];
  bool _yukleniyor = true;

  Personel? _secilenPersonel;
  int _secilenYil = DateTime.now().year;
  int _secilenAy = DateTime.now().month;
  PlatformFile? _secilenDosya;
  bool _yuklemeDevam = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _veriYukle());
  }

  Future<void> _veriYukle() async {
    final d = context.read<NobetDurumu>();
    setState(() => _yukleniyor = true);
    final personeller = await d.servis.personelleriGetir(d.birimId);
    final liste = await d.servis.birimBordroYuklemeleriniGetir(d.birimId);
    if (!mounted) return;
    setState(() {
      _personeller = personeller;
      _yukluListe = liste;
      _yukleniyor = false;
    });
  }

  Future<void> _dosyaSec() async {
    final sonuc = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (sonuc == null || sonuc.files.isEmpty) return;
    final dosya = sonuc.files.first;
    if ((dosya.size / 1024) > _maxBoyutKb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Dosya çok büyük (max $_maxBoyutKb KB).'),
        backgroundColor: R.kirmizi,
      ));
      return;
    }
    setState(() => _secilenDosya = dosya);
  }

  Future<void> _gonder(NobetDurumu d) async {
    if (_secilenPersonel == null || _secilenDosya == null) return;
    final bytes = _secilenDosya!.bytes;
    if (bytes == null) return;

    setState(() => _yuklemeDevam = true);
    try {
      final kayit = YuklenmisBordro(
        personelId: _secilenPersonel!.id,
        personelAd: _secilenPersonel!.ad,
        yil: _secilenYil,
        ay: _secilenAy,
        dosyaAdi: _secilenDosya!.name,
        yuklemeTarihi: DateTime.now(),
        pdfBase64: base64Encode(bytes),
      );
      await d.servis.bordroYukle(d.birimId, kayit);
      if (!mounted) return;
      setState(() {
        _secilenDosya = null;
        _secilenPersonel = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bordro yüklendi.')),
      );
      await _veriYukle();
    } finally {
      if (mounted) setState(() => _yuklemeDevam = false);
    }
  }

  Future<void> _ac(NobetDurumu d, YuklenmisBordro meta) async {
    final tam = await d.servis.bordroYuklemesiniGetir(
        d.birimId, meta.personelId, meta.yil, meta.ay);
    if (tam == null || tam.pdfBase64.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bordro dosyası okunamadı.')),
        );
      }
      return;
    }
    final bytes = base64Decode(tam.pdfBase64);
    if (!mounted) return;
    // Web'de dosya sistemine yazıp harici uygulamada açmak mümkün değil;
    // `printing` paketinin PdfPreview widget'ı hem web hem masaüstünde
    // önizleme + yazdırma/indirme araç çubuğu sağlar.
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              '${meta.personelAd} — ${T.aylar[meta.ay - 1]} ${meta.yil}',
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
          body: PdfPreview(
            build: (_) async => bytes,
            initialPageFormat: null,
            canChangePageFormat: false,
            canChangeOrientation: false,
            pdfFileName: meta.dosyaAdi,
          ),
        ),
      ),
    );
  }

  Future<void> _sil(NobetDurumu d, YuklenmisBordro meta) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bordroyu sil'),
        content: Text(
            '${meta.personelAd} — ${T.aylar[meta.ay - 1]} ${meta.yil} bordrosu silinsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: R.kirmizi),
              child: const Text('Sil')),
        ],
      ),
    );
    if (onay != true) return;
    await d.servis.bordroYuklemeSil(
        d.birimId, meta.personelId, meta.yil, meta.ay);
    await _veriYukle();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    return Padding(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.bordroYetkisi) _yukleFormu(d),
                if (d.bordroYetkisi) const SizedBox(height: 10),
                Expanded(child: _yukluListesi(d)),
              ],
            ),
    );
  }

  Widget _yukleFormu(NobetDurumu d) {
    final aylar = List.generate(12, (i) => i + 1);
    final yillar = [
      DateTime.now().year - 1,
      DateTime.now().year,
      DateTime.now().year + 1,
    ];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Tema.kenar(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bordro Yükle',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<Personel>(
                    decoration: const InputDecoration(
                      labelText: 'Personel',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    value: _secilenPersonel,
                    items: _personeller
                        .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.ad,
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (p) => setState(() => _secilenPersonel = p),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Yıl',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    value: _secilenYil,
                    items: yillar
                        .map((y) =>
                            DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (y) =>
                        setState(() => _secilenYil = y ?? _secilenYil),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Ay',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    value: _secilenAy,
                    items: aylar
                        .map((a) => DropdownMenuItem(
                            value: a, child: Text(T.aylar[a - 1])))
                        .toList(),
                    onChanged: (a) =>
                        setState(() => _secilenAy = a ?? _secilenAy),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _dosyaSec,
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: Text(_secilenDosya == null
                      ? 'PDF Seç (max $_maxBoyutKb KB)'
                      : _secilenDosya!.name),
                ),
                FilledButton.icon(
                  onPressed: (_secilenPersonel != null &&
                          _secilenDosya != null &&
                          !_yuklemeDevam)
                      ? () => _gonder(d)
                      : null,
                  icon: _yuklemeDevam
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload, size: 18),
                  label: const Text('Yükle'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _yukluListesi(NobetDurumu d) {
    if (_yukluListe.isEmpty) {
      return const Center(
        child: Text('Henüz yüklenmiş bordro yok.',
            style: TextStyle(color: R.gri)),
      );
    }
    return ListView.separated(
      itemCount: _yukluListe.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final meta = _yukluListe[i];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Tema.kenar(context)),
          ),
          child: ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: const Icon(Icons.picture_as_pdf_outlined,
                color: R.kirmizi, size: 22),
            title: Text(meta.personelAd,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13.5)),
            subtitle: Text(
              '${T.aylar[meta.ay - 1]} ${meta.yil}  ·  ${meta.dosyaAdi}'
              '\nYükleme: ${T.tarih(meta.yuklemeTarihi)}',
              style: const TextStyle(fontSize: 11.5, height: 1.4),
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Aç / Görüntüle',
                  icon: const Icon(Icons.open_in_new, color: R.mavi),
                  onPressed: () => _ac(d, meta),
                ),
                if (d.bordroYetkisi)
                  IconButton(
                    tooltip: 'Sil',
                    icon:
                        const Icon(Icons.delete_outline, color: R.kirmizi),
                    onPressed: () => _sil(d, meta),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

