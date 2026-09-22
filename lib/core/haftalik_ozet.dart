import '../modeller/modeller.dart';
import 'mesai_hesap.dart' as mh;

/// Bir hafta (veya dönem) için personel başına toplam NORMAL çalışma saati.
///
/// Resmi tatile denk gelen vardiyaların saatleri dahil edilmez — o günler
/// `gunSonucu.normal == 0` döner, fazla mesai günü olarak ayrıca sayılır.
/// Yalnızca normal (tatil dışı) mesai saatleri toplanır.
///
/// Haftalık Nöbet ekranı aynı anda birden fazla ayın `AyKaydi`'sini
/// yüklü tuttuğu için, hangi tarihin hangi `AyKaydi`'ye ait olduğunu
/// [kayitBul] üzerinden çözer — bu sayede bu fonksiyon ay sınırlarından
/// habersiz, saf bir toplama işlemi olarak kalır.
double haftalikToplamSaat({
  required List<DateTime> haftaGunleri,
  required KurumAyari ayar,
  required String personelId,
  required AyKaydi Function(DateTime tarih) kayitBul,
}) {
  var toplam = 0.0;
  for (final tarih in haftaGunleri) {
    final kayit = kayitBul(tarih);
    final gunSayisi = DateTime(tarih.year, tarih.month + 1, 0).day;
    // Ertesi gün başka bir aya ait olabilir (ay sınırı); kayitBul ile doğru
    // kaydı al ve kResmiTatil kodunu yarinKodResmiTatil'e yansıt.
    final ertesi = tarih.add(const Duration(days: 1));
    final ertesiKod = kayitBul(ertesi).kod(ertesi.day, personelId);
    toplam += mh
        .gunSonucu(
          ayar: ayar,
          kayit: kayit,
          gun: tarih.day,
          yil: tarih.year,
          ay: tarih.month,
          gunSayisi: gunSayisi,
          personelId: personelId,
          yarinKodResmiTatil: ertesiKod == kResmiTatil,
        )
        .normal;
  }
  return toplam;
}
