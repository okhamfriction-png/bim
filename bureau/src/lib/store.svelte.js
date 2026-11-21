// État de Bim sur le bureau : même fichier backlog.json que l'appli du téléphone
// (dépôt GitHub privé), mêmes règles de fusion. Le bureau ne modifie que les tâches ;
// l'agenda et les réglages de points sont lus tels quels.

export const PRIO = ['P0', 'P1', 'P2', 'P3', 'P4'];
export const LANES = ['Non négociable', 'Important', 'Si le temps', 'Petite tâche', 'Parking'];
export const CATS = ['Mission', 'Contenu', 'Destiny', 'Personnel', 'Parking'];
export const CAT_ICON = { Mission: '💼', Contenu: '🎬', Destiny: '🎭', Personnel: '📘', Parking: '🅿️' };
export const KINDS = {
  rue: { name: 'Rue', unit: 'blocs', icon: '🚶', coef: 3 },
  paris: { name: 'Vidéo Paris', unit: 'vidéos', icon: '🎥', coef: 2 },
  montee: { name: 'Vidéo montée', unit: 'vidéos', icon: '🎬', coef: 2 },
  short: { name: 'Short', unit: 'shorts', icon: '📱', coef: 1 },
  rangement: { name: 'Rangement', unit: 'jours', icon: '🗂️', coef: 1 },
  echauffement: { name: 'Échauffement', unit: 'sprints', icon: '🔥', coef: 2 },
};
/** Types payés une seule fois, quand la tâche entière est validée. */
const WHOLE = new Set(['echauffement']);

const read = (k, d) => {
  try {
    const v = localStorage.getItem(k);
    return v == null ? d : JSON.parse(v);
  } catch {
    return d;
  }
};
const write = (k, v) => {
  try {
    localStorage.setItem(k, JSON.stringify(v));
  } catch {}
};

const emptyDoc = () => ({ version: 2, tasks: [], schedule: {} });

export const app = $state({
  doc: read('bim.doc', emptyDoc()),
  // À défaut, le dépôt et le jeton déjà saisis dans l'appli web (même adresse, même navigateur).
  repo: read('bim.repo', '') || read('flutter.repo', ''),
  token: read('bim.token', '') || read('flutter.token', ''),
  sync: 'off', // off | sync | ok | error
  error: '',
  now: Date.now(),
  ui: {
    theme: 'system', // system | light | dark | auto (selon l'heure)
    darkFrom: 19, // en mode horaire : heure de passage en sombre
    lightFrom: 7, // et de retour en clair
    blocks: { sprint: true, backlog: false, agenda: true },
    agendaView: 'semaine', // jour | semaine
    ...read('bim.ui', {}),
  },
});
// Un bloc ajouté depuis (les notes) s'affiche même si les réglages enregistrés ne le connaissent pas.
app.ui.blocks = { notes: true, ...app.ui.blocks };

setInterval(() => (app.now = Date.now()), 60000);

export function saveUi() {
  write('bim.ui', $state.snapshot(app.ui));
}

// ---- Dates ----

export const ymd = (d) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
export const dateOf = (s) => {
  const [y, m, d] = s.split('-').map(Number);
  return new Date(y, m - 1, d);
};
export const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
export const mondayOf = (d) => addDays(d, -((d.getDay() + 6) % 7));
export const thisMonday = () => ymd(mondayOf(new Date(app.now)));

// ---- Tâches ----

const sched = () => app.doc.schedule ?? {};
const order = (a, b) => a.priority - b.priority || (a.rank ?? 0) - (b.rank ?? 0);
export const catOf = (t) =>
  CATS.includes(t.domain) ? t.domain : t.domain === 'Travail' ? 'Mission' : 'Personnel';
export const parked = (t) => catOf(t) === 'Parking';
export const isOpen = (t) => !t.deleted && t.status === 'todo';

