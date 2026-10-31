'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const sifre = require('../sifre');

test('sha256 özeti Dart tarafındaki Kimlik.sifreOzeti ile aynı biçimde', () => {
  // sha256('abc') — bilinen test vektörü
  assert.equal(sifre.sha256Ozeti('abc'),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  // UTF-8: Türkçe karakterler bayt olarak özetlenir
  assert.equal(sifre.sha256Ozeti('şifre'),
    require('crypto').createHash('sha256').update(Buffer.from('şifre', 'utf8')).digest('hex'));
});

test('scrypt kaydı: doğru şifre geçer, yanlışı geçmez, tuz her seferinde farklı', async () => {
  const a = await sifre.olustur('gizli123');
  const b = await sifre.olustur('gizli123');
  assert.equal(a.algo, 'scrypt');
  assert.notEqual(a.tuz, b.tuz);
  assert.notEqual(a.hash, b.hash);
  assert.equal(await sifre.dogrula('gizli123', a), true);
  assert.equal(await sifre.dogrula('gizli124', a), false);
});

test('eski sha256 kaydı doğrulanır', async () => {
  const kayit = {algo: 'sha256', hash: sifre.sha256Ozeti('eski123')};
  assert.equal(await sifre.dogrula('eski123', kayit), true);
  assert.equal(await sifre.dogrula('yanlis', kayit), false);
});

test('bozuk veya boş kayıt asla doğrulamaz', async () => {
  assert.equal(await sifre.dogrula('x', null), false);
  assert.equal(await sifre.dogrula('x', {}), false);
  assert.equal(await sifre.dogrula('x', {algo: 'bilinmiyor', hash: 'a'}), false);
  assert.equal(await sifre.dogrula('x', {algo: 'scrypt', hash: 'a'}), false);
});
