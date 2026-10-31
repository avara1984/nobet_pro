'use strict';

// Sunucu tarafı giriş mantığı. HTTP katmanından (giris.js) bağımsızdır:
// Firestore (`db`) ve Firebase Auth (`auth`) dışarıdan verilir, böylece
// bellekteki sahte nesnelerle test edilebilir.
//
// Depolama (istemci ile aynı düzen):
//   nobet_pro/kullanicilar_<kurum>   {j: JSON liste}   kullanıcı kayıtları
//   nobet_gizli/sifreler_<kurum>     {j: JSON harita}  uid -> {algo,tuz,hash}
//   nobet_gizli/ayar                 {kilitli: bool}   geçiş tamamlandı mı
//   nobet_gizli/deneme_<anahtar>     {j: JSON}         hatalı deneme sayacı
// `nobet_gizli` yalnızca Admin SDK ile erişilir (kurallar istemciye kapalı).

const crypto = require('crypto');
const sifre = require('./sifre');

const KOL = 'nobet_pro';
const GIZLI = 'nobet_gizli';

const DENEME_SINIRI = 5;
const DENEME_PENCERESI_MS = 15 * 60 * 1000;
const KILIT_SURESI_MS = 15 * 60 * 1000;

const GENEL_GIRIS_HATASI = 'T.C. Kimlik No / kullanıcı adı veya şifre hatalı.';

class Hata extends Error {
  constructor(durum, mesaj) {
    super(mesaj);
    this.durum = durum;
  }
}

// --- yardımcılar -------------------------------------------------------------

function kurumDogrula(kurumId) {
  const k = String(kurumId || '');
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(k)) throw new Hata(400, 'Geçersiz kurum.');
  return k;
}

function tcGecerli(tc) {
  return /^[1-9]\d{10}$/.test(String(tc || '').trim());
}

function yeniUid() {
  return `k${Date.now()}${String(crypto.randomInt(0, 1000)).padStart(3, '0')}`;
}

function ref(db, koleksiyon, id) {
  return db.collection(koleksiyon).doc(id);
}

function jsonCoz(snap, varsayilan, ad) {
  if (!snap.exists) return varsayilan;
  const j = (snap.data() || {}).j;
  if (!j) return varsayilan;
  try {
    return JSON.parse(j);
  } catch (_) {
    // Bozuk kaydı boş saymayız: üzerine yazıp veriyi kaybettirmek yerine dururuz.
    throw new Hata(500, `Kayıt okunamadı (bozuk veri): ${ad}`);
  }
}

/** Profilden türetilen etkin yetkiler (istemcideki Kullanici.haritadan ile aynı). */
function etkinAlanlar(k) {
  switch (k.yoneticiProfili) {
    case 'superAdmin':
      return {rol: 'yonetici', sadecePdf: false, kisitliBirim: '', bordro: true};
    case 'temizlikNobet':
      return {rol: 'editor', sadecePdf: false, kisitliBirim: 'temizlik', bordro: false};
    case 'bordro':
      return {rol: 'editor', sadecePdf: true, kisitliBirim: '', bordro: true};
    default: {
      const rol = ['yonetici', 'editor', 'izleyici'].includes(k.rol) ? k.rol : 'izleyici';
      const sadecePdf = k.sadecePdf === true;
      const kisitliBirim = ['guvenlik', 'temizlik'].includes(k.kisitliBirim)
        ? k.kisitliBirim
        : '';
      return {rol, sadecePdf, kisitliBirim, bordro: !sadecePdf && rol === 'yonetici'};
    }
  }
}

/** İstemciye gönderilen kullanıcı kaydı: şifre özeti asla taşınmaz. */
function acikProfil(k) {
  const {rol, sadecePdf, kisitliBirim} = etkinAlanlar(k);
  return {...k, rol, sadecePdf, kisitliBirim, sifreHash: ''};
}