/** Type de points : celui choisi, sinon celui annoncé au début du titre. */
export function kindOf(t) {
  if (KINDS[t.kind]) return t.kind;
  const s = (t.title ?? '').toLowerCase();
  if (s.startsWith('rue ·')) return 'rue';
  if (s.startsWith('vidéo paris')) return 'paris';
  if (s.startsWith('vidéo montée')) return 'montee';
  if (s.startsWith('short ·')) return 'short';
  if (s.startsWith('rangement ·')) return 'rangement';
  if (s.startsWith('échauffement ·')) return 'echauffement';
  return '';
}
export const iconOf = (t) => (t.call ? '📞' : KINDS[kindOf(t)]?.icon ?? CAT_ICON[catOf(t)]);
const subs = (t) => t.subs ?? [];
export const whole = (t) => WHOLE.has(kindOf(t));
// ---- Prise d'échauffement : secondes tenues avant le premier « euh », levier joué ou non ----
export const noted = (s) => (s.data?.duree ?? 0) > 0;
export const priseOk = (s) => noted(s) && s.data.levierOk === true;
const secs = (n) => (n < 60 ? `${n} s` : n % 60 === 0 ? `${n / 60} min` : `${Math.floor(n / 60)} min ${String(n % 60).padStart(2, '0')}`);
export const priseSummary = (s) => (noted(s) ? `${secs(s.data.duree)} ${priseOk(s) ? '✓' : '✗'}` : 'Résultat');
/** Record du sprint : le plus de secondes tenues. */
export const recordOf = (t) => {
  const r = subs(t).filter(noted).map((s) => s.data.duree);
  return r.length ? Math.max(...r) : null;
};
/** Note un des 2 résultats d'une prise ; le levier du sprint est repris de la tâche. */
export function setPrise(t, s, key, v) {
  const d = { levier: t.meta?.nouveau?.at(-1) ?? 'depart', ...(s.data ?? {}) };
  if (key === 'duree') {
    const n = parseInt(v, 10);
    if (Number.isNaN(n) || n <= 0) delete d.duree;
    else d.duree = n;
  } else d[key] = !!v;
  s.data = d;
  touch(t);
}
export const unitsTotal = (t) => (whole(t) ? 1 : subs(t).length || 1);
export const unitsDone = (t) =>
  subs(t).length && !whole(t) ? subs(t).filter((s) => s.done).length : t.status === 'done' ? 1 : 0;
export const coefOf = (t) => {
  const k = kindOf(t);
  if (!k) return 0;
  // Un seul échauffement payé par sprint : le plus ancien.
  if (WHOLE.has(k) && t.sprint && app.doc.tasks.some((o) =>
      o !== t && !o.deleted && o.sprint === t.sprint && kindOf(o) === k &&
      (o.createdAt < t.createdAt || (o.createdAt === t.createdAt && o.id < t.id)))) return 0;
  return sched().points?.coef?.[k] ?? KINDS[k].coef;
};
export const plannedOf = (t) => coefOf(t) * unitsTotal(t);
export const earnedOf = (t) => coefOf(t) * unitsDone(t);

const pts = (n) => `${n} pt${n > 1 ? 's' : ''}`;
/** « 0/9 pts » ou « 2 pts », vide pour une tâche sans points. */
export function pointsLabel(t) {
  if (!kindOf(t)) return '';
  return `${earnedOf(t)}/${pts(plannedOf(t))}`;
}
/** « 0/3 blocs », vide pour une tâche sans sous-tâche à points. */
export function unitsLabel(t) {
  const k = KINDS[kindOf(t)];
  if (!k || !subs(t).length) return '';
  if (kindOf(t) === 'rue') {
    const noted = subs(t).filter(hasData);
    const ab = noted.reduce((a, s) => a + (gained(s) ?? 0), 0);
    const oui = noted.reduce((a, s) => a + (s.data.oui ?? 0), 0);
    return `${unitsDone(t)}/${unitsTotal(t)} ${k.unit}` +
      (noted.length ? ` · ${ab >= 0 ? '+' : ''}${ab} ab. · ${oui} place${oui > 1 ? 's' : ''}` : '');
  }
  return whole(t)
    ? `${subs(t).filter((s) => s.done).length}/${subs(t).length} prises${recordOf(t) != null ? ` · record ${secs(recordOf(t))}` : ''}`
    : `${unitsDone(t)}/${unitsTotal(t)} ${k.unit}`;
}
/** Points d'un groupe de tâches : « 3/13 pts » dès qu'il y en a de gagnés, sinon « 13 pts ». */
export function lanePoints(tasks) {
  const planned = tasks.reduce((a, t) => a + plannedOf(t), 0);
  const earned = tasks.reduce((a, t) => a + earnedOf(t), 0);
  return earned ? `${earned}/${pts(planned)}` : pts(planned);
}
/** « 0/3 blocs · 0/9 pts », vide pour une tâche sans points. */
export function valueLabel(t) {
  const k = KINDS[kindOf(t)];
  if (!k) return '';
  const pts = (n) => `${n} pt${n > 1 ? 's' : ''}`;
  return subs(t).length && !whole(t)
    ? `${unitsDone(t)}/${unitsTotal(t)} ${k.unit} · ${earnedOf(t)}/${pts(plannedOf(t))}`
    : pts(coefOf(t));
}

