# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proje

Nöbet Pro — bir hastanenin Güvenlik ve Temizlik personeli için nöbet listesi
hazırlama/yönetim uygulaması (Flutter, Windows + Android hedefli). Veri
katmanı `VeriServisi` soyutlaması üzerinden iki implementasyonla çalışır:

- **`FirestoreServis`** (varsayılan) — veriler Firebase projesi
  `nobet-sistemi` içindeki tek `nobet_pro` koleksiyonunda tutulur, tüm
  cihazlar aynı veriyi görür. Doküman kimlikleri yerel anahtar düzeniyle
  birebir aynıdır; içerik `j` alanında JSON metnidir. Eski (Firebase'li)
  uygulama aynı projeyi kullanır ama farklı koleksiyonlarda çalıştığı için
  çakışma olmaz.
- **`YerelServis`** (otomatik yedek mod) — `main.dart` açılışta
  `Firebase.initializeApp` + `FirestoreServis.saglikKontrolu()` (10 sn
  zaman aşımıyla tek doküman okuması; kural/ağ doğrulaması) çalıştırır.
  Herhangi biri başarısız olursa uygulama sessizce tamamen yerel moda
  düşer; her şey `shared_preferences` ile cihazın diskine yazılır.
  Çevrimdışı önbellek (`persistenceEnabled`) açıktır — daha önce
  eşitlenmiş cihaz internetsiz de bulut modunda açılabilir.

İki servis de `YedeklenebilirServis`'i uygular ve **aynı yedek JSON
biçimini** üretir — yerel yedek buluta, bulut yedeği yerele geri
yüklenebilir. Yedekleme ekranında bulut modunda "Yerel veriyi buluta yükle"
taşıma butonu vardır. Ekranlar ve durum katmanı hangi implementasyonun
çalıştığını bilmez.

Kod ve UI metinleri tamamen Türkçe; sınıf/fonksiyon isimleri de Türkçedir
(`Kullanici`, `Personel`, `KurumAyari`, `ayKaydiKaydet` vb.). Yeni kod eklerken
bu isimlendirme diline uy.

Kodun çeşitli yerlerinde ("madde 2", "madde 3", "madde 6", "madde 12B" gibi)
harici bir gereksinim/yönetmelik dokümanına referanslar var — bunlar bordro ve
kapsama kurallarının kaynağı, repo içinde ayrı bir dosya olarak yok.

## Komutlar

```powershell
flutter pub get                 # bağımlılıkları kur
flutter run -d windows           # Windows'ta çalıştır
flutter run -d <device-id>       # Android cihaz/emülatörde çalıştır (flutter devices ile listele)
flutter analyze                  # statik analiz (flutter_lints kuralları, analysis_options.yaml)
flutter test                     # test paketini çalıştır
flutter build windows            # Windows release build
flutter build apk                # Android release build
```

**Testler:** `flutter create` şablonundan kalma bozuk `test/widget_test.dart`
silindi. Mevcut testler:
- `test/bordro_dogrulama_test.dart` — bordro hesabı (vergi dilimleri,
  Md.22/23/33/36/40 kalemleri, geçiş ayı farkları), nöbet listesinden girdi
  çıkarımı, `BellekServis` bordro CRUD'u ve JSON gidiş-dönüşü.
- `test/yonetici_profili_test.dart` — üç yönetici profilinin yetki matrisi,
  profil/bayrak tutarlılığı ve geriye dönük uyumluluk.
- `test/firestore_servis_test.dart` — `FirestoreServis` CRUD'u, önek
  taramaları ve yedek gidiş-dönüşü (`fake_cloud_firestore` ile, ağsız).

Ayrıca `kapsama_madde3_test`, `liste_doldur_test`, `hafta_araligi_test`,
`donem_haftalik_test`, `giris_servisi_test` (sunucu çağrıları `MockClient` ile)
gibi testler de `test/` altındadır; sunucu tarafı için `functions/test/`.

PDF çıktısında Türkçe karakterlerin doğru görünmesi için `assets/fonts/`
altında `Roboto-Regular.ttf` ve `Roboto-Bold.ttf` bulunmalı (yoksa
`PdfServis` sessizce Helvetica'ya düşer, bkz. `lib/servisler/pdf_servis.dart`).

## Mimari

Katmanlı yapı, durum yönetimi `provider` (ChangeNotifier) ile yapılıyor.

```
lib/core/            saf iş mantığı, UI'dan bağımsız
lib/modeller/         veri modelleri (modeller.dart + bordro_modelleri.dart)
lib/servisler/        veri katmanı + PDF üretimi
lib/durum/            ChangeNotifier'lar (uygulama durumu)
lib/ekranlar/         UI ekranları
```

Uygulama iki alt sistemden oluşur: **nöbet** (liste hazırlama/denetim) ve
**bordro** (maaş hesabı). Bordro, nöbet listesini *okur* — gece saati, fazla
mesai günü ve yol günü oradan çıkarılır — ama nöbet tarafı bordroyu hiç
tanımaz. Bu tek yönlü bağımlılığı koru.

### Veri katmanı (`servisler/`)

- `veri_servisi.dart` — `VeriServisi` abstract arayüzü (kurum ayarı, personel,
  ay kaydı, versiyon, duyuru, kullanıcı, bordro CRUD'ları) +
  `YedeklenebilirServis` (yedek dışa/içe aktarma sözleşmesi) + `BellekServis`
  (yalnızca bellekte tutan, kalıcı olmayan test implementasyonu).
- `yerel_servis.dart` — `YerelServis`: her şeyi `SharedPreferences` içine
  `jsonEncode` ile string olarak yazar. Anahtar isimlendirmesi önemli:
  `kurum_<id>`, `personeller_<id>`, `nobet_<id>_<yyyy-MM>[__<versiyon>]`,
  `kullanicilar_<id>` vb. — birim ayrımı (Güvenlik/Temizlik) ayrı bir alan
  değil, `kurumId` string'ine `#guvenlik` / `#temizlik` eklenerek yapılıyor
  (`NobetDurumu._birimId`). Yedekleme/geri yükleme (`tumVeriyiDisaAktar` /
  `yedektenYukle`) bu anahtar prefix'lerini tarayarak çalışır.
- **Windows'ta `runTransaction` KULLANMA:** cloud_firestore eklentisinin
  `runTransaction` çağrısı (yalnızca okusa bile) Windows masaüstünde uygulamayı
  yerel katmanda sonlandırır (`__fastfail`, olay günlüğünde `0xc0000409`).
  Düz get/set/batch/sorgu sorunsuzdur. `FirestoreServis._listeGuncelle`
  Windows'ta sade oku-değiştir-yaz'a düşer (`_islemDestekli`); yeni bir yerde
  transaction gerekirse aynı korumayı uygula. Web/Android'de transaction
  geçerlidir. Test: `test/firestore_servis_test.dart` "Windows: transaction…".
- `firestore_servis.dart` — `FirestoreServis`: aynı anahtar düzenini
  Firestore'daki `nobet_pro` koleksiyonuna uygular (doküman kimliği =
  yerel anahtar, içerik `j` alanında JSON metni). Prefix taramaları
  `FieldPath.documentId` aralık sorgusuyla yapılır. Yeni bir anahtar öneki
  eklersen hem `YerelServis.tumVeriyiDisaAktar` hem
  `FirestoreServis.tumVeriyiDisaAktar` listelerine eklemeyi unutma.
- `firestore.rules` (repo kökü) — Firestore güvenlik kuralları;
  `firebase deploy --only firestore:rules` ile yayınlanır. Aynı projeyi
  eski uygulama da kullandığı için genel (`/{kol}/{belge=**}`) kuralda
  `nobet_pro`, `ny_kullanicilar` ve `fcm_tokens` **açıkça hariç tutulur** —
  Firestore kuralları birbirini tamamladığından hariç tutulmazlarsa genel
  "okuma açık" kuralı bu koleksiyonları da giriş yapmadan okunur kılar.
  Konsoldan değişiklik yaparsan dosyayı da güncelle.
- `giris_servisi.dart` — `GirisServisi`: giriş, kayıt, ilk kurulum, şifre
  atama, "beni hatırla" açılışı. Ekranlar kullanıcı listesini **doğrudan
  okumaz**, bu servisi kullanır (`Provider<GirisServisi>` ile de erişilir).
  `BulutGirisServisi` şifreyi Cloud Functions'ta (`npGiris` vb.) doğrulatır,
  dönen özel token ile `FirebaseAuth.signInWithCustomToken` yapar;
  `YerelGirisServisi` yedek yerel modda eski cihaz-içi mantığı korur.
  Çağrılar düz JSON `http` ile yapılır (`cloud_functions` paketi Windows'u
  desteklemiyor). Kayıt/şifre işlemleri sunucudaki `kilitli` bayrağına göre
  iki yoldan gider (aşağıya bak).
- `firebase_options.dart` — FlutterFire CLI çıktısı (eski uygulamayla aynı
  `nobet-sistemi` projesi). Elle düzenlenmez.
- `pdf_servis.dart` — yatay A4 nöbet listesi PDF'i + yazdırma (`printing` paketi).

### Durum (`durum/nobet_durumu.dart`)

- `OturumDurumu` — sadece giriş yapan `Kullanici`'yi tutar (`main.dart` içinde
  `ChangeNotifierProvider.value` ile en üstte yaşar).
- `NobetDurumu` — asıl uygulama durumu; kullanıcı giriş yaptıktan sonra
  `ValueKey(uid)` ile yeniden oluşturulur. Aktif yıl/ay/birim/versiyon,
  `AyKaydi.atamalar` (gün_personelId → vardiya kodu haritası), geri alma
  yığını (`_gecmis`, sınır 40), kirli/kaydedildi durumu, `KapsamaMotoru` ve
  `Madde3Motoru` örneklerini (lazy, `_motoruTazele()` ile temizlenir) barındırır.
  Rol bazlı yetki kontrolleri burada merkezi: `duzenleyebilir`, `yonetebilir`,
  `bordroYetkisi`, `kilitli` (yayın kilidi + onay kilidi), `personelGorunumu`.

- **Personel listesi aya göre süzülür:** `Personel.gorevBaslangic` /
  `gorevBitis` (isteğe bağlı) doluysa kişi yalnızca görevde olduğu aylarda
  görünür (`Personel.ayAktifMi`). `NobetDurumu.personeller` **seçili ayın**
  listesidir (nöbet tabloları, özet, kapsama, PDF); `tumPersoneller` aya
  bakmaksızın tüm aktif personeldir — **Personeller, Raporlar ve Bordro
  ekranları bunu kullanır** (ücret tanımı ve yıllık raporlar aydan bağımsız).
  Yeni bir ekran eklerken hangisinin gerektiğini seç; tarihleri boş
  personel her ikisinde de görünür (eski kayıtlar etkilenmez).

### Yönetici profilleri (`YoneticiProfili`)

Eski uygulamanın "Admin Yönetimi" ekranındaki üç admin rolünün karşılığı.
Profil, `Kullanici` üzerindeki `rol` / `sadecePdf` / `kisitliBirim` alanlarını
**türetir** — bu üç alan profille birlikte elle ayarlanmaz, aksi hâlde
"yönetici ama sadece PDF" gibi çelişkili birleşimler oluşur.

| Profil | rol | sadecePdf | kisitliBirim | Bordro | Yönetim ekranları |
|---|---|---|---|---|---|
| Süper Admin | yonetici | – | – | ✓ | ✓ |
| Temizlik Nöbet Admini | editor | – | Temizlik | ✗ | ✗ |
| Bordro Admini | editor | ✓ | – | ✓ | ✗ |

- **Bordro Admini nöbet tarafında salt okunurdur ama bordroda tam yetkilidir**
  — bu yüzden bordro erişimi `yonetebilir` ile değil, ayrı `bordroYetkisi`
  bayrağıyla kontrol edilir. Bordro ekranlarında `yonetebilir` kullanma.
- `yoneticiProfili` null olan kayıtlar (eski kullanıcılar) eski davranışını
  korur: `bordroYetkisi` o zaman `!sadecePdf && rol.yonetebilir`'e düşer.
- `Kullanici.haritadan` içinde profil, diskteki çelişen bayrakları **ezer**;
  tek doğruluk kaynağı profildir.
- Profil atama `AdminYonetimiEkrani`'nda yapılır; `KullanicilarEkrani` profilli
  kullanıcılarda rol/birim/PDF alanlarını gizler.

### İş mantığı (`core/`)

- `kapsama_motoru.dart` — iki ayrı denetim motoru, ikisi de atamaları dakika
  bazlı zaman çizelgesine (`(gün-1)*1440 + dakika`) açıp süpürme çizgisi
  (sweep-line) algoritmasıyla segmentlere ayırıyor:
  - `KapsamaMotoru` — genel, kullanıcı tanımlı `KapsamaKurali` listesine göre
    min-personel kontrolü (Ayarlar ekranından yapılandırılabilir).
  - `Madde3Motoru` — eski uygulamadaki sabit 24 saatlik kapsama kontrolünün
    birebir portu (öncelik sıralı: boş gün → saat açığı → kadro eksik → tamam).
    Birime göre farklı kural uygular (Temizlik hep 1 kişi yeterli; Güvenlik'te
    hafta içi dahiliyesiz günlerde gündüz 2 kişi gerekir).
- `mesai_hesap.dart` — `gunSonucu()` tek bir günün bordro değerlerini
  (toplam/gece/normal saat, fazla mesai günü, yıllık izin) hesaplayan tek
  fonksiyon; hem `NobetDurumu.saatBilgisi` hem yıllık raporlar aynı fonksiyonu
  kullanır — mantığı iki yerde tekrarlama. Ayın son günündeki gece vardiyasının
  fazla mesaisi kasıtlı olarak 0 döner, bir sonraki ayın hesabına
  `oncekiAydanSarkanFazlaMesai()` ile devredilir (çift sayılmasın diye).
- `tarih.dart` — `intl` paketi kullanmadan Türkçe tarih/gün/ay biçimlendirme (`T` sınıfı).

### Modeller (`modeller/modeller.dart`)

Tek dosyada toplanmış: `Kullanici`, `Personel`, `VardiyaTanimi`, `KapsamaKurali`,
`KurumAyari`, `AyKaydi`, `PersonelOzeti`, `Duyuru`. Hepsinde `haritadan()`
factory + `haritasi` getter (JSON round-trip) var; yeni bir alan eklerken
ikisini de güncellemek gerekir.

Önemli kavramlar:
- **Vardiya kodları** sabit string'lerdir (`kGunduz12`, `kGece12`, `kMesai`,
  `kYillikIzin` vb.) ve depoda birebir bu metinlerle saklanır — yeniden
  adlandırma mevcut kayıtları bozar.