function bul(liste, girilen) {
  const kucuk = girilen.toLowerCase();
  return liste.find(
    (k) => k.kimlik === girilen ||
      (k.kullaniciAdi && String(k.kullaniciAdi).toLowerCase() === kucuk));
}

function yoneticiVarMi(liste, sifreler) {
  return liste.some((k) =>
    etkinAlanlar(k).rol === 'yonetici' &&
    k.kimlik &&
    (k.sifreHash || sifreler[k.uid]) &&
    k.onayli !== false);
}

// --- okuma/yazma -------------------------------------------------------------

async function kullanicilariOku(ctx, kurum, tx) {
  const r = ref(ctx.db, KOL, `kullanicilar_${kurum}`);
  const snap = tx ? await tx.get(r) : await r.get();
  return jsonCoz(snap, [], `kullanicilar_${kurum}`);
}

async function sifreleriOku(ctx, kurum, tx) {
  const r = ref(ctx.db, GIZLI, `sifreler_${kurum}`);
  const snap = tx ? await tx.get(r) : await r.get();
  return jsonCoz(snap, {}, `sifreler_${kurum}`);
}

async function kilitliMi(ctx, tx) {
  const r = ref(ctx.db, GIZLI, 'ayar');
  const snap = tx ? await tx.get(r) : await r.get();
  return snap.exists && (snap.data() || {}).kilitli === true;
}

function kullanicilariYaz(ctx, tx, kurum, liste) {
  tx.set(ref(ctx.db, KOL, `kullanicilar_${kurum}`), {j: JSON.stringify(liste)},
    {merge: true});
}

function sifreleriYaz(ctx, tx, kurum, harita) {
  tx.set(ref(ctx.db, GIZLI, `sifreler_${kurum}`), {j: JSON.stringify(harita)});
}

// --- hatalı deneme sınırı ----------------------------------------------------

function denemeAnahtari(kurum, girilen) {
  const ozet = crypto.createHash('sha256')
    .update(`${kurum}:${girilen.toLowerCase()}`).digest('hex');
  return `deneme_${ozet.slice(0, 32)}`;
}

async function kilitKontrol(ctx, anahtar) {
  const snap = await ref(ctx.db, GIZLI, anahtar).get();
  const d = jsonCoz(snap, {}, anahtar);
  if (d.kilitBitis && d.kilitBitis > ctx.simdi()) {
    const dk = Math.ceil((d.kilitBitis - ctx.simdi()) / 60000);
    throw new Hata(429, `Çok fazla hatalı deneme. Yaklaşık ${dk} dakika sonra tekrar deneyin.`);
  }
}

async function hataKaydet(ctx, anahtar) {
  const r = ref(ctx.db, GIZLI, anahtar);
  await ctx.db.runTransaction(async (tx) => {
    const d = jsonCoz(await tx.get(r), {}, anahtar);
    const simdi = ctx.simdi();
    if (!d.ilk || simdi - d.ilk > DENEME_PENCERESI_MS || (d.kilitBitis && d.kilitBitis <= simdi)) {
      d.sayac = 0;
      d.ilk = simdi;
      delete d.kilitBitis;
    }
    d.sayac += 1;
    if (d.sayac >= DENEME_SINIRI) d.kilitBitis = simdi + KILIT_SURESI_MS;
    tx.set(r, {j: JSON.stringify(d)});
  });
}

async function basariKaydet(ctx, anahtar) {
  await ref(ctx.db, GIZLI, anahtar).delete();
}

// --- şifre doğrulama ---------------------------------------------------------

/**
 * Şifre doğru mu ve kayıt yükseltilmeli mi?
 * Kayıtta eski `sifreHash` (SHA-256) varsa o geçerlidir; yoksa gizli depodaki
 * kayıt (`sha256` biçimindeyse doğrulama sonrası scrypt'e yükseltilir).
 */
