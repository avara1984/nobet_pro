'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const c = require('../cekirdek');
const {sahteBaglam, kullaniciYaz} = require('./sahte');

const KURUM = 'varsayilan';
const YONETICI = {uid: 'admin', rol: 'yonetici'};
const PERSONEL = {uid: 'veli', rol: 'izleyici'};

async function hataDurumu(vaat) {
  try {
    await vaat;
  } catch (e) {
    assert.ok(e instanceof c.Hata, `beklenmeyen hata: ${e && e.stack}`);
    return e;
  }
  assert.fail('hata bekleniyordu');
}

function kurumBelgesi(ek = {}) {
  return {'nobet_pro/kurum_varsayilan': {j: JSON.stringify({ad: 'Hastane', ...ek})}};
}

// --- Onay Kodu ---------------------------------------------------------------

test('onay kodu: hiçbir şey tanımlı değilse varsayılan 0000 geçerli', async () => {
  const s = sahteBaglam(kurumBelgesi());
  assert.deepEqual(await c.onayKodu(s.ctx, PERSONEL, {kurumId: KURUM, kod: '0000'}), {dogru: true});
  assert.deepEqual(await c.onayKodu(s.ctx, PERSONEL, {kurumId: KURUM, kod: '1234'}), {dogru: false});
});

test('onay kodu: taşınmamış eski kurulumda kurum ayarındaki kod okunur', async () => {
  const s = sahteBaglam(kurumBelgesi({onayKodu: '4821'}));
  assert.equal((await c.onayKodu(s.ctx, PERSONEL, {kurumId: KURUM, kod: '4821'})).dogru, true);
  assert.equal((await c.onayKodu(s.ctx, PERSONEL, {kurumId: KURUM, kod: '0000'})).dogru, false);
});

test('onay kodu: gizli kayıt varsa o geçerlidir, kurum ayarına bakılmaz', async () => {
  const s = sahteBaglam({...kurumBelgesi({onayKodu: '4821'}), 'nobet_gizli/onay_varsayilan': {kod: '7777'}});
  assert.equal((await c.onayKodu(s.ctx, PERSONEL, {kurumId: KURUM, kod: '7777'})).dogru, true);
  assert.equal((await c.onayKodu(s.ctx, PERSONEL, {kurumId: KURUM, kod: '4821'})).dogru, false);
});

test('onay kodu: 5 yanlış denemeden sonra doğru kod bile kilitlenir, süre dolunca açılır', async () => {
  const s = sahteBaglam({'nobet_gizli/onay_varsayilan': {kod: '7777'}});
  for (let i = 0; i < c.DENEME_SINIRI; i++) {
    assert.equal((await c.onayKodu(s.ctx, PERSONEL, {kurumId: KURUM, kod: '0001'})).dogru, false);
  }
  assert.equal((await hataDurumu(c.onayKodu(s.ctx, PERSONEL, {kurumId: KURUM, kod: '7777'}))).durum, 429);
  // Başka kullanıcının sayacı bağımsızdır.
  assert.equal((await c.onayKodu(s.ctx, {uid: 'baska'}, {kurumId: KURUM, kod: '7777'})).dogru, true);
  s.ilerlet(16 * 60 * 1000);
  assert.equal((await c.onayKodu(s.ctx, PERSONEL, {kurumId: KURUM, kod: '7777'})).dogru, true);
});

test('onay kodu ayarla: yalnızca yönetici, 4 karakter ya da boş', async () => {
  const s = sahteBaglam({});
  const istek = {kurumId: KURUM, kod: '5555'};
  assert.equal((await hataDurumu(c.onayKoduAyarla(s.ctx, PERSONEL, istek))).durum, 403);
  assert.equal((await hataDurumu(c.onayKoduAyarla(s.ctx, YONETICI, {...istek, kod: '12'}))).durum, 400);
  assert.equal((await hataDurumu(c.onayKoduAyarla(s.ctx, YONETICI, {...istek, kod: '12 4'}))).durum, 400);

  await c.onayKoduAyarla(s.ctx, YONETICI, istek);
  assert.equal(await c.gecerliOnayKodu(s.ctx, KURUM), '5555');
  await c.onayKoduAyarla(s.ctx, YONETICI, {kurumId: KURUM, kod: ''}); // özel kod yok
  assert.equal(await c.gecerliOnayKodu(s.ctx, KURUM), '0000');
});