- **Liste versiyonları** (`kListeVersiyonlari`): boş string = asıl "Nöbet
  Listesi", ayrıca "Aylık Normal Şablon", "Onaylanan Liste" (PIN korumalı),
  "Taslak". Rol bazlı görünürlük `rolVersiyonlari()`'de tanımlı.
- **Yayın kilidi** (`AyKaydi.yayinda`) ve **onay kilidi** (`Onaylanan Liste`
  versiyonu) birbirinden bağımsız iki kilit mekanizması; ikisi de
  `NobetDurumu.kilitli` üzerinden birleşik kontrol edilir.

### Ekranlar (`ekranlar/`)

`ana_ekran.dart` kabuk (yan menü + üst başlık + dashboard); `nobet_listesi_ekrani.dart`
asıl nöbet tablosu; `haftalik_nobet_ekrani.dart` hem Haftalık Nöbet hem (`donem: true` ile)
Haftalık 15-14 ekranıdır — aralık `core/donem_haftalik.dart`'tan gelir (15'ini
içeren haftanın Pazartesi'sinden 14'ünü içeren haftanın Pazar'ına), hafta
toplamları tam haftayı, en alttaki 15-14 toplamı yalnızca dönem günlerini
sayar; `aylik_ozet_ekrani.dart` bordro özeti + kapsama denetimi
görünümü; `yonetim_ekranlari.dart` tek dosyada birden fazla ekranı barındırır
(Personeller, Duyurular, Ayarlar, Kullanıcılar, Yedekleme, Raporlar) — yeni bir
yönetim ekranı eklerken bu dosyanın mevcut bölüm düzenini (`// ====` ayraçlarıyla)
takip et. `bordro_ekranlari.dart` aynı düzeni bordro tarafı için uygular.

