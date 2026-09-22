import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Giriş kimlik doğrulama yardımcıları (yerel).
///
/// Şifreler düz metin saklanmaz; SHA-256 özeti tutulur. Bu, tam bir güvenlik
/// çözümü değildir (tuz yok) ama yerel bir kurum uygulaması için düz metinden
/// belirgin biçimde iyidir.
class Kimlik {
  const Kimlik._();

  /// Şifreyi tek yönlü özetler.
  static String sifreOzeti(String sifre) =>
      sha256.convert(utf8.encode(sifre)).toString();

  /// Girilen şifre, saklı özetle eşleşiyor mu?
  static bool sifreDogru(String girilen, String saklananOzet) =>
      saklananOzet.isNotEmpty && sifreOzeti(girilen) == saklananOzet;

  /// Basit T.C. Kimlik No biçim kontrolü: 11 hane, hepsi rakam, 0 ile başlamaz.
  /// (Tam algoritmik doğrulama değil; kullanıcı hatasını yakalamak için yeterli.)
  static bool tcGecerli(String tc) {
    final t = tc.trim();
    if (t.length != 11) return false;
    if (!RegExp(r'^\d{11}$').hasMatch(t)) return false;
    if (t[0] == '0') return false;
    return true;
  }
}
