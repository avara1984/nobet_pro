import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/kapsama_motoru.dart';
import '../core/mesai_hesap.dart' as mh;
import '../core/tarih.dart';
import '../core/tema.dart';
import '../durum/nobet_durumu.dart';
import '../modeller/modeller.dart';
import 'aylik_ozet_ekrani.dart';
import 'bordro_ekranlari.dart';
import 'donem_nobet_ekrani.dart';
import 'haftalik_nobet_ekrani.dart';
import 'nobet_listesi_ekrani.dart';
import 'yonetim_ekranlari.dart';

enum Bolum {
  dashboard,
  nobetListesi,
  haftalikNobet,
  donem1514,
  aylikOzet,
  duyurular,
  personeller,
  raporlar,
  bordroHesapla,
  bordroKayitlari,
  bordroUcretler,
  bordroAyarlar,
  bordroRaporlar,
  bordroYukle,
  ayarlar,
  kullanicilar,
  adminYonetimi,
  yedekleme,
  cikis,
}

/// Yan menüdeki "Bordro İşlemleri" grubuna ait bölümler.
const Set<Bolum> kBordroBolumleri = {
  Bolum.bordroHesapla,
  Bolum.bordroKayitlari,
  Bolum.bordroUcretler,
  Bolum.bordroAyarlar,
  Bolum.bordroRaporlar,
  Bolum.bordroYukle,
};

class AnaEkran extends StatefulWidget {
  const AnaEkran({
    super.key,
    required this.temaDegistir,
    required this.koyuTema,
    required this.cikisYap,
  });

  final VoidCallback temaDegistir;
  final bool koyuTema;
  final Future<void> Function() cikisYap;

  @override
  State<AnaEkran> createState() => _AnaEkraniState();
}

