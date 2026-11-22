// Coffre de notes : chiffré dans le navigateur (AES-256-GCM, clé tirée du code par PBKDF2),
// rangé dans notes.json du dépôt privé. Même format que l'appli du téléphone (lib/notes.dart).
import { app } from './store.svelte.js';

// Les courses ont leur propre liste, hors du coffre (courses.svelte.js).
export const NOTE_CATS = ['Mémos', 'Codes et adresses', 'Mots de passe', 'Jetons'];
export const NOTE_ICON = { Courses: '🛒', 'Codes et adresses': '📍', 'Mots de passe': '🔑', Jetons: '🎫', Mémos: '📝' };
const ITER = 150000;

const read = (k) => {
  try {
    return JSON.parse(localStorage.getItem(k));
  } catch {
    return null;
  }
};
const write = (k, v) => {
  try {
    if (v == null) localStorage.removeItem(k);
    else localStorage.setItem(k, JSON.stringify(v));
  } catch {}
};
const b64 = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const newId = () =>
  Array.from({ length: 8 }, () => 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 36)]).join('');

const empty = () => ({ v: 1, salt: null, iter: ITER, check: '', notes: [] });

export const vault = $state({
  file: read('bim.notes') ?? empty(), // le coffre chiffré, tel qu'il est sur GitHub
  open: {}, // id → note en clair (coffre ouvert seulement)
  unlocked: false,
  busy: false,
  sync: 'idle', // idle | sync | error
  error: '',
});
let key = null;

export const exists = () => !!vault.file.salt;
export const allNotes = () =>
  Object.values(vault.open).sort((a, b) =>
    a.pinned !== b.pinned ? (a.pinned ? -1 : 1) : a.title.toLowerCase().localeCompare(b.title.toLowerCase()),
  );
export const noteCats = () => {
  const extra = [...new Set(Object.values(vault.open).map((n) => n.cat))].filter((c) => !NOTE_CATS.includes(c)).sort();
  return [...NOTE_CATS, ...extra];
};

// ---- Chiffrement ----

async function derive(code, salt, iter) {
  const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(code), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', hash: 'SHA-256', salt: unb64(salt), iterations: iter },
    base,
    { name: 'AES-GCM', length: 256 },
    true,
    ['encrypt', 'decrypt'],
  );
}
async function enc(text, k = key) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, k, new TextEncoder().encode(text)));
  const out = new Uint8Array(12 + ct.length);
  out.set(iv);
  out.set(ct, 12);
  return b64(out);
}
async function dec(c, k = key) {
  const all = unb64(c);
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: all.slice(0, 12) }, k, all.slice(12));
  return new TextDecoder().decode(plain);
}
const valid = async (k) => {
  try {
    return (await dec(vault.file.check, k)) === 'bim';
  } catch {
    return false;
  }
};
async function decryptOne(r) {
  if (r.deleted) {
    delete vault.open[r.id];
    return;
  }
  try {
    const p = JSON.parse(await dec(r.c));
    vault.open[r.id] = {
      id: r.id, updatedAt: r.updatedAt, title: p.title ?? '', cat: p.cat ?? 'Mémos', body: p.body ?? '',
      secret: p.secret ?? '', pinned: p.pinned === true,
      items: (p.items ?? []).map((i) => ({ id: i.id ?? newId(), text: i.text ?? '', done: i.done === true })),
    };
  } catch {
    delete vault.open[r.id];
  }
}
async function decryptAll() {
  vault.open = {};
  for (const r of vault.file.notes) await decryptOne(r);
}
async function remember(k) {
  key = k;
  write('bim.notesKey', b64(await crypto.subtle.exportKey('raw', k)));
  vault.unlocked = true;
}

// ---- Créer, ouvrir, fermer ----

export async function createVault(code) {
  if (code.length < 6) return "Choisis un code d'au moins 6 caractères.";
  vault.busy = true;
  try {
    await syncNotes();
    if (vault.sync === 'error') return `Impossible de vérifier s'il existe déjà un coffre : ${vault.error}`;
    if (exists()) return 'Un coffre existe déjà sur un autre appareil : entre son code.';
    const salt = b64(crypto.getRandomValues(new Uint8Array(16)));
    const k = await derive(code, salt, ITER);
    vault.file = { v: 1, salt, iter: ITER, check: await enc('bim', k), notes: [] };
    vault.open = {};
    await remember(k);
    persist();
    syncNotes();
    return null;
  } finally {
    vault.busy = false;
  }
}

export async function unlock(code) {
  vault.busy = true;
  try {
    const k = await derive(code, vault.file.salt, vault.file.iter ?? ITER);
    if (!(await valid(k))) return "Ce n'est pas le bon code.";
    await remember(k);
    await decryptAll();
    return null;
  } finally {
    vault.busy = false;
  }
}

export function lock() {
  key = null;
  vault.open = {};
  vault.unlocked = false;
  write('bim.notesKey', null);
}

// ---- Modifier ----

