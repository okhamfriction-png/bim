<script>
  // Santé du jour : deux cases par jour, comptées à part des points du sprint (lib/sante.dart).
  import { app, ymd, dateOf, addDays, health, cycleHealth, healthIn } from './store.svelte.js';

  let { sprint } = $props();
  const KEYS = [['p', 'Santé physique'], ['m', 'Santé mentale']];
  const SHORT = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
  const today = $derived(ymd(new Date(app.now)));
  const days = $derived(Array.from({ length: 7 }, (_, i) => addDays(dateOf(sprint), i)));
  const score = $derived(healthIn(sprint));
</script>

<div class="sante">
  <div class="top">
    <div><b>❤️ Santé du jour</b> <span class="muted">— est-ce que j'ai tenu ?</span></div>
    <span class="count">Santé : {score.p + score.m}/14</span>
  </div>
  <div class="line head"><span></span>{#each KEYS as [, name]}<span>{name}</span>{/each}</div>
  {#each days as day, i}
    {@const d = ymd(day)}
    <div class="line" class:now={d === today} class:future={d > today}>
      <span class="day">{SHORT[i]} {day.getDate()}</span>
      {#each KEYS as [k, name]}
        {@const v = health(d, k)}
        <span>
          <button class="box {k}" class:yes={v === true} class:no={v === false} disabled={d > today}
            aria-label="{name}, {SHORT[i]} {day.getDate()} : {v === true ? 'tenu' : v === false ? 'pas tenu' : 'pas renseigné'}"
            onclick={() => cycleHealth(d, k)}>{v === true ? '✓' : v === false ? '✕' : ''}</button>
        </span>
      {/each}
    </div>
  {/each}
</div>

<style>
  .sante { border: 1px solid var(--line); border-radius: 14px; overflow: hidden; margin-top: 14px; flex: none; background: var(--card); }
  .top { display: flex; justify-content: space-between; align-items: center; gap: 10px; padding: 10px 14px; background: var(--soft); }
  .count { font-weight: 800; white-space: nowrap; }
  .line { display: grid; grid-template-columns: 90px 1fr 1fr; align-items: center; padding: 5px 14px; }
  .line > span { text-align: center; }
  .line .day { text-align: left; font-weight: 600; }
  .head { font-size: 12.5px; font-weight: 800; color: var(--sub); padding-top: 8px; }
  .now { background: color-mix(in srgb, #ec4899 10%, transparent); }
  .now .day { font-weight: 900; }
  .future { opacity: .35; }
  .box { width: 30px; height: 30px; border-radius: 9px; border: 2px solid var(--line); font-weight: 900; font-size: 16px; line-height: 1; }
  .box:disabled { cursor: default; }
  .box.p.yes { background: #22c55e; border-color: #22c55e; color: #fff; }
  .box.m.yes { background: #8b5cf6; border-color: #8b5cf6; color: #fff; }
  .box.no { border-color: var(--p0); color: var(--p0); background: color-mix(in srgb, var(--p0) 14%, transparent); }
</style>