class _AnaEkraniState extends State<AnaEkran> {
  Bolum _bolum = Bolum.nobetListesi;
  bool _raporlarAcik = false;
  bool _bordroAcik = false;
  int _raporSekmesi = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _raporlarSekmeSec(int i) {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    setState(() {
      _bolum = Bolum.raporlar;
      _raporlarAcik = true;
      _raporSekmesi = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final genis = c.maxWidth >= 1000;
        return Scaffold(
          key: _scaffoldKey,
          drawer: genis ? null : Drawer(child: _YanMenu(
            secili: _bolum,
            raporlarAcik: _raporlarAcik,
            bordroAcik: _bordroAcik,
            raporSekmesi: _raporSekmesi,
            onSec: _bolumSec,
            onRaporlar: () => setState(() => _raporlarAcik = !_raporlarAcik),
            onBordro: () => setState(() => _bordroAcik = !_bordroAcik),
            onRaporSekmesi: _raporlarSekmeSec,
          )),
          appBar: genis
              ? null
              : AppBar(
                  backgroundColor: R.yan,
                  foregroundColor: Colors.white,
                  title: const Text('Nöbet Sistemi',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  actions: [
                    IconButton(
                      onPressed: widget.temaDegistir,
                      icon: Icon(widget.koyuTema
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined),
                    ),
                  ],
                ),
          body: Row(
            children: [
              if (genis)
                SizedBox(
                  width: 232,
                  child: _YanMenu(
                    secili: _bolum,
                    raporlarAcik: _raporlarAcik,
                    bordroAcik: _bordroAcik,
                    raporSekmesi: _raporSekmesi,
                    onSec: _bolumSec,
                    onRaporlar: () =>
                        setState(() => _raporlarAcik = !_raporlarAcik),
                    onBordro: () =>
                        setState(() => _bordroAcik = !_bordroAcik),
                    onRaporSekmesi: _raporlarSekmeSec,
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    _UstBaslik(
                      genis: genis,
                      temaDegistir: widget.temaDegistir,
                      koyuTema: widget.koyuTema,
                      onDuyurularAc: () => _bolumSec(Bolum.duyurular),
                    ),
                    Expanded(child: _govde(genis)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _bolumSec(Bolum b) async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    if (b == Bolum.cikis) {
      final onay = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Çıkış yap'),
          content: const Text(
            'Kullanıcı seçim ekranına dönülecek. Kaydedilmemiş '
            'değişiklikleriniz varsa önce kaydedin.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Çıkış yap')),
          ],
        ),
      );
      if (onay == true) await widget.cikisYap();
      return;
    }
    if (b == Bolum.duyurular) {
      context.read<NobetDurumu>().duyurularGoruldu();
    }
    setState(() => _bolum = b);
  }

  Widget _govde(bool genis) {
    final d = context.watch<NobetDurumu>();
    if (d.yukleniyor) {
      return const Center(child: CircularProgressIndicator());
    }
    if (d.hata != null) {
      return _Hata(mesaj: d.hata!, yenile: d.baslat);
    }

    return switch (_bolum) {
      Bolum.dashboard => _Dashboard(genis: genis),
      Bolum.nobetListesi => NobetListesiEkrani(genis: genis),
      Bolum.haftalikNobet => HaftalikNobetEkrani(genis: genis),
      Bolum.donem1514 => DonemNobetEkrani(genis: genis),
      Bolum.aylikOzet => AylikOzetEkrani(genis: genis),
      Bolum.duyurular => DuyurularEkrani(genis: genis),
      Bolum.personeller => PersonellerEkrani(genis: genis),
      Bolum.raporlar => RaporlarEkrani(
          key: ValueKey('raporlar_$_raporSekmesi'),
          genis: genis,
          baslangicSekme: _raporSekmesi,
        ),
      Bolum.bordroHesapla => BordroHesaplaEkrani(genis: genis),
      Bolum.bordroKayitlari => BordroKayitlariEkrani(genis: genis),
      Bolum.bordroUcretler => PersonelUcretleriEkrani(genis: genis),
      Bolum.bordroAyarlar => BordroAyarlariEkrani(genis: genis),
      Bolum.bordroRaporlar => BordroRaporlariEkrani(genis: genis),
      Bolum.bordroYukle => BordroYuklemeEkrani(genis: genis),
      Bolum.ayarlar => AyarlarEkrani(genis: genis),
      Bolum.kullanicilar => KullanicilarEkrani(genis: genis),
      Bolum.adminYonetimi => AdminYonetimiEkrani(genis: genis),
      Bolum.yedekleme => YedeklemeEkrani(genis: genis),
      Bolum.cikis => const SizedBox(),
    };
  }
}

// -----------------------------------------------------------------------------
// YAN MENÜ
// -----------------------------------------------------------------------------
class _YanMenu extends StatelessWidget {
  const _YanMenu({
    required this.secili,
    required this.raporlarAcik,
    required this.bordroAcik,
    required this.raporSekmesi,
    required this.onSec,
    required this.onRaporlar,
    required this.onBordro,
    required this.onRaporSekmesi,
  });

  final Bolum secili;
  final bool raporlarAcik;
  final bool bordroAcik;
  final int raporSekmesi;
  final Future<void> Function(Bolum) onSec;
  final VoidCallback onRaporlar;
  final VoidCallback onBordro;
  final void Function(int) onRaporSekmesi;

  @override
  Widget build(BuildContext context) {
    final oturum = context.watch<OturumDurumu>();
    final k = oturum.kullanici;

    final sadecePdfMi = k?.sadecePdf ?? false;
    // Yönetim ekranları: nöbet tarafını yönetebilenler (Süper Admin).
    // Bordro Admini sadecePdf olduğu için buraya giremez.
    final yonetici = !sadecePdfMi && oturum.rol.yonetebilir;
    final bordroYetkisi = oturum.bordroYetkisi;
    // Düzenleyebilenler tam yetkiyle, personel (izleyici) sadece
    // önizleme/görüntüleme amaçlı görür — Bordro Admini (sadecePdf) nöbet
    // tarafına hiç girmez.
    final haftalikYetkisi = !sadecePdfMi;

    return Container(
      color: R.yan,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: Colors.white,
                    backgroundImage: AssetImage('assets/logo.png'),
                  ),
                  SizedBox(width: 10),
                  Text('NÖBET SİSTEMİ',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: .3)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _oge(Bolum.dashboard, Icons.dashboard_outlined, 'Dashboard'),
                  _oge(Bolum.nobetListesi, Icons.calendar_month_outlined,
                      'Nöbet Listesi'),
                  if (haftalikYetkisi)
                    _oge(Bolum.haftalikNobet, Icons.view_week_outlined,
                        'Haftalık Nöbet'),
                  if (haftalikYetkisi)
                    _oge(Bolum.donem1514, Icons.date_range_outlined,
                        '15 - 14 Nöbet'),
                  _oge(Bolum.aylikOzet, Icons.insert_chart_outlined,
                      'Aylık Özet'),
                  if (!sadecePdfMi) ...[
                    _acilir(
                      ikon: Icons.description_outlined,
                      baslik: 'Raporlar',
                      acik: raporlarAcik,
                      aktif: secili == Bolum.raporlar,
                      onTap: onRaporlar,
                    ),
                    if (raporlarAcik) ...[
                      _altOge('Yıllık Dağılım', () => onRaporSekmesi(0),
                          aktif: secili == Bolum.raporlar &&
                              raporSekmesi == 0),
                      _altOge('Personel Bazlı', () => onRaporSekmesi(1),
                          aktif: secili == Bolum.raporlar &&
                              raporSekmesi == 1),
                    ],
                  ],
                  if (yonetici) ...[
                    _oge(Bolum.personeller, Icons.people_outline,
                        'Personeller'),
                    _oge(Bolum.kullanicilar, Icons.manage_accounts_outlined,
                        'Kullanıcılar'),
                    _oge(Bolum.adminYonetimi,
                        Icons.admin_panel_settings_outlined, 'Admin Yönetimi'),
                  ],
                  if (bordroYetkisi) ...[
                    _acilir(
                      ikon: Icons.payments_outlined,
                      baslik: 'Bordro İşlemleri',
                      acik: bordroAcik,
                      aktif: kBordroBolumleri.contains(secili),
                      onTap: onBordro,
                    ),
                    if (bordroAcik) ...[
                      if (!sadecePdfMi) ...[
                        _altOge('Bordro Hesapla',
                            () => onSec(Bolum.bordroHesapla),
                            aktif: secili == Bolum.bordroHesapla),
                        _altOge('Kayıtlı Bordrolar',
                            () => onSec(Bolum.bordroKayitlari),
                            aktif: secili == Bolum.bordroKayitlari),
                        _altOge('Personel Ücretleri',
                            () => onSec(Bolum.bordroUcretler),
                            aktif: secili == Bolum.bordroUcretler),
                        _altOge('Bordro Ayarları',
                            () => onSec(Bolum.bordroAyarlar),
                            aktif: secili == Bolum.bordroAyarlar),
                        _altOge('Bordro Raporları',
                            () => onSec(Bolum.bordroRaporlar),
                            aktif: secili == Bolum.bordroRaporlar),
                      ],
                      _altOge('Bordro Yükleme',
                          () => onSec(Bolum.bordroYukle),
                          aktif: secili == Bolum.bordroYukle),
                    ],
                  ],
                  if (yonetici) ...[
                    _oge(Bolum.ayarlar, Icons.settings_outlined, 'Ayarlar'),
                    _oge(Bolum.yedekleme, Icons.backup_outlined, 'Yedekleme'),
                  ],
                  if (!sadecePdfMi)
                    _oge(Bolum.duyurular, Icons.campaign_outlined, 'Duyurular'),
                  _oge(Bolum.cikis, Icons.logout, 'Çıkış Yap'),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 2, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '© 2026 Mehmet SAYAR - Tüm Hakları Saklıdır',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: R.gri, fontSize: 9, height: 1.15),
                    ),
                    const SizedBox(height: 3),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _whatsappAc,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FaIcon(FontAwesomeIcons.whatsapp,
                                size: 16, color: Color(0xFF25D366)),
                            SizedBox(width: 6),
                            Text('0553 599 98 58',
                                style: TextStyle(
                                    color: Color(0xFF25D366),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            InkWell(
              onTap: () => onSec(Bolum.cikis),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: R.yesil,
                      child: Text(
                        _basHarf(k?.ad ?? '?'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(k?.ad ?? 'Kullanıcı',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          Text(k?.rolEtiketiUzun ?? oturum.rol.etiket,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(color: R.gri, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_up,
                        color: R.gri, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _whatsappAc() async {
    final uri = Uri.parse('https://wa.me/905535999858');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _oge(Bolum b, IconData ikon, String baslik) {
    final aktif = secili == b;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: aktif ? R.mavi : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSec(b),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(ikon, size: 18, color: aktif ? Colors.white : R.gri),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(baslik,
                      style: TextStyle(
                        color: aktif ? Colors.white : const Color(0xFFD5DAE5),
                        fontSize: 13.5,
                        fontWeight:
                            aktif ? FontWeight.w600 : FontWeight.w500,
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Alt öğeleri olan açılır menü başlığı (Raporlar, Bordro İşlemleri…).
  Widget _acilir({
    required IconData ikon,
    required String baslik,
    required bool acik,
    required bool aktif,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: aktif ? R.mavi : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(ikon, size: 18, color: aktif ? Colors.white : R.gri),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(baslik,
                        style: TextStyle(
                            color: aktif
                                ? Colors.white
                                : const Color(0xFFD5DAE5),
                            fontSize: 13.5,
                            fontWeight:
                                aktif ? FontWeight.w600 : FontWeight.w500)),
                  ),
                  Icon(
                      acik
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: aktif ? Colors.white : R.gri),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _altOge(String baslik, VoidCallback onTap, {bool aktif = false}) =>
      Padding(
        padding: const EdgeInsets.only(left: 34, bottom: 4),
        child: Material(
          color: aktif ? Colors.white10 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: aktif ? R.mavi : R.gri,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(baslik,
                        style: TextStyle(
                          color: aktif ? Colors.white : R.gri,
                          fontSize: 12.5,
                          fontWeight:
                              aktif ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  static String _basHarf(String ad) {
    final p = ad.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return '?';
    if (p.length == 1) return p.first.substring(0, 1);
    return '${p.first.substring(0, 1)}${p.last.substring(0, 1)}';
  }
}

// -----------------------------------------------------------------------------
// ÜST BAŞLIK
// -----------------------------------------------------------------------------
class _UstBaslik extends StatelessWidget {
  const _UstBaslik({
    required this.genis,
    required this.temaDegistir,
    required this.koyuTema,
    required this.onDuyurularAc,
  });

  final bool genis;
  final VoidCallback temaDegistir;
  final bool koyuTema;
  final VoidCallback onDuyurularAc;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    final oturum = context.watch<OturumDurumu>();

    final birimIkonu = Icon(
      d.birim == Birim.guvenlik
          ? Icons.shield_outlined
          : Icons.cleaning_services_outlined,
      size: 16,
    );

    final birimDugmesi = !d.birimDegistirilebilir
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Tema.kenar(context)),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                birimIkonu,
                const SizedBox(width: 8),
                Text(d.birim.etiket),
                const SizedBox(width: 6),
                const Icon(Icons.lock, size: 13, color: R.gri),
              ],
            ),
          )
        : PopupMenuButton<Birim>(
            tooltip: 'Birim değiştir',
            onSelected: (b) => _birimDegistirKontrollu(context, d, b),
            itemBuilder: (_) => [
              for (final b in Birim.values)
                PopupMenuItem(
                  value: b,
                  child: Row(
                    children: [
                      Icon(
                        b == Birim.guvenlik
                            ? Icons.shield_outlined
                            : Icons.cleaning_services_outlined,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(b.etiket),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Tema.kenar(context)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  birimIkonu,
                  const SizedBox(width: 8),
                  Text(d.birim.etiket),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          );

    final donemDugmesi = OutlinedButton.icon(
      onPressed: () => _donemSecKontrollu(context, d),
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text(T.ayYil(d.yil, d.ay)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );

    final donemGrubu = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Önceki ay',
          onPressed: () => _ayKaydir(context, d, -1),
          icon: const Icon(Icons.chevron_left, size: 18),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        donemDugmesi,
        IconButton(
          tooltip: 'Sonraki ay',
          onPressed: () => _ayKaydir(context, d, 1),
          icon: const Icon(Icons.chevron_right, size: 18),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );

    final duyuruDugmesi = Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Duyurular',
          onPressed: onDuyurularAc,
          icon: const Icon(Icons.campaign_outlined, size: 20),
          visualDensity: VisualDensity.compact,
        ),
        if (d.okunmamisDuyuruSayisi > 0)
          Positioned(
            right: 4,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              decoration: BoxDecoration(
                color: R.kirmizi,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${d.okunmamisDuyuruSayisi}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ),
      ],
    );

    final basliklar = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          d.ayar.ad,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: genis ? 15 : 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .2,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${d.birim.uzunEtiket} · ${d.ayar.altBaslik}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: R.gri),
        ),
      ],
    );

    return Container(
      color: Tema.kart(context),
      padding: EdgeInsets.fromLTRB(genis ? 20 : 12, 6, genis ? 20 : 12, 6),
      child: genis
          ? Row(
              children: [
                Expanded(child: basliklar),
                const SizedBox(width: 12),
                birimDugmesi,
                const SizedBox(width: 8),
                donemGrubu,
                duyuruDugmesi,
                const SizedBox(width: 4),
                IconButton(
                  tooltip: koyuTema ? 'Açık tema' : 'Koyu tema',
                  onPressed: temaDegistir,
                  icon: Icon(koyuTema
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined),
                ),
                const SizedBox(width: 4),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: R.yesil,
                  child: Text(
                    _YanMenu._basHarf(oturum.kullanici?.ad ?? '?'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: basliklar),
                    duyuruDugmesi,
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: birimDugmesi),
                    const SizedBox(width: 8),
                    donemGrubu,
                  ],
                ),
              ],
            ),
    );
  }

  /// Kaydedilmemiş değişiklik varsa ay seçiciyi açmadan önce uyarır
  /// (madde 12C) — sessiz veri kaybını önler.
  static Future<void> _donemSecKontrollu(
      BuildContext context, NobetDurumu d) async {
    if (d.kirli) {
      final devam = await _kaydedilmemisUyarisi(
        context,
        baslik: 'Ay değiştirilemiyor',
        aciklama:
            'Bu ayda kaydedilmemiş değişiklikleriniz var. Lütfen önce '
            'kaydedin veya devam etmeden önce kaydetmeyi atlayın.',
      );
      if (devam == 'kaydet') {
        final oturum = context.read<OturumDurumu>();
        await d.kaydet(kaydeden: oturum.kullanici?.ad ?? '');
      } else if (devam != 'atla') {
        return; // vazgeçildi
      }
    }
    if (!context.mounted) return;
    await _donemSec(context, d);
  }

  /// Ok butonlarıyla bir ay ileri/geri gider (delta: -1 veya 1).
  static Future<void> _ayKaydir(
      BuildContext context, NobetDurumu d, int delta) async {
    var yeniAy = d.ay + delta;
    var yeniYil = d.yil;
    if (yeniAy < 1) {
      yeniAy = 12;
      yeniYil--;
    } else if (yeniAy > 12) {
      yeniAy = 1;
      yeniYil++;
    }
    if (d.kirli) {
      final devam = await _kaydedilmemisUyarisi(
        context,
        baslik: 'Ay değiştirilemiyor',
        aciklama:
            'Bu ayda kaydedilmemiş değişiklikleriniz var. Lütfen önce '
            'kaydedin veya devam etmeden önce kaydetmeyi atlayın.',
      );
      if (devam == 'kaydet') {
        final oturum = context.read<OturumDurumu>();
        await d.kaydet(kaydeden: oturum.kullanici?.ad ?? '');
      } else if (devam != 'atla') {
        return; // vazgeçildi
      }
    }
    if (!context.mounted) return;
    d.donemDegistir(yeniYil, yeniAy);
  }

  /// Kaydedilmemiş değişiklik varsa birim değiştirmeden önce uyarır.
  static Future<void> _birimDegistirKontrollu(
      BuildContext context, NobetDurumu d, Birim hedef) async {
    if (hedef == d.birim) return;
    if (d.kirli) {
      final devam = await _kaydedilmemisUyarisi(
        context,
        baslik: 'Birim değiştirilemiyor',
        aciklama:
            '${d.birim.etiket} listesinde kaydedilmemiş değişiklikleriniz '
            'var. ${hedef.etiket} biriminie geçmeden önce ne yapmak '
            'istersiniz?',
      );
      if (devam == 'kaydet') {
        final oturum = context.read<OturumDurumu>();
        await d.kaydet(kaydeden: oturum.kullanici?.ad ?? '');
      } else if (devam != 'atla') {
        return; // vazgeçildi
      }
    }
    if (!context.mounted) return;
    await d.birimDegistir(hedef);
  }

  static Future<String?> _kaydedilmemisUyarisi(
    BuildContext context, {
    required String baslik,
    required String aciklama,
  }) =>
      _KaydedilmemisUyarisi.goster(context, baslik: baslik, aciklama: aciklama);

  static Future<void> _donemSec(BuildContext context, NobetDurumu d) async {
    var yil = d.yil;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: Row(
            children: [
              IconButton(
                  tooltip: 'Önceki yıl',
                  onPressed: () => yenile(() => yil--),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text('$yil',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  tooltip: 'Sonraki yıl',
                  onPressed: () => yenile(() => yil++),
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var a = 1; a <= 12; a++)
                  ChoiceChip(
                    label: Text(T.aylarKisa[a - 1]),
                    selected: yil == d.yil && a == d.ay,
                    onSelected: (_) {
                      Navigator.pop(ctx);
                      d.donemDegistir(yil, a);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DASHBOARD
// -----------------------------------------------------------------------------
class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.genis});
  final bool genis;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    // Süper Admin dışındaki herkes yalnızca Bilgilendirme alanını görür.
    final tamYetki = d.yonetebilir;
    return SingleChildScrollView(
      padding: genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      // Tam genişlik: yalnızca Bilgilendirme görünen kullanıcılarda da sola yaslı.
      child: SizedBox(
        width: double.infinity,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tamYetki) ...[
          LayoutBuilder(
            builder: (context, kisit) {
              const aralik = 14.0;
              // Masaüstünde sabit 232 genişlikte kartlar satıra sığdığı
              // kadar dizilir; telefonda ekran genişliği 232*2'yi
              // karşılamayacağı için (dar ekranlarda kartlar tek tek alt
              // alta düşerdi) genişlik, tam olarak 2 kart/satır sığacak
              // şekilde hesaplanır.
              final kartW = genis
                  ? 170.0
                  : (kisit.maxWidth - aralik) / 2;
              return Wrap(
                spacing: aralik,
                runSpacing: aralik,
                children: [
                  _kart(context, 'Toplam Personel', '${d.personeller.length}',
                      Icons.people_outline, R.mavi, kartW),
                  _kart(context, 'Doldurulan Gün',
                      '${d.doldurulanGun}/${d.gunSayisi}',
                      Icons.event_available_outlined, R.yesil, kartW),
                  _kart(
                      context,
                      'Kapsama Sorunu',
                      '${d.sorunluGun} gün',
                      Icons.warning_amber_rounded,
                      d.sorunluGun == 0 ? R.yesil : R.turuncu,
                      kartW),
                  _kart(context, 'Yayın Durumu',
                      d.kayit.yayinda ? 'Yayında' : 'Taslak',
                      Icons.visibility_outlined,
                      d.kayit.yayinda ? R.yesil : R.gri,
                      kartW),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          // Genişlik, 12 ay kutusunun (58px + 6px boşluk) tek satıra
          // sığacağı en dar ölçüye sabitlenir — panel artık ekranın
          // tamamına yayılmıyor, sola doğru daralıyor.
          SizedBox(
            width: genis ? 800.0 : double.infinity,
            child: _YillikYayinDurumu(yil: d.yil, d: d),
          ),
          const SizedBox(height: 10),
          ],
          SizedBox(
            width: genis ? 800.0 : double.infinity,
            child: _aylikBilgilendirme(context, d),
          ),
          if (tamYetki) ...[
          const SizedBox(height: 16),
          Text('${T.ayYil(d.yil, d.ay)} — Kapsama Sorunu Olan Günler',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          ..._sorunListesi(context, d),
          ],
        ],
      ),
      ),
    );
  }

  static String _sayi(double v) {
    final metin = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return metin.replaceAll('.', ',');
  }

  /// Seçili ay için: normal çalışma saati, resmî tatiller (arife = yarım gün),
  /// yıllık izin kullananlar ve personel başına toplam/kalan yıllık izin.
  Widget _aylikBilgilendirme(BuildContext context, NobetDurumu d) {
    final tatiller = <(DateTime, double)>[];
    for (var g = 1; g <= d.gunSayisi; g++) {
      final tarih = DateTime(d.yil, d.ay, g);
      if (d.ayar.resmiTatilMi(tarih)) {
        tatiller.add((tarih, 1.0));
      } else if (d.ayar.yarimGunMu(tarih)) {
        tatiller.add((tarih, 0.5));
      }
    }
    final izinliler =
        d.ozetler.where((o) => o.yillikIzinKullanilan > 0).toList();
    final ayAdi = T.aylar[d.ay - 1];

    const kalin = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700);
    const govde = TextStyle(fontSize: 12.5, height: 1.4);

    final saatIcerik = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(_sayi(d.aylikHedefSaat),
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: R.mavi,
                height: 1.1)),
        const SizedBox(width: 6),
        const Text('Saat',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: R.mavi)),
      ],
    );

    final tatilIcerik = tatiller.isEmpty
        ? Row(children: [
            const Icon(Icons.check_circle_outline, size: 16, color: R.yesil),
            const SizedBox(width: 8),
            Expanded(
                child: Text('$ayAdi ayında resmî tatil yok.', style: govde)),
          ])
        : Column(
            children: [
              for (final (tarih, gun) in tatiller)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 40,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: (gun < 1 ? R.turuncu : R.kirmizi)
                            .withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(children: [
                        Text('${tarih.day}',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                color: gun < 1 ? R.turuncu : R.kirmizi)),
                        Text(T.gunKisa(tarih),
                            style: const TextStyle(
                                fontSize: 9.5, color: R.gri, height: 1.2)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(T.gunAdi(tarih), style: kalin),
                          Text(T.tarih(tarih),
                              style: const TextStyle(
                                  fontSize: 11.5, color: R.gri)),
                        ],
                      ),
                    ),
                    _bilgiChip('${_sayi(gun)} gün',
                        gun < 1 ? R.turuncu : R.kirmizi),
                  ]),
                ),
            ],
          );

    final izinIcerik = !d.listeGorunurMu
        ? const Row(children: [
            Icon(Icons.lock_outline, size: 16, color: R.gri),
            SizedBox(width: 8),
            Expanded(
                child: Text('Bu Ayın Nöbet Listesi Henüz Yayınlanmamıştır.',
                    style: govde)),
          ])
        : izinliler.isEmpty
        ? Row(children: [
            const Icon(Icons.event_available_outlined,
                size: 16, color: R.yesil),
            const SizedBox(width: 8),
            Expanded(
                child: Text('$ayAdi Ayında Yıllık İzin Kullanan Yok',
                    style: govde)),
          ])
        : Column(
            children: [
              for (final o in izinliler)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    _bilgiAvatar(o.personel.ad, R.yesil),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(o.personel.ad,
                          style: kalin, overflow: TextOverflow.ellipsis),
                    ),
                    _bilgiChip('${o.yillikIzinKullanilan} gün', R.yesil),
                  ]),
                ),
            ],
          );

    return Container(
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tema.kenar(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                R.mavi.withValues(alpha: .18),
                R.mavi.withValues(alpha: .03),
              ]),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 18, color: R.mavi),
              const SizedBox(width: 8),
              const Text('Bilgilendirme',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              _bilgiChip(T.ayYil(d.yil, d.ay), R.mavi),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(builder: (context, k) {
              const aralik = 10.0;
              final sutun = k.maxWidth >= 640 ? 3 : 1;
              final w = (k.maxWidth - aralik * (sutun - 1)) / sutun;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: aralik,
                    runSpacing: aralik,
                    children: [
                      _bilgiKarti(
                        ikon: Icons.schedule,
                        renk: R.mavi,
                        baslik: '$ayAdi Ayı Normal Çalışma Saati',
                        icerik: saatIcerik,
                        genislik: w,
                      ),
                      _bilgiKarti(
                        ikon: Icons.celebration_outlined,
                        renk: R.turuncu,
                        baslik: 'Resmî Tatiller',
                        icerik: tatilIcerik,
                        genislik: w,
                      ),
                      _bilgiKarti(
                        ikon: Icons.beach_access_outlined,
                        renk: R.yesil,
                        baslik: 'Yıllık İzin Kullanan Personel',
                        icerik: izinIcerik,
                        genislik: w,
                      ),
                    ],
                  ),
                  const SizedBox(height: aralik),
                  _bilgiKarti(
                    ikon: Icons.insights_outlined,
                    renk: R.kirmizi,
                    baslik: 'Yıl İçi Resmî Tatil Çalışmaları (Fazla Mesai)',
                    icerik: _YillikFazlaMesai(d: d),
                    genislik: double.infinity,
                  ),
                  const SizedBox(height: aralik),
                  _bilgiKarti(
                    ikon: Icons.event_note_outlined,
                    renk: const Color(0xFF8B5CF6),
                    baslik: 'Yıllık İzin Durumu (Onaylanan Liste)',
                    icerik: _YillikIzinDurumu(d: d),
                    genislik: double.infinity,
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _bilgiKarti({
    required IconData ikon,
    required Color renk,
    required String baslik,
    required Widget icerik,
    required double genislik,
  }) {
    return Container(
      width: genislik,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: renk.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: renk.withValues(alpha: .16),
                shape: BoxShape.circle,
              ),
              child: Icon(ikon, size: 16, color: renk),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(baslik,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 10),
          icerik,
        ],
      ),
    );
  }

  List<Widget> _sorunListesi(BuildContext context, NobetDurumu d) {
    final sorunlu = d.madde3
        .tumAy(d.yil, d.ay)
        .where((k) => k.durum != GercekDurum.tamam)
        .toList();
    if (sorunlu.isEmpty) {
      return [
        Row(children: const [
          Icon(Icons.check_circle_outline, color: R.yesil, size: 18),
          SizedBox(width: 8),
          Text('Bu ay için tüm kapsama kuralları sağlanıyor.'),
        ])
      ];
    }
    return [
      for (final k in sorunlu.take(15))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                k.durum == GercekDurum.kadroEksik
                    ? Icons.warning_amber_rounded
                    : Icons.error_outline,
                color: k.durum == GercekDurum.kadroEksik ? R.turuncu : R.kirmizi,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${T.tarih(DateTime(d.yil, d.ay, k.gun))} — ${k.mesaj}',
                  style: const TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _kart(BuildContext context, String baslik, String deger,
      IconData ikon, Color renk, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tema.kenar(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(ikon, color: renk, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(baslik,
                  style: const TextStyle(fontSize: 12.5, color: R.gri)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(deger,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Yıllık Yayın Durumu — o yılın 12 ayının Onaylanan Liste yayın durumunu gösterir
// -----------------------------------------------------------------------------
/// Personel başına toplam (hak) ve kalan yıllık izin — kullanım HER ZAMAN
/// "Onaylanan Liste"den okunur ([NobetDurumu.yillikIzinKullanimi], Aylık
/// Özet panelindeki "Kalan Yıllık İzin" ile aynı hesap).
class _YillikIzinDurumu extends StatefulWidget {
  const _YillikIzinDurumu({required this.d});
  final NobetDurumu d;

  @override
  State<_YillikIzinDurumu> createState() => _YillikIzinDurumuState();
}

class _YillikIzinDurumuState extends State<_YillikIzinDurumu> {
  late Future<Map<String, int>> _gelecek;

  @override
  void initState() {
    super.initState();
    _gelecek = widget.d.yillikIzinKullanimi();
  }

  @override
  void didUpdateWidget(_YillikIzinDurumu eski) {
    super.didUpdateWidget(eski);
    if (eski.d.yil != widget.d.yil ||
        eski.d.ay != widget.d.ay ||
        eski.d.birim != widget.d.birim) {
      _gelecek = widget.d.yillikIzinKullanimi();
    }
  }

  @override
  Widget build(BuildContext context) {
    const govde = TextStyle(fontSize: 12.5, height: 1.4);
    final personeller = widget.d.personeller;
    if (personeller.isEmpty) {
      return const Text('Kayıtlı personel yok.', style: govde);
    }
    return FutureBuilder<Map<String, int>>(
      future: _gelecek,
      builder: (context, anlik) {
        if (!anlik.hasData) {
          return const Text('Yükleniyor…', style: govde);
        }
        final kullanim = anlik.data!;
        return Column(
          children: [
            for (final p in personeller) _satir(p, kullanim[p.id] ?? 0),
          ],
        );
      },
    );
  }

  Widget _satir(Personel p, int kullanilan) {
    final kota = p.yillikIzinKotasi;
    final kalan = kota - kullanilan;
    final renk = kalan <= 0
        ? R.kirmizi
        : (kalan <= 5 ? R.turuncu : R.yesil);
    final oran = kota <= 0 ? 0.0 : (kullanilan / kota).clamp(0.0, 1.0);
    final toplamYazi = Text('Toplam $kota gün',
        style: const TextStyle(fontSize: 12, color: R.gri));
    final cubuk = ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: oran,
        minHeight: 6,
        backgroundColor: renk.withValues(alpha: .15),
        valueColor: AlwaysStoppedAnimation<Color>(renk),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(builder: (context, k) {
        // Dar telefonda "Toplam" yazısı ismi kısaltmasın diye çubuğun yanına iner.
        final dar = k.maxWidth < 320;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _bilgiAvatar(p.ad, renk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.ad,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              if (!dar) ...[toplamYazi, const SizedBox(width: 8)],
              _bilgiChip('Kalan $kalan gün', renk),
            ]),
            const SizedBox(height: 6),
            if (dar)
              Row(children: [
                Expanded(child: cubuk),
                const SizedBox(width: 8),
                toplamYazi,
              ])
            else
              cubuk,
          ],
        );
      }),
    );
  }
}

Widget _bilgiChip(String metin, Color renk) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(metin,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
    );

Widget _bilgiAvatar(String ad, Color renk) => CircleAvatar(
      radius: 12,
      backgroundColor: renk.withValues(alpha: .18),
      child: Text(_YanMenu._basHarf(ad),
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: renk)),
    );

typedef _FazlaMesaiVeri = ({Map<String, List<double>> matris, int sonAy});

/// Yıl başından bulunulan aya kadar (gelecek aylar hariç) resmî tatillerde
/// çalışmadan doğan fazla mesai günleri — "Onaylanan Liste"den, Raporlar'daki
/// "Yıllık Fazla Mesai" ile aynı hesapla ([mh.aylikFazlaMesaiGunu]); ay ay
/// da gösterilir.
class _YillikFazlaMesai extends StatefulWidget {
  const _YillikFazlaMesai({required this.d});
  final NobetDurumu d;

  @override
  State<_YillikFazlaMesai> createState() => _YillikFazlaMesaiState();
}

class _YillikFazlaMesaiState extends State<_YillikFazlaMesai> {
  late Future<_FazlaMesaiVeri> _gelecek;

  @override
  void initState() {
    super.initState();
    _gelecek = _yukle();
  }

  @override
  void didUpdateWidget(_YillikFazlaMesai eski) {
    super.didUpdateWidget(eski);
    if (eski.d.yil != widget.d.yil || eski.d.birim != widget.d.birim) {
      _gelecek = _yukle();
    }
  }

  Future<_FazlaMesaiVeri> _yukle() async {
    final d = widget.d;
    final yil = d.yil;
    final simdi = DateTime.now();
    final sonAy = yil == simdi.year ? simdi.month : (yil < simdi.year ? 12 : 0);
    final matris = <String, List<double>>{
      for (final p in d.personeller) p.id: List<double>.filled(12, 0),
    };
    if (sonAy == 0) return (matris: matris, sonAy: sonAy);

    Future<AyKaydi?> oku(int ay) async {
      try {
        return await d.servis
            .ayKaydiGetir(d.birimId, yil, ay, versiyon: kVersiyonOnayli);
      } catch (_) {
        return null;
      }
    }

    final kayitlar = await Future.wait([for (var a = 1; a <= sonAy; a++) oku(a)]);
    AyKaydi? onceki;
    for (var ay = 1; ay <= sonAy; ay++) {
      final kayit = kayitlar[ay - 1];
      if (kayit != null) {
        for (final p in d.personeller) {
          matris[p.id]![ay - 1] = mh.aylikFazlaMesaiGunu(
            ayar: d.ayar,
            kayit: kayit,
            oncekiAyKayit: onceki,
            personelId: p.id,
            yil: yil,
            ay: ay,
          );
        }
      }
      onceki = kayit;
    }
    return (matris: matris, sonAy: sonAy);
  }

  static String _sayi(double v) {
    final metin =
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return metin.replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    const govde = TextStyle(fontSize: 12.5, height: 1.4);
    final d = widget.d;
    if (d.personeller.isEmpty) {
      return const Text('Kayıtlı personel yok.', style: govde);
    }
    return FutureBuilder<_FazlaMesaiVeri>(
      future: _gelecek,
      builder: (context, anlik) {
        if (!anlik.hasData) return const Text('Yükleniyor…', style: govde);
        final veri = anlik.data!;
        if (veri.sonAy == 0) {
          return Text('${d.yil} yılı için henüz veri yok.', style: govde);
        }
        final toplamlar = {
          for (final p in d.personeller)
            p.id: veri.matris[p.id]!.fold<double>(0, (t, v) => t + v),
        };
        final aySum = [
          for (var i = 0; i < 12; i++)
            d.personeller.fold<double>(0, (t, p) => t + veri.matris[p.id]![i]),
        ];
        final genel = toplamlar.values.fold<double>(0, (t, v) => t + v);
        final maks =
            toplamlar.values.fold<double>(1, (m, v) => v > m ? v : m);

        final ozet = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_sayi(genel),
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: R.kirmizi,
                        height: 1.1)),
                const SizedBox(width: 6),
                const Text('gün',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: R.kirmizi)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Ocak – ${T.aylar[veri.sonAy - 1]} ${d.yil}\ntoplam fazla mesai',
              style: const TextStyle(fontSize: 11.5, color: R.gri, height: 1.4),
            ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, k) {
              final grafik = _grafik(aySum, veri.sonAy);
              if (k.maxWidth >= 520) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(width: 170, child: ozet),
                    const SizedBox(width: 12),
                    Expanded(child: grafik),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [ozet, const SizedBox(height: 12), grafik],
              );
            }),
            const SizedBox(height: 14),
            for (final p in d.personeller)
              _satir(p, toplamlar[p.id] ?? 0, maks),
          ],
        );
      },
    );
  }

  Widget _grafik(List<double> aySum, int sonAy) {
    final maks = aySum.fold<double>(1, (m, v) => v > m ? v : m);
    const yukseklik = 46.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 12; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 14,
                    child: aySum[i] > 0
                        ? Text(_sayi(aySum[i]),
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: R.kirmizi))
                        : null,
                  ),
                  Container(
                    height: aySum[i] <= 0
                        ? 3.0
                        : (yukseklik * aySum[i] / maks < 6
                            ? 6.0
                            : yukseklik * aySum[i] / maks),
                    decoration: BoxDecoration(
                      color: aySum[i] > 0
                          ? R.kirmizi
                          : R.gri.withValues(alpha: i < sonAy ? .35 : .15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    T.aylar[i].substring(0, 3),
                    style: TextStyle(
                        fontSize: 9.5, color: i < sonAy ? null : R.gri),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _satir(Personel p, double toplam, double maks) {
    final renk = toplam > 0 ? R.kirmizi : R.gri;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(builder: (context, k) {
        final isim = Text(p.ad,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis);
        final genis = k.maxWidth >= 520;
        final cubuk = ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (toplam / maks).clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: renk.withValues(alpha: .15),
            valueColor: AlwaysStoppedAnimation<Color>(renk),
          ),
        );
        // Telefonda isim tam görünsün diye çubuk kısa ve sabit genişlikte;
        // kalan yeri isim alır.
        return Row(children: [
          _bilgiAvatar(p.ad, renk),
          const SizedBox(width: 8),
          if (genis) SizedBox(width: 170, child: isim) else Expanded(child: isim),
          const SizedBox(width: 8),
          if (genis) Expanded(child: cubuk) else SizedBox(width: 75, child: cubuk),
          const SizedBox(width: 10),
          _bilgiChip('${_sayi(toplam)} gün', renk),
        ]);
      }),
    );
  }
}

class _YillikYayinDurumu extends StatefulWidget {
  const _YillikYayinDurumu({required this.yil, required this.d});
  final int yil;
  final NobetDurumu d;

