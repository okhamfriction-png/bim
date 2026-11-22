<script>
  // Sprints clôturés : la courbe de vélocité, puis chaque sprint avec son bilan figé.
  import { closedSprints, closureOf, closedPoints, velocity, velocityLabel, reopenSprint, dateOf, addDays } from './store.svelte.js';
  import Bilan from './Bilan.svelte';

  let { close } = $props();
  const all = $derived(closedSprints());
  let open = $state(null);
  const shown = $derived(open ?? all[0]);
  const fmt = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long' });
  const range = (s) => `${fmt.format(dateOf(s))} au ${fmt.format(addDays(dateOf(s), 6))}`;
  const short = (s) => `${dateOf(s).getDate()}/${dateOf(s).getMonth() + 1}`;

  // Courbe : une barre par sprint (du plus ancien au plus récent), un trait pour sa cible.
  const W = 560, H = 190, TOP = 18, BOTTOM = 22;
  const bars = $derived([...all.slice(0, 12)].reverse());
  const hi = $derived(Math.max(1, velocity() ?? 0, ...bars.flatMap((s) => [closedPoints(s), closureOf(s).target])));
  const y = (v) => TOP + (H - TOP - BOTTOM) * (1 - v / hi);
  const slot = $derived(W / Math.max(1, bars.length));
  const bw = $derived(Math.min(46, Math.max(8, slot * 0.55)));

  function reopen(s) {
    if (confirm('Rouvrir ce sprint ? Son bilan ne sera plus figé et il faudra le clôturer à nouveau. Les tâches reportées, mises au parking ou abandonnées restent où elles sont.')) reopenSprint(s);
  }
</script>

<div class="veil" onclick={close} role="presentation"></div>
<div class="panel" role="dialog" aria-label="Sprints clôturés">
  <div class="top">
    <h2>Sprints clôturés</h2>
    <button class="btn" onclick={close}>Fermer</button>
  </div>
  <div class="scroll">
    {#if !all.length}
      <p class="muted">Aucun sprint clôturé pour l'instant.</p>
    {:else}
      <div class="box">
        <h4>Vélocité <small class="muted">Points faits par sprint · {velocityLabel()}</small></h4>
        <svg viewBox="0 0 {W} {H}" role="img" aria-label="Points faits par sprint">
          <line x1="0" x2={W} y1={y(0)} y2={y(0)} class="axis" />
          {#each bars as s, i}
            {@const x = slot * (i + 0.5)}
            {@const p = closedPoints(s)}
            {@const t = closureOf(s).target}
            <rect x={x - bw / 2} y={y(p)} width={bw} height={y(0) - y(p)} rx="5" class:ok={p >= t} />
            <line x1={x - bw / 2 - 4} x2={x + bw / 2 + 4} y1={y(t)} y2={y(t)} class="target" />
            <text {x} y={y(p) - 5} class="val">{p}</text>
            <text {x} y={H - 5} class="day">{short(s)}</text>
          {/each}
          <line x1="0" x2={W} y1={y(velocity())} y2={y(velocity())} class="avg" />
        </svg>
        <p class="muted small">Barre : points faits. Trait gris : cible. Pointillés bleus : moyenne des 3 derniers sprints.</p>
      </div>
      {#each all as s (s)}
        <button class="sprint" onclick={() => (open = shown === s ? '' : s)}>
          <b>Sprint du {range(s)}</b>
          <span>{closedPoints(s)} / {closureOf(s).target} pts {shown === s ? '▾' : '▸'}</span>
        </button>
        {#if shown === s}
          <Bilan b={closureOf(s)} full />
          <button class="btn re" onclick={() => reopen(s)}>Rouvrir ce sprint</button>
        {/if}
      {/each}
    {/if}
  </div>
</div>

<style>
  .veil { position: fixed; inset: 0; background: rgba(0, 0, 0, .4); z-index: 20; }
  .panel {
    position: fixed; top: 0; right: 0; bottom: 0; width: min(620px, 100vw); z-index: 21;
    background: var(--bg); border-left: 1px solid var(--line); display: flex; flex-direction: column;
  }
  .top { display: flex; justify-content: space-between; align-items: center; padding: 16px 20px 10px; }
  h2 { margin: 0; font-size: 18px; }
  .scroll { flex: 1; min-height: 0; overflow: auto; padding: 4px 20px 20px; display: flex; flex-direction: column; gap: 10px; }
  .box { background: var(--card); border: 1px solid var(--line); border-radius: 14px; overflow: hidden; flex: none; }
  h4 { margin: 0; padding: 9px 14px; font-size: 14px; background: var(--soft); }
  h4 small { font-weight: 500; margin-left: 8px; }
  svg { display: block; width: 100%; padding: 10px 12px 0; }
  rect { fill: var(--accent); }
  rect.ok { fill: var(--ok); }
  .axis { stroke: var(--line); }
  .target { stroke: var(--sub); stroke-width: 2; }
  .avg { stroke: #0ea5e9; stroke-width: 2; stroke-dasharray: 5 5; }
  text { text-anchor: middle; font-size: 11.5px; fill: var(--sub); }
  text.val { fill: var(--ink); font-weight: 800; }
  p { margin: 0; }
  .small { font-size: 12.5px; padding: 6px 14px 10px; }
  .sprint {
    display: flex; justify-content: space-between; gap: 12px; padding: 12px 14px; text-align: left; flex: none;
    background: var(--card); border: 1px solid var(--line); border-radius: 14px; font-size: 15px;
  }
  .sprint span { font-weight: 800; white-space: nowrap; }
  .re { align-self: flex-start; flex: none; }
</style>