Yan menüdeki bölümler `Bolum` enum'u ile seçilir; "Raporlar" ve "Bordro
İşlemleri" açılır gruplardır (`_acilir` + `_altOge`). Bordro grubundaki beş
bölüm `kBordroBolumleri` kümesinde toplanır ve yalnızca yöneticiye görünür.

## Giriş güvenliği (sunucu tarafı doğrulama)

Giriş artık istemcide değil `functions/` altındaki HTTPS fonksiyonlarında
(`npDurum`, `npGiris`, `npUyeOl`, `npYoneticiOlustur`, `npBen`,
`npSifreAyarla`, `npSifreleriTasi`; bölge `europe-west1`, mantık
`functions/cekirdek.js`, testler `functions/test/`, `cd functions; npm test`).

- **Şifreler:** tuzlu `scrypt` (`functions/sifre.js`). Eski uygulamadan gelen
  tuzsuz SHA-256 özetleri doğru şifreyle girilince otomatik yükseltilir.
  Özetler `nobet_gizli/sifreler_<kurum>` içinde durur; bu koleksiyona yalnızca
  Admin SDK erişir (**`firestore.rules` genel kuralında `nobet_gizli` hariç
  tutulmak zorundadır**). 5 hatalı denemede TC başına 15 dk kilit.