async function sifreKontrol(parola, k, sifreler) {
  if (k.sifreHash) {
    return {ok: sifre.esitMi(sifre.sha256Ozeti(parola), k.sifreHash), yukselt: true};
  }
  const kayit = sifreler[k.uid];
  if (!kayit) return {ok: false, yukselt: false};
  return {
    ok: await sifre.dogrula(parola, kayit),
    yukselt: kayit.algo === 'sha256',
  };
}

/** Şifreyi scrypt olarak saklar; kullanıcı kaydındaki eski özeti siler. */
async function sifreYaz(ctx, kurum, uid, parola) {
  const kayit = await sifre.olustur(parola);
  await ctx.db.runTransaction(async (tx) => {
    const liste = await kullanicilariOku(ctx, kurum, tx);
    const sifreler = await sifreleriOku(ctx, kurum, tx);
    sifreler[uid] = kayit;
    sifreleriYaz(ctx, tx, kurum, sifreler);
    const k = liste.find((x) => x.uid === uid);
    if (k && k.sifreHash) {
      k.sifreHash = '';
      kullanicilariYaz(ctx, tx, kurum, liste);
    }
  });
}

// --- oturum ------------------------------------------------------------------

async function oturumAc(ctx, kurum, k) {
  const e = etkinAlanlar(k);
  const token = await ctx.auth.createCustomToken(k.uid, {
    nobet: true,
    kurumId: kurum,
    rol: e.rol,
    bordro: e.bordro,
    sadecePdf: e.sadecePdf,
    kisitliBirim: e.kisitliBirim,
  });
  return {token, kullanici: acikProfil(k)};
}

function hesapDurumuKontrol(k) {
  if (k.onayli === false) throw new Hata(403, 'Hesabınız henüz yönetici onayı bekliyor.');
  if (k.aktif === false) throw new Hata(403, 'Hesabınız pasif durumda. Yöneticinize başvurun.');
}

// --- uç noktalar -------------------------------------------------------------

async function durum(ctx, {kurumId}) {
  const kurum = kurumDogrula(kurumId);
  const liste = await kullanicilariOku(ctx, kurum);
  const sifreler = await sifreleriOku(ctx, kurum);
  return {yoneticiVar: yoneticiVarMi(liste, sifreler), kilitli: await kilitliMi(ctx)};
}

async function girisYap(ctx, {kurumId, kimlik, sifre: parola}) {
  const kurum = kurumDogrula(kurumId);
  const girilen = String(kimlik || '').trim();
  const s = String(parola || '');
  if (!girilen || !s) {
    throw new Hata(400, 'T.C. Kimlik No veya kullanıcı adınızı ve şifrenizi girin.');
  }
  const anahtar = denemeAnahtari(kurum, girilen);
  await kilitKontrol(ctx, anahtar);

  const liste = await kullanicilariOku(ctx, kurum);
  const sifreler = await sifreleriOku(ctx, kurum);
  const k = bul(liste, girilen);
  let sonuc = {ok: false, yukselt: false};
  if (k) {
    sonuc = await sifreKontrol(s, k, sifreler);
  } else {
    await sifre.olustur(s); // kayıt yokken de benzer süre harca
  }
  if (!sonuc.ok) {
    await hataKaydet(ctx, anahtar);
    throw new Hata(401, GENEL_GIRIS_HATASI);
  }
  await basariKaydet(ctx, anahtar);
  hesapDurumuKontrol(k);

  if (sonuc.yukselt && await kilitliMi(ctx)) await sifreYaz(ctx, kurum, k.uid, s);
  return oturumAc(ctx, kurum, k);
}

/** "Beni hatırla" açılışı: güncel profili ve taze yetki bilgili token'ı verir. */
async function ben(ctx, kimlikBilgisi, {kurumId}) {
  const kurum = kurumDogrula(kurumId);
  const liste = await kullanicilariOku(ctx, kurum);
  const k = liste.find((x) => x.uid === kimlikBilgisi.uid);
  if (!k) throw new Hata(404, 'Kullanıcı bulunamadı.');
  hesapDurumuKontrol(k);
  return oturumAc(ctx, kurum, k);
}