// --- Oturum engelleme --------------------------------------------------------

const kisi = (uid, ek = {}) => ({uid, aktif: true, onayli: true, ...ek});

test('engel: pasif, onaysız ve silinen engellenir; aktif olanlar engellenmez', () => {
  const sonuc = c.engelHesapla(
    [kisi('a'), kisi('b'), kisi('c'), kisi('d')],
    [kisi('a'), kisi('b', {aktif: false}), kisi('c', {onayli: false})]);
  assert.deepEqual(sonuc.engelli.sort(), ['b', 'c', 'd']);
  assert.deepEqual(sonuc.aktif, ['a']);
});

test('engel listesi: yeni engellenenin oturumu iptal edilir, tekrar çağrı çift iptal etmez', async () => {
  const s = sahteBaglam({});
  const onceki = [kisi('a'), kisi('b')];
  const yeniler = await c.engelleriGuncelle(s.ctx, onceki, [kisi('a'), kisi('b', {aktif: false})]);
  assert.deepEqual(yeniler, ['b']);
  assert.deepEqual(s.ctx.auth.iptal, ['b']);
  assert.deepEqual(JSON.parse(JSON.stringify(s.depo.get('nobet_gizli/engelli'))), {uidler: {b: true}});

  await c.engelleriGuncelle(s.ctx, onceki, [kisi('a'), kisi('b', {aktif: false})]);
  assert.deepEqual(s.ctx.auth.iptal, ['b'], 'zaten engelli olan için yeniden iptal yok');
});

test('engel listesi: yeniden aktifleştirilen listeden çıkar', async () => {
  const s = sahteBaglam({});
  await c.engelleriGuncelle(s.ctx, [], [kisi('a', {aktif: false}), kisi('b')]);
  assert.deepEqual(s.depo.get('nobet_gizli/engelli').uidler, {a: true});
  await c.engelleriGuncelle(s.ctx, [], [kisi('a'), kisi('b')]);
  assert.deepEqual(s.depo.get('nobet_gizli/engelli').uidler, {});
});

test('engel listesi: Firebase oturumu olmayan uid için iptal hatası yutulur', async () => {
  const s = sahteBaglam({});
  s.ctx.auth.revokeRefreshTokens = async () => { throw new Error('auth/user-not-found'); };
  const yeniler = await c.engelleriGuncelle(s.ctx, [], [kisi('x', {aktif: false})]);
  assert.deepEqual(yeniler, ['x']);
  assert.deepEqual(s.depo.get('nobet_gizli/engelli').uidler, {x: true});
});

// --- Veri taşıma -------------------------------------------------------------

function bordroluDepo() {
  return sahteBaglam({
    ...kurumBelgesi({onayKodu: '4821'}),
    ...kullaniciYaz([kisi('admin'), kisi('pasif', {aktif: false})]),
    'nobet_pro/nobet_varsayilan#guvenlik_2026-07': {j: '{"atamalar":{}}'},
    'nobet_pro/bordro_varsayilan#guvenlik_p1_2026-07': {j: '{"brut":1}'},
    'nobet_pro/bordro_pdf_varsayilan#guvenlik_p1_2026-07': {j: '{"pdfBase64":"AAAA"}'},
    'nobet_pro/bordro_ayari_2026': {j: '{"yil":2026}'},
    'nobet_pro/ucretler_varsayilan#guvenlik': {j: '[{"personelId":"p1"}]'},
  });
}

