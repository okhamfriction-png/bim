<script>
  // Fiche d'un rappel : une phrase, un jour, une heure. Comme lib/rappels.dart sur le téléphone.
  import { ymd, dateOf, saveReminder, toggleReminder, removeReminder } from './store.svelte.js';
  import { parseReminder, defaultTime, when } from './rappel.js';

  let { event = null, day = null, close, done = () => {} } = $props();
  let text = $state(event?.label ?? '');
  let date = $state(event ? event.date : ymd(day ?? new Date()));
  const pad = (n) => String(n).padStart(2, '0');
  const clock = (m) => `${pad(Math.floor(m / 60))}:${pad(m % 60)}`;
  let time = $state(clock(event ? event.start : defaultTime(day ?? new Date())));
  let datePicked = false, timePicked = false; // choisi à la main : la phrase ne le change plus

  function typed() {
    const r = parseReminder(text);
    if (r.day && !datePicked) {
      date = ymd(r.day);
      if (r.minutes == null && !timePicked && !event) time = clock(defaultTime(r.day));
    }
    if (r.minutes != null && !timePicked) time = clock(r.minutes);
  }
  function save(e) {
    e?.preventDefault();
    const label = parseReminder(text).text;
    if (!label || !date || !time) return;
    const [h, m] = time.split(':').map(Number);
    saveReminder(event, label, dateOf(date), h * 60 + m);
    done(`Rappel ${when(dateOf(date), h * 60 + m)} : ${label}`);
    close();
  }
</script>

<div class="veil" onclick={close} role="presentation"></div>
<form class="card" onsubmit={save}>
  <h3>🔔 {event ? 'Rappel' : 'Nouveau rappel'}</h3>
  <!-- svelte-ignore a11y_autofocus -->
  <input class="text" bind:value={text} oninput={typed} placeholder="Préparer la tablette dimanche 11h" autofocus />
  <span class="muted small">Écris le jour et l'heure dans la phrase, ou choisis-les ici.</span>
  <div class="row">
    <input type="date" bind:value={date} onchange={() => (datePicked = true)} aria-label="Jour" />
    <input type="time" bind:value={time} onchange={() => (timePicked = true)} aria-label="Heure" />
  </div>
  <div class="actions">
    {#if event}
      <button type="button" class="btn del" onclick={() => { removeReminder(event); close(); }}>Supprimer</button>
      <button type="button" class="btn" onclick={() => { toggleReminder(event); close(); }}>{event.done ? 'À refaire' : "C'est fait"}</button>
    {/if}
    <span class="grow"></span>
    <button type="button" class="btn" onclick={close}>Annuler</button>
    <button class="btn primary" disabled={!text.trim()}>Enregistrer</button>
  </div>
</form>

<style>
  .veil { position: fixed; inset: 0; background: rgba(0, 0, 0, .4); z-index: 30; }
  .card {
    position: fixed; z-index: 31; top: 16vh; left: 50%; transform: translateX(-50%); width: min(500px, 92vw);
    background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 20px;
    display: flex; flex-direction: column; gap: 10px; box-shadow: 0 20px 60px rgba(0, 0, 0, .3);
  }
  h3 { margin: 0; font-size: 18px; }
  .text { font-size: 16px; }
  .small { font-size: 12.5px; }
  .row { display: flex; gap: 10px; }
  .row input { flex: 1; font-weight: 700; }
  .actions { display: flex; align-items: center; gap: 8px; padding-top: 6px; }
  .grow { flex: 1; }
  .del { color: var(--p0); }
  .btn:disabled { opacity: .45; cursor: default; }
</style>