function sifreKurali(parola) {
  if (String(parola || '').length < 6) throw new Hata(400, 'Şifre en az 6 karakter olmalı.');
}

async function kilitliGerekli(ctx) {
  if (!(await kilitliMi(ctx))) {
    throw new Hata(409, 'Bu işlem geçiş tamamlanınca etkinleşir.');
  }
}

async function uyeOl(ctx, {kurumId, ad, kimlik, sifre: parola}) {
  const kurum = kurumDogrula(kurumId);
  await kilitliGerekli(ctx);
  const adTemiz = String(ad || '').trim();
  const tc = String(kimlik || '').trim();
  if (adTemiz.length < 3) throw new Hata(400, 'Ad soyad girin.');
  if (!tcGecerli(tc)) throw new Hata(400, 'Geçerli bir 11 haneli T.C. Kimlik No girin.');
  sifreKurali(parola);
  const kayit = await sifre.olustur(parola);

  await ctx.db.runTransaction(async (tx) => {
    const liste = await kullanicilariOku(ctx, kurum, tx);
    const sifreler = await sifreleriOku(ctx, kurum, tx);
    if (liste.some((k) => k.kimlik === tc)) {
      throw new Hata(409, 'Bu T.C. Kimlik No zaten kayıtlı.');
    }
    const uid = yeniUid();
    liste.push({
      uid, ad: adTemiz, eposta: '', rol: 'izleyici', kurumId: kurum, aktif: true,
      pin: '', sadecePdf: false, kisitliBirim: '', yoneticiProfili: '',
      kimlik: tc, kullaniciAdi: '', sifreHash: '', onayli: false,
    });
    sifreler[uid] = kayit;
    kullanicilariYaz(ctx, tx, kurum, liste);
    sifreleriYaz(ctx, tx, kurum, sifreler);
  });
  return {tamam: true};
}

async function yoneticiOlustur(ctx, {kurumId, ad, kimlik, sifre: parola}) {
  const kurum = kurumDogrula(kurumId);
  await kilitliGerekli(ctx);
  const adTemiz = String(ad || '').trim();
  const tc = String(kimlik || '').trim();
  if (adTemiz.length < 3) throw new Hata(400, 'Ad soyad girin.');
  if (!tcGecerli(tc)) throw new Hata(400, 'Geçerli bir 11 haneli T.C. Kimlik No girin.');
  sifreKurali(parola);
  const kayit = await sifre.olustur(parola);

  let olusan;
  await ctx.db.runTransaction(async (tx) => {
    const liste = await kullanicilariOku(ctx, kurum, tx);
    const sifreler = await sifreleriOku(ctx, kurum, tx);
    if (yoneticiVarMi(liste, sifreler)) {
      throw new Hata(409, 'Yönetici hesabı zaten oluşturulmuş.');
    }
    // İlk açılışta servis kimliksiz varsayılan bir "Yönetici" yaratır; varsa yükselt.
    const bos = liste.find((k) => etkinAlanlar(k).rol === 'yonetici' && !k.kimlik);
    if (bos) {
      Object.assign(bos, {ad: adTemiz, kimlik: tc, onayli: true, sifreHash: ''});
      olusan = bos;
    } else {
      olusan = {
        uid: yeniUid(), ad: adTemiz, eposta: '', rol: 'yonetici', kurumId: kurum,
        aktif: true, pin: '', sadecePdf: false, kisitliBirim: '',
        yoneticiProfili: 'superAdmin', kimlik: tc, kullaniciAdi: '', sifreHash: '',
        onayli: true,
      };
      liste.push(olusan);
    }
    sifreler[olusan.uid] = kayit;
    kullanicilariYaz(ctx, tx, kurum, liste);
    sifreleriYaz(ctx, tx, kurum, sifreler);
  });
  return oturumAc(ctx, kurum, olusan);
}

