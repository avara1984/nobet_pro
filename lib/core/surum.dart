/// Çalışan uygulamanın sürüm etiketi — hangi cihazda hangi derlemenin
/// çalıştığını ayırt etmek için giriş ekranında ve yan menüde gösterilir.
///
/// Derleme etiketi derleme sırasında verilir (`tool/derle.ps1` bunu yapar):
/// `flutter build ... --dart-define=DERLEME=261031-1850`. Verilmezse
/// ("flutter run" ile geliştirirken) "geliştirme" görünür.
const String kSurumNo = '1.0.0';

const String kDerleme =
    String.fromEnvironment('DERLEME', defaultValue: 'geliştirme');

/// Ekranda gösterilen kısa metin, ör. `v1.0.0 · derleme 261031-1850`.
const String kSurumMetni = 'v$kSurumNo · derleme $kDerleme';
