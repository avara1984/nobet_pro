'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const c = require('../cekirdek');
const sifre = require('../sifre');
const {sahteBaglam, kullaniciYaz} = require('./sahte');

const KURUM = 'varsayilan';
const TC_ALI = '12345678901';
const TC_VELI = '10987654321';

function kisi(uid, ek = {}) {
  return {
    uid, ad: uid, eposta: '', rol: 'izleyici', kurumId: KURUM, aktif: true, pin: '',
    sadecePdf: false, kisitliBirim: '', yoneticiProfili: '', kimlik: '',
    kullaniciAdi: '', sifreHash: '', onayli: true, ...ek,
  };
}

/** Eski biçimde (sifreHash dolu) iki kullanıcı: bir süper admin, bir personel. */
function eskiKurulum(ek = {}) {
  return sahteBaglam({
    ...kullaniciYaz([
      kisi('admin', {
        ad: 'Ali Yönetici', rol: 'yonetici', yoneticiProfili: 'superAdmin',
        kimlik: TC_ALI, kullaniciAdi: 'ali', sifreHash: sifre.sha256Ozeti('sifre123'),
      }),
      kisi('veli', {
        ad: 'Veli Personel', kimlik: TC_VELI, sifreHash: sifre.sha256Ozeti('veli1234'),
      }),
    ]),
    ...ek,
  });
}

const giris = (s, kimlik, parola) =>
  c.girisYap(s.ctx, {kurumId: KURUM, kimlik, sifre: parola});

async function hataDurumu(vaat) {
  try {
    await vaat;
  } catch (e) {
    assert.ok(e instanceof c.Hata, `beklenmeyen hata: ${e && e.stack}`);
    return e;
  }
  assert.fail('hata bekleniyordu');
}

// --- yetkiler ----------------------------------------------------------------

test('profil yetkileri istemcideki tabloyla aynı', () => {
  assert.deepEqual(c.etkinAlanlar({yoneticiProfili: 'superAdmin'}),
    {rol: 'yonetici', sadecePdf: false, kisitliBirim: '', bordro: true});
  assert.deepEqual(c.etkinAlanlar({yoneticiProfili: 'temizlikNobet', rol: 'yonetici'}),
    {rol: 'editor', sadecePdf: false, kisitliBirim: 'temizlik', bordro: false});
  assert.deepEqual(c.etkinAlanlar({yoneticiProfili: 'bordro'}),
    {rol: 'editor', sadecePdf: true, kisitliBirim: '', bordro: true});
  // Profilsiz eski kayıtlar
  assert.equal(c.etkinAlanlar({rol: 'yonetici'}).bordro, true);
  assert.equal(c.etkinAlanlar({rol: 'yonetici', sadecePdf: true}).bordro, false);
  assert.equal(c.etkinAlanlar({rol: 'editor'}).bordro, false);
  assert.equal(c.etkinAlanlar({rol: 'saçma'}).rol, 'izleyici');
});

// --- giriş -------------------------------------------------------------------

test('eski SHA-256 şifresiyle giriş: token + şifresiz profil, kayıt değişmez', async () => {
  const s = eskiKurulum();
  const sonuc = await giris(s, TC_ALI, 'sifre123');
  assert.equal(sonuc.token, 'token:admin');
  assert.equal(sonuc.kullanici.sifreHash, '');
  assert.deepEqual(s.ctx.auth.son.claims, {
    nobet: true, kurumId: KURUM, rol: 'yonetici', bordro: true, sadecePdf: false,
    kisitliBirim: '',
  });
  // Geçiş bitmedi (kilitli değil): eski istemciler için kayıt aynen kalmalı.
  assert.equal(s.kullanicilar()[0].sifreHash, sifre.sha256Ozeti('sifre123'));
  assert.deepEqual(s.sifreler(), {});
});

test('kullanıcı adıyla giriş (büyük/küçük harf fark etmez)', async () => {
  const s = eskiKurulum();
  assert.equal((await giris(s, 'ALİ'.replace('İ', 'i'), 'sifre123')).token, 'token:admin');
});

