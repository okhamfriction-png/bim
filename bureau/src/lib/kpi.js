// Tableau de bord : mêmes calculs que l'appli du téléphone (lib/kpi.dart), à partir des tâches
// et des clôtures. Rien n'est enregistré ici.
import {
  app, kindOf, coefOf, plannedOf, catOf, parked, sprintOf, current, thisMonday, closedSprints,
  closureOf, mondayOf, addDays, dateOf, whole, PRIO,
} from './store.svelte.js';

const DAY = 86400000;
const subs = (t) => t.subs ?? [];
/** Instants où les unités d'une tâche ont été livrées. */
const deliveries = (t) =>
  !subs(t).length || whole(t)
    ? t.status === 'done' ? [t.doneAt ?? t.updatedAt] : []
    : subs(t).filter((s) => s.done).map((s) => s.doneAt ?? t.doneAt ?? t.updatedAt);

export const median = (l) => {
  if (!l.length) return null;
  const s = [...l].sort((a, b) => a - b);
  return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
};
/** « 3 j », « 5 h », « – » sans donnée. */
export const days = (d) =>
  d == null ? '–' : d < 1 ? `${Math.max(1, Math.round(d * 24))} h` : d < 10 ? `${d.toFixed(1).replace('.', ',')} j` : `${Math.round(d)} j`;

/** Tous les indicateurs sur les `weeks` dernières semaines (semaine en cours comprise). */
export function kpi(weeks) {
  const now = app.now;
  const m0 = mondayOf(new Date(now));
  const mondays = Array.from({ length: weeks }, (_, i) => addDays(m0, -7 * (weeks - 1 - i)));
  const span = mondays.map((m) => [m.getTime(), addDays(m, 7).getTime()]);
  const ix = (ms) => (ms == null ? -1 : span.findIndex(([a, b]) => ms >= a && ms < b));
  const zero = () => Array(weeks).fill(0);
  const k = {
    weeks, mondays, created: zero(), done: zero(), dropped: zero(),
    points: Array.from({ length: weeks }, () => ({})),
    byCat: {}, byPrio: {}, lead: [], leadByPrio: {},
    open: 0, parked: 0, noSprint: 0, stale: 0, reported: 0, reportedTwice: 0, ages: [0, 0, 0, 0],
    burnSprint: null, burnTotal: 0, burn: [], sprints: [],
  };
  for (const t of app.doc.tasks) {
    if (t.deleted) continue;
    const kind = kindOf(t);
    const coef = kind ? coefOf(t) : 0;
    if (coef) {
      for (const d of deliveries(t)) {
        const i = ix(d);
        if (i >= 0) k.points[i][kind] = (k.points[i][kind] ?? 0) + coef;
      }
    }
    const c = ix(t.createdAt);
    if (c >= 0) k.created[c]++;
    if (t.status === 'done') {
      const d = ix(t.doneAt);
      if (d >= 0) {
        k.done[d]++;
        k.byCat[catOf(t)] = (k.byCat[catOf(t)] ?? 0) + 1;
        k.byPrio[PRIO[t.priority]] = (k.byPrio[PRIO[t.priority]] ?? 0) + 1;
        if (t.createdAt > 0) {
          const n = Math.max(0, t.doneAt - t.createdAt) / DAY;
          k.lead.push(n);
          (k.leadByPrio[t.priority] ??= []).push(n);
        }
      }
    } else if (t.status === 'dropped') {
      const d = ix(t.updatedAt);
      if (d >= 0) k.dropped[d]++;
    } else if (parked(t)) {
      k.parked++;
    } else {
      k.open++;
      if (sprintOf(t) == null) k.noSprint++;
      if (t.updatedAt < now - 7 * DAY) k.stale++;
      if ((t.meta?.reports ?? 0) >= 1) k.reported++;
      if ((t.meta?.reports ?? 0) >= 2) k.reportedTwice++;
      const age = (now - t.createdAt) / DAY;
      k.ages[age <= 7 ? 0 : age <= 30 ? 1 : age <= 90 ? 2 : 3]++;
    }
  }
  // Burndown du sprint en cours, s'il a commencé.
  const s = current();
  if (s <= thisMonday() && (app.doc.schedule?.sprints ?? []).includes(s)) {
    k.burnSprint = s;
    const ts = app.doc.tasks.filter((t) => !t.deleted && t.sprint === s && t.status !== 'dropped');
    k.burnTotal = ts.reduce((a, t) => a + plannedOf(t), 0);
    const start = dateOf(s);
    for (let i = 0; i < 7; i++) {
      if (addDays(start, i).getTime() > now) break;
      const end = addDays(start, i + 1).getTime();
      let got = 0;
      for (const t of ts) got += coefOf(t) * deliveries(t).filter((d) => d < end).length;
      k.burn.push(k.burnTotal - got);
    }
  }
  for (const key of closedSprints().slice(0, 12).reverse()) {
    const b = closureOf(key);
    const n = (x) => b[x]?.length ?? 0;
    k.sprints.push({ sprint: key, done: n('done'), all: n('done') + n('carried') + n('parked') + n('dropped'), points: b.points, target: b.target });
  }
  const sum = (l) => l.reduce((a, b) => a + b, 0);
  k.totalDone = sum(k.done);
  k.totalCreated = sum(k.created);
  k.totalDropped = sum(k.dropped);
  k.totalPoints = sum(k.points.map((w) => sum(Object.values(w))));
  return k;
}
