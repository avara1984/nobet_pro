# Üç platformu (web, Windows, Android) AYNI derleme etiketiyle derler.
# Etiket giriş ekranında ve yan menüde görünür (lib/core/surum.dart), böylece
# hangi cihazda hangi sürümün çalıştığı ayırt edilir.
#
# Kullanım:  .\tool\derle.ps1
# Sonra:     firebase deploy --only hosting   (web)
#            Inno Setup ile kurulum dosyası   (Windows; bkz. CLAUDE.md / hafıza)
param([switch]$AtlaAndroid)

# NOT: $ErrorActionPreference = 'Stop' KULLANMA — Windows PowerShell 5.1'de
# flutter'ın stderr'e yazdığı bilgi satırları (ör. "Wasm dry run succeeded")
# hata sayılıp betiği keser. Başarı yalnızca çıkış koduyla (LASTEXITCODE) anlaşılır.
$etiket = Get-Date -Format 'yyMMdd-HHmm'
Write-Host "Derleme etiketi: $etiket"

flutter build web --dart-define=DERLEME=$etiket
if ($LASTEXITCODE -ne 0) { throw 'web derlemesi başarısız' }
flutter build windows --dart-define=DERLEME=$etiket
if ($LASTEXITCODE -ne 0) { throw 'windows derlemesi başarısız' }
if (-not $AtlaAndroid) {
  flutter build apk --dart-define=DERLEME=$etiket
  if ($LASTEXITCODE -ne 0) { throw 'apk derlemesi başarısız' }
}
Write-Host "Tamam. Etiket: $etiket"
