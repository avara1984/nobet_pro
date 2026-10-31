/// intl paketine ihtiyaç duymadan Türkçe tarih biçimlendirme.
class T {
  static const aylar = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  static const aylarKisa = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];

  /// DateTime.weekday 1 = Pazartesi
  static const gunler = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe',
    'Cuma', 'Cumartesi', 'Pazar',
  ];

  static const gunlerKisa = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  static String iki(int n) => n.toString().padLeft(2, '0');

  static String tarih(DateTime d) => '${iki(d.day)}.${iki(d.month)}.${d.year}';

  static String tarihSaat(DateTime d) =>
      '${tarih(d)} ${iki(d.hour)}:${iki(d.minute)}';

  static String gunAdi(DateTime d) => gunler[d.weekday - 1];

  static String gunKisa(DateTime d) => gunlerKisa[d.weekday - 1];

  static String ayYil(int yil, int ay) => '${aylar[ay - 1]} $yil';

  /// 'yyyy-MM' → Firestore doküman kimliği
  static String donemAnahtari(int yil, int ay) => '$yil-${iki(ay)}';

  static bool haftaSonu(DateTime d) =>
      d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

  /// 495 → '08:15'
  static String dakikaSaat(int dakika) {
    final d = dakika % 1440;
    return '${iki(d ~/ 60)}:${iki(d % 60)}';
  }

  static String sureMetni(int dakika) {
    final s = dakika ~/ 60;
    final d = dakika % 60;
    return d == 0 ? '$s sa' : '$s sa $d dk';
  }
}
