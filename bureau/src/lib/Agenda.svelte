<script>
  import {
    app, saveUi, mondayOf, addDays, ymd, dateOf, dayItems, weekName, kidsWeek, hm,
    remindersOn, remindersNow, toggleReminder,
  } from './store.svelte.js';
  import Rappel from './Rappel.svelte';

  let { said = () => {} } = $props();
  let editing = $state(null); // { event } ou { day } : la fiche de rappel ouverte
  const due = $derived(remindersNow());
  const fmtDue = new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'numeric' });
  const overdue = (e) => !e.done && (e.date < ymd(today) || e.start <= today.getHours() * 60 + today.getMinutes());

  const H0 = 7, H1 = 22, PX = 44; // heures affichées, pixels par heure
  const DAYS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  let offset = $state(0); // semaines (ou jours) par rapport à aujourd'hui

  const today = $derived(new Date(app.now));
  const week = $derived(app.ui.agendaView === 'semaine');
  const first = $derived(week ? addDays(mondayOf(today), offset * 7) : addDays(today, offset));
  const days = $derived(week ? Array.from({ length: 7 }, (_, i) => addDays(first, i)) : [first]);
  // Ligne « maintenant » : gardée dans la grille même avant 7 h ou après 22 h.
  const nowY = $derived(
    Math.min((H1 - H0) * PX, Math.max(0, ((today.getHours() * 60 + today.getMinutes()) / 60 - H0) * PX)));
  const showNow = $derived(days.some((d) => ymd(d) === ymd(today)));
  const clock = $derived(`${today.getHours()}:${String(today.getMinutes()).padStart(2, '0')}`);
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
  <button class="btn bell" onclick={() => (editing = { day: week ? null : first })}>🔔 Rappel</button>
  <div class="seg">
    <button class:on={!week} onclick={() => view('jour')}>Jour</button>
    <button class:on={week} onclick={() => view('semaine')}>Semaine</button>
  </div>
</div>
<div class="kids" class:with={kidsWeek(first)}>{weekName(first)}</div>
{#if due.length}
  <div class="due">
    {#each due as e (e.id)}
      <div class="rem" class:done={e.done}>
        <button class="tick" onclick={() => toggleReminder(e)} title={e.done ? 'À refaire' : "C'est fait"}>{e.done ? '✓' : ''}</button>
        <button class="lab" onclick={() => (editing = { event: e })}>{e.label}</button>
        <span class:late={overdue(e)}>{e.date === ymd(today) ? '' : `${fmtDue.format(dateOf(e.date))} · `}{hm(e.start)}</span>
      </div>
    {/each}
  </div>
{/if}

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
      {#if showNow}<span class="clock" style="top: {nowY}px">{clock}</span>{/if}
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
        {#each remindersOn(d) as e (e.id)}
          <button class="rap" class:done={e.done} style="top: {top(e.start)}px" title="{hm(e.start)} · {e.label}"
            onclick={() => (editing = { event: e })}>🔔 {week ? '' : `${hm(e.start)} · `}{e.label}</button>
        {/each}
        {#if showNow}
          <div class="now" class:here={ymd(d) === ymd(today)} style="top: {nowY}px"></div>
        {/if}
      </div>
    {/each}
  </div>
</div>

{#if editing}{#key editing}<Rappel event={editing.event} day={editing.day} close={() => (editing = null)} done={said} />{/key}{/if}

<style>
  .bell { font-weight: 800; }
  .due { border-top: 1px solid var(--line); padding: 4px 10px; display: flex; flex-direction: column; }
  .rem { display: flex; align-items: center; gap: 9px; padding: 4px 2px; font-size: 13.5px; }
  .rem .tick {
    width: 20px; height: 20px; border-radius: 50%; border: 2px solid #0d9488; flex: none;
    color: #fff; font-size: 12px; font-weight: 900; line-height: 1;
  }
  .rem.done .tick { background: #0d9488; }
  .rem .lab { flex: 1; text-align: left; font-weight: 700; }
  .rem.done .lab { text-decoration: line-through; color: var(--sub); }
  .rem span { font-weight: 800; color: var(--sub); white-space: nowrap; }
  .rem span.late { color: var(--p0); }
  .rap {
    position: absolute; left: 2px; max-width: calc(100% - 4px); transform: translateY(-50%); z-index: 2;
    background: #0d9488; color: #fff; border: 1.5px solid var(--card); border-radius: 99px;
    padding: 1px 7px; font-size: 11.5px; font-weight: 800; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .rap.done { opacity: .5; text-decoration: line-through; }
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
  .now { position: absolute; left: 0; right: 0; border-top: 1px solid color-mix(in srgb, #2563eb 40%, transparent); z-index: 3; }
  .now.here { border-top: 3px solid #2563eb; margin-top: -1px; }
  .now.here::before { content: ''; position: absolute; left: -5px; top: -7px; width: 11px; height: 11px; border-radius: 50%; background: #2563eb; }
  .hours .clock { z-index: 3; right: 2px; background: #2563eb; color: #fff; font-weight: 800; border-radius: 6px; padding: 1px 5px; }
</style>
