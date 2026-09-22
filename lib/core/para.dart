/// intl paketine ihtiyaç duymadan Türkçe para/sayı biçimlendirme.
/// [T] sınıfının tarih tarafındaki rolünün para karşılığıdır.
class Para {
  /// 64220.31 → '64.220,31'  ·  -1234.5 → '-1.234,50'
  static String tl(double deger, {int basamak = 2}) {
    final eksi = deger < 0;
    final metin = deger.abs().toStringAsFixed(basamak);
    final nokta = metin.indexOf('.');
    final tam = nokta == -1 ? metin : metin.substring(0, nokta);
    final kesir = nokta == -1 ? '' : metin.substring(nokta + 1);

    final tampon = StringBuffer();
    for (var i = 0; i < tam.length; i++) {
      if (i > 0 && (tam.length - i) % 3 == 0) tampon.write('.');
      tampon.write(tam[i]);
    }

    final govde = kesir.isEmpty ? tampon.toString() : '$tampon,$kesir';
    return eksi ? '-$govde' : govde;
  }

  /// Sonuna ' ₺' ekler: 64220.31 → '64.220,31 ₺'
  static String tlSimge(double deger, {int basamak = 2}) =>
      '${tl(deger, basamak: basamak)} ₺';

  /// Kullanıcının yazdığı metni sayıya çevirir.
  ///
  /// Hem '1.234,56' (Türkçe) hem '1234.56' (klavye) kabul edilir:
  /// ikisi birden varsa nokta binlik, virgül ondalık sayılır; yalnız
  /// biri varsa ondalık ayraç kabul edilir. Çözülemezse null döner.
  static double? coz(String metin) {
    var t = metin.trim().replaceAll('₺', '').replaceAll(' ', '');
    if (t.isEmpty) return null;

    final noktaVar = t.contains('.');
    final virgulVar = t.contains(',');

    if (noktaVar && virgulVar) {
      // Her ikisi var: nokta binlik ayraç, virgül ondalık
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (virgulVar) {
      // Yalnız virgül: ondalık ayraç
      t = t.replaceAll(',', '.');
    } else if (noktaVar) {
      // Yalnız nokta: son noktadan sonra tam 3 basamak varsa binlik ayraç
      // ("83.774" → 83774), değilse ondalık ("1.5" → 1.5).
      final sonNokta = t.lastIndexOf('.');
      if (t.substring(sonNokta + 1).length == 3) {
        t = t.replaceAll('.', '');
      }
    }
    return double.tryParse(t);
  }

  /// Çözülemeyen metinlerde [varsayilan] döner — form alanları için.
  static double cozVeya(String metin, [double varsayilan = 0]) =>
      coz(metin) ?? varsayilan;

  /// 0.16 → '%16'  ·  0.00759 → '%0,759'
  static String yuzde(double oran, {int basamak = 2}) {
    final metin = tl(oran * 100, basamak: basamak);
    // Gereksiz sondaki sıfırları at: '16,00' → '16'
    if (!metin.contains(',')) return '%$metin';
    final temiz =
        metin.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r',$'), '');
    return '%$temiz';
  }

  /// Ondalık kısmı gereksizse gizler: 31.0 → '31' · 7.5 → '7,5'
  static String sade(double deger) {
    if (deger == deger.roundToDouble()) return tl(deger, basamak: 0);
    return tl(deger, basamak: 1);
  }
}