test('yanlış şifre ile kayıtsız kullanıcı aynı hatayı alır', async () => {
  const s = eskiKurulum();
  const a = await hataDurumu(giris(s, TC_ALI, 'yanlis'));
  const b = await hataDurumu(giris(s, '55555555555', 'yanlis'));
  assert.equal(a.durum, 401);
  assert.equal(b.durum, 401);
  assert.equal(a.message, b.message);
});

test('5 hatalı denemeden sonra doğru şifre bile kilitlenir, süre dolunca açılır', async () => {
  const s = eskiKurulum();
  for (let i = 0; i < c.DENEME_SINIRI; i++) {
    assert.equal((await hataDurumu(giris(s, TC_ALI, 'yanlis'))).durum, 401);
  }
  const kilit = await hataDurumu(giris(s, TC_ALI, 'sifre123'));
  assert.equal(kilit.durum, 429);

  s.ilerlet(16 * 60 * 1000);
  assert.equal((await giris(s, TC_ALI, 'sifre123')).token, 'token:admin');
});

test('başarılı giriş hatalı deneme sayacını sıfırlar', async () => {
  const s = eskiKurulum();
  for (let i = 0; i < c.DENEME_SINIRI - 1; i++) {
    await hataDurumu(giris(s, TC_ALI, 'yanlis'));
  }
  await giris(s, TC_ALI, 'sifre123');
  for (let i = 0; i < c.DENEME_SINIRI - 1; i++) {
    assert.equal((await hataDurumu(giris(s, TC_ALI, 'yanlis'))).durum, 401);
  }
});

test('onaysız ve pasif hesap doğru şifreyle bile girmez', async () => {
  const s = sahteBaglam(kullaniciYaz([
    kisi('a', {kimlik: TC_ALI, sifreHash: sifre.sha256Ozeti('abcdef'), onayli: false}),
    kisi('b', {kimlik: TC_VELI, sifreHash: sifre.sha256Ozeti('abcdef'), aktif: false}),
  ]));
  const a = await hataDurumu(giris(s, TC_ALI, 'abcdef'));
  const b = await hataDurumu(giris(s, TC_VELI, 'abcdef'));
  assert.equal(a.durum, 403);
  assert.match(a.message, /onay/);
  assert.equal(b.durum, 403);
  assert.match(b.message, /pasif/);
  assert.equal(s.ctx.auth.son, null, 'token üretilmemeli');
});

test('bozuk kullanıcı kaydı hata verir, kimseyi içeri almaz', async () => {
  const s = sahteBaglam({'nobet_pro/kullanicilar_varsayilan': {j: '{bozuk'}});
  assert.equal((await hataDurumu(giris(s, TC_ALI, 'x'))).durum, 500);
});

// --- geçiş (kilitleme) -------------------------------------------------------

test('geçiş: özetler gizli depoya taşınır, kayıttan silinir, yedek alınır', async () => {
  const s = eskiKurulum();
  const sonuc = await c.sifreleriTasi(s.ctx, {rol: 'yonetici'}, {kurumId: KURUM});
  assert.deepEqual(sonuc, {tasinan: 2, kilitli: true});
  assert.ok(s.kullanicilar().every((k) => k.sifreHash === ''));
  assert.equal(s.sifreler().admin.algo, 'sha256');
  assert.equal(s.depo.get('nobet_gizli/ayar').kilitli, true);
  const yedekler = [...s.depo.keys()].filter((k) => k.startsWith('nobet_gizli/yedek_kullanicilar_'));
  assert.equal(yedekler.length, 1);
  assert.match(JSON.parse(s.depo.get(yedekler[0]).j)[0].sifreHash, /^[0-9a-f]{64}$/,
    'yedekte eski özet bulunmalı (geri dönüş için)');
});

test('geçiş yalnızca yöneticiye açık ve tekrar çalıştırılabilir', async () => {
  const s = eskiKurulum();
  assert.equal((await hataDurumu(c.sifreleriTasi(s.ctx, {rol: 'editor'}, {kurumId: KURUM}))).durum, 403);
  await c.sifreleriTasi(s.ctx, {rol: 'yonetici'}, {kurumId: KURUM});
  const ikinci = await c.sifreleriTasi(s.ctx, {rol: 'yonetici'}, {kurumId: KURUM});
  assert.equal(ikinci.tasinan, 0);
  assert.equal(s.sifreler().admin.algo, 'sha256', 'ikinci çalıştırma kayıtları bozmaz');
});

