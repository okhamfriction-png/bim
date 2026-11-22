// La liste de courses : en clair dans courses.json du dépôt privé (même format que lib/courses.dart),
// donc visible sans code et modifiable par la commande `bim courses`.
import { app } from './store.svelte.js';

const newId = () =>
  Array.from({ length: 8 }, () => 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 36)]).join('');
const b64text = (s) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
const textb64 = (s) => new TextDecoder().decode(Uint8Array.from(atob(s.replace(/\n/g, '')), (c) => c.charCodeAt(0)));
const stored = () => {
  try {
    return JSON.parse(localStorage.getItem('bim.courses')) ?? [];
  } catch {
    return [];
  }
};

export const courses = $state({ items: stored(), error: '' });

export const courseItems = () => {
  const l = courses.items.filter((i) => !i.deleted);
  return [...l.filter((i) => !i.done), ...l.filter((i) => i.done)];
};

let timer;
function changed() {
  try {
    localStorage.setItem('bim.courses', JSON.stringify(courses.items));
  } catch {}
  clearTimeout(timer);
  timer = setTimeout(syncCourses, 1200);
}

export function addCourse(text) {
  const s = text.trim();
  if (!s) return;
  const same = courses.items.find((i) => !i.deleted && i.text.toLowerCase() === s.toLowerCase());
  if (same) {
    if (!same.done) return;
    same.done = false;
    same.updatedAt = Date.now();
  } else courses.items.push({ id: newId(), text: s, done: false, updatedAt: Date.now() });
  changed();
}
export function toggleCourse(i) {
  i.done = !i.done;
  i.updatedAt = Date.now();
  changed();
}
export function clearCourses() {
  for (const i of courses.items) {
    if (!i.deleted && i.done) {
      i.deleted = true;
      i.updatedAt = Date.now();
    }
  }
  changed();
}

function merge(remote) {
  const byId = new Map(courses.items.map((i) => [i.id, i]));
  for (const r of remote.items ?? []) {
    const l = byId.get(r.id);
    if (!l) courses.items.push(r);
    else if (r.updatedAt > l.updatedAt) courses.items[courses.items.indexOf(l)] = r;
  }
  const old = Date.now() - 30 * 86400000;
  courses.items = courses.items.filter((i) => !(i.deleted && i.updatedAt < old));
}
const encode = () =>
  JSON.stringify({ v: 1, items: [...$state.snapshot(courses.items)].sort((a, b) => (a.id < b.id ? -1 : 1)) }, null, 1);

let busy = false;
export async function syncCourses() {
  if (!app.repo || !app.token || busy) return;
  busy = true;
  const base = `https://api.github.com/repos/${app.repo}/contents/courses.json`;
  const headers = {
    Authorization: `Bearer ${app.token}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  try {
    for (let n = 0; n < 3; n++) {
      const r = await fetch(`${base}?t=${Date.now()}`, { headers, cache: 'no-store' });
      let sha;
      let theirs = null;
      if (r.status === 200) {
        const j = await r.json();
        sha = j.sha;
        theirs = textb64(j.content);
        merge(JSON.parse(theirs));
      } else if (r.status !== 404) {
        throw new Error(`GitHub a répondu ${r.status}`);
      }
      const mine = encode();
      if (mine === theirs || (theirs == null && !courses.items.length)) break;
      const p = await fetch(base, {
        method: 'PUT',
        headers,
        body: JSON.stringify({ message: 'bim : courses (bureau)', content: b64text(mine), sha }),
      });
      if (p.ok) break;
      if (p.status !== 409 && p.status !== 422) throw new Error(`GitHub a refusé l'écriture (${p.status})`);
      if (n === 2) throw new Error('Conflit de synchro, réessaie');
    }
    try {
      localStorage.setItem('bim.courses', JSON.stringify(courses.items));
    } catch {}
    courses.error = '';
  } catch (e) {
    courses.error = e.message || `${e}`;
  }
  busy = false;
}

syncCourses();
document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && syncCourses());
setInterval(() => document.visibilityState === 'visible' && syncCourses(), 45000);
