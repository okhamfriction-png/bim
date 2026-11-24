<script>
  // Tableau de bord : chiffres clés et courbes, comme dans l'appli du téléphone (lib/kpi.dart).
  import { kpi, median, days } from './kpi.js';
  import { KINDS, CATS, PRIO, dateOf, addDays } from './store.svelte.js';
  import Bars from './Bars.svelte';

  let weeks = $state(8);
  const k = $derived(kpi(weeks));
  const labels = $derived(k.mondays.map((m) => `${m.getDate()}/${m.getMonth() + 1}`));
  const rate = $derived(k.totalCreated ? Math.round((100 * k.totalDone) / k.totalCreated) : null);
  const KIND_COLOR = { rue: '#f59e0b', paris: '#ef4444', montee: '#a855f7', short: '#0ea5e9', rangement: '#22c55e', recap: '#14b8a6', echauffement: '#f97316' };
  const CAT_COLOR = { Mission: '#3b82f6', Contenu: '#f59e0b', Destiny: '#a855f7', Personnel: '#22c55e', Parking: '#94a3b8' };
  const usedKinds = $derived(Object.keys(KINDS).filter((x) => k.points.some((w) => (w[x] ?? 0) > 0)));
  const fmt = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long' });
  const range = (s) => `${fmt.format(dateOf(s))} au ${fmt.format(addDays(dateOf(s), 6))}`;
  const total = (o) => Object.values(o).reduce((a, b) => a + b, 0);

  // Burndown : 0 = lundi matin, 7 = dimanche soir.
  const W = 560, H = 170, UP = 16, DOWN = 20, PAD = 14;
  const bx = (d) => PAD + ((W - 2 * PAD) * d) / 7;
  const by = (v) => UP + (H - UP - DOWN) * (1 - v / Math.max(1, k.burnTotal));
  const path = $derived(`M${bx(0)},${by(k.burnTotal)} ` + k.burn.map((v, i) => `L${bx(i + 1)},${by(v)}`).join(' '));
</script>