export const sprintOf = (t) => (t.sprint && t.sprint >= thisMonday() ? t.sprint : null);
export const sprints = () =>
  [...new Set((sched().sprints ?? []).filter((s) => s >= thisMonday()))].sort();
export const backlog = () => app.doc.tasks.filter(isOpen).sort(order);
export const sprintTasks = (s) => backlog().filter((t) => !parked(t) && sprintOf(t) === s);
export const looseTasks = () => backlog().filter((t) => parked(t) || sprintOf(t) == null);
export const doneThisWeek = () => {
  const m = mondayOf(new Date(app.now)).getTime();
  return app.doc.tasks
    .filter((t) => !t.deleted && t.status === 'done' && (t.doneAt ?? 0) >= m)
    .sort((a, b) => b.doneAt - a.doneAt);
};

// ---- Points de valeur ----

function deliveries(t) {
  if (!subs(t).length || whole(t)) return t.status === 'done' ? [t.doneAt ?? t.updatedAt] : [];
  return subs(t)
    .filter((s) => s.done)
    .map((s) => s.doneAt ?? t.doneAt ?? t.updatedAt);
}
function valueBetween(from, to) {
  let n = 0;
  for (const t of app.doc.tasks) {
    if (t.deleted || !kindOf(t)) continue;
    n += coefOf(t) * deliveries(t).filter((d) => d >= from && d < to).length;
  }
  return n;
}
/** Jetons bonus : un tous les 30 points de rue gagnés depuis le début, moins ceux dépensés. */
export const BONUS_EVERY = 30;
export const bonus = () => {
  let rue = 0;
  for (const t of app.doc.tasks) {
    if (!t.deleted && kindOf(t) === 'rue') rue += coefOf(t) * deliveries(t).length;
  }
  const spent = sched().points?.spent?.length ?? 0;
  return { left: Math.max(0, Math.floor(rue / BONUS_EVERY) - spent), progress: rue % BONUS_EVERY };
};
export const valueWeek = () => {
  const m = mondayOf(new Date(app.now));
  return valueBetween(m.getTime(), addDays(m, 7).getTime());
};
export const valueToday = () => {
  const d = new Date(app.now);
  const a = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  return valueBetween(a.getTime(), addDays(a, 1).getTime());
};
export const plannedIn = (s) =>
  app.doc.tasks.filter((t) => !t.deleted && t.sprint === s).reduce((a, t) => a + plannedOf(t), 0);
export const p0In = (s) =>
  app.doc.tasks.filter((t) => !t.deleted && t.sprint === s && t.priority === 0).length;
export function targetOf(s) {
  const p = sched().points ?? {};
  if (p.targets?.[s] != null) return p.targets[s];
  return kidsWeek(dateOf(s)) ? p.kids ?? 70 : p.free ?? 90;
}

// ---- Agenda (lecture seule) ----

export function weekOf(d) {
  const a = mondayOf(dateOf(sched().anchor ?? '2026-01-05'));
  const m = mondayOf(d);
  const w = Math.round(
    (Date.UTC(m.getFullYear(), m.getMonth(), m.getDate()) -
      Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) /
      (7 * 86400000),
  );
  return w % 2 === 0 ? 'a' : 'b';
}
export const weekName = (d) =>
  weekOf(d) === 'a' ? sched().nameA ?? 'Semaine A' : sched().nameB ?? 'Semaine B';
export const kidsWeek = (d) => weekName(d).toLowerCase().includes('avec');
const on = (b, day) =>
  (b.week === '*' || b.week === weekOf(day)) && (b.days ?? []).includes(((day.getDay() + 6) % 7) + 1);

