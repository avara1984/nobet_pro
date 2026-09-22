import '../modeller/bordro_modelleri.dart';
import '../modeller/modeller.dart';
import 'mesai_hesap.dart' as mh;

/// Bordro hesaplamasının saf iş mantığı — UI'dan ve veri katmanından
/// bağımsızdır, test edilebilir.
///
/// Gece saati ve fazla mesai (tatil çalışma) günü BURADA yeniden
/// hesaplanmaz; nöbet tarafındaki [mh.gunSonucu] kullanılır — bordro ile
/// Aylık Özet ekranı aynı sayıyı göstersin ve mantık tek yerde dursun diye.

// -----------------------------------------------------------------------------
// NÖBET LİSTESİNDEN GİRDİ ÇEKME
// -----------------------------------------------------------------------------
/// Nöbet listesinden okunan aylık bordro girdileri.
typedef NobetGirdisi = ({
  double geceSaati,
  int tatilGunu,
  int yolGunu,
  int doluGun,
});

const NobetGirdisi kBosNobetGirdisi =
    (geceSaati: 0.0, tatilGunu: 0, yolGunu: 0, doluGun: 0);

/// Yol/yemek yardımı sayılmayan vardiya kodları (fiilen çalışılmayan günler).
const Set<String> kYolDisiKodlar = {
  '',
  kNobetIzni,
  kYillikIzin,
  kHaftaTatili,
  kResmiTatil,
  kIdariIzin,
};

/// Bir personelin bir aya ait bordro girdilerini nöbet listesinden çıkarır.
///
/// - **Gece saati** ve **tatil (fazla mesai) günü**: bordro ayının 1'i →
///   son günü. Ay sonundaki gece vardiyasının bir sonraki aya sarkması
///   [mh.aylikFazlaMesaiGunu] tarafından zaten yönetilir.
/// - **Yol/yemek günü**: ayın 15'i → bir sonraki ayın 14'ü (bordro dönemi),
///   bu yüzden [sonrakiAyKaydi] gerekir.
NobetGirdisi nobettenGirdi({
  required KurumAyari ayar,
  required AyKaydi kayit,
  required AyKaydi? oncekiAyKaydi,
  required AyKaydi? sonrakiAyKaydi,
  required String personelId,
  required int yil,
  required int ay,
}) {
  final gunSayisi = DateTime(yil, ay + 1, 0).day;

  var geceSaati = 0.0;
  var doluGun = 0;
  for (var g = 1; g <= gunSayisi; g++) {
    final sonuc = mh.gunSonucu(
      ayar: ayar,
      kayit: kayit,
      gun: g,
      yil: yil,
      ay: ay,
      gunSayisi: gunSayisi,
      personelId: personelId,
    );
    geceSaati += sonuc.gece;
    if (kayit.kod(g, personelId).isNotEmpty) doluGun++;
  }

  final tatilGunu = mh.aylikFazlaMesaiGunu(
    ayar: ayar,
    kayit: kayit,
    oncekiAyKayit: oncekiAyKaydi,
    personelId: personelId,
    yil: yil,
    ay: ay,
  );

  return (
    geceSaati: geceSaati,
    tatilGunu: tatilGunu.round(),
    yolGunu: yolGunuSayisi(
      kayit: kayit,
      sonrakiAyKaydi: sonrakiAyKaydi,
      personelId: personelId,
      yil: yil,
      ay: ay,
    ),
    doluGun: doluGun,
  );
}

/// Yol/yemek günü: ayın 15'inden bir sonraki ayın 14'üne kadar fiilen
/// çalışılan (izin/tatil kodu olmayan) gün sayısı.
int yolGunuSayisi({
  required AyKaydi kayit,
  required AyKaydi? sonrakiAyKaydi,
  required String personelId,
  required int yil,
  required int ay,
}) {
  var sayi = 0;

  final gunSayisi = DateTime(yil, ay + 1, 0).day;
  for (var g = 15; g <= gunSayisi; g++) {
    if (!kYolDisiKodlar.contains(kayit.kod(g, personelId))) sayi++;
  }

  if (sonrakiAyKaydi != null) {
    for (var g = 1; g <= 14; g++) {
      if (!kYolDisiKodlar.contains(sonrakiAyKaydi.kod(g, personelId))) sayi++;
    }
  }

  return sayi;
}

