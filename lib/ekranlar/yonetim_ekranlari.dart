import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/kimlik.dart';
import '../core/tarih.dart';
import '../core/tema.dart';
import '../core/mesai_hesap.dart' as mh;
import '../durum/nobet_durumu.dart';
import '../modeller/modeller.dart';
import '../servisler/firestore_servis.dart';
import '../servisler/veri_servisi.dart';
import '../servisler/yerel_servis.dart';

// =============================================================================
// PERSONELLER
// =============================================================================
class PersonellerEkrani extends StatelessWidget {
  const PersonellerEkrani({super.key, required this.genis});
  final bool genis;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    return Padding(
      padding: genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _duzenle(context, d, null),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Personel Ekle'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _topluEkle(context, d),
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('Toplu Ekle'),
              ),
              const Spacer(),
              Text('${d.personeller.length} kayıt',
                  style: const TextStyle(color: R.gri, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: d.personeller.length,
              onReorder: (eski, yeni) async {
                if (yeni > eski) yeni -= 1;
                final liste = List.of(d.personeller);
                final p = liste.removeAt(eski);
                liste.insert(yeni, p);
                for (var i = 0; i < liste.length; i++) {
                  liste[i].sira = i;
                  await d.personelKaydet(liste[i]);
                }
              },
              itemBuilder: (ctx, i) {
                final p = d.personeller[i];
                return Card(
                  key: ValueKey(p.id),
                  elevation: 0,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? R.koyuKart
                      : const Color(0xFFE9ECF2),
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Tema.kenar(context)),
                  ),
                  child: ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: p.mesaiMi ? R.turuncu : R.mavi,
                      child: Text(p.basHarfler,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                    title: Text(p.ad,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(
                      [
                        p.mesaiMi ? 'Mesai Personeli' : 'Nöbetçi Personel',
                        'Yıllık İzin: ${p.yillikIzinKotasi} gün',
                        if (p.tcNo.isNotEmpty) 'TC: ${p.tcMaskeli}',
                        if (p.sicil.isNotEmpty) 'Sicil: ${p.sicil}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Personeli düzenle',
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          onPressed: () => _duzenle(context, d, p),
                        ),
                        IconButton(
                          tooltip: 'Personeli çıkar',
                          icon: const Icon(Icons.delete_outline,
                              size: 19, color: R.kirmizi),
                          onPressed: () => _sil(context, d, p),
                        ),
                        const Icon(Icons.drag_handle, color: R.gri),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Her satıra bir isim yapıştırılır. Satır sonuna (M) yazılırsa
  /// o kişi mesai (dahiliye) personeli olarak eklenir.
  Future<void> _topluEkle(BuildContext context, NobetDurumu d) async {
    final metin = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Toplu personel ekle'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Her satıra bir isim yazın veya listeyi olduğu gibi '
                'yapıştırın. Mesai (dahiliye) personeli için satır sonuna '
                '(M) ekleyin.',
                style: TextStyle(fontSize: 12, color: R.gri, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: metin,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: 'Ahmet Yılmaz\nAyşe Demir\nFatma Kaya (M)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );

    final satirlar = metin.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (satirlar.isEmpty) return;

    var sira = d.personeller.length;
    var eklenen = 0;
    for (final satir in satirlar) {
      var ad = satir;
      var mesai = false;
      final buyuk = ad.toUpperCase();
      if (buyuk.endsWith('(M)')) {
        mesai = true;
        ad = ad.substring(0, ad.length - 3).trim();
      }
      if (ad.isEmpty) continue;
      if (d.personeller.any((p) => p.ad.toLowerCase() == ad.toLowerCase())) {
        continue;
      }
      await d.personelKaydet(Personel(
        id: 'p${DateTime.now().microsecondsSinceEpoch}_$sira',
        ad: ad,
        gorev: mesai ? GorevTipi.mesai : GorevTipi.nobetci,
        sira: sira,
      ));
      sira++;
      eklenen++;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$eklenen personel eklendi.')),
      );
    }
  }

  Future<void> _sil(
      BuildContext context, NobetDurumu d, Personel p) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Personeli çıkar'),
        content: Text(
            '${p.ad} listeden çıkarılacak. Geçmiş aylardaki atamaları korunur.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Çıkar')),
        ],
      ),
    );
    if (onay == true) await d.personelSil(p.id);
  }