test('geçişten sonra eski şifre geçer ve ilk girişte scrypt\'e yükseltilir', async () => {
  const s = eskiKurulum();
  await c.sifreleriTasi(s.ctx, {rol: 'yonetici'}, {kurumId: KURUM});

  assert.equal((await hataDurumu(giris(s, TC_ALI, 'yanlis'))).durum, 401);
  assert.equal((await giris(s, TC_ALI, 'sifre123')).token, 'token:admin');
  assert.equal(s.sifreler().admin.algo, 'scrypt');
  assert.equal(s.sifreler().veli.algo, 'sha256', 'girmeyen kullanıcı dokunulmaz');

  // Yükseltilmiş kayıtla yine girer, yanlış şifre yine girmez.
  assert.equal((await giris(s, TC_ALI, 'sifre123')).token, 'token:admin');
  assert.equal((await hataDurumu(giris(s, TC_ALI, 'yanlis'))).durum, 401);
});

test('durum: geçişten önce/sonra', async () => {
  const s = eskiKurulum();
  assert.deepEqual(await c.durum(s.ctx, {kurumId: KURUM}), {yoneticiVar: true, kilitli: false});
  await c.sifreleriTasi(s.ctx, {rol: 'yonetici'}, {kurumId: KURUM});
  assert.deepEqual(await c.durum(s.ctx, {kurumId: KURUM}), {yoneticiVar: true, kilitli: true});
});

// --- kayıt / kurulum / şifre -------------------------------------------------

test('üye ol ve ilk kurulum geçiş bitmeden kapalı', async () => {
  const s = eskiKurulum();
  const uye = await hataDurumu(c.uyeOl(s.ctx,
    {kurumId: KURUM, ad: 'Yeni Kişi', kimlik: '23456789012', sifre: 'abcdef'}));
  assert.equal(uye.durum, 409);
  const yon = await hataDurumu(c.yoneticiOlustur(s.ctx,
    {kurumId: KURUM, ad: 'Yeni Kişi', kimlik: '23456789012', sifre: 'abcdef'}));
  assert.equal(yon.durum, 409);
});

test('üye ol: onaysız kayıt oluşur, yönetici onaylayınca girer; TC çakışması reddedilir', async () => {
  const s = eskiKurulum();
  await c.sifreleriTasi(s.ctx, {rol: 'yonetici'}, {kurumId: KURUM});
  const kayit = {kurumId: KURUM, ad: 'Yeni Kişi', kimlik: '23456789012', sifre: 'abcdef'};
  await c.uyeOl(s.ctx, kayit);

  const yeni = s.kullanicilar().find((k) => k.kimlik === '23456789012');
  assert.equal(yeni.onayli, false);
  assert.equal(yeni.sifreHash, '', 'kullanıcı kaydında özet bulunmaz');
  assert.equal(s.sifreler()[yeni.uid].algo, 'scrypt');

  assert.match((await hataDurumu(giris(s, '23456789012', 'abcdef'))).message, /onay/);
  assert.equal((await hataDurumu(c.uyeOl(s.ctx, kayit))).durum, 409);
  assert.equal((await hataDurumu(c.uyeOl(s.ctx, {...kayit, kimlik: '123'}))).durum, 400);
  assert.equal((await hataDurumu(c.uyeOl(s.ctx, {...kayit, kimlik: '34567890123', sifre: '123'}))).durum, 400);

  const liste = s.kullanicilar();
  liste.find((k) => k.uid === yeni.uid).onayli = true;
  s.depo.set('nobet_pro/kullanicilar_varsayilan', {j: JSON.stringify(liste)});
  assert.equal((await giris(s, '23456789012', 'abcdef')).token, `token:${yeni.uid}`);
});