- **Token:** `npGiris` özel token üretir; claim'ler `nobet, rol, bordro,
  sadecePdf, kisitliBirim, kurumId` (`etkinAlanlar` — profil kuralları
  `Kullanici.haritadan` ile aynı tutulmalı). Yetki değişince en geç bir
  sonraki açılışta (`npBen` taze token verir) yansır. Token üretimi için
  çalışma hizmet hesabına "Service Account Token Creator" rolü gerekir.
- **İki aşama (`nobet_gizli/ayar.kilitli`):**
  - `false` (geçiş): giriş sunucudan, ama kayıt/ilk kurulum/şifre atama eski
    yoldan (kullanıcı kaydına doğrudan SHA-256 yazılır) — eski sürümler de
    çalışsın diye. Kurallar (`firestore.rules`) hâlâ `auth != null`.
  - `true` (**2026-10-31'den beri canlı**): `npSifreleriTasi` çalıştırıldı.
    Kayıt/şifre yalnızca sunucudan; kullanıcı kayıtlarında şifre özeti yoktur.
    `firestore.rules` rol/bordro/birim bazlıdır, anonim oturum `nobet_pro`ya
    giremez. Eski sürümler (anonim oturumla çalışanlar) giriş yapamaz.
    Kural özeti: `kullanicilar_*` yalnızca yönetici; `bordro_*`/`ucretler_*`
    yalnızca `bordro` claim'i; `nobet_*` yazma yalnızca editör/yönetici ve
    "sadece PDF" olmayan; `kisitliBirim` doluysa diğer birimin belgeleri kapalı.
- Yerel yedek modda (`YerelGirisServisi`) bunların hiçbiri geçerli değil.
- Bilinen sınır: `kurum_` dokümanındaki Onay Kodu giriş yapmış herkesçe
  okunabilir; sunucuya taşınmadı.

## Bordro alt sistemi

Eski (Firebase tabanlı) uygulamadan uyarlandı; veri katmanı üzerinden
(`VeriServisi`) Firestore'a, yedek modda cihaza yazar.

- `modeller/bordro_modelleri.dart` — `VergiDilimi`, `BordroAyari` (yıllık
  sabitler), `PersonelUcreti`, `BordroSonucu`. Aynı `haritadan()`/`haritasi`
  kuralı geçerlidir.
- `core/bordro_hesap.dart` — saf hesap: `bordroHesapla()`, dilimli gelir
  vergisi (`dilimliVergi`, `dilimliVergiFarki`) ve nöbet listesinden girdi
  çıkarımı (`nobettenGirdi`, `yolGunuSayisi`).
- `core/para.dart` — `intl` kullanmadan Türkçe para biçimi (`Para.tl`,
  `Para.coz`); tarih tarafındaki `T` sınıfının para karşılığı.
- `servisler/bordro_pdf_servis.dart` — tek bordro (dikey A4) ve toplu döküm.

Önemli kurallar:
- **Gece saati ve fazla mesai günü burada yeniden hesaplanmaz** —
  `core/mesai_hesap.dart` içindeki `gunSonucu()` / `aylikFazlaMesaiGunu()`
  kullanılır. Bordro ile Aylık Özet aynı sayıyı göstermeli.
- `PersonelUcreti` **`Personel.id`** ile bağlanır, isimle değil. Eski
  uygulamadaki "isim birebir tutmuyor, veri eşleşmedi" sınıfı hatalar bu
  yüzden oluşamaz.
- **Yol/yemek günü** bordro dönemidir: ayın 15'i → sonraki ayın 14'ü. Bu
  yüzden hesap iki `AyKaydi` ister.
- Depolama anahtarları: `bordro_ayari_<yil>` (birimden bağımsız),
  `ucretler_<birimId>`, `bordro_<birimId>_<personelId>_<yyyy-MM>`. Üçü de
  `tumVeriyiDisaAktar()` taramasına dahildir.
- Kaydedilen `BordroSonucu` hesaplandığı hâliyle saklanır; ayarları sonradan
  değiştirmek geçmiş bordroları **değiştirmez**.

## Duyuru bildirim sistemi

`Duyuru`'ya "okundu" alanı yok — "görüldü" durumu tamamen yerelde,
`NobetDurumu.tercihler` (`SharedPreferences`) üzerinde `uid` bazlı tutulur
(`son_gorulen_duyuru_<uid>` anahtarı). Kullanıcı bazlı olmasının nedeni:
ortak kullanılan bir hastane bilgisayarında birden fazla personel giriş
yapabiliyor; salt cihaz bazlı bir işaret olsaydı biri okuyunca diğeri de
"okumuş" sayılırdı.

- `NobetDurumu.okunmamisDuyuruSayisi` — aktif birime görünen (`duyurular`
  getter'ı) duyurulardan `_sonGorulenDuyuruZamani`'ndan sonraki sayısı.
  İlk girişte (kayıtlı zaman yoksa) `DateTime.now()` ile tohumlanır —
  yeni bir kullanıcıya geçmişteki tüm duyurular okunmamış gibi yığılmaz.
- `NobetDurumu.duyurularGoruldu()` — Duyurular ekranına girildiğinde
  (`ana_ekran.dart`'taki `_bolumSec`) çağrılır, zamanı `DateTime.now()`'a
  çeker ve diske yazar.
- `NobetDurumu.duyurulariYenile()` — 5 dakikada bir çalışan bir
  `Timer.periodic` (`baslat()` içinde kurulur, `dispose()`'da iptal edilir)
  ve Android'de FCM'den ön planda mesaj geldiğinde bu metodu çağırır;
  ikisi de aynı anda tetiklenirse `_duyuruYukleniyor` bayrağı çift
  yüklemeyi engeller.
- **Kim okudu (yönetici):** Duyurular ekranı açıldığında
  `NobetDurumu._duyuruOkumaIsaretle()` ekranın gösterdiği tüm duyuruları
  o kullanıcı adına depoya yazar (`duyuruokuma_<kurumId>_<uid>` anahtarı,
  `{duyuruId: ISO zaman}`; daha önce yazılanların zamanı korunur).
  **Kullanıcı başına ayrı doküman** — herkes yalnızca kendi kaydını yazdığı
  için eşzamanlı yazma çakışması olmaz. `VeriServisi.duyuruOkumalariniGetir/
  Kaydet/tumDuyuruOkumalari` üç serviste de var; yeni önek yedek listelerine
  (`tumVeriyiDisaAktar`) eklendi ve `duyurular_` önekiyle çakışmaz (Cloud
  Function tetiklenmez). Süper Admin `DuyurularEkrani`nda her duyurunun
  yanında "Okuyan X/Y" rozeti görür; `DuyuruOkumaBilgisi.hedefKitle`
  paydayı belirler (onaylı, aktif, sadece-PDF olmayan, hedef birime uyan).
- Rozet UI'ı `ana_ekran.dart`'taki `_UstBaslik` (her ekranda sabit üst
  çubuk) içinde — sol menüdeki "Duyurular" öğesinde ayrı bir rozet yok
  (bilinçli sadeleştirme).

**Android push (sadece Android — Windows/web FCM desteklemiyor):**
`lib/servisler/bildirim_servisi.dart`, girişten sonra
`defaultTargetPlatform == TargetPlatform.android` kontrolüyle çalışır;
`duyuru-<kurumId>-hepsi` ve (kısıtlı değilse) hem
`duyuru-<kurumId>-guvenlik` hem `duyuru-<kurumId>-temizlik` konularına
abone olur. `functions/index.js`'teki `duyuruBildirimGonder` Cloud
Function'ı, `nobet_pro/duyurular_<kurumId>` belgesinin `j` alanındaki JSON
dizisini yazma öncesi/sonrası karşılaştırıp (tek belgede tüm duyurular
saklandığı için "yeni doküman" tetikleyicisi işe yaramaz) yeni eklenen
duyuru(lar) için ilgili konuya `notification` payload'ı gönderir.

**ÖNEMLİ — Cloud Functions codebase ayrımı:** Aynı Firebase projesini
(`nobet-sistemi`) paylaşan eski (Firebase tabanlı) uygulamanın kendi
Cloud Function'ı (`duyuruBildirimi`, `duyurular/{duyuruId}` koleksiyonunu
dinler — bambaşka bir veri yolu, çakışma yok) zaten `europe-west1`'de
deployda duruyor. Bu yüzden `firebase.json`'da
`"functions": {"codebase": "nobetsistemi", ...}` ile **ayrı bir codebase
adı** kullanılıyor — aksi hâlde `firebase deploy --only functions` bu
depodaki kaynak kodunda olmayan `duyuruBildirimi`'ni silmeye çalışır
(interaktif olmayan modda reddedilir ama codebase adını kaldırmayın).