<div class="scroll">
  <div class="seg">
    {#each [4, 8, 12] as n}<button class:on={weeks === n} onclick={() => (weeks = n)}>{n} semaines</button>{/each}
  </div>
  <div class="tiles">
    <div class="tile"><small>Faites</small><b class="ok">{k.totalDone}</b><small>sur {weeks} semaines</small></div>
    <div class="tile"><small>Créées</small><b>{k.totalCreated}</b><small>{rate == null ? '' : `${rate} % de faites`}</small></div>
    <div class="tile"><small>Points</small><b>{k.totalPoints}</b><small>de valeur</small></div>
    <div class="tile"><small>Délai médian</small><b>{days(median(k.lead))}</b><small>création → fait</small></div>
    <div class="tile"><small>Ouvertes</small><b>{k.open}</b><small>{k.parked} au parking</small></div>
    <div class="tile"><small>Abandonnées</small><b class:bad={k.totalDropped > 0}>{k.totalDropped}</b></div>
  </div>

  {#if k.burnSprint}
    <div class="box">
      <h4>Burndown du sprint en cours <small>Sprint du {range(k.burnSprint)} · points restants</small></h4>
      <svg viewBox="0 0 {W} {H}" role="img">
        <line x1="0" x2={W} y1={by(0)} y2={by(0)} class="axis" />
        <line x1={bx(0)} y1={by(k.burnTotal)} x2={bx(7)} y2={by(0)} class="ideal" />
        <path d={path} class="left" />
        {#each k.burn as v, i}<circle cx={bx(i + 1)} cy={by(v)} r="3.5" />{/each}
        <text x={bx(0)} y={by(k.burnTotal) - 6} class="val">{k.burnTotal}</text>
        {#if k.burn.length}<text x={bx(k.burn.length)} y={by(k.burn.at(-1)) - 8} class="val">{k.burn.at(-1)}</text>{/if}
        {#each ['L', 'M', 'M', 'J', 'V', 'S', 'D'] as d, i}<text x={(bx(i) + bx(i + 1)) / 2} y={H - 4}>{d}</text>{/each}
      </svg>
      <p class="legend"><i style="background: var(--accent)"></i>Restant <i style="background: var(--sub)"></i>Rythme idéal</p>
    </div>
  {/if}

  <div class="box">
    <h4>Créées et faites par semaine <small>Si les créées dépassent les faites, le backlog grossit</small></h4>
    <div class="pad"><Bars {labels} series={[k.created, k.done]} colors={['var(--sub)', 'var(--ok)']} /></div>
    <p class="legend"><i style="background: var(--sub)"></i>Créées <i style="background: var(--ok)"></i>Faites</p>
  </div>

  <div class="box">
    <h4>Points de valeur par semaine <small>Par type de tâche</small></h4>
    <div class="pad">
      <Bars {labels} stacked series={usedKinds.map((x) => k.points.map((w) => w[x] ?? 0))} colors={usedKinds.map((x) => KIND_COLOR[x])} />
    </div>
    <p class="legend">{#each usedKinds as x}<i style="background: {KIND_COLOR[x]}"></i>{KINDS[x].name} {/each}</p>
  </div>

  {#if k.sprints.length}
    <div class="box">
      <h4>Engagement tenu par sprint <small>Tâches terminées sur tâches engagées, à la clôture</small></h4>
      <div class="pad">
        <Bars labels={k.sprints.map((s) => `${dateOf(s.sprint).getDate()}/${dateOf(s.sprint).getMonth() + 1}`)}
          series={[k.sprints.map((s) => (s.all ? (100 * s.done) / s.all : 0))]} colors={['#0ea5e9']} suffix=" %" top={100} />
      </div>
    </div>
  {/if}

  {#each [['Faites par catégorie', k.byCat, CATS, (c) => CAT_COLOR[c]], ['Faites par priorité', k.byPrio, PRIO, (c) => `var(--p${PRIO.indexOf(c)})`]] as [title, data, order, color]}
    <div class="box">
      <h4>{title} <small>Sur {weeks} semaines</small></h4>
      {#if !total(data)}<p class="muted pad">Rien sur la période.</p>{/if}
      {#each order.filter((c) => data[c]) as c}
        <div class="share">
          <span>{c}</span>
          <div class="bar"><i style="width: {(100 * data[c]) / total(data)}%; background: {color(c)}"></i></div>
          <b>{data[c]} · {Math.round((100 * data[c]) / total(data))} %</b>
        </div>
      {/each}
    </div>
  {/each}

  <div class="box">
    <h4>Délai de réalisation <small>De la création à la fin, médiane par priorité</small></h4>
    {#if !k.lead.length}<p class="muted pad">Rien de terminé sur la période.</p>{/if}
    {#each PRIO as name, i}
      {#if k.leadByPrio[i]}
        <div class="row"><span><span class="chip" style="background: var(--p{i})">{name}</span> <span class="muted">{k.leadByPrio[i].length} tâches</span></span><b>{days(median(k.leadByPrio[i]))}</b></div>
      {/if}
    {/each}
  </div>

  <div class="box">
    <h4>Ce qui reste ouvert <small>Hors parking, aujourd'hui</small></h4>
    {#each [['Créées depuis 7 jours ou moins', k.ages[0]], ['Entre 8 et 30 jours', k.ages[1]], ['Entre 31 et 90 jours', k.ages[2]], ['Plus de 90 jours', k.ages[3], true], ['Hors sprint', k.noSprint], ['Jamais touchées depuis 7 jours', k.stale], ['Déjà reportées', k.reported], ['Reportées 2 fois ou plus', k.reportedTwice, true]] as [label, n, alert]}
      <div class="row"><span>{label}</span><b class:bad={alert && n > 0}>{n}</b></div>
    {/each}
  </div>
</div>

<style>
  .scroll { overflow: auto; flex: 1; min-height: 0; padding: 12px; display: flex; flex-direction: column; gap: 10px; }
  /* Sur un grand écran, les courbes gardent une taille lisible. */
  .scroll > :global(*) { width: 100%; max-width: 760px; align-self: center; }
  .seg { display: flex; gap: 2px; padding: 3px; background: var(--line); border-radius: 11px; flex: none; }
  .seg button { flex: 1; padding: 6px; border-radius: 8px; font-size: 13.5px; font-weight: 800; color: var(--sub); }
  .seg button.on { background: var(--card); color: var(--ink); }
  .tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 8px; flex: none; }
  .tile { border: 1px solid var(--line); border-radius: 14px; padding: 10px 12px; display: flex; flex-direction: column; }
  .tile small { color: var(--sub); font-size: 12px; min-height: 15px; }
  .tile b { font-size: 24px; font-weight: 900; }
  .ok { color: var(--ok); }
  .bad { color: var(--p0); }
  .box { border: 1px solid var(--line); border-radius: 14px; overflow: hidden; flex: none; }
  h4 { margin: 0; padding: 9px 14px; font-size: 14px; background: var(--soft); }
  h4 small { display: block; font-weight: 500; color: var(--sub); font-size: 12.5px; }
  .pad { padding: 12px 12px 4px; margin: 0; }
  svg { display: block; width: 100%; padding: 12px 12px 4px; }
  .axis { stroke: var(--line); }
  .ideal { stroke: var(--sub); stroke-width: 1.5; }
  .left { fill: none; stroke: var(--accent); stroke-width: 3; stroke-linejoin: round; }
  circle { fill: var(--accent); }
  text { text-anchor: middle; font-size: 11px; fill: var(--sub); }
  text.val { fill: var(--ink); font-weight: 800; }
  .legend { margin: 0; padding: 6px 14px 10px; font-size: 12.5px; color: var(--sub); }
  .legend i { display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin: 0 6px 0 10px; }
  .legend i:first-child { margin-left: 0; }
  .share { display: flex; align-items: center; gap: 10px; padding: 7px 14px; }
  .share span { width: 86px; flex: none; }
  .share b { width: 80px; text-align: right; flex: none; }
  .bar { flex: 1; height: 9px; border-radius: 99px; background: var(--line); overflow: hidden; }
  .bar i { display: block; height: 100%; border-radius: 99px; }
  .row { display: flex; justify-content: space-between; gap: 12px; padding: 8px 14px; border-top: 1px solid var(--line); }
  .chip { color: #fff; font-size: 11.5px; font-weight: 900; padding: 2px 6px; border-radius: 6px; }
</style>