test('ilk kurulum: boş varsayılan yönetici yükseltilir, ikinci kez yapılamaz', async () => {
  const s = sahteBaglam(kullaniciYaz([kisi('yonetici', {ad: 'Yönetici', rol: 'yonetici'})]));
  s.depo.set('nobet_gizli/ayar', {kilitli: true});
  assert.deepEqual(await c.durum(s.ctx, {kurumId: KURUM}), {yoneticiVar: false, kilitli: true});

  const sonuc = await c.yoneticiOlustur(s.ctx,
    {kurumId: KURUM, ad: 'Ayşe Yönetici', kimlik: TC_ALI, sifre: 'sifre123'});
  assert.equal(sonuc.token, 'token:yonetici');
  assert.equal(s.kullanicilar().length, 1, 'mükerrer kayıt oluşmamalı');
  assert.equal(s.kullanicilar()[0].onayli, true);

  assert.equal((await hataDurumu(c.yoneticiOlustur(s.ctx,
    {kurumId: KURUM, ad: 'Başka Biri', kimlik: TC_VELI, sifre: 'sifre123'}))).durum, 409);
  assert.equal((await giris(s, TC_ALI, 'sifre123')).token, 'token:yonetici');
});

test('şifre ayarla: yalnızca yönetici; eski şifre iptal olur', async () => {
  const s = eskiKurulum();
  await c.sifreleriTasi(s.ctx, {rol: 'yonetici'}, {kurumId: KURUM});
  const istek = {kurumId: KURUM, uid: 'veli', sifre: 'yenisifre'};

  assert.equal((await hataDurumu(c.sifreAyarla(s.ctx, {rol: 'editor'}, istek))).durum, 403);
  assert.equal((await hataDurumu(c.sifreAyarla(s.ctx, {rol: 'yonetici'}, {...istek, sifre: '123'}))).durum, 400);
  assert.equal((await hataDurumu(c.sifreAyarla(s.ctx, {rol: 'yonetici'}, {...istek, uid: 'yok'}))).durum, 404);

  await c.sifreAyarla(s.ctx, {rol: 'yonetici'}, istek);
  assert.equal(s.sifreler().veli.algo, 'scrypt');
  assert.equal((await hataDurumu(giris(s, TC_VELI, 'veli1234'))).durum, 401);
  assert.equal((await giris(s, TC_VELI, 'yenisifre')).token, 'token:veli');
});

// --- ben ---------------------------------------------------------------------

test('ben: güncel yetkiyle yeni token verir; pasifleşen girmez', async () => {
  const s = eskiKurulum();
  const sonuc = await c.ben(s.ctx, {uid: 'veli'}, {kurumId: KURUM});
  assert.equal(sonuc.token, 'token:veli');
  assert.equal(sonuc.kullanici.sifreHash, '');
  assert.equal(s.ctx.auth.son.claims.rol, 'izleyici');

  // Yönetici rolü değişince bir sonraki açılışta yeni claim alınır.
  const liste = s.kullanicilar();
  liste.find((k) => k.uid === 'veli').yoneticiProfili = 'bordro';
  s.depo.set('nobet_pro/kullanicilar_varsayilan', {j: JSON.stringify(liste)});
  await c.ben(s.ctx, {uid: 'veli'}, {kurumId: KURUM});
  assert.equal(s.ctx.auth.son.claims.bordro, true);
  assert.equal(s.ctx.auth.son.claims.sadecePdf, true);

  liste.find((k) => k.uid === 'veli').aktif = false;
  s.depo.set('nobet_pro/kullanicilar_varsayilan', {j: JSON.stringify(liste)});
  assert.equal((await hataDurumu(c.ben(s.ctx, {uid: 'veli'}, {kurumId: KURUM}))).durum, 403);
  assert.equal((await hataDurumu(c.ben(s.ctx, {uid: 'yok'}, {kurumId: KURUM}))).durum, 404);
});

test('geçersiz kurum kimliği reddedilir', async () => {
  const s = eskiKurulum();
  assert.equal((await hataDurumu(c.durum(s.ctx, {kurumId: '../x'}))).durum, 400);
  assert.equal((await hataDurumu(c.durum(s.ctx, {}))).durum, 400);
});