/** Ce qu'il y a un jour donné : blocs fixes (déplacés ou raccourcis), dates ponctuelles, repères. */
export function dayItems(day) {
  const s = sched();
  const d = ymd(day);
  const blocks = s.blocks ?? [];
  const moves = s.moves ?? [];
  const events = s.events ?? [];
  const out = [];
  const cut = (b, end) => {
    for (const e of events) {
      if (e.date === d && e.blockId === b.id && e.cutEnd != null && e.cutEnd < end) return e.cutEnd;
    }
    return end;
  };
  // Une date « étiquette » précise le bloc ce jour-là (la salle de la répétition) sans ajouter de case.
  const labelOf = (b, orig) =>
    events.find((e) => e.tag === true && e.date === orig && e.blockId === b.id)?.label ?? b.label;
  for (const b of blocks.filter((b) => b.fixed !== false && on(b, day))) {
    if (moves.some((m) => m.key === `${b.id}|${d}`)) continue;
    const end = cut(b, b.end);
    if (end > b.start) out.push({ type: 'bloc', start: b.start, end, label: labelOf(b, d) });
  }
  for (const m of moves.filter((m) => m.toDate === d)) {
    const [id, orig] = m.key.split('|');
    const b = blocks.find((b) => b.id === id);
    if (b) out.push({ type: 'bloc', start: m.toStart, end: m.toStart + (b.end - b.start), label: labelOf(b, orig) });
  }
  for (const e of events.filter((e) => e.date === d && e.tag !== true)) {
    out.push({ type: 'date', start: e.start, end: e.start + 60, label: e.label });
  }
  for (const b of blocks.filter((b) => b.fixed === false && on(b, day))) {
    out.push({ type: 'repere', start: b.start, end: b.start, label: b.label });
  }
  return out.sort((a, b) => a.start - b.start);
}
export const hm = (m) =>
  m % 60 === 0 ? `${Math.floor(m / 60)} h` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}`;

// ---- Modifications ----

const newId = () =>
  Array.from({ length: 8 }, () => 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 36)]).join('');

let timer;
function changed() {
  write('bim.doc', $state.snapshot(app.doc));
  clearTimeout(timer);
  timer = setTimeout(sync, 1500);
}
export function touch(t) {
  t.updatedAt = Date.now();
  changed();
}

export function addTask(title, { priority = 2, domain = 'Contenu', sprint = null } = {}) {
  const s = title.trim();
  if (!s) return;
  const now = Date.now();
  app.doc.tasks.push({
    id: newId(),
    title: s,
    note: '',
    links: [],
    domain,
    priority,
    source: '',
    rank: Math.max(0, ...app.doc.tasks.map((t) => t.rank ?? 0)) + 1,
    status: 'todo',
    createdAt: now,
    updatedAt: now,
    doneAt: null,
    pickedOn: null,
    call: false,
    sprint,
    deleted: false,
  });
  changed();
}
export function complete(t) {
  t.doneAt = Date.now();
  t.status = 'done';
  touch(t);
}
export function reopen(t) {
  t.archived = false;
  t.doneAt = null;
  t.status = 'todo';
  touch(t);
}
/** Toutes cochées : la tâche est faite. Une case décochée : elle redevient à faire. */
function settle(t) {
  if (!subs(t).length) return;
  const all = t.subs.every((s) => s.done);
  if (all && t.status !== 'done') {
    t.doneAt = Date.now();
    t.status = 'done';
  } else if (!all && t.status === 'done') {
    t.archived = false;
    t.doneAt = null;
    t.status = 'todo';
  }
}
export function toggleSub(t, s) {
  s.done = !s.done;
  if (s.done) s.doneAt = Date.now();
  else delete s.doneAt;
  settle(t);
  touch(t);
}
/** Ce qu'on note à la fin d'un bloc de rue : [clé, libellé, nombre ?]. */
export const BLOCK_FIELDS = [
  ['approches', 'Approches (sur 20)', true],
  ['avant', 'Abonnés avant', true],
  ['apres', 'Abonnés après', true],
  ['demandes', 'Demandes de place', true],
  ['oui', 'Nombre de oui', true],
  ['objection', 'Objection la plus entendue', false],
  ['changer', 'Une chose à changer au bloc suivant', false],
];
const gained = (s) =>
  s.data?.avant != null && s.data?.apres != null ? s.data.apres - s.data.avant : null;
/** « 20/20 · +3 ab. · 1/4 places », vide si rien n'est noté. */
export function blockSummary(s) {
  const d = s.data ?? {};
  const g = gained(s);
  return [
    d.approches != null ? `${d.approches}/20` : '',
    g != null ? `${g >= 0 ? '+' : ''}${g} ab.` : '',
    d.demandes != null || d.oui != null ? `${d.oui ?? 0}/${d.demandes ?? 0} places` : '',
  ].filter(Boolean).join(' · ');
}
export const hasData = (s) => Object.keys(s.data ?? {}).length > 0;
export function setSubField(t, s, key, isNum, v) {
  const x = String(v ?? '').trim();
  const d = { ...(s.data ?? {}) };
  if (!x || (isNum && Number.isNaN(parseInt(x, 10)))) delete d[key];
  else d[key] = isNum ? parseInt(x, 10) : x;
  if (Object.keys(d).length) s.data = d;
  else delete s.data;
  touch(t);
}
export function setSubResult(t, s, v) {
  const x = String(v ?? '').trim();
  if (x) s.result = x;
  else delete s.result;
  touch(t);
}
export function addSub(t, title) {
  const s = title.trim();
  if (!s) return;
  t.subs = [...subs(t), { title: s, done: false }];
  settle(t);
  touch(t);
}
export function removeSub(t, s) {
  t.subs = t.subs.filter((x) => x !== s);
  if (!t.subs.length) delete t.subs;
  settle(t);
  touch(t);
}
export function remove(t) {
  t.deleted = true;
  touch(t);
}
/** Range une tâche dans un couloir de priorité (et un sprint), avant `before` ou en fin de couloir. */
export function place(t, priority, sprint, before, lane) {
  t.priority = priority;
  if (sprint !== undefined) t.sprint = sprint;
  const others = lane.filter((x) => x !== t);
  const i = before ? others.indexOf(before) : others.length;
  const lo = others[i - 1]?.rank;
  const hi = others[i]?.rank;
  if (lo != null && hi != null) t.rank = (lo + hi) / 2;
  else if (lo != null) t.rank = lo + 1;
  else if (hi != null) t.rank = hi - 1;
  touch(t);
}

// ---- Synchro GitHub ----

const b64decode = (s) =>
  new TextDecoder().decode(Uint8Array.from(atob(s.replace(/\n/g, '')), (c) => c.charCodeAt(0)));
const b64encode = (s) => {
  let bin = '';
  for (const b of new TextEncoder().encode(s)) bin += String.fromCharCode(b);
  return btoa(bin);
};
const canon = (tasks) => JSON.stringify([...tasks].sort((a, b) => (a.id < b.id ? -1 : 1)));

/** Fusion par tâche : la version la plus récente gagne. L'agenda vient toujours du dépôt. */
function merge(remote) {
  const mine = new Map(app.doc.tasks.map((t) => [t.id, t]));
  const out = [];
  for (const r of remote.tasks ?? []) {
    const l = mine.get(r.id);
    out.push(l && (l.updatedAt ?? 0) >= (r.updatedAt ?? 0) ? $state.snapshot(l) : r);
    mine.delete(r.id);
  }
  for (const l of mine.values()) out.push($state.snapshot(l));
  return { ...remote, tasks: out };
}

let busy = false;
export async function sync() {
  if (!app.repo || !app.token || busy) return;
  busy = true;
  app.sync = 'sync';
  const base = `https://api.github.com/repos/${app.repo}/contents/backlog.json`;
  const headers = {
    Authorization: `Bearer ${app.token}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  try {
    for (let i = 0; i < 3; i++) {
      const r = await fetch(`${base}?t=${Date.now()}`, { headers, cache: 'no-store' });
      let sha;
      let remote = emptyDoc();
      if (r.status === 200) {
        const j = await r.json();
        sha = j.sha;
        remote = JSON.parse(b64decode(j.content));
      } else if (r.status === 401) {
        throw new Error('GitHub ne reconnaît pas ce jeton : il est mal copié ou expiré.');
      } else if (r.status === 404) {
        throw new Error(
          `Ce jeton ne voit pas le dépôt ${app.repo}. Sur GitHub : « Only select repositories » → bim-data, puis Contents → « Read and write ».`,
        );
      } else {
        throw new Error(`GitHub a répondu ${r.status}`);
      }
      const merged = merge(remote);
      app.doc = merged;
      write('bim.doc', merged);
      if (canon(merged.tasks) === canon(remote.tasks ?? [])) break;
      const p = await fetch(base, {
        method: 'PUT',
        headers,
        body: JSON.stringify({
          message: 'bim : synchro (bureau)',
          content: b64encode(JSON.stringify(merged, null, 1)),
          sha,
        }),
      });
      if (p.ok) break;
      if (p.status === 403 || p.status === 404) {
        throw new Error(`Ce jeton peut lire ${app.repo} mais pas y écrire : Contents → « Read and write ».`);
      }
      if (p.status !== 409 && p.status !== 422) throw new Error(`GitHub a refusé l'écriture (${p.status})`);
      if (i === 2) throw new Error('Conflit de synchro, réessaie');
    }
    app.sync = 'ok';
    app.error = '';
  } catch (e) {
    app.sync = 'error';
    app.error = e.message || `${e}`;
  }
  busy = false;
}

export async function link(repo, token) {
  app.repo = repo.trim();
  app.token = token.trim();
  write('bim.repo', app.repo);
  write('bim.token', app.token);
  await sync();
}

// Au retour sur l'onglet et toutes les 45 secondes : reprendre ce que le téléphone a changé.
document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && sync());
setInterval(() => document.visibilityState === 'visible' && sync(), 45000);
