<script>
  // Le bilan chiffré d'un sprint : brouillon avant la clôture, ou bilan figé (avec `full`).
  import { BILAN_CATS, HEALTH, santeLabel } from './store.svelte.js';

  let { b, full = false } = $props();
  const pts = (n) => `${n} pt${n > 1 ? 's' : ''}`;
  const gap = $derived(b.points - b.target);
  const when = (ms) =>
    new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long', hour: 'numeric', minute: '2-digit' }).format(new Date(ms));
  const LISTS = [
    ['Terminées', 'done'],
    ['Reportées', 'carried'],
    ['Au parking', 'parked'],
    ['Abandonnées', 'dropped'],
  ];
</script>

<div class="box score">
  <div class="big">
    <b>{b.points}</b><span class="muted">/ {pts(b.target)}</span>
    <span class="pill" class:ok={gap >= 0}>{gap >= 0 ? `Cible atteinte${gap > 0 ? ` · +${gap}` : ''}` : `Écart ${gap}`}</span>
  </div>
  <div class="bar"><i class:ok={gap >= 0} style="width: {b.target ? Math.min(100, (100 * b.points) / b.target) : 0}%"></i></div>
</div>
<div class="box">
  <h4>Points par catégorie</h4>
  {#each BILAN_CATS as c}<div class="row"><span>{c}</span><b>{pts(b.byCat?.[c] ?? 0)}</b></div>{/each}
</div>
<div class="box">
  <h4>Tâches</h4>
  {#each LISTS as [label, key]}<div class="row"><span>{label}</span><b>{b[key]?.length ?? 0}</b></div>{/each}
</div>
{#if b.sante}
  <div class="box">
    <h4>Santé <span class="muted">· à part des points du sprint</span></h4>
    <div class="row"><span>Santé</span><b>{santeLabel(b)}</b></div>
    {#each HEALTH.filter(([k]) => k in b.sante) as [k, name]}<div class="row"><span>{name}</span><b>{b.sante[k]}/7</b></div>{/each}
  </div>
{/if}
{#if full}
  {#if b.keep}<div class="box"><h4>Ce que je retiens</h4><p>{b.keep}</p></div>{/if}
  {#if b.decisions}<div class="box"><h4>Décisions pour le sprint suivant</h4><p>{b.decisions}</p></div>{/if}
  {#each LISTS as [label, key]}
    {#if b[key]?.length}
      <div class="box">
        <h4>{label} · {b[key].length}</h4>
        {#each b[key] as t}
          <div class="row">
            <span>{t.title}{#if t.result}<small class="muted"> · {t.result}</small>{/if}</span>
            {#if t.points}<b>{pts(t.points)}</b>{/if}
          </div>
        {/each}
      </div>
    {/if}
  {/each}
  <p class="muted small">Clôturé le {when(b.closedAt)}.</p>
{/if}

<style>
  .box { background: var(--card); border: 1px solid var(--line); border-radius: 14px; overflow: hidden; flex: none; }
  .score { padding: 14px; }
  .big { display: flex; align-items: baseline; gap: 8px; }
  .big b { font-size: 36px; line-height: 1; font-weight: 900; }
  .pill { margin-left: auto; font-size: 12.5px; font-weight: 800; padding: 4px 10px; border-radius: 99px; color: var(--p0); background: color-mix(in srgb, var(--p0) 14%, transparent); }
  .pill.ok { color: var(--ok); background: color-mix(in srgb, var(--ok) 16%, transparent); }
  .bar { height: 7px; border-radius: 99px; background: var(--line); overflow: hidden; margin-top: 10px; }
  .bar i { display: block; height: 100%; background: var(--accent); border-radius: 99px; }
  .bar i.ok { background: var(--ok); }
  h4 { margin: 0; padding: 9px 14px; font-size: 14px; background: var(--soft); }
  .row { display: flex; justify-content: space-between; gap: 12px; padding: 8px 14px; border-top: 1px solid var(--line); }
  p { margin: 0; padding: 12px 14px; white-space: pre-wrap; line-height: 1.35; }
  .small { font-size: 12.5px; text-align: center; padding: 2px; }
</style>
