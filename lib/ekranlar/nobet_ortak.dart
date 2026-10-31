import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../durum/nobet_durumu.dart';
import '../modeller/modeller.dart';
import '../servisler/giris_servisi.dart';

// Üç nöbet ekranının (Nöbet Listesi, Haftalık Nöbet, Haftalık 15-14 ve
// 15 - 14 Nöbet) ORTAK parçaları. Buraya yalnızca ekranlar arasında birebir aynı
// olan kod konur; bir ekrana özgü görünüm (ör. Nöbet Listesi'nin "bugün"
// vurgusu ve daha koyu hafta sonu zemini) kendi dosyasında kalır.

/// Tablo başlık satırının yüksekliği.
const double kNobetBaslikY = 37;

/// Hücreler arası ince çizgi rengi.
/// Tablo iç çizgileri — [Tema.kenar] bu yoğun ızgarada neredeyse
/// görünmüyordu (özellikle hafta sonu/tatil zeminiyle üst üste
/// binince). Burada belirgin, sabit kontrastlı bir çizgi rengi
/// kullanılıyor.
Color nobetCizgi(BuildContext c) {
  final koyu = Theme.of(c).brightness == Brightness.dark;
  return koyu ? Colors.white30 : const Color(0xFFB9C0CC);
}

/// "Ad Soyad" → ("Ad", "Soyad"); son kelime soyad sayılır.
(String, String) nobetAdSoyadAyir(String tamAd) {
  final t = tamAd.trim();
  final i = t.lastIndexOf(' ');
  if (i == -1) return (t, '');
  return (t.substring(0, i), t.substring(i + 1));
}

/// Haftalık / 15 - 14 tablolarının başlık hücresi.
Widget nobetBaslikHucre(BuildContext context, String metin, double w,
        {Color? kenarRengi}) =>
    Container(
      width: w,
      height: kNobetBaslikY,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Tema.nobetTabloBaslik(context),
        border:
            Border(right: BorderSide(color: kenarRengi ?? nobetCizgi(context))),
      ),
      child: Text(metin,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
    );

/// Haftalık / 15 - 14 tablolarının personel başlık hücresi (ad ve soyad iki satır).
Widget nobetPersonelBaslikHucre(BuildContext context, Personel p, double w) {
  final (ad, soyad) = nobetAdSoyadAyir(p.ad);
  const stil =
      TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.1);
  return Container(
    width: w,
    height: kNobetBaslikY,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: Tema.nobetTabloBaslik(context),
      border: Border(right: BorderSide(color: nobetCizgi(context))),
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

/// Haftalık / 15 - 14 tablolarının satır zemini. (Nöbet Listesi'nin zemini
/// farklıdır: "bugün" vurgusu vardır, hafta sonu daha koyudur.)
Color? nobetSatirZemini(BuildContext context, bool vurgu,
    {bool tatil = false, bool yarimGun = false}) {
  final koyu = Theme.of(context).brightness == Brightness.dark;
  if (tatil) {
    return koyu ? R.kirmizi.withValues(alpha: .16) : const Color(0xFFFDE7E7);
  }
  if (yarimGun) {
    return koyu ? R.turuncu.withValues(alpha: .15) : const Color(0xFFFFF2DC);
  }
  if (vurgu) {
    return koyu ? Colors.white.withValues(alpha: .06) : const Color(0xFFE9EBF0);
  }
  return null;
}

/// Nöbet ekranı durumlarının ortak davranışları: bilgi mesajı, "Onaylanan
/// Liste" kod kilidi, nöbet ihlali ve tatil uyarı diyalogları.
mixin NobetEkraniOrtak<T extends StatefulWidget> on State<T> {
  /// Alt kenarda kısa bir bilgi mesajı gösterir (öncekini kapatır).
  void bilgi(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), width: 380));

  /// "Onaylanan Liste" üzerinde düzenleme yapılmadan önce PIN sorar.
  /// Doğru girilirse kilit bu oturumluk açık kalır (madde 12B). Kod
  /// sunucuda doğrulanır; çok fazla yanlış denemede kısa süre kilitlenir.
  Future<bool> kilidiAc(NobetDurumu d) async {
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
    try {
      if (await d.onayKoduDogruMu(girilen)) {
        d.kilidiAc();
        return true;
      }
    } on GirisHatasi catch (e) {
      // Çok fazla yanlış deneme veya sunucuya ulaşılamadı.
      if (mounted) bilgi(e.mesaj);
      return false;
    }
    if (mounted) bilgi('Şifre yanlış, tekrar deneyin.');
    return false;
  }

  /// Nöbet ihlali (ör. gece nöbetinden çıkıp ertesi gün gündüze yazma) için
  /// onay diyaloğu. `true` = kullanıcı riske rağmen yazmak istedi.
  Future<bool?> ihlalOnayi(String mesaj) {
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

  /// Resmi tatil/pazar gününde Y.İ. veya İ.İ. seçildiğinde çıkan
  /// bilgilendirme. Engellemez — sadece bilgilendirir (madde 12A.3).
  Future<void> tatilYIUyarisi(String kod) {
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
}