// -----------------------------------------------------------------------------
// HESAPLAMA
// -----------------------------------------------------------------------------
/// Tek bir aylık bordroyu hesaplar.
///
/// [oncekiYillikMatrah] o yıl içinde bu aydan önce birikmiş vergi matrahıdır;
/// gelir vergisi dilimli olarak bu birikimin üzerine hesaplanır.
BordroSonucu bordroHesapla({
  required Personel personel,
  required PersonelUcreti ucret,
  required BordroAyari ayar,
  required int yil,
  required int ay,
  required int calismaGunu,
  required int sgkGunu,
  required double geceSaati,
  required int tatilGunu,
  required int yolGunu,
  required double oncekiYillikMatrah,
  bool gecisAyi = false,
  double ucretFarki = 0,
  double sosyalYardimFarki = 0,
  double yolYardimiFarki = 0,
  double hizmetZammiFarki = 0,
  double sendikaFarki = 0,
}) {
  // --- GELİRLER ---
  // Md.33 — günlük ücret × çalışma günü
  final gunlukUcretToplami = ucret.gunlukUcret * calismaGunu;

  // Md.38 — sosyal yardım (aylık sabit)
  final sosyalYardim = ayar.sosyalYardim;

  // Md.36 — hizmet primi = Md.33 tutarının %16'sı
  final hizmetPrimi = gunlukUcretToplami * ayar.hizmetPrimiOrani;

  // Md.58 — hizmet zammı (kişiye özel sabit)
  final hizmetZammi = ucret.hizmetZammi;

  // Md.40 — yol yardımı. Sabit aylık tanımlıysa doğrudan; yoksa günlük×gün.
  final yolYardimi = ucret.yolYardimiAylik > 0
      ? ucret.yolYardimiAylik
      : (ucret.yolYardimiGunluk > 0
              ? ucret.yolYardimiGunluk
              : ayar.yolYardimiGunluk) *
          yolGunu;

  // Md.23 — gece çalışma. 7,5 saat = 1 günlük çalışma kabul edilir.
  final geceCalismaUcreti =
      (ucret.gunlukUcret / 7.5) * ayar.geceKatsayisi * geceSaati;

  // Md.22 — resmi tatil çalışması
  final tatilCalismaUcreti = ucret.gunlukUcret * ayar.tatilKatsayisi * tatilGunu;

  // --- GEÇİŞ AYI FARKLARI ---
  // Geçiş ayında normal hesap ESKİ ücretle yapılır, üstüne bordrodaki fark
  // satırları eklenir. Hizmet primi farkı otomatik: %16 × ücret farkı.
  final hizmetPrimiFarki = gecisAyi ? ayar.hizmetPrimiOrani * ucretFarki : 0.0;
  final farkToplami = gecisAyi
      ? ucretFarki +
          hizmetPrimiFarki +
          sosyalYardimFarki +
          yolYardimiFarki +
          hizmetZammiFarki
      : 0.0;

  final brutGelir = gunlukUcretToplami +
      sosyalYardim +
      hizmetPrimi +
      hizmetZammi +
      yolYardimi +
      geceCalismaUcreti +
      tatilCalismaUcreti +
      farkToplami;

  // --- KESİNTİLER ---
  final sgkMatrahi = brutGelir;
  final sgkCalisanKesintisi = sgkMatrahi * ayar.sgkCalisan;
  final sgkIssizlikKesintisi = sgkMatrahi * ayar.sgkIssizlik;

  // Sendika kesintisi bir günlük ücrettir ve vergi matrahından düşülür.
  final sendikaKesintisi = ucret.sendikaUyesi
      ? ucret.gunlukUcret + (gecisAyi ? sendikaFarki : 0.0)
      : 0.0;

  final aylikVergiMatrahi = sgkMatrahi -
      sgkCalisanKesintisi -
      sgkIssizlikKesintisi -
      sendikaKesintisi;

  final yillikMatrah = oncekiYillikMatrah + aylikVergiMatrahi;

  final gelirVergisi = dilimliVergiFarki(
    oncekiMatrah: oncekiYillikMatrah,
    yeniMatrah: yillikMatrah,
    dilimler: ayar.vergiDilimleri,
  );

  // Gelir vergisi istisnası, çalışanın net ücretinden düşülmez — kurumun
  // vergi dairesine yatırdığı tutarı azaltan ayrı bir kalemdir (referans
  // bordroda "Gelir Vergisi İstisnası" bilgi amaçlı gösterilir, kesinti
  // toplamına dahil edilmez). Bu yüzden [netGelirVergisi] sadece bilgi
  // amaçlıdır; kesinti toplamında ve ödenecek tutarda tam [gelirVergisi]
  // kullanılır.
  final gelirVergisiIstisnasi = ayar.gelirVergisiIstisnasi;
  final netGelirVergisi =
      (gelirVergisi - gelirVergisiIstisnasi).clamp(0.0, double.infinity);

  // Damga vergisi = (brüt gelir − asgari ücret istisnası) × oran
  final damgaMatrahi =
      (brutGelir - ayar.damgaVergisiIstisnasi).clamp(0.0, double.infinity);
  final damgaVergisi = damgaMatrahi * ayar.damgaVergisiOrani;

  final toplamKesinti = sgkCalisanKesintisi +
      sgkIssizlikKesintisi +
      gelirVergisi +
      damgaVergisi +
      sendikaKesintisi;

  return BordroSonucu(
    personelId: personel.id,
    personelAd: personel.ad,
    yil: yil,
    ay: ay,
    calismaGunu: calismaGunu,
    sgkGunu: sgkGunu,
    geceSaati: geceSaati,
    tatilGunu: tatilGunu,
    yolGunu: yolGunu,
    gunlukUcretToplami: gunlukUcretToplami,
    sosyalYardim: sosyalYardim,
    hizmetPrimi: hizmetPrimi,
    hizmetZammi: hizmetZammi,
    yolYardimi: yolYardimi,
    geceCalismaUcreti: geceCalismaUcreti,
    tatilCalismaUcreti: tatilCalismaUcreti,
    brutGelir: brutGelir,
    sgkMatrahi: sgkMatrahi,
    sgkCalisanKesintisi: sgkCalisanKesintisi,
    sgkIssizlikKesintisi: sgkIssizlikKesintisi,
    aylikVergiMatrahi: aylikVergiMatrahi,
    oncekiYillikMatrah: oncekiYillikMatrah,
    yillikMatrah: yillikMatrah,
    gelirVergisi: gelirVergisi,
    gelirVergisiIstisnasi: gelirVergisiIstisnasi,
    netGelirVergisi: netGelirVergisi,
    damgaVergisi: damgaVergisi,
    sendikaKesintisi: sendikaKesintisi,
    toplamKesinti: toplamKesinti,
    odenecekTutar: brutGelir - toplamKesinti,
    gecisAyi: gecisAyi,
    ucretFarki: gecisAyi ? ucretFarki : 0,
    hizmetPrimiFarki: hizmetPrimiFarki,
    sosyalYardimFarki: gecisAyi ? sosyalYardimFarki : 0,
    yolYardimiFarki: gecisAyi ? yolYardimiFarki : 0,
    hizmetZammiFarki: gecisAyi ? hizmetZammiFarki : 0,
    sendikaFarki: gecisAyi ? sendikaFarki : 0,
    hesaplama: DateTime.now(),
  );
}

/// Bu ayın gelir vergisi = (yeni kümülatif matrahın vergisi) −
/// (önceki kümülatif matrahın vergisi).
double dilimliVergiFarki({
  required double oncekiMatrah,
  required double yeniMatrah,
  required List<VergiDilimi> dilimler,
}) {
  final onceki = dilimliVergi(oncekiMatrah, dilimler);
  final yeni = dilimliVergi(yeniMatrah, dilimler);
  return (yeni - onceki).clamp(0.0, double.infinity);
}

/// Belirli bir kümülatif matraha karşılık gelen toplam gelir vergisi.
double dilimliVergi(double toplam, List<VergiDilimi> dilimler) {
  if (toplam <= 0) return 0;
  var kalan = toplam;
  var vergi = 0.0;
  var oncekiSinir = 0.0;

  for (final dilim in dilimler) {
    final buDilimde = (dilim.ustSinir - oncekiSinir).clamp(0.0, kalan);
    vergi += buDilimde * dilim.oran;
    kalan -= buDilimde;
    oncekiSinir = dilim.ustSinir;
    if (kalan <= 0) break;
  }
  return vergi;
}
