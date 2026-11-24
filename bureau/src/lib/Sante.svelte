<script>
  // Santé du jour : deux cases par jour, comptées à part des points du sprint (lib/sante.dart).
  import { app, ymd, dateOf, addDays, health, cycleHealth, healthTotal, HEALTH } from './store.svelte.js';

  let { sprint } = $props();
  const KEYS = HEALTH;
  const SHORT = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
  const today = $derived(ymd(new Date(app.now)));
  const days = $derived(Array.from({ length: 7 }, (_, i) => addDays(dateOf(sprint), i)));
  const score = $derived(healthTotal(sprint));
  // Replié par défaut : seule la ligne du jour. Un clic sur l'en-tête montre la semaine.
  let open = $state(false);
  const shown = $derived(open || !days.some((d) => ymd(d) === today) ? days : days.filter((d) => ymd(d) === today));
</script>

<div class="sante">
  <button class="top" onclick={() => (open = !open)} aria-expanded={open}>
    <div><b>❤️ Santé du jour</b> <span class="muted">— est-ce que j'ai tenu ?</span></div>
    <span class="count">Santé : {score}/{7 * KEYS.length} {open ? '▾' : '▸'}</span>
  </button>
  <div class="line head"><span></span>{#each KEYS as [, name, , icon]}<span class="ico" title={name} role="img" aria-label={name}>{icon}</span>{/each}</div>
  {#each shown as day}
    {@const i = days.indexOf(day)}
    {@const d = ymd(day)}
    <div class="line" class:now={d === today} class:future={d > today}>
      <span class="day">{SHORT[i]} {day.getDate()}</span>
      {#each KEYS as [k, name, color]}
        {@const v = health(d, k)}
        <span>
          <button class="box" style="--c: {color}" class:yes={v === true} class:no={v === false} disabled={d > today}
            aria-label="{name}, {SHORT[i]} {day.getDate()} : {v === true ? 'tenu' : v === false ? 'pas tenu' : 'pas renseigné'}"
            onclick={() => cycleHealth(d, k)}>{v === true ? '✓' : v === false ? '✕' : ''}</button>
        </span>
      {/each}
    </div>
  {/each}
</div>

<style>
  .sante { border: 1px solid var(--line); border-radius: 14px; overflow: hidden; margin-top: 14px; flex: none; background: var(--card); }
  .top { width: 100%; text-align: left; display: flex; justify-content: space-between; align-items: center; gap: 10px; padding: 10px 14px; background: var(--soft); }
  .count { font-weight: 800; white-space: nowrap; }
  .line { display: grid; grid-template-columns: 90px repeat(5, 1fr); align-items: center; padding: 5px 14px; }
  .line > span { text-align: center; }
  .line .day { text-align: left; font-weight: 600; }
  .head { font-size: 12.5px; font-weight: 800; color: var(--sub); padding-top: 8px; }
  .ico { font-size: 22px; line-height: 1; }
  .now { background: color-mix(in srgb, #ec4899 10%, transparent); }
  .now .day { font-weight: 900; }
  .future { opacity: .35; }
  .box { width: 30px; height: 30px; border-radius: 9px; border: 2px solid var(--line); font-weight: 900; font-size: 16px; line-height: 1; }
  .box:disabled { cursor: default; }
  .box.yes { background: var(--c); border-color: var(--c); color: #fff; }
  .box.no { border-color: var(--p0); color: var(--p0); background: color-mix(in srgb, var(--p0) 14%, transparent); }
</style>
