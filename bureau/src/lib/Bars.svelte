<script>
  // Barres par semaine : groupées (une par série) ou empilées.
  let { labels, series, colors, stacked = false, suffix = '', top = null } = $props();
  const W = 560, H = 170, UP = 16, DOWN = 20;
  const n = $derived(labels.length);
  const hi = $derived(
    Math.max(top ?? 1, ...labels.map((_, i) =>
      stacked ? series.reduce((a, s) => a + s[i], 0) : Math.max(0, ...series.map((s) => s[i])))),
  );
  const y = (v) => UP + (H - UP - DOWN) * (1 - v / hi);
  const slot = $derived(W / Math.max(1, n));
  const group = $derived(Math.min(slot * 0.72, 44));
  const stack = (i) => {
    let base = 0;
    return series.map((s, j) => {
      const r = { j, from: base, to: base + s[i] };
      base += s[i];
      return r;
    });
  };
</script>

<svg viewBox="0 0 {W} {H}" role="img">
  <line x1="0" x2={W} y1={y(0)} y2={y(0)} class="axis" />
  {#each labels as l, i}
    {@const x = slot * (i + 0.5)}
    {#if stacked}
      {#each stack(i) as r}
        {#if r.to > r.from}<rect x={x - group / 2} y={y(r.to)} width={group} height={y(r.from) - y(r.to)} fill={colors[r.j]} />{/if}
      {/each}
      {@const total = series.reduce((a, s) => a + s[i], 0)}
      {#if total > 0}<text {x} y={y(total) - 4} class="val">{Math.round(total)}{suffix}</text>{/if}
    {:else}
      {@const w = group / Math.max(1, series.length)}
      {#each series as s, j}
        {#if s[i] > 0}
          <rect x={x - group / 2 + w * j + 1} y={y(s[i])} width={w - 2} height={y(0) - y(s[i])} rx="3" fill={colors[j]} />
          <text x={x - group / 2 + w * (j + 0.5)} y={y(s[i]) - 4} class="val">{Math.round(s[i])}{suffix}</text>
        {/if}
      {/each}
    {/if}
    {#if n <= 8 || i % 2 === 0}<text {x} y={H - 4}>{l}</text>{/if}
  {/each}
</svg>

<style>
  svg { display: block; width: 100%; }
  .axis { stroke: var(--line); }
  text { text-anchor: middle; font-size: 11px; fill: var(--sub); }
  text.val { fill: var(--ink); font-weight: 800; }
</style>
