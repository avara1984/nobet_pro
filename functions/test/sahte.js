'use strict';

// Testler için bellekte çalışan sahte Firestore ve Auth.
// Transaction yazmaları, işlem hatasız bitince uygulanır (hata = geri alma).

function sahteBaglam(baslangic = {}) {
  const depo = new Map(Object.entries(baslangic));
  const simdi = {t: 1_700_000_000_000};

  const goruntu = (yol) => ({
    exists: depo.has(yol),
    data: () => (depo.has(yol) ? structuredClone(depo.get(yol)) : undefined),
  });
  const yaz = (yol, v, secenek) => {
    const onceki = secenek && secenek.merge ? depo.get(yol) || {} : {};
    depo.set(yol, {...onceki, ...structuredClone(v)});
  };
  const doc = (kol, id) => {
    const yol = `${kol}/${id}`;
    return {
      yol,
      get: async () => goruntu(yol),
      set: async (v, s) => yaz(yol, v, s),
      delete: async () => { depo.delete(yol); },
    };
  };

  const db = {
    collection: (kol) => ({
      doc: (id) => doc(kol, id),
      get: async () => ({
        docs: [...depo.keys()]
          .filter((y) => y.startsWith(`${kol}/`))
          .map((y) => {
            const id = y.slice(kol.length + 1);
            return {id, data: () => structuredClone(depo.get(y)), ref: doc(kol, id)};
          }),
      }),
    }),
    batch: () => {
      const islemler = [];
      return {
        set: (r, v, s) => { islemler.push(() => yaz(r.yol, v, s)); },
        delete: (r) => { islemler.push(() => depo.delete(r.yol)); },
        commit: async () => { islemler.forEach((f) => f()); },
      };
    },
    runTransaction: async (fn) => {
      const yazmalar = [];
      const tx = {
        get: async (r) => goruntu(r.yol),
        set: (r, v, s) => { yazmalar.push(() => yaz(r.yol, v, s)); },
        delete: (r) => { yazmalar.push(() => depo.delete(r.yol)); },
      };
      const sonuc = await fn(tx);
      yazmalar.forEach((f) => f());
      return sonuc;
    },
  };
  const auth = {
    son: null,
    iptal: [],
    revokeRefreshTokens: async (uid) => { auth.iptal.push(uid); },
    createCustomToken: async (uid, claims) => {
      auth.son = {uid, claims};
      return `token:${uid}`;
    },
  };
  return {
    ctx: {db, auth, simdi: () => simdi.t},
    depo,
    ilerlet: (ms) => { simdi.t += ms; },
    /** nobet_pro/kullanicilar_<kurum> içeriği (JSON çözülmüş). */
    kullanicilar: (kurum = 'varsayilan') =>
      JSON.parse(depo.get(`nobet_pro/kullanicilar_${kurum}`).j),
    sifreler: (kurum = 'varsayilan') => {
      const d = depo.get(`nobet_gizli/sifreler_${kurum}`);
      return d ? JSON.parse(d.j) : {};
    },
  };
}

function kullaniciYaz(liste, kurum = 'varsayilan') {
  return {[`nobet_pro/kullanicilar_${kurum}`]: {j: JSON.stringify(liste)}};
}

module.exports = {sahteBaglam, kullaniciYaz};
