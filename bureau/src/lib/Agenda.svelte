<script>
  import { app, saveUi, mondayOf, addDays, ymd, dayItems, weekName, kidsWeek, hm } from './store.svelte.js';

  const H0 = 7, H1 = 22, PX = 44; // heures affichées, pixels par heure
  const DAYS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  let offset = $state(0); // semaines (ou jours) par rapport à aujourd'hui

  const today = $derived(new Date(app.now));
  const week = $derived(app.ui.agendaView === 'semaine');
  const first = $derived(week ? addDays(mondayOf(today), offset * 7) : addDays(today, offset));
  const days = $derived(week ? Array.from({ length: 7 }, (_, i) => addDays(first, i)) : [first]);
  const nowY = $derived(((today.getHours() * 60 + today.getMinutes()) / 60 - H0) * PX);
  const fmt = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long' });
  const fmtDay = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });

  function color(it) {
    const s = it.label.toLowerCase();
    if (it.type === 'date') return '#eab308';
    if (s.includes('rue')) return '#f97316';
    if (s.includes('sport')) return '#22c55e';
    if (s.includes('destiny') || s.includes('répét')) return '#a855f7';
    return '#3b82f6';
  }
  function view(v) {
    app.ui.agendaView = v;
    offset = 0;
    saveUi();
  }
  const top = (m) => Math.max(0, (m / 60 - H0) * PX);
</script>

<div class="bar">
  <button class="btn" onclick={() => offset--} aria-label="Précédent">‹</button>
  <strong>
    {week ? `${fmt.format(days[0])} – ${fmt.format(days[6])}` : fmtDay.format(first)}
  </strong>
  <button class="btn" onclick={() => offset++} aria-label="Suivant">›</button>
  {#if offset !== 0}<button class="btn" onclick={() => (offset = 0)}>Aujourd'hui</button>{/if}
  <span class="grow"></span>
  <div class="seg">
    <button class:on={!week} onclick={() => view('jour')}>Jour</button>
    <button class:on={week} onclick={() => view('semaine')}>Semaine</button>
  </div>
</div>
<div class="kids" class:with={kidsWeek(first)}>{weekName(first)}</div>

<div class="scroll">
  <div class="head" style="grid-template-columns: 44px repeat({days.length}, 1fr)">
    <span></span>
    {#each days as d}
      <span class="dh" class:today={ymd(d) === ymd(today)}>
        {DAYS[(d.getDay() + 6) % 7]} <b>{d.getDate()}</b>
      </span>
    {/each}
  </div>
  <div class="grid" style="grid-template-columns: 44px repeat({days.length}, 1fr); height: {(H1 - H0) * PX}px">
    <div class="hours">
      {#each Array.from({ length: H1 - H0 }, (_, i) => H0 + i) as h}
        <span style="top: {(h - H0) * PX}px">{h} h</span>
      {/each}
    </div>
    {#each days as d}
      <div class="col" class:today={ymd(d) === ymd(today)}>
        {#each Array.from({ length: H1 - H0 }, (_, i) => i) as i}
          <i style="top: {i * PX}px"></i>
        {/each}
        {#each dayItems(d) as it}
          {#if it.type === 'repere'}
            <div class="hint" style="top: {top(it.start)}px" title="{hm(it.start)} · {it.label}">
              <span>{hm(it.start)} · {it.label}</span>
            </div>
          {:else}
            <div
              class="ev"
              style="top: {top(it.start)}px; height: {Math.max(22, ((it.end - it.start) / 60) * PX - 2)}px; background: {color(it)}"
              title="{hm(it.start)} – {hm(it.end)} · {it.label}"
            >
              <b>{it.label}</b>
              <small>{hm(it.start)}{it.type === 'bloc' ? ` – ${hm(it.end)}` : ''}</small>
            </div>
          {/if}
        {/each}
        {#if ymd(d) === ymd(today) && nowY > 0 && nowY < (H1 - H0) * PX}
          <div class="now" style="top: {nowY}px"></div>
        {/if}
      </div>
    {/each}
  </div>
</div>

<style>
  .bar { display: flex; align-items: center; gap: 8px; padding: 10px 12px; border-top: 1px solid var(--line); }
  .bar strong { font-size: 14.5px; }
  .grow { flex: 1; }
  .seg { display: flex; background: var(--soft); border: 1px solid var(--line); border-radius: 10px; padding: 2px; }
  .seg button { padding: 5px 12px; border-radius: 8px; font-weight: 700; font-size: 13px; color: var(--sub); }
  .seg button.on { background: var(--card); color: var(--ink); box-shadow: var(--shadow); }
  .kids { padding: 6px 14px; font-weight: 800; font-size: 13px; color: #0ea5e9; background: color-mix(in srgb, #0ea5e9 10%, var(--card)); }
  .kids.with { color: #ec4899; background: color-mix(in srgb, #ec4899 10%, var(--card)); }
  .scroll { overflow: auto; flex: 1; min-height: 0; }
  .head { display: grid; position: sticky; top: 0; background: var(--card); z-index: 2; border-bottom: 1px solid var(--line); }
  .dh { text-align: center; padding: 7px 0; font-size: 12.5px; color: var(--sub); font-weight: 700; }
  .dh b { color: var(--ink); font-size: 14px; }
  .dh.today b { background: var(--accent); color: var(--on-accent); border-radius: 99px; padding: 1px 7px; }
  .grid { display: grid; position: relative; }
  .hours { position: relative; }
  .hours span { position: absolute; right: 6px; transform: translateY(-50%); font-size: 11.5px; color: var(--sub); }
  .col { position: relative; border-left: 1px solid var(--line); }
  .col.today { background: color-mix(in srgb, var(--accent) 7%, transparent); }
  .col i { position: absolute; left: 0; right: 0; border-top: 1px solid var(--line); opacity: .6; }
  .ev {
    position: absolute; left: 3px; right: 3px; border-radius: 8px; color: #fff; padding: 3px 6px;
    overflow: hidden; display: flex; flex-direction: column; line-height: 1.2; z-index: 1;
  }
  .ev b { font-size: 12.5px; }
  .ev small { font-size: 11px; opacity: .9; }
  .hint { position: absolute; left: 0; right: 0; border-top: 2px dashed #ec4899; z-index: 1; }
  .hint span {
    position: absolute; top: 1px; left: 3px; right: 3px; font-size: 10.5px; color: #ec4899; font-weight: 700;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .now { position: absolute; left: 0; right: 0; border-top: 2px solid var(--p0); z-index: 3; }
</style>
