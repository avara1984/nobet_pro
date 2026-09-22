# NÖBET PRO — Kurulum

Veriler **Firestore'da** (bulutta) tutulur — Windows ve Android aynı veriyi
görür. İnternet yoksa veya Firebase'e ulaşılamazsa uygulama kendiliğinden
**yerel moda** düşer ve cihazın kendi diskine kaydeder; Yedekleme
ekranındaki rozetten hangi modda olduğunuzu görürsünüz.

---

## Adım 1 — Projeyi oluşturun

Eski `nobet_pro` klasörünü tamamen silin. Sonra temiz bir yerden:

```powershell
cd C:\
flutter create --platforms=windows,android nobet_pro
cd C:\nobet_pro
```

## Adım 2 — Dosyaları kopyalayın

Zip'i açın. İçindeki **`lib`** klasörünü ve **`pubspec.yaml`** dosyasını
`C:\nobet_pro\` içine kopyalayın, sorduğunda **üzerine yaz** deyin.

## Adım 3 — Çalıştırın

```powershell
flutter pub get
flutter run -d windows
```

İlk açılışta personel listesi boştur. **Personeller** bölümünden ekleyin.

---

## Firebase / Firestore notları

- Uygulama, eski nöbet sistemiyle **aynı Firebase projesini**
  (`nobet-sistemi`) kullanır; kimlik bilgileri `lib/firebase_options.dart`
  içindedir. Veriler eski uygulamanınkilerden ayrı, tek bir **`nobet_pro`**
  koleksiyonunda durur — iki uygulama birbirine karışmaz.
- Firebase Console → Firestore → **Rules** içinde `nobet_pro`
  koleksiyonuna izin verilmiş olmalı. En basit hâliyle mevcut kuralların
  içine şunu ekleyin:

  ```
  match /nobet_pro/{belge} {
    allow read, write: if true;
  }
  ```

- **Bu cihazda eski yerel veri varsa:** Yedekleme → **"Yerel veriyi buluta
  yükle"** butonu tüm yerel veriyi tek seferde Firestore'a taşır.
- İnternet kesildiğinde Firestore'un kendi önbelleği devreye girer;
  bağlantı gelince değişiklikler kendiliğinden eşitlenir.

---

## PDF fontu (isteğe bağlı)

`C:\nobet_pro\assets\fonts\` klasörüne `Roboto-Regular.ttf` ve
`Roboto-Bold.ttf` koyun (fonts.google.com/specimen/Roboto → zip içindeki
`static` klasöründen). Koymazsanız uygulama yine çalışır, sadece PDF'te
Türkçe karakterler bozuk görünür.

---

## Nasıl kullanılır

1. **Personeller** → personelleri ekleyin, mesai personelini işaretleyin
2. **Ayarlar → Vardiya tanımları** → gerçek vardiya saatlerinizi girin
3. **Ayarlar → Kapsama kuralları** → her aralıkta en az kaç kişi olmalı
4. **Nöbet Listesi** → ay seçin, **Liste Yap** ile taslak üretin
5. Hücrelere dokunup düzeltin (uzun basmak hücreyi temizler)
6. **Kaydet** → **PDF İndir**

Durum sütunu: yeşil = kurallar sağlandı, turuncu = eksik var,
kırmızı = o gün hiç çalışan yok. İşaretin üzerine gelirseniz neyin eksik
olduğunu yazar.

---

## Dosya haritası

```
lib/
├── main.dart                        uygulama girişi (Firebase + yerel yedek)
├── firebase_options.dart            Firebase proje kimlikleri
├── core/
│   ├── tema.dart                    renkler + açık/koyu tema
│   ├── tarih.dart / para.dart       Türkçe tarih ve para yardımcıları
│   ├── kapsama_motoru.dart          dakika bazlı kapsama denetimi
│   ├── mesai_hesap.dart             gün bazlı bordro değerleri
│   └── bordro_hesap.dart            maaş hesabı
├── modeller/                        modeller.dart + bordro_modelleri.dart
├── servisler/
│   ├── veri_servisi.dart            veri katmanı arayüzü
│   ├── firestore_servis.dart        bulut (Firestore) implementasyonu
│   ├── yerel_servis.dart            yerel (disk) implementasyonu
│   ├── pdf_servis.dart              yatay A4 nöbet PDF'i
│   └── bordro_pdf_servis.dart       dikey A4 bordro PDF'i
├── durum/nobet_durumu.dart          uygulama durumu
└── ekranlar/
    ├── ana_ekran.dart               yan menü, üst başlık, dashboard
    ├── nobet_listesi_ekrani.dart    nöbet tablosu
    ├── aylik_ozet_ekrani.dart       özet + kapsama denetimi
    ├── bordro_ekranlari.dart        bordro işlemleri (5 ekran)
    └── yonetim_ekranlari.dart       personel, duyuru, ayar, admin, yedek
```
