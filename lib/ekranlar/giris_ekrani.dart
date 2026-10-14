import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/kimlik.dart';
import '../core/tema.dart';
import '../modeller/modeller.dart';
import '../servisler/veri_servisi.dart';
import 'uye_ol_ekrani.dart';

/// Uygulama açılışında ve "Çıkış Yap" sonrasında gösterilen giriş ekranı.
///
/// Akış:
///  * Henüz kimlik/şifresi olan bir yönetici yoksa → "Yönetici hesabı oluştur"
///    (ilk kurulum). Oluşturulan yönetici hemen giriş yapar.
///  * Aksi hâlde → T.C. Kimlik No + şifre ile giriş. Personel "Üye ol" ile
///    kaydolur, yönetici onaylayınca giriş yapabilir.
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({
    super.key,
    required this.servis,
    required this.kurumId,
    required this.girisYapildi,
    this.baslangicKimlik = '',
    this.baslangicHatirla = true,
  });

  final VeriServisi servis;
  final String kurumId;

  /// İkinci parametre "Beni hatırla" seçili mi — kaydetme işini
  /// `main.dart` üstlenir.
  final void Function(Kullanici kullanici, bool hatirla) girisYapildi;

  /// Daha önce hatırlanan T.C. Kimlik No (alan hazır dolu gelir).
  final String baslangicKimlik;

  /// "Beni hatırla" kutusunun açılıştaki durumu.
  final bool baslangicHatirla;

  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  List<Kullanici>? _kullanicilar;
  String? _yuklemeHatasi;
  bool _mesgul = false;

  // Giriş alanları
  final _tc = TextEditingController();
  final _sifre = TextEditingController();
  bool _sifreGizli = true;
  late bool _beniHatirla;

  // İlk kurulum (yönetici) alanları
  final _yAd = TextEditingController();
  final _yTc = TextEditingController();
  final _ySifre = TextEditingController();
  final _ySifre2 = TextEditingController();
  bool _ySifreGizli = true;

  @override
  void initState() {
    super.initState();
    _beniHatirla = widget.baslangicHatirla;
    _tc.text = widget.baslangicKimlik;
    _yukle();
  }

  @override
  void dispose() {
    _tc.dispose();
    _sifre.dispose();
    _yAd.dispose();
    _yTc.dispose();
    _ySifre.dispose();
    _ySifre2.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() {
      _kullanicilar = null;
      _yuklemeHatasi = null;
    });
    try {
      final liste = await widget.servis.kullanicilariGetir(widget.kurumId);
      if (mounted) setState(() => _kullanicilar = liste);
    } catch (e) {
      if (mounted) setState(() => _yuklemeHatasi = '$e');
    }
  }

  /// Kimlik + şifresi tanımlı, onaylı bir yönetici var mı?
  bool get _yoneticiVar => (_kullanicilar ?? const []).any((k) =>
      k.rol == Rol.yonetici &&
      k.kimlik.isNotEmpty &&
      k.sifreHash.isNotEmpty &&
      k.onayli);

  void _hata(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mesaj), backgroundColor: R.kirmizi),
    );
  }

  // ── GİRİŞ ────────────────────────────────────────────────────────────
  Future<void> _girisDene() async {
    final girilen = _tc.text.trim();
    final sifre = _sifre.text;
    if (girilen.isEmpty) {
      _hata('T.C. Kimlik No veya kullanıcı adınızı girin.');
      return;
    }
    if (sifre.isEmpty) {
      _hata('Şifrenizi girin.');
      return;
    }

    final girilenKucuk = girilen.toLowerCase();
    final eslesenler = (_kullanicilar ?? const [])
        .where((k) =>
            k.kimlik == girilen ||
            (k.kullaniciAdi.isNotEmpty &&
                k.kullaniciAdi.toLowerCase() == girilenKucuk))
        .toList();
    if (eslesenler.isEmpty) {
      _hata('Bu T.C. Kimlik No veya kullanıcı adıyla kayıt bulunamadı.');
      return;
    }
    final k = eslesenler.first;
    if (!Kimlik.sifreDogru(sifre, k.sifreHash)) {
      _hata('Şifre hatalı.');
      return;
    }
    if (!k.onayli) {
      _hata('Hesabınız henüz yönetici onayı bekliyor.');
      return;
    }
    if (!k.aktif) {
      _hata('Hesabınız pasif durumda. Yöneticinize başvurun.');
      return;
    }
    widget.girisYapildi(k, _beniHatirla);
  }

  // ── İLK KURULUM: YÖNETİCİ OLUŞTUR ────────────────────────────────────
  Future<void> _yoneticiOlustur() async {
    final ad = _yAd.text.trim();
    final tc = _yTc.text.trim();
    final s1 = _ySifre.text;
    final s2 = _ySifre2.text;

    if (ad.length < 3) {
      _hata('Ad soyad girin.');
      return;
    }
    if (!Kimlik.tcGecerli(tc)) {
      _hata('Geçerli bir 11 haneli T.C. Kimlik No girin.');
      return;
    }
    if (s1.length < 6) {
      _hata('Şifre en az 6 karakter olmalı.');
      return;
    }
    if (s1 != s2) {
      _hata('Şifreler eşleşmiyor.');
      return;
    }

    setState(() => _mesgul = true);
    try {
      // Servisler ilk açılışta kimliksiz varsayılan bir "Yönetici" oluşturur;
      // varsa onu yükselt (mükerrer kayıt olmasın), yoksa yeni admin yarat.
      final bosYonetici = (_kullanicilar ?? const []).where((k) =>
          k.rol == Rol.yonetici && k.kimlik.isEmpty).toList();
      final yonetici = bosYonetici.isNotEmpty
          ? bosYonetici.first.kopyala(
              ad: ad,
              kimlik: tc,
              sifreHash: Kimlik.sifreOzeti(s1),
              onayli: true,
            )
          : Kullanici.yonetici(
              uid: 'k${DateTime.now().microsecondsSinceEpoch}',
              ad: ad,
              kurumId: widget.kurumId,
              profil: YoneticiProfili.superAdmin,
              kimlik: tc,
              sifreHash: Kimlik.sifreOzeti(s1),
              onayli: true,
            );
      await widget.servis.kullaniciKaydet(widget.kurumId, yonetici);
      widget.girisYapildi(yonetici, _beniHatirla);
    } catch (e) {
      if (mounted) {
        setState(() => _mesgul = false);
        _hata('Yönetici oluşturulamadı: $e');
      }
    }
  }

  // ── ÜYE OL ───────────────────────────────────────────────────────────
  Future<void> _uyeOlAc() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UyeOlEkrani(
        servis: widget.servis,
        kurumId: widget.kurumId,
        mevcutKullanicilar: _kullanicilar ?? const [],
      ),
    ));
    // Dönüşte listeyi tazele (yeni kayıt eklenmiş olabilir).
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [R.yan, R.maviKoyu],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _kart(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kart() {
    Widget icerik;
    if (_yuklemeHatasi != null) {
      icerik = _hataIcerigi();
    } else if (_kullanicilar == null) {
      icerik = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!_yoneticiVar) {
      icerik = _ilkKurulumIcerigi();
    } else {
      icerik = _girisIcerigi();
    }

    return Card(
      elevation: 12,
      color: Tema.kart(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _baslik(),
              const SizedBox(height: 22),
              icerik,
            ],
          ),
        ),
      ),
    );
  }

  Widget _baslik() {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: R.maviKoyu.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: Image.asset('assets/amblem.jpg', fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.shield_outlined, color: R.maviKoyu, size: 36)),
        ),
        const SizedBox(height: 14),
        const Text(
          'AYDIN YENİPAZAR İLÇE DEVLET HASTANESİ',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: .2),
        ),
        const SizedBox(height: 2),
        const Text('Nöbet Yönetim Sistemi',
            style: TextStyle(fontSize: 12, color: R.gri)),
      ],
    );
  }

  // ── GİRİŞ İÇERİĞİ ────────────────────────────────────────────────────
  Widget _girisIcerigi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _alan(
          controller: _tc,
          etiket: 'T.C. Kimlik No veya Kullanıcı Adı',
          ikon: Icons.badge_outlined,
          kimlikVeyaAd: true,
        ),
        const SizedBox(height: 14),
        _alan(
          controller: _sifre,
          etiket: 'Şifre',
          ikon: Icons.lock_outline,
          gizli: _sifreGizli,
          gizliDegistir: () => setState(() => _sifreGizli = !_sifreGizli),
          onSubmit: _girisDene,
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _beniHatirla = !_beniHatirla),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _beniHatirla,
                    activeColor: R.mavi,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                    onChanged: (v) =>
                        setState(() => _beniHatirla = v ?? false),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Beni hatırla',
                      style: TextStyle(fontSize: 13.5)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _beniHatirla
              ? 'Bu cihazda bir daha giriş bilgisi sorulmaz. '
                  'Çıkış yaparsanız yeniden sorulur.'
              : 'Her açılışta T.C. Kimlik No ve şifre istenir.',
          style: const TextStyle(fontSize: 11, color: R.gri, height: 1.35),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _mesgul ? null : _girisDene,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
            backgroundColor: R.mavi,
          ),
          child: const Text('GİRİŞ YAP',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .5)),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _uyeOlAc,
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('Hesabınız yok mu? Üye olun'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            foregroundColor: R.mavi,
            side: const BorderSide(color: R.mavi),
          ),
        ),
      ],
    );
  }

  // ── İLK KURULUM İÇERİĞİ ──────────────────────────────────────────────
  Widget _ilkKurulumIcerigi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: R.turuncu.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: R.turuncu.withValues(alpha: 0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined,
                  color: R.turuncu, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'İlk kurulum: Yönetici hesabı oluşturun. Bu hesapla giriş '
                  'yapıp personel kayıtlarını onaylayabilirsiniz.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _alan(
            controller: _yAd, etiket: 'Ad Soyad', ikon: Icons.person_outline),
        const SizedBox(height: 14),
        _alan(
            controller: _yTc,
            etiket: 'T.C. Kimlik No',
            ikon: Icons.badge_outlined,
            tcMi: true),
        const SizedBox(height: 14),
        _alan(
          controller: _ySifre,
          etiket: 'Şifre (en az 6 karakter)',
          ikon: Icons.lock_outline,
          gizli: _ySifreGizli,
          gizliDegistir: () => setState(() => _ySifreGizli = !_ySifreGizli),
        ),
        const SizedBox(height: 14),
        _alan(
          controller: _ySifre2,
          etiket: 'Şifre Tekrar',
          ikon: Icons.lock_outline,
          gizli: _ySifreGizli,
          onSubmit: _yoneticiOlustur,
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _mesgul ? null : _yoneticiOlustur,
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
              : const Text('OLUŞTUR VE GİRİŞ YAP',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, letterSpacing: .5)),
        ),
      ],
    );
  }

  Widget _hataIcerigi() {
    return Column(
      children: [
        const Icon(Icons.cloud_off, size: 36, color: R.gri),
        const SizedBox(height: 12),
        const Text(
          'Kullanıcı bilgileri yüklenemedi. Bağlantınızı kontrol edin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _yukle,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Tekrar dene'),
        ),
      ],
    );
  }

  // ── ORTAK ALAN ───────────────────────────────────────────────────────
  Widget _alan({
    required TextEditingController controller,
    required String etiket,
    required IconData ikon,
    bool tcMi = false,
    bool kimlikVeyaAd = false,
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
          : (kimlikVeyaAd ? [_KimlikVeyaAdFormatter()] : null),
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
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: R.mavi, width: 2),
        ),
      ),
    );
  }
}

/// Giriş alanı hem T.C. Kimlik No hem kullanıcı adı alır: yalnızca rakamdan
/// oluşan bir giriş (T.C. Kimlik No) 11 haneden fazla yazılamaz; harf içeren
/// kullanıcı adlarına sınır yok.
class _KimlikVeyaAdFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue eski, TextEditingValue yeni) {
    final metin = yeni.text;
    if (metin.length > 11 && RegExp(r'^\d+$').hasMatch(metin)) {
      return TextEditingValue(
        text: metin.substring(0, 11),
        selection: const TextSelection.collapsed(offset: 11),
      );
    }
    return yeni;
  }
}
