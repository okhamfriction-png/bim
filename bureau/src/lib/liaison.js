// Code de liaison : relier un nouvel appareil depuis un appareil déjà relié, sans recopier le
// jeton GitHub. Même format que l'appli du téléphone (lib/liaison_code.dart) :
//   bim1.<base64url(sel 16 | nonce 12 | chiffré + tag 16)>, AES-256-GCM, clé PBKDF2-SHA256
//   tirée d'un code court de 6 caractères, affiché à côté et tapé à la main.
// Le lien porte le code dans le fragment (#relier=…), qui ne part jamais vers le serveur.

export const PREFIX = 'bim1.';
export const ITER = 200000;
export const MINUTES = 15;
export const PAGE = 'https://okhamfriction-png.github.io/bim/';
export const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const b64u = (bytes) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = (s) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));

export const normPin = (s) => (s ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
export const showPin = (p) => (p.length === 6 ? `${p.slice(0, 3)}-${p.slice(3)}` : p);

export function newPin() {
  const out = [];
  const r = crypto.getRandomValues(new Uint8Array(32));
  // Tirage sans biais : on écarte les octets au-delà du dernier multiple de la taille de l'alphabet.
  const max = 256 - (256 % ALPHABET.length);
  for (const b of r) if (b < max && out.length < 6) out.push(ALPHABET[b % ALPHABET.length]);
  return out.length === 6 ? out.join('') : newPin();
}

async function derive(pin, salt) {
  const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(normPin(pin)), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations: ITER },
    base,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

export async function makeLiaison(repo, token, pin, now = Date.now()) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plain = JSON.stringify({ r: repo, t: token, x: now + MINUTES * 60000 });
  const ct = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await derive(pin, salt), new TextEncoder().encode(plain)),
  );
  const all = new Uint8Array(16 + 12 + ct.length);
  all.set(salt);
  all.set(iv, 16);
  all.set(ct, 28);
  return PREFIX + b64u(all);
}

export const liaisonLink = (code) => `${PAGE}#relier=${code}`;
export const findLiaison = (text) => (text ?? '').match(/bim1\.[A-Za-z0-9_-]{40,}/)?.[0] ?? null;

/** Déchiffre un code de liaison ; lève une Error dont le message se montre tel quel. */
export async function readLiaison(pasted, pin, now = Date.now()) {
  const code = findLiaison(pasted);
  if (!code) throw new Error("Ce n'est pas un code de liaison Bim.");
  if (normPin(pin).length !== 6) throw new Error('Le code court a 6 caractères.');
  let all;
  try {
    all = unb64u(code.slice(PREFIX.length));
  } catch {
    throw new Error('Code de liaison abîmé : recopie-le en entier.');
  }
  if (all.length < 16 + 12 + 16 + 1) throw new Error('Code de liaison incomplet : recopie-le en entier.');
  let j;
  try {
    const plain = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: all.slice(16, 28) },
      await derive(pin, all.slice(0, 16)),
      all.slice(28),
    );
    j = JSON.parse(new TextDecoder().decode(plain));
  } catch {
    throw new Error("Ce n'est pas le bon code court, ou le code de liaison est incomplet.");
  }
  if ((j.x ?? 0) < now) throw new Error("Ce code de liaison a expiré : fais-en un nouveau sur l'appareil déjà relié.");
  const repo = (j.r ?? '').trim();
  const token = (j.t ?? '').trim();
  if (!repo || !token) throw new Error('Code de liaison vide.');
  return { repo, token };
}
