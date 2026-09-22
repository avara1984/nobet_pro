import '../modeller/modeller.dart';

/// Gece vardiyasından çıkan personelin ertesi gün gündüz vardiyasına
/// yazılamayacağı kuralın SAF hâli.
///
/// `NobetDurumu.dinlenmeIhlali` ve Haftalık Nöbet ekranı bu fonksiyonu
/// paylaşır — ikisi de aynı kuralı uygular, farkları sadece [oncekiKod]'u
/// nereden okuduklarıdır (aylık ekran tek `AyKaydi`'den, haftalık ekran
/// ay sınırında doğru `AyKaydi`'yi bularak).
///
/// [oncekiKod] bilinmiyorsa (örn. ızgaranın en baştaki günü, önceki gün
/// yüklü değil) her zaman null döner — kontrol sessizce atlanır.
String? dinlenmeIhlaliMetni({
  required String personelAdi,
  required String? oncekiKod,
  required String yeniKod,
}) {
  // 24:00-08:00'dan çıkan personel için kural daha sıkı: o gün SADECE
  // yine 24:00-08:00 (aynı vardiyada devam) ya da boş/N.İ. yazılabilir —
  // 20:00-08:00 dahil başka HERHANGİ bir vardiya yasaktır.
  if (oncekiKod == kGece8) {
    if (yeniKod.isEmpty || yeniKod == kNobetIzni || yeniKod == kGece8) {
      return null;
    }
    return '$personelAdi bir önceki gün $oncekiKod vardiyasındaydı.\n'
        'Bu vardiyadan çıkan personel yeterli dinlenme süresi olmadan '
        '$yeniKod vardiyasına devam edemez — sadece $kGece8 ya da '
        'boş/$kNobetIzni yazılabilir.';
  }

  if (oncekiKod != kGece12) return null;

  const yasak = {kGunduz12, kSabah8, kAksam8, kMesai};
  if (!yasak.contains(yeniKod)) return null;

  return '$personelAdi bir önceki gün $oncekiKod vardiyasındaydı.\n'
      'Sabah 08:00’de çıkan personel yeterli dinlenme süresi olmadan '
      '$yeniKod vardiyasına devam edemez.';
}
