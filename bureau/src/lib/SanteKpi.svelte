<script>
  // Section « Santé » du tableau de bord (lib/sante.dart, SanteKpiView).
  import { santeKpi } from './kpi.js';

  const k = $derived(santeKpi());
  const KEYS = [['p', 'Santé physique', '#22c55e'], ['m', 'Santé mentale', '#8b5cf6']];
  const fmt = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long' });
  const enough = $derived(k.rue.held[0] >= 5 && k.rue.missed[0] >= 5);
  const avg = (g) => (g[0] ? g[1].toFixed(1).replace('.', ',') : '–');
  const W = 560, H = 160, L = 22, DOWN = 20, UP = 8;
  const x = (i) => L + 6 + ((W - L - 32) * i) / 7;
  const y = (v) => UP + (H - UP - DOWN) * (1 - v / 7);
  const path = (l) => l.map((v, i) => `${i ? 'L' : 'M'}${x(i)},${y(v)}`).join(' ');
</script>

<div class="box">
  <h4>❤️ Santé <small>Jours tenus sur 7, par semaine</small></h4>
  <div class="grid head"><span>Semaine du</span><span style="color: #22c55e">Santé physique</span><span style="color: #8b5cf6">Santé mentale</span><span>Les deux</span></div>
  {#each k.mondays.toReversed() as mo, r}
    {@const i = k.mondays.length - 1 - r}
    <div class="grid" class:now={r === 0}><span>{fmt.format(mo)}</span><b>{k.p[i]}/7</b><b>{k.m[i]}/7</b><b>{k.both[i]}/7</b></div>
  {/each}
</div>

<div class="box">
  <h4>Séries <small>Jours tenus d'affilée</small></h4>
  <div class="grid three head"><span></span><span>En cours</span><span>Meilleure</span></div>
  {#each KEYS as [key, name, color]}
    <div class="grid three"><span style="color: {color}; font-weight: 800">{name}</span><b>{k.streak[key]} j</b><b>{k.best[key]} j</b></div>
  {/each}
</div>

<div class="box">
  <h4>Santé sur 8 semaines <small>Jours tenus par semaine</small></h4>
  <svg viewBox="0 0 {W} {H}" role="img">
    {#each [0, 7] as v}<line x1={L} x2={W} y1={y(v)} y2={y(v)} class="axis" /><text x="8" y={y(v) + 4}>{v}</text>{/each}
    {#each k.mondays as mo, i}<text x={x(i)} y={H - 4}>{mo.getDate()}/{mo.getMonth() + 1}</text>{/each}
    {#each KEYS as [key, , color]}
      <path d={path(k[key])} style="stroke: {color}" />
      {#each k[key] as v, i}<circle cx={x(i)} cy={y(v)} r="3.5" style="fill: {color}" />{/each}
    {/each}
  </svg>
  <p class="legend">{#each KEYS as [, name, color]}<i style="background: {color}"></i>{name} {/each}</p>
</div>

<div class="box">
  <h4>Santé mentale et rue <small>Moyenne d'approches par jour de rue</small></h4>
  <div class="grid three head"><span>Santé mentale</span><span>Jours</span><span>Moyenne</span></div>
  <div class="grid three"><span>Tenue</span><b>{k.rue.held[0]}</b><b>{enough ? avg(k.rue.held) : '–'}</b></div>
  <div class="grid three"><span>Pas tenue</span><b>{k.rue.missed[0]}</b><b>{enough ? avg(k.rue.missed) : '–'}</b></div>
  {#if !enough}<p class="note">Pas assez de données : il faut 5 jours dans chaque groupe.</p>{/if}
</div>

<style>
  .box { border: 1px solid var(--line); border-radius: 14px; overflow: hidden; flex: none; }
  h4 { margin: 0; padding: 9px 14px; font-size: 14px; background: var(--soft); }
  h4 small { display: block; font-weight: 500; color: var(--sub); font-size: 12.5px; }
  .grid { display: grid; grid-template-columns: 1.4fr 1fr 1fr 1fr; padding: 7px 14px; border-top: 1px solid var(--line); text-align: center; }
  .grid.three { grid-template-columns: 1.4fr 1fr 1fr; }
  .grid > :first-child { text-align: left; }
  .grid.head { font-size: 12.5px; font-weight: 800; color: var(--sub); }
  .grid.now { background: color-mix(in srgb, #ec4899 8%, transparent); }
  .grid.now > :first-child { font-weight: 800; }
  svg { display: block; width: 100%; padding: 12px 12px 4px; }
  .axis { stroke: var(--line); }
  path { fill: none; stroke-width: 3; stroke-linejoin: round; }
  text { text-anchor: middle; font-size: 11px; fill: var(--sub); }
  .legend { margin: 0; padding: 6px 14px 10px; font-size: 12.5px; color: var(--sub); }
  .legend i { display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin: 0 6px 0 10px; }
  .legend i:first-child { margin-left: 0; }
  .note { margin: 0; padding: 6px 14px 10px; font-size: 13px; color: var(--sub); }
</style>
