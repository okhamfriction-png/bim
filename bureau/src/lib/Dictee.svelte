<script>
  // Dictée : on parle, Bim range. Le premier mot dit où : « note… », « tâche… », « courses… », « rappel… ».
  import { onMount } from 'svelte';
  import { route, splitArticles } from './dictee.js';
  import { addTask, saveReminder } from './store.svelte.js';
  import { parseReminder, defaultTime, when } from './rappel.js';
  import { addCourse } from './courses.svelte.js';
  import { vault, newNote, saveNote } from './notes.svelte.js';

  let { close, done } = $props();
  let text = $state('');
  let kind = $state('note');
  let chosen = false; // destination choisie à la main : la phrase ne la change plus
  let listening = $state(false);
  let error = $state('');
  let rec;
  const KINDS = [['note', '📝 Note'], ['tache', '✅ Tâche'], ['courses', '🛒 Courses'], ['rappel', '🔔 Rappel']];
  // Un rappel : le jour et l'heure dits dans la phrase, sinon aujourd'hui à la prochaine heure.
  const reminder = $derived.by(() => {
    const r = parseReminder(text);
    const day = r.day ?? new Date();
    return { text: r.text, day, minutes: r.minutes ?? defaultTime(day) };
  });
  const locked = $derived(kind === 'note' && !vault.unlocked);

  function start() {
    const R = window.SpeechRecognition ?? window.webkitSpeechRecognition;
    error = '';
    if (!R) {
      error = "La dictée n'est pas disponible dans ce navigateur (essaie Chrome). Écris ta phrase.";
      return;
    }
    rec = new R();
    rec.lang = 'fr-FR';
    rec.interimResults = true;
    rec.onstart = () => (listening = true);
    rec.onend = () => (listening = false);
    rec.onerror = (e) => {
      listening = false;
      if (!text) {
        error = e.error === 'not-allowed'
          ? "Le navigateur n'a pas le droit d'utiliser le micro."
          : "Je n'ai rien entendu. Clique sur le micro pour réessayer, ou écris.";
      }
    };
    rec.onresult = (e) => {
      const said = [...e.results].map((r) => r[0].transcript).join(' ');
      const [k, t] = route(said);
      if (!chosen) kind = k;
      text = t;
    };
    rec.start();
  }
  onMount(() => {
    start();
    return () => rec?.abort();
  });

  function save(e) {
    e?.preventDefault();
    const s = text.trim();
    if (!s || locked) return;
    let where;
    if (kind === 'courses') {
      const l = splitArticles(s);
      l.forEach(addCourse);
      where = l.length > 1 ? `${l.length} articles ajoutés aux courses` : 'Ajouté aux courses';
    } else if (kind === 'rappel') {
      if (!reminder.text) return;
      saveReminder(null, reminder.text, reminder.day, reminder.minutes);
      done(`Rappel ${when(reminder.day, reminder.minutes)} : ${reminder.text}`);
      close();
      return;
    } else if (kind === 'tache') {
      addTask(s, { domain: 'Personnel' });
      where = 'Tâche ajoutée au backlog';
    } else {
      saveNote({ ...newNote(), title: s });
      where = 'Note enregistrée';
    }
    done(`${where} : ${s}`);
    close();
  }
</script>

<div class="veil" onclick={close} role="presentation"></div>
<form class="card" onsubmit={save}>
  <div class="top">
    <button type="button" class="mic" class:on={listening} onclick={() => (listening ? rec.stop() : start())}
      title={listening ? 'Arrêter' : 'Parler'}>{listening ? '◼' : '🎤'}</button>
    <div>
      <h3>{listening ? "Je t'écoute…" : 'Dictée'}</h3>
      <span class="muted">Commence par « note », « tâche », « courses » ou « rappel ».</span>
    </div>
  </div>
  <!-- svelte-ignore a11y_autofocus -->
  <textarea rows="3" bind:value={text} placeholder="Ce que tu dis s'écrit ici" autofocus
    onkeydown={(e) => e.key === 'Enter' && !e.shiftKey && save(e)}></textarea>
  {#if error}<p class="err">{error}</p>{/if}
  <div class="picks">
    {#each KINDS as [k, label]}
      <button type="button" class:on={kind === k} onclick={() => { kind = k; chosen = true; }}>{label}</button>
    {/each}
  </div>
  {#if kind === 'rappel' && text.trim()}<p class="when">Rappel {when(reminder.day, reminder.minutes)}. Dis le jour et l'heure dans la phrase pour les changer.</p>{/if}
  {#if locked}<p class="warn">Le coffre de notes est fermé : ouvre-le dans le bloc Notes, ou range ça en tâche.</p>{/if}
  <div class="actions">
    <button type="button" class="btn" onclick={close}>Annuler</button>
    <button class="btn primary" disabled={!text.trim() || locked}>Enregistrer</button>
  </div>
</form>

<style>
  .veil { position: fixed; inset: 0; background: rgba(0, 0, 0, .4); z-index: 30; }
  .card {
    position: fixed; z-index: 31; top: 14vh; left: 50%; transform: translateX(-50%); width: min(520px, 92vw);
    background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 20px;
    display: flex; flex-direction: column; gap: 12px; box-shadow: 0 20px 60px rgba(0, 0, 0, .3);
  }
  .top { display: flex; align-items: center; gap: 14px; }
  .mic { width: 52px; height: 52px; border-radius: 50%; background: var(--accent); font-size: 22px; flex: none; }
  .mic.on { background: var(--p0); color: #fff; }
  h3 { margin: 0; font-size: 18px; }
  textarea { font-size: 16px; }
  p { margin: 0; }
  .err { color: var(--p0); font-weight: 600; }
  .warn { color: var(--p1); font-size: 13.5px; }
  .when { color: #0d9488; font-weight: 700; font-size: 13.5px; }
  .picks { display: flex; flex-wrap: wrap; gap: 8px; }
  .picks button { border: 1.5px solid var(--line); border-radius: 99px; padding: 6px 13px; font-weight: 600; }
  .picks button.on { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 20%, transparent); font-weight: 800; }
  .actions { display: flex; justify-content: flex-end; gap: 8px; }
  .btn:disabled { opacity: .45; cursor: default; }
</style>
