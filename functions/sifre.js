'use strict';

// Şifre özetleme ve doğrulama.
//
// İki biçim vardır:
//  - 'sha256': eski uygulamanın tuzsuz SHA-256 özeti (yalnızca geçiş için;
//    doğru şifreyle girilince otomatik 'scrypt'e yükseltilir).
//  - 'scrypt': tuzlu, yavaş özet (yeni kayıtlar).

const crypto = require('crypto');

const SCRYPT = {N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024};
const ANAHTAR_UZUNLUGU = 64;

/** Dart tarafındaki Kimlik.sifreOzeti ile aynı: sha256(utf8(sifre)) hex. */
function sha256Ozeti(sifre) {
  return crypto.createHash('sha256').update(String(sifre), 'utf8').digest('hex');
}

function scryptOzeti(sifre, tuz) {
  return new Promise((coz, reddet) => {
    crypto.scrypt(String(sifre), tuz, ANAHTAR_UZUNLUGU, SCRYPT, (hata, anahtar) =>
      hata ? reddet(hata) : coz(anahtar));
  });
}

/** Yeni şifre için saklanacak kayıt. */
async function olustur(sifre) {
  const tuz = crypto.randomBytes(16);
  const anahtar = await scryptOzeti(sifre, tuz);
  return {algo: 'scrypt', tuz: tuz.toString('hex'), hash: anahtar.toString('hex')};
}

function esitMi(a, b) {
  const x = Buffer.from(String(a), 'utf8');
  const y = Buffer.from(String(b), 'utf8');
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

/** Girilen şifre [kayit] ile eşleşiyor mu? Kayıt yoksa/bozuksa false. */
async function dogrula(sifre, kayit) {
  if (!kayit || typeof kayit !== 'object' || !kayit.hash) return false;
  if (kayit.algo === 'sha256') return esitMi(sha256Ozeti(sifre), kayit.hash);
  if (kayit.algo === 'scrypt' && kayit.tuz) {
    const anahtar = await scryptOzeti(sifre, Buffer.from(kayit.tuz, 'hex'));
    return esitMi(anahtar.toString('hex'), kayit.hash);
  }
  return false;
}

module.exports = {sha256Ozeti, olustur, dogrula, esitMi};
