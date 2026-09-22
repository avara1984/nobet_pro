import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/kimlik.dart';
import '../core/tema.dart';
import '../modeller/modeller.dart';
import '../servisler/veri_servisi.dart';

/// Personel kendi hesabını oluşturur. Kayıt onaysız (`onayli = false`) başlar;
/// yönetici Kullanıcılar ekranından onaylayınca giriş yapabilir.
class UyeOlEkrani extends StatefulWidget {
  const UyeOlEkrani({
    super.key,
    required this.servis,
    required this.kurumId,
    required this.mevcutKullanicilar,
  });

  final VeriServisi servis;
  final String kurumId;
  final List<Kullanici> mevcutKullanicilar;

  @override
  State<UyeOlEkrani> createState() => _UyeOlEkraniState();
}

class _UyeOlEkraniState extends State<UyeOlEkrani> {
  final _ad = TextEditingController();
  final _tc = TextEditingController();
  final _sifre = TextEditingController();
  final _sifre2 = TextEditingController();
  bool _gizli = true;
  bool _mesgul = false;

  @override
  void dispose() {
    _ad.dispose();
    _tc.dispose();
    _sifre.dispose();
    _sifre2.dispose();
    super.dispose();
  }

  void _hata(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mesaj), backgroundColor: R.kirmizi),
    );
  }

  Future<void> _kaydol() async {
    final ad = _ad.text.trim();
    final tc = _tc.text.trim();
    final s1 = _sifre.text;
    final s2 = _sifre2.text;

    if (ad.length < 3) return _hata('Ad soyad girin.');
    if (!Kimlik.tcGecerli(tc)) {
      return _hata('Geçerli bir 11 haneli T.C. Kimlik No girin.');
    }
    if (widget.mevcutKullanicilar.any((k) => k.kimlik == tc)) {
      return _hata('Bu T.C. Kimlik No zaten kayıtlı.');
    }
    if (s1.length < 6) return _hata('Şifre en az 6 karakter olmalı.');
    if (s1 != s2) return _hata('Şifreler eşleşmiyor.');

    setState(() => _mesgul = true);
    try {
      final yeni = Kullanici(
        uid: 'k${DateTime.now().microsecondsSinceEpoch}',
        ad: ad,
        eposta: '',
        rol: Rol.izleyici,
        kurumId: widget.kurumId,
        kimlik: tc,
        sifreHash: Kimlik.sifreOzeti(s1),
        onayli: false,
      );
      await widget.servis.kullaniciKaydet(widget.kurumId, yeni);
      if (!mounted) return;
      await _basariGoster();
    } catch (e) {
      if (mounted) {
        setState(() => _mesgul = false);
        _hata('Kayıt yapılamadı: $e');
      }
    }
  }

  Future<void> _basariGoster() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: R.yesil.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: R.yesil, size: 46),
            ),
            const SizedBox(height: 16),
            const Text('Kayıt Başarılı',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Başvurunuz yöneticiye iletildi.\nOnay sonrası giriş yapabilirsiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: R.gri, height: 1.4),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: R.yan,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 12,
              color: Tema.kart(context),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          color: R.mavi,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 4),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Üye Ol',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold)),
                            Text('Hesap oluşturun',
                                style: TextStyle(fontSize: 12, color: R.gri)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _alan(_ad, 'Ad Soyad', Icons.person_outline),
                    const SizedBox(height: 14),
                    _alan(_tc, 'T.C. Kimlik No', Icons.badge_outlined,
                        tcMi: true),
                    const SizedBox(height: 14),
                    _alan(_sifre, 'Şifre (en az 6 karakter)', Icons.lock_outline,
                        gizli: _gizli,
                        gizliDegistir: () => setState(() => _gizli = !_gizli)),
                    const SizedBox(height: 14),
                    _alan(_sifre2, 'Şifre Tekrar', Icons.lock_outline,
                        gizli: _gizli, onSubmit: _kaydol),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _mesgul ? null : _kaydol,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: R.mavi,
                      ),
                      child: _mesgul
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('KAYIT OL',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, letterSpacing: .5)),
                    ),
                    const SizedBox(height: 12),
                    const Text('Kayıt sonrası yönetici onayı gereklidir.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: R.gri)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _alan(
    TextEditingController controller,
    String etiket,
    IconData ikon, {
    bool tcMi = false,
    bool gizli = false,
    VoidCallback? gizliDegistir,
    VoidCallback? onSubmit,
  }) {
    return TextField(
      controller: controller,
      obscureText: gizli,
      keyboardType: tcMi ? TextInputType.number : TextInputType.text,
      inputFormatters: tcMi
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ]
          : null,
      textInputAction:
          onSubmit != null ? TextInputAction.done : TextInputAction.next,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      decoration: InputDecoration(
        labelText: etiket,
        prefixIcon: Icon(ikon, size: 20, color: R.mavi),
        suffixIcon: gizliDegistir == null
            ? null
            : IconButton(
                icon: Icon(gizli ? Icons.visibility_off : Icons.visibility,
                    size: 20),
                onPressed: gizliDegistir,
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: R.mavi, width: 2),
        ),
      ),
    );
  }
}