  @override
  State<_YillikYayinDurumu> createState() => _YillikYayinDurumuState();
}

class _YillikYayinDurumuState extends State<_YillikYayinDurumu> {
  late Future<List<bool>> _gelecek;

  @override
  void initState() {
    super.initState();
    _gelecek = _yukle();
  }

  @override
  void didUpdateWidget(_YillikYayinDurumu eski) {
    super.didUpdateWidget(eski);
    if (eski.yil != widget.yil || eski.d.birimId != widget.d.birimId) {
      setState(() => _gelecek = _yukle());
    }
  }

  Future<List<bool>> _yukle() async {
    final sonuclar = <bool>[];
    for (var ay = 1; ay <= 12; ay++) {
      try {
        final kayit = await widget.d.servis.ayKaydiGetir(
          widget.d.birimId,
          widget.yil,
          ay,
          versiyon: kVersiyonOnayli,
        );
        sonuclar.add(kayit.yayinda);
      } catch (_) {
        sonuclar.add(false);
      }
    }
    return sonuclar;
  }

  @override
  Widget build(BuildContext context) {
    const ayAdlari = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Tema.kart(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Tema.kenar(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 16, color: R.maviKoyu),
              const SizedBox(width: 6),
              Text('${widget.yil} — Aylık Yayın Durumu',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<bool>>(
            future: _gelecek,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 32,
                  child: Center(child: LinearProgressIndicator()),
                );
              }
              final durum = snap.data ?? List.filled(12, false);
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < 12; i++)
                    _ayKutu(context, ayAdlari[i], i + 1, durum[i]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _ayKutu(BuildContext ctx, String ad, int ay, bool yayinda) {
    final aktif = ay == widget.d.ay && widget.yil == widget.d.yil;
    final renk = yayinda ? R.yesil : R.gri;
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: yayinda
            ? R.yesil.withValues(alpha: .12)
            : Tema.tabloBaslik(ctx),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: aktif ? R.mavi : (yayinda ? R.yesil : Colors.transparent),
          width: aktif ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            yayinda ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 14,
            color: renk,
          ),
          const SizedBox(height: 3),
          Text(ad,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
                color: aktif ? R.mavi : null,
              )),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
class _Hata extends StatelessWidget {
  const _Hata({required this.mesaj, required this.yenile});
  final String mesaj;
  final Future<void> Function() yenile;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40, color: R.gri),
              const SizedBox(height: 12),
              Text(mesaj, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: yenile, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
}


/// Kaydedilmemiş değişiklik varken ay/birim değiştirme veya çıkış öncesi
/// gösterilen ortak uyarı (madde 12C). 'kaydet' / 'atla' / null (vazgeç) döner.
class _KaydedilmemisUyarisi {
  static Future<String?> goster(
    BuildContext context, {
    required String baslik,
    required String aciklama,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: R.turuncu, size: 30),
        title: Text(baslik),
        content: Text(aciklama, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'atla'),
              child: const Text('Kaydetmeden devam et')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'kaydet'),
              child: const Text('Kaydet ve devam et')),
        ],
      ),
    );
  }
}