/**
 * ID token'ı olmayan tek seferlik işlemler (geçiş betiği) için: kimlik + şifre
 * ile yönetici doğrular. Giriş ile aynı yoldan geçtiği için hız sınırı ve
 * hesap durumu kontrolleri de uygulanır.
 */
async function yoneticiyiDogrula(ctx, {kurumId, kimlik, sifre: parola}) {
  const sonuc = await girisYap(ctx, {kurumId, kimlik, sifre: parola});
  if (etkinAlanlar(sonuc.kullanici).rol !== 'yonetici') {
    throw new Hata(403, 'Bu işlem için yönetici yetkisi gerekir.');
  }
  return {uid: sonuc.kullanici.uid, rol: 'yonetici'};
}

function yoneticiGerekli(kimlikBilgisi) {
  if (kimlikBilgisi.rol !== 'yonetici') throw new Hata(403, 'Bu işlem için yönetici yetkisi gerekir.');
}

async function sifreAyarla(ctx, kimlikBilgisi, {kurumId, uid, sifre: parola}) {
  const kurum = kurumDogrula(kurumId);
  yoneticiGerekli(kimlikBilgisi);
  await kilitliGerekli(ctx);
  sifreKurali(parola);
  const kayit = await sifre.olustur(parola);

  await ctx.db.runTransaction(async (tx) => {
    const liste = await kullanicilariOku(ctx, kurum, tx);
    const sifreler = await sifreleriOku(ctx, kurum, tx);
    const k = liste.find((x) => x.uid === uid);
    if (!k) throw new Hata(404, 'Kullanıcı bulunamadı.');
    sifreler[uid] = kayit;
    sifreleriYaz(ctx, tx, kurum, sifreler);
    if (k.sifreHash) {
      k.sifreHash = '';
      kullanicilariYaz(ctx, tx, kurum, liste);
    }
  });
  return {tamam: true};
}

/**
 * Tek seferlik geçiş: SHA-256 özetlerini gizli depoya taşır, kullanıcı
 * kayıtlarından siler ve `kilitli` bayrağını açar. Önce kullanıcı listesinin
 * yedeğini alır; tekrar çalıştırmak zararsızdır.
 */
async function sifreleriTasi(ctx, kimlikBilgisi, {kurumId}) {
  const kurum = kurumDogrula(kurumId);
  yoneticiGerekli(kimlikBilgisi);

  let tasinan = 0;
  await ctx.db.runTransaction(async (tx) => {
    const kaynak = await tx.get(ref(ctx.db, KOL, `kullanicilar_${kurum}`));
    const liste = jsonCoz(kaynak, [], `kullanicilar_${kurum}`);
    const sifreler = await sifreleriOku(ctx, kurum, tx);

    if (kaynak.exists) {
      tx.set(ref(ctx.db, GIZLI, `yedek_kullanicilar_${kurum}_${ctx.simdi()}`),
        {j: (kaynak.data() || {}).j || '[]'});
    }
    for (const k of liste) {
      if (!k.sifreHash) continue;
      sifreler[k.uid] = {algo: 'sha256', hash: k.sifreHash};
      k.sifreHash = '';
      tasinan += 1;
    }
    if (kaynak.exists) kullanicilariYaz(ctx, tx, kurum, liste);
    sifreleriYaz(ctx, tx, kurum, sifreler);
    tx.set(ref(ctx.db, GIZLI, 'ayar'), {kilitli: true}, {merge: true});
  });
  return {tasinan, kilitli: true};
}

module.exports = {
  Hata, durum, girisYap, ben, uyeOl, yoneticiOlustur, sifreAyarla, sifreleriTasi,
  yoneticiyiDogrula,
  // testler için
  etkinAlanlar, acikProfil, DENEME_SINIRI,
};
