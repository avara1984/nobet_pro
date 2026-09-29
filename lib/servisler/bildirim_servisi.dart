import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../durum/nobet_durumu.dart';
import '../modeller/modeller.dart';

/// Sadece Android'de gerçek OS push bildirimi kurar — Firebase Cloud
/// Messaging Windows/web'de desteklenmediği için diğer platformlarda no-op.
/// Girişten sonra ([NobetDurumu.baslat] tamamlandığında) bir kez çağrılır.
Future<void> bildirimleriBaslat(NobetDurumu d) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;

  final mesajlasma = FirebaseMessaging.instance;
  await mesajlasma.requestPermission();

  final kurumId = d.kurumId;
  await mesajlasma.subscribeToTopic('duyuru-$kurumId-hepsi');

  // kisitliBirim yoksa (Süper Admin, Bordro Admini vb.) her iki birime de
  // abone ol — aktif birim NobetDurumu.birimDegistir() ile değişebiliyor,
  // her geçişte yeniden abone olmak yerine baştan ikisine de kayıtlı olmak
  // daha basit ve ucuz.
  final kisit = d.kisitliBirim;
  if (kisit == null) {
    await mesajlasma
        .subscribeToTopic('duyuru-$kurumId-${Birim.guvenlik.name}');
    await mesajlasma
        .subscribeToTopic('duyuru-$kurumId-${Birim.temizlik.name}');
  } else {
    await mesajlasma.subscribeToTopic('duyuru-$kurumId-${kisit.name}');
  }

  // Uygulama ön plandayken FCM mesajı gelirse sistem bildirimi göstermek
  // yerine sadece uygulama içi durumu tazele — okunmamış rozeti zaten
  // güncellenir. Arka planda/kapalıyken Android, Cloud Function'ın
  // gönderdiği 'notification' alanını otomatik sistem bildirimi olarak
  // gösteriyor, ekstra kod gerekmiyor.
  FirebaseMessaging.onMessage.listen((_) => d.duyurulariYenile());
}
