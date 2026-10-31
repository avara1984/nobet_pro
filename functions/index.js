const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

admin.initializeApp();

// Giriş uç noktaları (npDurum, npGiris, ...) — bkz. giris.js
Object.assign(exports, require('./giris'));

// Nöbet Sistemi'nde duyurular tek doküman-per-kurum olarak saklanır:
// nobet_pro/duyurular_<kurumId>, içerik 'j' alanında JSON dizisi (bkz.
// lib/servisler/yerel_servis.dart ve lib/servisler/firestore_servis.dart —
// ikisi de aynı depolama sözleşmesini paylaşır). Bu yüzden "yeni duyuru"yu
// tek belgeye yazılan dizinin öncesi/sonrasını karşılaştırarak buluyoruz.
exports.duyuruBildirimGonder = onDocumentWritten(
  'nobet_pro/{docId}',
  async (event) => {
    const docId = event.params.docId;
    if (!docId.startsWith('duyurular_')) return;
    const kurumId = docId.slice('duyurular_'.length);

    let eskiListe = [];
    let yeniListe = [];
    try {
      eskiListe = JSON.parse(event.data?.before?.data()?.j ?? '[]');
    } catch (e) {
      console.warn('Eski duyuru listesi çözümlenemedi:', e);
    }
    try {
      yeniListe = JSON.parse(event.data?.after?.data()?.j ?? '[]');
    } catch (e) {
      console.warn('Yeni duyuru listesi çözümlenemedi:', e);
      return;
    }

    const eskiIdler = new Set(eskiListe.map((d) => d.id));
    const yeniDuyurular = yeniListe.filter((d) => !eskiIdler.has(d.id));

    for (const d of yeniDuyurular) {
      const konu = `duyuru-${kurumId}-${d.hedef || 'hepsi'}`;
      try {
        await admin.messaging().send({
          topic: konu,
          notification: {
            title: d.baslik || 'Yeni duyuru',
            body: d.icerik || '',
          },
        });
        console.log(`Bildirim gönderildi: ${konu} — "${d.baslik}"`);
      } catch (e) {
        console.error(`Bildirim gönderilemedi (${konu}):`, e);
      }
    }
  },
);
