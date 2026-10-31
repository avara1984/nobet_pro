'use strict';

// Giriş uç noktaları (HTTPS). Asıl mantık cekirdek.js içindedir.
//
// İstemci `cloud_functions` paketini kullanmaz (Windows'u desteklemiyor);
// düz JSON POST ile çağırır. ID token isteyen uç noktalar
// `Authorization: Bearer <idToken>` bekler.

const {onRequest} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const cekirdek = require('./cekirdek');

const SECENEKLER = {
  region: 'europe-west1',
  cors: [
    'https://nobet-sistemi.web.app',
    'https://nobet-sistemi.firebaseapp.com',
    /^http:\/\/localhost(:\d+)?$/,
  ],
  invoker: 'public',
  maxInstances: 5,
  timeoutSeconds: 30,
};

function baglam() {
  return {db: admin.firestore(), auth: admin.auth(), simdi: () => Date.now()};
}

async function tokenDogrula(baslik) {
  const m = /^Bearer (.+)$/.exec(baslik || '');
  if (!m) throw new cekirdek.Hata(401, 'Oturum gerekli.');
  let cozulen;
  try {
    cozulen = await admin.auth().verifyIdToken(m[1]);
  } catch (_) {
    throw new cekirdek.Hata(401, 'Oturum geçersiz veya süresi dolmuş.');
  }
  // Anonim oturumlar (eski uygulamalar) bu uç noktaları kullanamaz.
  if (cozulen.nobet !== true) throw new cekirdek.Hata(403, 'Yetkisiz.');
  return cozulen;
}

function uc(isle, {tokenGerekli = false} = {}) {
  return onRequest(SECENEKLER, async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({hata: 'Yalnızca POST kabul edilir.'});
      return;
    }
    try {
      const govde = req.body && typeof req.body === 'object' ? req.body : {};
      const kimlik = tokenGerekli ? await tokenDogrula(req.get('Authorization')) : null;
      res.json(await isle(baglam(), govde, kimlik));
    } catch (e) {
      if (e instanceof cekirdek.Hata) {
        res.status(e.durum).json({hata: e.message});
      } else {
        console.error(e);
        res.status(500).json({hata: 'Sunucu hatası.'});
      }
    }
  });
}

exports.npDurum = uc((c, g) => cekirdek.durum(c, g));
exports.npGiris = uc((c, g) => cekirdek.girisYap(c, g));
exports.npUyeOl = uc((c, g) => cekirdek.uyeOl(c, g));
exports.npYoneticiOlustur = uc((c, g) => cekirdek.yoneticiOlustur(c, g));
exports.npBen = uc((c, g, k) => cekirdek.ben(c, k, g), {tokenGerekli: true});
exports.npSifreAyarla = uc((c, g, k) => cekirdek.sifreAyarla(c, k, g), {tokenGerekli: true});
exports.npSifreleriTasi = uc((c, g, k) => cekirdek.sifreleriTasi(c, k, g), {tokenGerekli: true});