test('taşıma / kopyala: bordro belgeleri yeni koleksiyona geçer, eskiler yerinde kalır', async () => {
  const s = bordroluDepo();
  const sonuc = await c.bordroVeOnayTasi(s.ctx, YONETICI, {kurumId: KURUM, adim: 'kopyala'});
  assert.equal(sonuc.kopyalanan, 4);
  for (const id of ['bordro_varsayilan#guvenlik_p1_2026-07',
    'bordro_pdf_varsayilan#guvenlik_p1_2026-07', 'bordro_ayari_2026',
    'ucretler_varsayilan#guvenlik']) {
    assert.ok(s.depo.has(`nobet_bordro/${id}`), `nobet_bordro/${id} bekleniyordu`);
    assert.ok(s.depo.has(`nobet_pro/${id}`), 'kopyada eski belge silinmemeli');
  }
  assert.ok(!s.depo.has('nobet_bordro/nobet_varsayilan#guvenlik_2026-07'), 'nöbet listesi taşınmaz');
  assert.deepEqual(s.depo.get('nobet_gizli/onay_varsayilan'), {kod: '4821'});
});

test('taşıma: yalnızca yönetici, geçerli adım', async () => {
  const s = bordroluDepo();
  assert.equal((await hataDurumu(c.bordroVeOnayTasi(s.ctx, PERSONEL, {kurumId: KURUM, adim: 'kopyala'}))).durum, 403);
  assert.equal((await hataDurumu(c.bordroVeOnayTasi(s.ctx, YONETICI, {kurumId: KURUM, adim: 'sil'}))).durum, 400);
});

test('taşıma / temizle: kopyalanmadan silmeyi reddeder', async () => {
  const s = bordroluDepo();
  const e = await hataDurumu(c.bordroVeOnayTasi(s.ctx, YONETICI, {kurumId: KURUM, adim: 'temizle'}));
  assert.equal(e.durum, 409);
  assert.ok(s.depo.has('nobet_pro/bordro_ayari_2026'), 'hiçbir şey silinmemeli');
});

test('taşıma / temizle: içerik farklıysa silmez', async () => {
  const s = bordroluDepo();
  await c.bordroVeOnayTasi(s.ctx, YONETICI, {kurumId: KURUM, adim: 'kopyala'});
  s.depo.set('nobet_pro/bordro_ayari_2026', {j: '{"yil":2026,"yeni":true}'}); // kopyadan sonra değişti
  const e = await hataDurumu(c.bordroVeOnayTasi(s.ctx, YONETICI, {kurumId: KURUM, adim: 'temizle'}));
  assert.equal(e.durum, 409);
  assert.match(e.message, /bordro_ayari_2026/);
  assert.ok(s.depo.has('nobet_pro/bordro_varsayilan#guvenlik_p1_2026-07'), 'hiçbir şey silinmemeli');
});

test('taşıma / temizle: eskiler silinir, onay kodu ayardan çıkar, engel listesi tohumlanır', async () => {
  const s = bordroluDepo();
  await c.bordroVeOnayTasi(s.ctx, YONETICI, {kurumId: KURUM, adim: 'kopyala'});
  const sonuc = await c.bordroVeOnayTasi(s.ctx, YONETICI, {kurumId: KURUM, adim: 'temizle'});

  assert.equal(sonuc.silinen, 4);
  assert.ok(![...s.depo.keys()].some((k) => k.startsWith('nobet_pro/bordro_') || k.startsWith('nobet_pro/ucretler_')));
  assert.ok(s.depo.has('nobet_pro/nobet_varsayilan#guvenlik_2026-07'), 'nöbet listesine dokunulmaz');
  assert.equal([...s.depo.keys()].filter((k) => k.startsWith('nobet_bordro/')).length, 4,
    'yeni koleksiyonda 4 belge kalmalı');

  const kurum = JSON.parse(s.depo.get('nobet_pro/kurum_varsayilan').j);
  assert.equal('onayKodu' in kurum, false, 'kod kurum ayarından çıkmalı');
  assert.equal(kurum.ad, 'Hastane', 'diğer ayarlar korunmalı');
  assert.equal(await c.gecerliOnayKodu(s.ctx, KURUM), '4821', 'kod gizli depoda korunmalı');
  assert.deepEqual(s.depo.get('nobet_gizli/engelli').uidler, {pasif: true});

  // Tekrar çalıştırmak zararsız.
  const tekrar = await c.bordroVeOnayTasi(s.ctx, YONETICI, {kurumId: KURUM, adim: 'temizle'});
  assert.equal(tekrar.silinen, 0);
});
