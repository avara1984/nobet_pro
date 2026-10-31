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

/// [dinlenmeIhlaliMetni]'nin TERS yönü: yazılmak istenen vardiyadan ([yeniKod])
/// çıkan personelin ERTESİ gün zaten yazılı bir vardiyası ([sonrakiKod]) varsa
/// aynı dinlenme kuralı geçerlidir. Örn. 3 Aralık'ta 08:00-20:00 varken
/// 2 Aralık'a gece vardiyası yazmak, gece vardiyasından çıkıp doğrudan gündüze
/// geçmek demektir.
///
/// Kural, ileri yönle aynı yasak vardiya kümelerini kullanır; ancak yalnızca
/// GERÇEK çalışma vardiyalarını ihlal sayar (izin, hafta/resmi tatil kodları
/// "arka arkaya vardiya" oluşturmaz, uyarı üretmez).
///
/// [sonrakiKod] bilinmiyorsa (ertesi gün yüklü değil / ay sonu) null döner.
String? ertesiGunDinlenmeIhlaliMetni({
  required String personelAdi,
  required String yeniKod,
  required String? sonrakiKod,
}) {
  if (sonrakiKod == null || sonrakiKod.isEmpty) return null;

  // 24:00-08:00 yazılıyorsa ertesi gün SADECE yine 24:00-08:00 olabilir;
  // 20:00-08:00 dahil her çalışma vardiyası yasaktır.
  const calismaVardiyalari = {kGunduz12, kGece12, kSabah8, kAksam8, kMesai};
  final yasak = switch (yeniKod) {
    kGece8 => calismaVardiyalari.difference({kGece8}),
    // 20:00-08:00'dan çıkan sabah 08:00'de biter: ertesi gün gündüz/mesai yasak,
    // yine gece olabilir.
    kGece12 => const {kGunduz12, kSabah8, kAksam8, kMesai},
    _ => const <String>{},
  };
  if (!yasak.contains(sonrakiKod)) return null;

  return '$personelAdi için ertesi gün $sonrakiKod vardiyası zaten yazılı.\n'
      '$yeniKod vardiyasından çıkan personel yeterli dinlenme süresi olmadan '
      '$sonrakiKod vardiyasına devam edemez.';
}