  Future<void> _duzenle(
      BuildContext context, NobetDurumu d, Personel? mevcut) async {
    final ad = TextEditingController(text: mevcut?.ad ?? '');
    final sicil = TextEditingController(text: mevcut?.sicil ?? '');
    final tc = TextEditingController(text: mevcut?.tcNo ?? '');
    final kota =
        TextEditingController(text: '${mevcut?.yillikIzinKotasi ?? 30}');
    var mesai = mevcut?.mesaiMi ?? false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: Text(mevcut == null ? 'Personel ekle' : 'Personeli düzenle'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ad,
                  decoration: const InputDecoration(labelText: 'Ad Soyad'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tc,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'T.C. Kimlik No',
                    helperText: '11 hane. Boş bırakılabilir.',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sicil,
                  decoration:
                      const InputDecoration(labelText: 'Sicil no (isteğe bağlı)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: kota,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Yıllık izin hakkı (gün)',
                    helperText: 'Kıdeme göre genelde 20 veya 30',
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mesai personeli (dahiliye)'),
                  subtitle: const Text(
                      'Nöbet döngüsüne girmez. Hafta sonu H.T., resmi tatil '
                      'R.T., diğer günler 08:00 - 17:30'),
                  value: mesai,
                  onChanged: (v) => yenile(() => mesai = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                if (ad.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Ad Soyad gerekli.')),
                  );
                  return;
                }
                final tcTemiz = tc.text.trim();
                if (tcTemiz.isNotEmpty && !Personel.tcGecerliMi(tcTemiz)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('T.C. Kimlik No 11 haneli olmalı.')),
                  );
                  return;
                }
                final p = mevcut ??
                    Personel(
                      id: 'p${DateTime.now().microsecondsSinceEpoch}',
                      ad: '',
                      sira: d.personeller.length,
                    );
                p.ad = ad.text.trim();
                p.sicil = sicil.text.trim();
                p.tcNo = tcTemiz;
                p.yillikIzinKotasi = int.tryParse(kota.text.trim()) ?? 30;
                p.gorev = mesai ? GorevTipi.mesai : GorevTipi.nobetci;
                d.personelKaydet(p);
                Navigator.pop(ctx);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// DUYURULAR
// =============================================================================

class DuyurularEkrani extends StatelessWidget {
  const DuyurularEkrani({super.key, required this.genis});
  final bool genis;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    return Padding(
      padding: genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.duzenleyebilir)
            Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: d.yonetebilir ? '' : 'Duyuru ekleme yetkiniz yok.',
                child: FilledButton.icon(
                  onPressed: d.yonetebilir ? () => _ekle(context, d) : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Duyuru ekle'),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Expanded(
            child: d.tumDuyurular.isEmpty
                ? const Center(
                    child: Text('Henüz duyuru yok.',
                        style: TextStyle(color: R.gri)))
                : ListView.separated(
                    itemCount: d.tumDuyurular.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final duyuru = d.tumDuyurular[i];
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Tema.kenar(context)),
                        ),
                        child: ListTile(
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(duyuru.baslik,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (duyuru.hedef == null
                                          ? R.mavi
                                          : R.gri)
                                      .withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  duyuru.hedefEtiketi,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: duyuru.hedef == null
                                        ? R.maviKoyu
                                        : R.gri,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${duyuru.icerik}\n${T.tarih(duyuru.tarih)}'
                              '${duyuru.yazar.isEmpty ? '' : ' · ${duyuru.yazar}'}',
                              style: const TextStyle(height: 1.4),
                            ),
                          ),
                          isThreeLine: true,
                          trailing: d.yonetebilir
                              ? IconButton(
                                  tooltip: 'Duyuruyu sil',
                                  icon: const Icon(Icons.delete_outline,
                                      color: R.kirmizi),
                                  onPressed: () => d.duyuruSil(duyuru.id),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _ekle(BuildContext context, NobetDurumu d) async {
    final baslik = TextEditingController();
    final icerik = TextEditingController();
    final yazar = context.read<OturumDurumu>().kullanici?.ad ?? '';
    Birim? hedef; // null = hepsi

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: const Text('Yeni duyuru'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: baslik,
                  decoration: const InputDecoration(labelText: 'Başlık'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: icerik,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'İçerik'),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Kime gönderilsin?',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Hepsi'),
                      selected: hedef == null,
                      onSelected: (_) => yenile(() => hedef = null),
                    ),
                    for (final b in Birim.values)
                      ChoiceChip(
                        label: Text('Sadece ${b.etiket}'),
                        selected: hedef == b,
                        onSelected: (_) => yenile(() => hedef = b),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                if (baslik.text.trim().isEmpty) return;
                d.duyuruKaydet(Duyuru(
                  id: 'd${DateTime.now().microsecondsSinceEpoch}',
                  baslik: baslik.text.trim(),
                  icerik: icerik.text.trim(),
                  tarih: DateTime.now(),
                  yazar: yazar,
                  hedef: hedef,
                ));
                Navigator.pop(ctx);
              },
              child: const Text('Yayınla'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// AYARLAR — kurum, vardiyalar, kapsama kuralları
// =============================================================================
class AyarlarEkrani extends StatefulWidget {
  const AyarlarEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  late TextEditingController _ad;
  late TextEditingController _alt;
  late TextEditingController _onayKodu;
  bool _onayKoduGizli = true;
  int? _tatilYili;

  @override
  void initState() {
    super.initState();
    final d = context.read<NobetDurumu>();
    _ad = TextEditingController(text: d.ayar.ad);
    _alt = TextEditingController(text: d.ayar.altBaslik);
    _onayKodu = TextEditingController(text: d.ayar.onayKodu);
  }

  @override
  void dispose() {
    _ad.dispose();
    _alt.dispose();
    _onayKodu.dispose();
    super.dispose();
  }

  static const _renkler = [
    0xFF1D4ED8, 0xFF0F766E, 0xFFB45309,
    0xFFB91C1C, 0xFF6D28D9, 0xFF9CA3AF,
  ];

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    final ayar = d.ayar;

    return SingleChildScrollView(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bolum(context, 'Kurum Bilgileri', [
            TextField(
                controller: _ad,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Kurum Adı',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                )),
            const SizedBox(height: 8),
            TextField(
                controller: _alt,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Alt Başlık',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                )),
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final secici = TextButton(
                onPressed: () => _saatSec(
                  ayar.gunBaslangicDk,
                  (dk) {
                    ayar.gunBaslangicDk = dk;
                    d.ayarKaydet(ayar);
                  },
                ),
                child: Text(T.dakikaSaat(ayar.gunBaslangicDk)),
              );
              const aciklama = Text(
                'Nöbet günü bu saatte başlar; gece vardiyası ertesi güne sarkar.',
                style: TextStyle(fontSize: 11.5, color: R.gri),
              );
              return widget.genis
                  ? Row(
                      children: [
                        const Text('Nöbet Günü Başlangıcı: ',
                            style: TextStyle(fontSize: 13)),
                        secici,
                        const Expanded(child: aciklama),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Nöbet Günü Başlangıcı: ',
                                style: TextStyle(fontSize: 13)),
                            secici,
                          ],
                        ),
                        const SizedBox(height: 2),
                        aciklama,
                      ],
                    );
            }),
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final onayAlani = SizedBox(
                width: 220,
                child: TextField(
                  controller: _onayKodu,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: _onayKoduGizli,
                  decoration: InputDecoration(
                    labelText: 'Onaylı Liste Kodu',
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    suffixIcon: IconButton(
                      tooltip: _onayKoduGizli ? 'Kodu göster' : 'Kodu gizle',
                      icon: Icon(_onayKoduGizli
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _onayKoduGizli = !_onayKoduGizli),
                    ),
                  ),
                ),
              );
              const aciklama = Text.rich(
                TextSpan(
                  style:
                      TextStyle(fontSize: 11.5, color: R.gri, height: 1.4),
                  children: [
                    TextSpan(
                      text: '"Onaylanan Liste" versiyonu her zaman PIN '
                          'korumalıdır. Boş bırakılırsa varsayılan kod ',
                    ),
                    TextSpan(
                      text: '0000',
                      style: TextStyle(
                          color: R.kirmizi, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ' geçerli olur.'),
                  ],
                ),
              );
              return widget.genis
                  ? Row(
                      children: [
                        onayAlani,
                        const SizedBox(width: 14),
                        const Expanded(child: aciklama),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        onayAlani,
                        const SizedBox(height: 6),
                        aciklama,
                      ],
                    );
            }),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () {
                  ayar.onayKodu =
                      _onayKodu.text.trim().length == 4 ? _onayKodu.text.trim() : '';
                  ayar.ad = _ad.text.trim();
                  ayar.altBaslik = _alt.text.trim();
                  d.ayarKaydet(ayar);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ayarlar kaydedildi.')),
                  );
                },
                child: const Text('Kaydet'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _bolum(context, 'Vardiya Tanımları', [
            for (var i = 0; i < ayar.vardiyalar.length; i++)
              _vardiyaSatiri(d, ayar, i),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _vardiyaDuzenle(d, ayar, null),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Vardiya Ekle'),
            ),
          ]),
          const SizedBox(height: 8),
          _bolum(context, 'Resmi Tatil ve Arife Günleri', [
            const Text(
              'Resmi tatilde çalışan gündüz personelinin saati normal '
              'mesaiden düşülür ve fazla mesai günü olarak sayılır. '
              'Arife (yarım gün) günlerinde 3.5 saat normal mesai yazılır.',
              style: TextStyle(fontSize: 12, color: R.gri, height: 1.5),
            ),
            const SizedBox(height: 5),
            _yilSekmeleri(d, ayar),
            const SizedBox(height: 5),
            _tatilBolumu(d, ayar, 'Resmi Tatiller (Tam Gün)',
                ayar.resmiTatiller, R.yesil, true),
            const SizedBox(height: 6),
            _tatilBolumu(d, ayar, 'Arife / Yarım Günler', ayar.yarimGunler,
                R.turuncu, false),
            const SizedBox(height: 10),
            const Text(
              'Bir günün üzerine tıklayıp türünü değiştirebilir veya '
              'kaldırabilirsiniz.',
              style: TextStyle(fontSize: 11.5, color: R.gri),
            ),
          ]),
          const SizedBox(height: 8),
          _bolum(context, 'Kapsama Kuralları', [
            const Text(
              'Her kural, belirtilen saat aralığında en az kaç personelin '
              'görevde olması gerektiğini tanımlar (varsayılan: en az 1 '
              'kişi; kuralı düzenleyerek değiştirebilirsiniz). Durum '
              'sütunundaki yeşil/turuncu/kırmızı işaretler bu kurallara '
              'göre hesaplanır.',
              style: TextStyle(fontSize: 12, color: R.gri, height: 1.5),
            ),
            const SizedBox(height: 9),
            for (var i = 0; i < ayar.kurallar.length; i++)
              _kuralSatiri(d, ayar, i),
            const SizedBox(height: 7),
            OutlinedButton.icon(
              onPressed: () => _kuralDuzenle(d, ayar, null),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Kural Ekle'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _bolum(BuildContext context, String baslik, List<Widget> cocuklar) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Tema.kart(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tema.kenar(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(baslik,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 3),
            ...cocuklar,
          ],
        ),
      );

  static int? _yilCikar(String tarih) {
    final p = tarih.split('.');
    if (p.length != 3) return null;
    return int.tryParse(p[2]);
  }

  Widget _yilSekmeleri(NobetDurumu d, KurumAyari ayar) {
    final yillar = <int>{
      DateTime.now().year,
      ...ayar.resmiTatiller.map(_yilCikar).whereType<int>(),
      ...ayar.yarimGunler.map(_yilCikar).whereType<int>(),
    }.toList()
      ..sort();
    _tatilYili ??= DateTime.now().year;
    if (!yillar.contains(_tatilYili)) _tatilYili = yillar.last;

    int sayi(int yil) =>
        ayar.resmiTatiller.where((t) => _yilCikar(t) == yil).length +
        ayar.yarimGunler.where((t) => _yilCikar(t) == yil).length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final y in yillar)
          InkWell(
            onTap: () => setState(() => _tatilYili = y),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: y == _tatilYili ? R.mavi : Tema.tabloBaslik(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: y == _tatilYili ? R.mavi : Tema.kenar(context)),
              ),
              child: Text('$y  (${sayi(y)})',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: y == _tatilYili ? Colors.white : null,
                  )),
            ),
          ),
      ],
    );
  }

  Widget _tatilBolumu(
      NobetDurumu d, KurumAyari ayar, String baslik, Set<String> kume,
      Color renk, bool tamGunMu) {
    final yil = _tatilYili;
    final sirali = kume.where((t) => _yilCikar(t) == yil).toList()
      ..sort(_tarihKarsilastir);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(baslik,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(width: 4),
            Text('(${sirali.length})',
                style: const TextStyle(fontSize: 12, color: R.gri)),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => _tatilEkle(d, ayar, tamGunMu),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Gün Ekle'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (sirali.isEmpty)
          Text('$yil yılında henüz gün eklenmedi.',
              style: const TextStyle(fontSize: 12, color: R.gri))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in sirali)
                PopupMenuButton<String>(
                  tooltip: 'Düzenle',
                  onSelected: (secim) async {
                    if (secim == 'tur') {
                      kume.remove(t);
                      (tamGunMu ? ayar.yarimGunler : ayar.resmiTatiller).add(t);
                      await d.ayarKaydet(ayar);
                      if (mounted) setState(() {});
                      return;
                    }
                    // 'sil' — diğer silme işlemleriyle tutarlı olsun diye
                    // onay isteniyor (ek bulgu 9).
                    final onay = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Günü kaldır'),
                        content: Text('$t tatil listesinden kaldırılacak.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Vazgeç')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Kaldır')),
                        ],
                      ),
                    );
                    if (onay != true) return;
                    kume.remove(t);
                    await d.ayarKaydet(ayar);
                    if (mounted) setState(() {});
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'tur',
                      child: Row(children: [
                        Icon(
                            tamGunMu
                                ? Icons.hourglass_bottom
                                : Icons.wb_sunny_outlined,
                            size: 16),
                        const SizedBox(width: 10),
                        Text(tamGunMu
                            ? 'Yarım güne (arife) çevir'
                            : 'Tam güne çevir'),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'sil',
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 16, color: R.kirmizi),
                        SizedBox(width: 10),
                        Text('Kaldır', style: TextStyle(color: R.kirmizi)),
                      ]),
                    ),
                  ],
                  child: Chip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t, style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, size: 15),
                      ],
                    ),
                    labelPadding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 0),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: renk.withValues(alpha: .10),
                    side: BorderSide(color: renk.withValues(alpha: .35)),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  static int _tarihKarsilastir(String a, String b) {
    List<int> boz(String x) {
      final p = x.split('.');
      if (p.length != 3) return [0, 0, 0];
      return [
        int.tryParse(p[2]) ?? 0,
        int.tryParse(p[1]) ?? 0,
        int.tryParse(p[0]) ?? 0
      ];
    }

    final x = boz(a), y = boz(b);
    for (var i = 0; i < 3; i++) {
      final c = x[i].compareTo(y[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  Future<void> _tatilEkle(
      NobetDurumu d, KurumAyari ayar, bool tamGunMu) async {
    final secim = await showDatePicker(
      context: context,
      initialDate: DateTime(d.yil, d.ay, 1),
      firstDate: DateTime(d.yil - 2),
      lastDate: DateTime(d.yil + 3),
      helpText: tamGunMu ? 'Resmi tatil günü seçin' : 'Arife günü seçin',
    );
    if (secim == null || !mounted) return;

    final metin = T.tarih(secim);

    if (ayar.resmiTatiller.contains(metin) ||
        ayar.yarimGunler.contains(metin)) {
      final mevcutTur = ayar.resmiTatiller.contains(metin)
          ? 'tam gün resmi tatil'
          : 'yarım gün (arife)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$metin zaten $mevcutTur olarak kayıtlı.')),
      );
      return;
    }

    (tamGunMu ? ayar.resmiTatiller : ayar.yarimGunler).add(metin);
    await d.ayarKaydet(ayar);
    if (mounted) setState(() => _tatilYili = secim.year);
  }

  Widget _vardiyaSatiri(NobetDurumu d, KurumAyari ayar, int i) {
    final v = ayar.vardiyalar[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: Color(v.renk), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          SizedBox(
              width: 44,
              child: Text(v.kod,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          if (widget.genis) ...[
            SizedBox(
                width: 150,
                child: Text(v.etiket, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: Text(
                v.saat > 0
                    ? '${v.saat.toStringAsFixed(1)} sa'
                        '${v.geceSaati > 0 ? ' (${v.geceSaati.toStringAsFixed(1)} gece)' : ''}'
                    : 'İzin/boş',
                style: const TextStyle(fontSize: 12, color: R.gri),
              ),
            ),
          ] else ...[
            Expanded(child: Text(v.etiket)),
            Text(
              v.saat > 0
                  ? '${v.saat.toStringAsFixed(1)} sa'
                      '${v.geceSaati > 0 ? ' (${v.geceSaati.toStringAsFixed(1)} gece)' : ''}'
                  : 'İzin/boş',
              style: const TextStyle(fontSize: 12, color: R.gri),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: () => _vardiyaDuzenle(d, ayar, i),
          ),
          IconButton(
            tooltip: 'Vardiyayı sil',
            icon: const Icon(Icons.delete_outline, size: 18, color: R.kirmizi),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: () {
              ayar.vardiyalar.removeAt(i);
              d.ayarKaydet(ayar);
            },
          ),
        ],
      ),
    );
  }

  Widget _kuralSatiri(NobetDurumu d, KurumAyari ayar, int i) {
    final k = ayar.kurallar[i];
    final gunMetni = k.gunler.isEmpty
        ? 'Her gün'
        : (k.gunler.toList()..sort())
            .map((g) => T.gunlerKisa[g - 1])
            .join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: widget.genis ? 10 : 5,
        runSpacing: 2,
        children: [
          SizedBox(
            height: 27,
            width: 37,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: k.aktif,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) {
                  ayar.kurallar[i] = k.kopyala(aktif: v);
                  d.ayarKaydet(ayar);
                },
              ),
            ),
          ),
          widget.genis
              ? SizedBox(
                  width: 70,
                  child: Text(k.ad,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)))
              : Text(k.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
          widget.genis
              ? SizedBox(width: 115, child: Text(k.araligMetni))
              : Text(k.araligMetni),
          if (widget.genis)
            Text(gunMetni, style: const TextStyle(fontSize: 12, color: R.gri)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                onPressed: () => _kuralDuzenle(d, ayar, i),
              ),
              const SizedBox(width: 1),
              IconButton(
                tooltip: 'Kuralı sil',
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: R.kirmizi),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                onPressed: () {
                  ayar.kurallar.removeAt(i);
                  d.ayarKaydet(ayar);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saatSec(int mevcutDk, void Function(int) sonuc) async {
    final secim = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: mevcutDk ~/ 60, minute: mevcutDk % 60),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (secim != null) {
      setState(() => sonuc(secim.hour * 60 + secim.minute));
    }
  }

  // --- vardiya diyaloğu -------------------------------------------------------
  Future<void> _vardiyaDuzenle(
      NobetDurumu d, KurumAyari ayar, int? index) async {
    final mevcut = index == null ? null : ayar.vardiyalar[index];
    final kod = TextEditingController(text: mevcut?.kod ?? '');
    final etiket = TextEditingController(text: mevcut?.etiket ?? '');
    final toplamSaat = TextEditingController(
        text: (mevcut?.toplamSaat ?? 0) == 0
            ? ''
            : '${mevcut!.toplamSaat}');
    final geceSaati = TextEditingController(
        text: (mevcut?.geceSaati ?? 0) == 0 ? '' : '${mevcut!.geceSaati}');
    var bas = mevcut?.baslangicDk ?? 480;
    var bit = mevcut?.bitisDk ?? 1200;
    var calisiyor = mevcut?.calisiyor ?? true;
    var renk = mevcut?.renk ?? _renkler.first;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) {
          Future<void> saatSec(bool baslangic) async {
            final o = baslangic ? bas : bit;
            final secim = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay(hour: o ~/ 60, minute: o % 60),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                child: child!,
              ),
            );
            if (secim == null) return;
            final dk = secim.hour * 60 + secim.minute;
            yenile(() {
              if (baslangic) {
                bas = dk;
              } else {
                bit = dk;
              }
              if (etiket.text.isEmpty || etiket.text.contains('–')) {
                etiket.text =
                    '${T.dakikaSaat(bas)}–${T.dakikaSaat(bit)}';
              }
            });
          }

          return AlertDialog(
            title:
                Text(mevcut == null ? 'Vardiya ekle' : 'Vardiyayı düzenle'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: kod,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(labelText: 'Kod'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: etiket,
                          decoration:
                              const InputDecoration(labelText: 'Görünen ad'),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Çalışma vardiyası'),
                    subtitle: const Text('Kapatılırsa izin/tatil olarak sayılır'),
                    value: calisiyor,
                    onChanged: (v) => yenile(() => calisiyor = v),
                  ),
                  if (calisiyor)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => saatSec(true),
                            child: Text('Başlangıç: ${T.dakikaSaat(bas)}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => saatSec(false),
                            child: Text('Bitiş: ${T.dakikaSaat(bit)}'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: toplamSaat,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Bordro saati',
                            helperText: 'Mola düşülmüş',
                            helperMaxLines: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: geceSaati,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Gece saati',
                            helperText: 'Bunun kaçı gece',
                            helperMaxLines: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      children: [
                        for (final r in _renkler)
                          InkWell(
                            onTap: () => yenile(() => renk = r),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: Color(r),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: renk == r
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç')),
              FilledButton(
                onPressed: () {
                  if (kod.text.trim().isEmpty) return;
                  final yeni = VardiyaTanimi(
                    kod: kod.text.trim(),
                    etiket: etiket.text.trim().isEmpty
                        ? kod.text.trim()
                        : etiket.text.trim(),
                    kisa: mevcut?.kisa ?? '',
                    baslangicDk: calisiyor ? bas : 0,
                    bitisDk: calisiyor ? bit : 0,
                    calisiyor: calisiyor,
                    renk: renk,
                    izinSayilir: !calisiyor,
                    toplamSaat: double.tryParse(
                            toplamSaat.text.replaceAll(',', '.')) ??
                        0,
                    geceSaati:
                        double.tryParse(geceSaati.text.replaceAll(',', '.')) ??
                            0,
                    yarimGunSaati: mevcut?.yarimGunSaati ?? -1,
                  );
                  if (index == null) {
                    ayar.vardiyalar.add(yeni);
                  } else {
                    ayar.vardiyalar[index] = yeni;
                  }
                  d.ayarKaydet(ayar);
                  Navigator.pop(ctx);
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- kural diyaloğu ---------------------------------------------------------
  Future<void> _kuralDuzenle(
      NobetDurumu d, KurumAyari ayar, int? index) async {
    final mevcut = index == null ? null : ayar.kurallar[index];
    final ad = TextEditingController(text: mevcut?.ad ?? '');
    var bas = mevcut?.baslangicDk ?? 480;
    var bit = mevcut?.bitisDk ?? 1200;
    var min = mevcut?.minPersonel ?? 1;
    final gunler = <int>{...(mevcut?.gunler ?? const <int>{})};

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) {
          Future<void> saatSec(bool baslangic) async {
            final o = baslangic ? bas : bit;
            final secim = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay(hour: o ~/ 60, minute: o % 60),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                child: child!,
              ),
            );
            if (secim == null) return;
            yenile(() {
              if (baslangic) {
                bas = secim.hour * 60 + secim.minute;
              } else {
                bit = secim.hour * 60 + secim.minute;
              }
            });
          }

          return AlertDialog(
            title: Text(mevcut == null ? 'Kural ekle' : 'Kuralı düzenle'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ad,
                    decoration: const InputDecoration(
                        labelText: 'Kural adı (ör. Gece)'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => saatSec(true),
                          child: Text('Başlangıç: ${T.dakikaSaat(bas)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => saatSec(false),
                          child: Text('Bitiş: ${T.dakikaSaat(bit)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text('En az personel:'),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Kişi sayısını azalt',
                        onPressed: () =>
                            yenile(() => min = min > 1 ? min - 1 : 1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$min',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      IconButton(
                        tooltip: 'Kişi sayısını artır',
                        onPressed: () => yenile(() => min++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Geçerli günler (boş = her gün)',
                        style: TextStyle(fontSize: 12, color: R.gri)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var g = 1; g <= 7; g++)
                        FilterChip(
                          label: Text(T.gunlerKisa[g - 1]),
                          selected: gunler.contains(g),
                          onSelected: (s) => yenile(() {
                            if (s) {
                              gunler.add(g);
                            } else {
                              gunler.remove(g);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç')),
              FilledButton(
                onPressed: () {
                  if (ad.text.trim().isEmpty) return;
                  final yeni = KapsamaKurali(
                    ad: ad.text.trim(),
                    baslangicDk: bas,
                    bitisDk: bit,
                    minPersonel: min,
                    gunler: gunler,
                  );
                  if (index == null) {
                    ayar.kurallar.add(yeni);
                  } else {
                    ayar.kurallar[index] = yeni;
                  }
                  d.ayarKaydet(ayar);
                  Navigator.pop(ctx);
                },
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// KULLANICILAR
// =============================================================================
class KullanicilarEkrani extends StatefulWidget {
  const KullanicilarEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<KullanicilarEkrani> createState() => _KullanicilarEkraniState();
}

class _KullanicilarEkraniState extends State<KullanicilarEkrani> {
  late Future<List<Kullanici>> _gelecek;
  late Birim _secilenBirim;

  @override
  void initState() {
    super.initState();
    _secilenBirim = context.read<NobetDurumu>().birim;
    _yukle();
  }

  void _yukle() {
    final d = context.read<NobetDurumu>();
    _gelecek = d.servis.kullanicilariGetir(d.kurumId);
  }

  @override
  Widget build(BuildContext context) {
    final d = context.read<NobetDurumu>();
    final oturum = context.watch<OturumDurumu>();

    return Padding(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _duzenle(d, null),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Kullanıcı ekle'),
              ),
              const SizedBox(width: 12),
              SegmentedButton<Birim>(
                segments: const [
                  ButtonSegment(
                    value: Birim.guvenlik,
                    label: Text('Güvenlik'),
                    icon: Icon(Icons.security_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: Birim.temizlik,
                    label: Text('Temizlik'),
                    icon: Icon(Icons.cleaning_services_outlined, size: 16),
                  ),
                ],
                selected: {_secilenBirim},
                onSelectionChanged: (s) =>
                    setState(() => _secilenBirim = s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const Spacer(),
              const Text(
                'Roller: Yönetici her şeyi, Liste Sorumlusu listeyi, '
                'Personel sadece görüntüler.',
                style: TextStyle(fontSize: 11.5, color: R.gri),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Kullanici>>(
              future: _gelecek,
              builder: (ctx, anlik) {
                if (anlik.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final tumListe = anlik.data ?? const <Kullanici>[];
                final liste = tumListe
                    .where((k) =>
                        k.kisitliBirim == null ||
                        k.kisitliBirim == _secilenBirim)
                    .toList();
                return ListView.separated(
                  itemCount: liste.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (ctx, i) {
                    final k = liste[i];
                    final aktifMi = oturum.kullanici?.uid == k.uid;
                    return Card(
                      elevation: 0,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? R.koyuKart
                          : const Color(0xFFE9ECF2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: aktifMi ? R.mavi : Tema.kenar(context),
                          width: aktifMi ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        leading: CircleAvatar(
                          radius: 13,
                          backgroundColor:
                              k.rol == Rol.yonetici ? R.maviKoyu : R.gri,
                          child: Text(k.basHarfler,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10.5)),
                        ),
                        title: Row(
                          children: [
                            Text(k.ad,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5)),
                            if (aktifMi) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: R.mavi,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('Aktif',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 10)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          [
                            k.rolEtiketiUzun,
                            if (k.kimlik.isNotEmpty)
                              'TC ile giriş'
                            else if (k.pinliMi)
                              'Giriş kodu var'
                            else
                              'Kod yok',
                            if (!k.onayli) 'Onay bekliyor',
                          ].join(' · '),
                          style: TextStyle(
                              fontSize: 10.5,
                              color: k.onayli ? null : R.turuncu,
                              fontWeight:
                                  k.onayli ? null : FontWeight.w600),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!k.onayli)
                              IconButton(
                                tooltip: 'Üyeliği onayla',
                                icon: const Icon(Icons.check_circle_outline,
                                    size: 20, color: R.yesil),
                                onPressed: () async {
                                  await d.servis.kullaniciKaydet(
                                      d.kurumId, k.kopyala(onayli: true));
                                  if (mounted) setState(_yukle);
                                },
                              ),
                            IconButton(
                              tooltip: 'Kullanıcıyı düzenle',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _duzenle(d, k),
                            ),
                            if (liste.length > 1 && !aktifMi)
                              IconButton(
                                tooltip: 'Kullanıcıyı sil',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: R.kirmizi),
                                onPressed: () async {
                                  await d.servis.kullaniciSil(d.kurumId, k.uid);
                                  if (mounted) setState(_yukle);
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _duzenle(NobetDurumu d, Kullanici? mevcut) async {
    final ad = TextEditingController(text: mevcut?.ad ?? '');
    final pin = TextEditingController(text: mevcut?.pin ?? '');
    var rol = mevcut?.rol ?? Rol.izleyici;
    var sadecePdf = mevcut?.sadecePdf ?? false;
    Birim? kisitliBirim = mevcut?.kisitliBirim;
    var pinGizli = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: Text(mevcut == null ? 'Kullanıcı ekle' : 'Kullanıcıyı düzenle'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ad,
                  decoration: const InputDecoration(labelText: 'Ad Soyad'),
                ),
                const SizedBox(height: 14),
                if (mevcut?.yoneticiProfili == null) ...[
                  DropdownButtonFormField<Rol>(
                    initialValue: rol,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: [
                      for (final r in Rol.values)
                        DropdownMenuItem(value: r, child: Text(r.etiket)),
                    ],
                    onChanged: (v) => yenile(() => rol = v ?? rol),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: pin,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: pinGizli,
                  decoration: InputDecoration(
                    labelText: 'Giriş kodu (isteğe bağlı)',
                    helperText: '4 hane. Boş bırakılırsa kod sorulmaz.',
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: pinGizli ? 'Kodu göster' : 'Kodu gizle',
                      icon: Icon(pinGizli
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => yenile(() => pinGizli = !pinGizli),
                    ),
                  ),
                ),
                const Divider(height: 24),
                if (mevcut?.yoneticiProfili != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: R.mavi.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.admin_panel_settings_outlined,
                          size: 17, color: R.maviKoyu),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bu kullanıcı "${mevcut!.yoneticiProfili!.etiket}" '
                          'profiline sahip. Rol, birim kısıtı ve bordro '
                          'yetkisi profilden gelir; Admin Yönetimi '
                          'bölümünden değiştirin.',
                          style: const TextStyle(fontSize: 11.5, height: 1.4),
                        ),
                      ),
                    ]),
                  )
                else
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sadece PDF (bordro modu)'),
                    subtitle: const Text(
                        'Girişte Onaylanan Liste açılır; hiçbir düzenleme '
                        'yapılamaz, sadece görüntülenir ve PDF indirilir.'),
                    value: sadecePdf,
                    onChanged: (v) => yenile(() => sadecePdf = v),
                  ),
                if (mevcut?.yoneticiProfili == null) ...[
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Birim kısıtı',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Seçilirse kullanıcı yalnızca o birime girebilir.',
                      style: TextStyle(fontSize: 11.5, color: R.gri),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Kısıt yok'),
                        selected: kisitliBirim == null,
                        onSelected: (_) => yenile(() => kisitliBirim = null),
                      ),
                      for (final b in Birim.values)
                        ChoiceChip(
                          label: Text('Sadece ${b.etiket}'),
                          selected: kisitliBirim == b,
                          onSelected: (_) => yenile(() => kisitliBirim = b),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () async {
                if (ad.text.trim().isEmpty) return;
                final temizPin =
                    pin.text.trim().length == 4 ? pin.text.trim() : '';
                final yeni = mevcut == null
                    ? Kullanici(
                        uid: 'k${DateTime.now().microsecondsSinceEpoch}',
                        ad: ad.text.trim(),
                        eposta: '',
                        rol: rol,
                        kurumId: d.kurumId,
                        pin: temizPin,
                        sadecePdf: sadecePdf,
                        kisitliBirim: kisitliBirim,
                      )
                    : mevcut.kopyala(
                        ad: ad.text.trim(),
                        rol: rol,
                        pin: temizPin,
                        sadecePdf: sadecePdf,
                        kisitliBirim: kisitliBirim,
                        kisitliBirimSil: kisitliBirim == null,
                      );
                await d.servis.kullaniciKaydet(d.kurumId, yeni);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(_yukle);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ADMİN YÖNETİMİ
// =============================================================================
/// Eski uygulamadaki "Admin Yönetimi" ekranının karşılığı: yalnızca yönetici
/// profili atanmış kullanıcıları listeler ve profil atamaya odaklanır.
/// Genel kullanıcı listesi için [KullanicilarEkrani] kullanılır.
class AdminYonetimiEkrani extends StatefulWidget {
  const AdminYonetimiEkrani({super.key, required this.genis});
  final bool genis;

  @override
  State<AdminYonetimiEkrani> createState() => _AdminYonetimiEkraniState();
}

class _AdminYonetimiEkraniState extends State<AdminYonetimiEkrani> {
  List<Kullanici> _hepsi = const [];
  bool _mesgul = false;

  static Color profilRengi(YoneticiProfili p) => switch (p) {
        YoneticiProfili.superAdmin => R.maviKoyu,
        YoneticiProfili.temizlikNobet => R.yesil,
        YoneticiProfili.bordro => R.turuncu,
      };

  static IconData profilIkonu(YoneticiProfili p) => switch (p) {
        YoneticiProfili.superAdmin => Icons.shield_moon_outlined,
        YoneticiProfili.temizlikNobet => Icons.cleaning_services_outlined,
        YoneticiProfili.bordro => Icons.payments_outlined,
      };

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final d = context.read<NobetDurumu>();
    setState(() => _mesgul = true);
    try {
      _hepsi = await d.servis.kullanicilariGetir(d.kurumId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kullanıcılar okunamadı: $e')),
        );
      }
    }
    if (mounted) setState(() => _mesgul = false);
  }

  List<Kullanici> get _adminler =>
      _hepsi.where((k) => k.yoneticiProfili != null).toList();

  List<Kullanici> get _adminOlmayanlar =>
      _hepsi.where((k) => k.yoneticiProfili == null).toList();

  /// Yeni admin ekler veya mevcut bir kullanıcıya profil atar.
  Future<void> _profilAta({Kullanici? mevcut}) async {
    final ad = TextEditingController(text: mevcut?.ad ?? '');
    final pin = TextEditingController(text: mevcut?.pin ?? '');
    final tc = TextEditingController(text: mevcut?.kimlik ?? '');
    final kullaniciAdi =
        TextEditingController(text: mevcut?.kullaniciAdi ?? '');
    final sifre1 = TextEditingController();
    final sifre2 = TextEditingController();
    var profil = mevcut?.yoneticiProfili ?? YoneticiProfili.temizlikNobet;
    Kullanici? hedef = mevcut;
    var pinGizli = true;
    var sifreGizli = true;

    final kaydet = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: Text(mevcut == null ? 'Admin Ekle' : 'Admini Düzenle'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Yeni kayıtta: mevcut bir kullanıcıyı yükseltme seçeneği
                  if (mevcut == null && _adminOlmayanlar.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    DropdownButtonFormField<Kullanici?>(
                      initialValue: hedef,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Mevcut kullanıcıyı yükselt',
                        helperText:
                            'Boş bırakırsanız yeni bir kullanıcı oluşturulur.',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Yeni kullanıcı oluştur')),
                        for (final k in _adminOlmayanlar)
                          DropdownMenuItem(
                              value: k,
                              child: Text('${k.ad} (${k.rol.etiket})',
                                  overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => yenile(() {
                        hedef = v;
                        if (v != null) {
                          ad.text = v.ad;
                          pin.text = v.pin;
                        }
                      }),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 6),
                  TextField(
                    controller: ad,
                    decoration: const InputDecoration(
                      labelText: 'Ad Soyad',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pin,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: pinGizli,
                    decoration: InputDecoration(
                      labelText: 'Giriş kodu (isteğe bağlı)',
                      helperText: '4 hane. Boş bırakılırsa kod sorulmaz.',
                      counterText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      suffixIcon: IconButton(
                        tooltip: pinGizli ? 'Kodu göster' : 'Kodu gizle',
                        icon: Icon(pinGizli
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => yenile(() => pinGizli = !pinGizli),
                      ),
                    ),
                  ),
                  if (mevcut != null || hedef == null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: R.mavi.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Bu kişi Personel/Kullanıcı olarak "Üye ol" ile kayıt '
                        'olmadan doğrudan giriş yapacaksa T.C. Kimlik No ve/veya '
                        'kullanıcı adı ile bir şifre belirleyin. İkisi de boş '
                        'bırakılırsa giriş yapamaz.',
                        style: TextStyle(fontSize: 11.5, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tc,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'T.C. Kimlik No (isteğe bağlı)',
                        helperText: 'Girişte kullanılabilir.',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: kullaniciAdi,
                      decoration: const InputDecoration(
                        labelText: 'Kullanıcı Adı (isteğe bağlı)',
                        helperText: 'T.C. yerine bununla da giriş yapılabilir.',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: sifre1,
                      obscureText: sifreGizli,
                      decoration: InputDecoration(
                        labelText: mevcut?.sifreHash.isNotEmpty == true
                            ? 'Yeni şifre (değiştirmek için)'
                            : 'Şifre',
                        helperText: 'En az 6 karakter.',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        suffixIcon: IconButton(
                          tooltip: sifreGizli ? 'Göster' : 'Gizle',
                          icon: Icon(sifreGizli
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => yenile(() => sifreGizli = !sifreGizli),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: sifre2,
                      obscureText: sifreGizli,
                      decoration: const InputDecoration(
                        labelText: 'Şifre Tekrar',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                  const Divider(height: 18),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Yönetici profili',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ),
                  const SizedBox(height: 6),
                  for (final p in YoneticiProfili.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => yenile(() => profil = p),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: profil == p
                                ? profilRengi(p).withValues(alpha: .08)
                                : null,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: profil == p
                                  ? profilRengi(p)
                                  : Tema.kenar(ctx),
                              width: profil == p ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                profil == p
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: profil == p ? profilRengi(p) : R.gri,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Icon(profilIkonu(p),
                                          size: 15, color: profilRengi(p)),
                                      const SizedBox(width: 6),
                                      Text(p.etiket,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: profilRengi(p))),
                                    ]),
                                    const SizedBox(height: 3),
                                    Text(p.aciklama,
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            color: R.gri,
                                            height: 1.4)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
    if (ad.text.trim().isEmpty) return;

    final d = context.read<NobetDurumu>();
    final temizPin = pin.text.trim().length == 4 ? pin.text.trim() : '';

    final tcMetin = tc.text.trim();
    final kullaniciAdiMetin = kullaniciAdi.text.trim();
    final s1 = sifre1.text;
    final s2 = sifre2.text;

    if (tcMetin.isNotEmpty && !Kimlik.tcGecerli(tcMetin)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Geçerli bir 11 haneli T.C. Kimlik No girin.')));
      return;
    }
    if (s1.isNotEmpty) {
      if (s1.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Şifre en az 6 karakter olmalı.')));
        return;
      }
      if (s1 != s2) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Şifreler eşleşmiyor.')));
        return;
      }
    }
    if (tcMetin.isNotEmpty) {
      final cakisan = _hepsi.any((k) =>
          k.kimlik == tcMetin && k.uid != (hedef?.uid ?? ''));
      if (cakisan) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bu T.C. Kimlik No başka bir kullanıcıda kayıtlı.')));
        return;
      }
    }
    if (kullaniciAdiMetin.isNotEmpty) {
      final kucuk = kullaniciAdiMetin.toLowerCase();
      final cakisan = _hepsi.any((k) =>
          k.kullaniciAdi.toLowerCase() == kucuk &&
          k.uid != (hedef?.uid ?? ''));
      if (cakisan) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bu kullanıcı adı başka bir kullanıcıda kayıtlı.')));
        return;
      }
    }

    final yeni = hedef == null
        ? Kullanici.yonetici(
            uid: 'k${DateTime.now().microsecondsSinceEpoch}',
            ad: ad.text.trim(),
            kurumId: d.kurumId,
            profil: profil,
            pin: temizPin,
            kimlik: tcMetin,
            kullaniciAdi: kullaniciAdiMetin,
            sifreHash: s1.isNotEmpty ? Kimlik.sifreOzeti(s1) : '',
            onayli: true,
          )
        : hedef!.kopyala(
            ad: ad.text.trim(),
            pin: temizPin,
            yoneticiProfili: profil,
            kimlik: tcMetin.isNotEmpty ? tcMetin : null,
            kullaniciAdi: kullaniciAdiMetin.isNotEmpty ? kullaniciAdiMetin : null,
            sifreHash: s1.isNotEmpty ? Kimlik.sifreOzeti(s1) : null,
            onayli: true,
          );

    await d.servis.kullaniciKaydet(d.kurumId, yeni);
    await _yukle();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${yeni.ad} — ${profil.etiket} olarak kaydedildi.')),
      );
    }
  }

  /// Profili kaldırır; kullanıcı normal kullanıcıya (Personel) döner.
  Future<void> _profilKaldir(Kullanici k) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.person_remove_outlined,
            color: R.turuncu, size: 30),
        title: const Text('Yönetici yetkisini kaldır'),
        content: Text(
          '${k.ad} artık "${k.yoneticiProfili!.etiket}" olmayacak. Kullanıcı '
          'silinmez, Personel rolüne döner ve yönetim ekranlarına giremez.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: R.turuncu),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yetkiyi kaldır')),
        ],
      ),
    );
    if (onay != true || !mounted) return;

    final d = context.read<NobetDurumu>();
    await d.servis.kullaniciKaydet(
      d.kurumId,
      k.kopyala(rol: Rol.izleyici, profilSil: true),
    );
    await _yukle();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${k.ad} artık yönetici değil.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    final oturum = context.watch<OturumDurumu>();
    final adminler = _adminler;

    // Son Süper Admin kilitlenmemeli — kendini yetkisiz bırakma koruması.
    final superSayisi = adminler
        .where((k) => k.yoneticiProfili == YoneticiProfili.superAdmin)
        .length;

    return Padding(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _profilAta(),
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                label: const Text('Admin Ekle'),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Yenile',
                onPressed: _yukle,
                icon: const Icon(Icons.refresh),
              ),
              const Spacer(),
              if (widget.genis)
                const Text(
                  'Profil; rol, birim kısıtı ve bordro yetkisini birlikte belirler.',
                  style: TextStyle(fontSize: 11.5, color: R.gri),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _mesgul
                ? const Center(child: CircularProgressIndicator())
                : adminler.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.admin_panel_settings_outlined,
                                  size: 44, color: R.gri),
                              const SizedBox(height: 12),
                              const Text('Tanımlı admin yok',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              const Text(
                                'Mevcut kullanıcılar eski rol düzeniyle '
                                'çalışmaya devam eder. "Admin ekle" ile '
                                'birine profil atayabilirsiniz.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: R.gri, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: adminler.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 2),
                        itemBuilder: (ctx, i) {
                          final k = adminler[i];
                          final p = k.yoneticiProfili!;
                          final renk = profilRengi(p);
                          final aktifMi = oturum.kullanici?.uid == k.uid;
                          final sonSuper =
                              p == YoneticiProfili.superAdmin &&
                                  superSayisi <= 1;

                          return Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: renk.withValues(alpha: .45),
                                width: aktifMi ? 1.5 : 1,
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 0),
                              leading: CircleAvatar(
                                radius: 13,
                                backgroundColor: renk.withValues(alpha: .15),
                                child: Icon(profilIkonu(p),
                                    size: 14, color: renk),
                              ),
                              title: Row(children: [
                                Flexible(
                                  child: Text(k.ad,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: renk)),
                                ),
                                if (aktifMi) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: R.mavi,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text('Aktif',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10)),
                                  ),
                                ],
                              ]),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 1),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 0),
                                    decoration: BoxDecoration(
                                      color: renk.withValues(alpha: .10),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: renk.withValues(alpha: .4)),
                                    ),
                                    child: Text(p.etiket,
                                        style: TextStyle(
                                            fontSize: 9.5,
                                            color: renk,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    [
                                      k.pinliMi ? 'Giriş kodu var' : 'Kod yok',
                                      k.kisitliBirim == null
                                          ? 'Tüm birimler'
                                          : 'Sadece ${k.kisitliBirim!.etiket}',
                                      k.bordroYetkisi
                                          ? 'Bordro yetkili'
                                          : 'Bordro yok',
                                    ].join(' · '),
                                    style: const TextStyle(fontSize: 10.5),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Düzenle',
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 20, color: R.mavi),
                                    onPressed: () => _profilAta(mevcut: k),
                                  ),
                                  IconButton(
                                    tooltip: sonSuper
                                        ? 'Son Süper Admin kaldırılamaz'
                                        : 'Yönetici yetkisini kaldır',
                                    icon: Icon(Icons.person_remove_outlined,
                                        size: 20,
                                        color: sonSuper ? R.gri : R.turuncu),
                                    onPressed: sonSuper
                                        ? null
                                        : () => _profilKaldir(k),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (!_mesgul && _adminOlmayanlar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${_adminOlmayanlar.length} kullanıcı profilsiz — eski rol '
                'düzeniyle çalışıyor. Kullanıcılar bölümünden yönetilir.',
                style: const TextStyle(fontSize: 11.5, color: R.gri),
              ),
            ),
          // d yalnızca servis erişimi için okundu; yeniden çizimi tetiklesin.
          if (d.yukleniyor) const SizedBox.shrink(),
        ],
      ),
    );
  }
}

// =============================================================================
// YEDEKLEME
// =============================================================================
class YedeklemeEkrani extends StatelessWidget {
  const YedeklemeEkrani({super.key, required this.genis});
  final bool genis;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    final servis = d.servis is YedeklenebilirServis
        ? d.servis as YedeklenebilirServis
        : null;
    final bulutMu = d.servis is FirestoreServis;

    return SingleChildScrollView(
      padding: genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Yedekleme',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (bulutMu ? R.yesil : R.turuncu).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(bulutMu ? Icons.cloud_done_outlined : Icons.computer,
                    size: 13, color: bulutMu ? R.yesil : R.turuncu),
                const SizedBox(width: 5),
                Text(bulutMu ? 'Bulut (Firestore)' : 'Yerel mod',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: bulutMu ? R.yesil : R.turuncu)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            bulutMu
                ? 'Veriler Firestore\'da tutulur; tüm cihazlar aynı veriyi '
                    'görür. Yine de ara ara yedek alıp bir metin dosyasına '
                    'kaydetmenizi öneririz.'
                : 'Veriler bu cihazın kendi deposunda tutulur (buluta '
                    'bağlanılamadı). Uygulamayı silerseniz veriler kaybolur; '
                    'ara ara yedek alıp bir metin dosyasına kaydedin.',
            style: const TextStyle(fontSize: 12.5, color: R.gri, height: 1.5),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: servis == null
                    ? null
                    : () async {
                        final json = await servis.tumVeriyiDisaAktar();
                        await Clipboard.setData(ClipboardData(text: json));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Yedek panoya kopyalandı. Bir metin '
                                  'dosyasına yapıştırıp saklayın.'),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Tüm veriyi panoya kopyala'),
              ),
              OutlinedButton.icon(
                onPressed: servis == null
                    ? null
                    : () => _geriYukle(context, d, servis),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Panodan geri yükle'),
              ),
            ],
          ),
          if (bulutMu) ...[
            const SizedBox(height: 26),
            const Text('Bu cihazdaki eski yerel veri',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            const Text(
              'Bulut moduna geçmeden önce bu cihazda kayıtlı veriler varsa '
              '(personeller, nöbet listeleri, bordrolar) buluta tek seferde '
              'taşıyabilirsiniz. Buluttaki aynı kayıtların üzerine yazılır.',
              style: TextStyle(fontSize: 12.5, color: R.gri, height: 1.5),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _yereldenBulutaTasi(context, d),
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('Yerel veriyi buluta yükle'),
            ),
          ],
          const SizedBox(height: 26),
          const Text('Sadece bu dönemin listesi',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          Text(
            '${d.birim.etiket} · ${T.ayYil(d.yil, d.ay)}',
            style: const TextStyle(fontSize: 12.5, color: R.gri),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final json = const JsonEncoder.withIndent('  ').convert({
                'birim': d.birim.name,
                'kurum': d.ayar.haritasi,
                'personeller':
                    d.personeller.map((p) => p.haritasi).toList(),
                'donem': d.kayit.haritasi,
              });
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dönem yedeği kopyalandı.')),
                );
              }
            },
            icon: const Icon(Icons.file_copy_outlined, size: 18),
            label: const Text('Bu dönemi kopyala'),
          ),
        ],
      ),
    );
  }

  Future<void> _geriYukle(BuildContext context, NobetDurumu d,
      YedeklenebilirServis servis) async {
    final pano = await Clipboard.getData(Clipboard.kTextPlain);
    final metin = pano?.text ?? '';

    if (metin.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Pano boş. Önce yedek metnini kopyalayın.')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: R.turuncu, size: 30),
        title: const Text('Yedekten geri yükle'),
        content: const Text(
          'Panodaki yedek yazılacak ve mevcut veriler üzerine '
          'yazılacak. Devam edilsin mi?',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Geri yükle')),
        ],
      ),
    );
    if (onay != true) return;

    try {
      await servis.yedektenYukle(metin);
      await d.baslat();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yedek geri yüklendi.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yedek okunamadı: $e')),
        );
      }
    }
  }

  /// Bulut modundayken, bu cihazın eski yerel (SharedPreferences)
  /// verisini Firestore'a kopyalar. Yerel veri silinmez.
  Future<void> _yereldenBulutaTasi(
      BuildContext context, NobetDurumu d) async {
    final onay = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud_upload_outlined,
            color: R.maviKoyu, size: 30),
        title: const Text('Yerel veriyi buluta yükle'),
        content: const Text(
          'Bu cihazda kayıtlı tüm yerel veri (personeller, nöbet '
          'listeleri, ayarlar, kullanıcılar, bordrolar) Firestore\'a '
          'yazılacak. Buluttaki aynı kayıtların ÜZERİNE YAZILIR. '
          'Devam edilsin mi?',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Buluta yükle')),
        ],
      ),
    );
    if (onay != true || !context.mounted) return;

    try {
      final tercihler = await SharedPreferences.getInstance();
      final yerel = YerelServis(tercihler);
      final json = await yerel.tumVeriyiDisaAktar();

      final harita = jsonDecode(json) as Map<String, dynamic>;
      final kayitSayisi = (harita['veri'] as Map).length;
      if (kayitSayisi == 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Bu cihazda taşınacak yerel veri yok.')),
          );
        }
        return;
      }

      await (d.servis as YedeklenebilirServis).yedektenYukle(json);
      await d.baslat();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('$kayitSayisi kayıt buluta yüklendi.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Taşıma başarısız: $e')),
        );
      }
    }
  }
}

// =============================================================================
// RAPORLAR — yıllık dağılım
// =============================================================================
class RaporlarEkrani extends StatefulWidget {
  const RaporlarEkrani({super.key, required this.genis, this.baslangicSekme = 0});
  final bool genis;
  final int baslangicSekme;

  @override
  State<RaporlarEkrani> createState() => _RaporlarEkraniState();
}

class _RaporlarEkraniState extends State<RaporlarEkrani> {
  late int _yil;
  late int _sekme; // 0: aylık saat dağılımı, 1: yıllık fazla mesai
  Future<Map<String, List<double>>>? _gelecek;
  Future<Map<String, double>>? _fazlaMesaiGelecek;

  @override
  void initState() {
    super.initState();
    _yil = context.read<NobetDurumu>().yil;
    _sekme = widget.baslangicSekme;
    _yukle();
  }

  void _yukle() {
    final d = context.read<NobetDurumu>();
    _gelecek = _hesapla(d, _yil);
    _fazlaMesaiGelecek = _fazlaMesaiHesapla(d, _yil);
  }

  /// Madde 12O: Ocak'tan bulunulan aya kadar (bugün dahil, gelecek aylar
  /// hariç) her personelin toplam fazla mesai gün sayısı.
  Future<Map<String, double>> _fazlaMesaiHesapla(
      NobetDurumu d, int yil) async {
    final simdi = DateTime.now();
    final sonAy = yil == simdi.year ? simdi.month : (yil < simdi.year ? 12 : 0);
    final sonuc = <String, double>{for (final p in d.personeller) p.id: 0.0};
    if (sonAy == 0) return sonuc;

    AyKaydi? oncekiAyKayit;
    for (var ay = 1; ay <= sonAy; ay++) {
      final kayit = await d.servis
          .ayKaydiGetir(d.birimId, yil, ay, versiyon: kVersiyonOnayli);
      for (final p in d.personeller) {
        sonuc[p.id] = (sonuc[p.id] ?? 0) +
            mh.aylikFazlaMesaiGunu(
              ayar: d.ayar,
              kayit: kayit,
              oncekiAyKayit: oncekiAyKayit,
              personelId: p.id,
              yil: yil,
              ay: ay,
            );
      }
      oncekiAyKayit = kayit;
    }
    return sonuc;
  }

  Future<Map<String, List<double>>> _hesapla(NobetDurumu d, int yil) async {
    final sonuc = <String, List<double>>{
      for (final p in d.personeller) p.id: List.filled(12, 0),
    };
    final simdi = DateTime.now();
    final sonAy = yil == simdi.year ? simdi.month : (yil < simdi.year ? 12 : 0);
    for (var ay = 1; ay <= sonAy; ay++) {
      final kayit = await d.servis
          .ayKaydiGetir(d.birimId, yil, ay, versiyon: kVersiyonOnayli);
      final gun = DateTime(yil, ay + 1, 0).day;
      for (final p in d.personeller) {
        var saat = 0.0;
        for (var g = 1; g <= gun; g++) {
          saat += d.ayar.vardiyaBul(kayit.kod(g, p.id)).saat;
        }
        sonuc[p.id]![ay - 1] = saat;
      }
    }
    return sonuc;
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<NobetDurumu>();
    return SingleChildScrollView(
      padding: widget.genis
          ? const EdgeInsets.fromLTRB(20, 6, 20, 20)
          : const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Aylık Saat Dağılımı'),
                      selected: _sekme == 0,
                      onSelected: (_) => setState(() => _sekme = 0),
                    ),
                    ChoiceChip(
                      label: const Text('Yıllık Fazla Mesai'),
                      selected: _sekme == 1,
                      onSelected: (_) => setState(() => _sekme = 1),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _yil--;
                  _yukle();
                }),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_yil',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: () => setState(() {
                  _yil++;
                  _yukle();
                }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_sekme == 1) _fazlaMesaiRaporu(d) else _saatDagilimRaporu(d),
        ],
      ),
    );
  }

  Widget _saatDagilimRaporu(NobetDurumu d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          const Text('Yıllık Çalışma Saati Dağılımı',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, List<double>>>(
            future: _gelecek,
            builder: (ctx, anlik) {
              if (anlik.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final veri = anlik.data ?? {};
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
                    headingRowColor:
                        WidgetStatePropertyAll(Tema.tabloBaslik(context)),
                    columnSpacing: 12,
                    headingRowHeight: 36,
                    dataRowMinHeight: 32,
                    dataRowMaxHeight: 36,
                    columns: [
                      const DataColumn(label: Text('Personel')),
                      for (final a in T.aylarKisa)
                        DataColumn(label: Text(a), numeric: true),
                      const DataColumn(label: Text('Toplam'), numeric: true),
                    ],
                    rows: [
                      for (final p in d.personeller)
                        DataRow(cells: [
                          DataCell(Text(p.ad,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                          for (var i = 0; i < 12; i++)
                            DataCell(Text(
                              (veri[p.id]?[i] ?? 0) == 0
                                  ? '–'
                                  : (veri[p.id]![i]).toStringAsFixed(0),
                            )),
                          DataCell(Text(
                            (veri[p.id] ?? const <double>[])
                                .fold(0.0, (t, s) => t + s)
                                .toStringAsFixed(0),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          )),
                        ]),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  /// Madde 12O: yıl başından bulunulan aya kadar kişi bazlı toplam
  /// fazla mesai gün sayısı, yatay çubukla.
  Widget _fazlaMesaiRaporu(NobetDurumu d) {
    final simdi = DateTime.now();
    final sonAy = _yil == simdi.year ? simdi.month : (_yil < simdi.year ? 12 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sonAy == 0
              ? '$_yil yılı için henüz veri yok (gelecek yıl).'
              : '$_yil — Ocak\'tan ${T.aylar[sonAy - 1]} ayı sonuna kadar '
                  'toplam fazla mesai günü',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 4),
        const Text(
          'Bulunulan aya kadar (bugün dahil) veriler kullanılır. Her ay '
          'için fazla mesai, aylık özet tablosuyla aynı mantıkla hesaplanır.',
          style: TextStyle(fontSize: 11.5, color: R.gri, height: 1.4),
        ),
        const SizedBox(height: 14),
        FutureBuilder<Map<String, double>>(
          future: _fazlaMesaiGelecek,
          builder: (ctx, anlik) {
            if (anlik.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final veri = anlik.data ?? {};
            final maks = veri.values.isEmpty
                ? 1.0
                : (veri.values.reduce((a, b) => a > b ? a : b)).clamp(1, 1e9);

            if (d.personeller.isEmpty) {
              return const Text('Kayıtlı personel yok.',
                  style: TextStyle(color: R.gri));
            }

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Tema.kart(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Tema.kenar(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in d.personeller)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(p.ad,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: (veri[p.id] ?? 0) / maks,
                                minHeight: 10,
                                backgroundColor:
                                    Tema.tabloBaslik(context),
                                color: (veri[p.id] ?? 0) > 0
                                    ? R.turuncu
                                    : R.gri,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: ((veri[p.id] ?? 0) > 0
                                      ? R.turuncu
                                      : R.gri)
                                  .withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${(veri[p.id] ?? 0).toStringAsFixed(0)} gün',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: (veri[p.id] ?? 0) > 0
                                    ? R.turuncu
                                    : R.gri,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