const plainOf = (n) => ({
  title: n.title,
  cat: n.cat,
  ...(n.body ? { body: n.body } : {}),
  ...(n.secret ? { secret: n.secret } : {}),
  ...(n.pinned ? { pinned: true } : {}),
  ...(n.items?.length ? { items: n.items.map((i) => ({ id: i.id, text: i.text, ...(i.done ? { done: true } : {}) })) } : {}),
});
function put(rec) {
  const i = vault.file.notes.findIndex((r) => r.id === rec.id);
  if (i >= 0 && vault.file.notes[i].updatedAt > rec.updatedAt) return;
  if (i >= 0) vault.file.notes[i] = rec;
  else vault.file.notes.push(rec);
  changed();
}
export const newNote = (cat = 'Mémos') => ({ id: newId(), updatedAt: Date.now(), title: '', cat, body: '', secret: '', pinned: false, items: [] });
export const newItem = (text) => ({ id: newId(), text, done: false });

export async function saveNote(n) {
  if (!key) return;
  n.updatedAt = Date.now();
  vault.open[n.id] = n;
  const snap = $state.snapshot(n);
  put({ id: n.id, updatedAt: snap.updatedAt, c: await enc(JSON.stringify(plainOf(snap))) });
}
export function removeNote(n) {
  delete vault.open[n.id];
  put({ id: n.id, updatedAt: Date.now(), deleted: true, c: '' });
}

let timer;
function persist() {
  write('bim.notes', $state.snapshot(vault.file));
}
function changed() {
  persist();
  clearTimeout(timer);
  timer = setTimeout(syncNotes, 1500);
}

// ---- Synchro ----

const b64text = (s) => b64(new TextEncoder().encode(s));
const textb64 = (s) => new TextDecoder().decode(unb64(s.replace(/\n/g, '')));
const stamp = (f) => JSON.stringify([f.salt, (f.notes ?? []).map((n) => [n.id, n.updatedAt]).sort()]);

async function merge(remote) {
  if (!remote.salt) return;
  const f = vault.file;
  if (f.salt !== remote.salt) {
    if (f.salt && f.notes.some((n) => !n.deleted)) {
      throw new Error('Deux coffres différents : un ici, un autre déjà synchronisé. Recopie tes notes d\'ici avant de reprendre l\'autre.');
    }
    vault.file = { ...empty(), ...remote };
    lock();
    persist();
    return;
  }
  const byId = new Map(f.notes.map((n) => [n.id, n]));
  let touched = false;
  for (const r of remote.notes ?? []) {
    const l = byId.get(r.id);
    if (l && l.updatedAt >= r.updatedAt) continue;
    if (l) f.notes[f.notes.indexOf(l)] = r;
    else f.notes.push(r);
    touched = true;
    if (key) await decryptOne(r);
  }
  const old = Date.now() - 60 * 86400000;
  vault.file.notes = vault.file.notes.filter((n) => !(n.deleted && n.updatedAt < old));
  if (touched) persist();
}

let busy = false;
export async function syncNotes() {
  if (!app.repo || !app.token || busy) return;
  busy = true;
  vault.sync = 'sync';
  const base = `https://api.github.com/repos/${app.repo}/contents/notes.json`;
  const headers = {
    Authorization: `Bearer ${app.token}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  try {
    for (let i = 0; i < 3; i++) {
      const r = await fetch(`${base}?t=${Date.now()}`, { headers, cache: 'no-store' });
      let sha;
      let remote = null;
      if (r.status === 200) {
        const j = await r.json();
        sha = j.sha;
        remote = JSON.parse(textb64(j.content));
        await merge(remote);
      } else if (r.status !== 404) {
        throw new Error(`GitHub a répondu ${r.status}`);
      }
      if (!exists()) break;
      const mine = $state.snapshot(vault.file);
      if (remote && stamp(mine) === stamp(remote)) break;
      mine.notes.sort((a, b) => (a.id < b.id ? -1 : 1));
      const p = await fetch(base, {
        method: 'PUT',
        headers,
        body: JSON.stringify({ message: 'bim : notes (bureau)', content: b64text(JSON.stringify(mine, null, 1)), sha }),
      });
      if (p.ok) break;
      if (p.status !== 409 && p.status !== 422) throw new Error(`GitHub a refusé l'écriture (${p.status})`);
      if (i === 2) throw new Error('Conflit de synchro, réessaie');
    }
    vault.sync = 'idle';
    vault.error = '';
  } catch (e) {
    vault.sync = 'error';
    vault.error = e.message || `${e}`;
  }
  busy = false;
}

// Au démarrage : rouvrir le coffre si la clé est restée sur cet ordinateur.
(async () => {
  const k = read('bim.notesKey');
  if (k && exists()) {
    try {
      const imported = await crypto.subtle.importKey('raw', unb64(k), 'AES-GCM', true, ['encrypt', 'decrypt']);
      if (await valid(imported)) {
        key = imported;
        vault.unlocked = true;
        await decryptAll();
      } else write('bim.notesKey', null);
    } catch {}
  }
  syncNotes();
})();
document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && syncNotes());
setInterval(() => document.visibilityState === 'visible' && syncNotes(), 45000);
