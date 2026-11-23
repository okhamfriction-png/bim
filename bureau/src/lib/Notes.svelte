<script>
  import {
    vault, exists, allNotes, noteCats, NOTE_ICON, createVault, unlock, lock, saveNote, removeNote,
    newNote, newItem, syncNotes,
  } from './notes.svelte.js';
  import { app } from './store.svelte.js';
  import { courses, courseItems, addCourse, toggleCourse, clearCourses, syncCourses } from './courses.svelte.js';

  let { liaison } = $props();
  let code = $state('');
  let again = $state('');
  let error = $state('');
  let cat = $state('');
  let query = $state('');
  let editing = $state(null); // copie de la note en cours de modification
  let fresh = $state(false);
  let otherCat = $state('');
  let line = $state('');
  let shown = $state({}); // id → valeur cachée affichée
  let copied = $state('');
  let quick = $state({}); // id → texte en cours d'ajout à la liste
  let article = $state('');
  let fast = $state(''); // note tapée en une ligne
  let more = $state(false); // options repliées de la fiche

  // Les listes rangées dans la catégorie « Courses » du coffre rejoignent la liste commune.
  $effect(() => {
    if (!vault.unlocked) return;
    for (const n of allNotes().filter((n) => n.cat === 'Courses' && n.items.length)) {
      for (const i of n.items) if (!i.done) addCourse(i.text);
      if (!n.body && !n.secret) removeNote(n);
      else saveNote({ ...$state.snapshot(n), items: [], cat: 'Mémos' });
    }
  });
  function capture(e) {
    e.preventDefault();
    if (!fast.trim()) return;
    saveNote({ ...newNote(cat || 'Mémos'), title: fast.trim() });
    fast = '';
  }

  const list = $derived(
    allNotes().filter((n) => {
      const q = query.toLowerCase();
      return (
        (!cat || n.cat === cat) &&
        (!q || n.title.toLowerCase().includes(q) || n.body.toLowerCase().includes(q) ||
          n.items.some((i) => i.text.toLowerCase().includes(q)))
      );
    }),
  );
  const used = $derived(noteCats().filter((c) => allNotes().some((n) => n.cat === c)));

  async function go(e) {
    e.preventDefault();
    if (vault.busy) return;
    if (!exists() && code !== again) {
      error = 'Les deux codes ne sont pas identiques.';
      return;
    }
    error = (await (exists() ? unlock(code) : createVault(code))) ?? '';
    if (!error) code = again = '';
  }
  function copy(text, id) {
    navigator.clipboard?.writeText(text);
    copied = id;
    setTimeout(() => (copied = ''), 1200);
  }
  function edit(n) {
    editing = n ? JSON.parse(JSON.stringify($state.snapshot(n))) : newNote(cat || 'Mémos');
    fresh = !n;
    otherCat = '';
    line = '';
    more = editing.items.length > 0 || editing.pinned || !noteCats().includes(editing.cat);
  }
  function addLine() {
    if (!line.trim()) return;
    editing.items.push(newItem(line.trim()));
    line = '';
  }
  function save() {
    addLine();
    const n = editing;
    if (otherCat.trim()) n.cat = otherCat.trim();
    n.title = n.title.trim();
    if (!n.title && !n.body.trim() && !n.secret && !n.items.length) return (editing = null);
    saveNote(n);
    editing = null;
  }
  function del() {
    if (!confirm('Supprimer cette note ? Elle disparaît aussi du téléphone.')) return;
    removeNote(editing);
    editing = null;
  }
  function toggle(n, i) {
    i.done = !i.done;
    saveNote(n);
  }
  function quickAdd(n) {
    const s = (quick[n.id] ?? '').trim();
    if (!s) return;
    n.items.push(newItem(s));
    quick[n.id] = '';
    saveNote(n);
  }
  function clearDone(n) {
    n.items = n.items.filter((i) => !i.done);
    saveNote(n);
  }
</script>

<article class="courses">
  <div class="title"><span>🛒</span><b>Courses</b><small>{courseItems().filter((i) => !i.done).length || 'Rien'} à acheter</small></div>
  {#if courses.error}<p class="err pad">{courses.error} <button class="link" onclick={syncCourses}>Réessayer</button></p>{/if}
  {#each courseItems() as i (i.id)}
    <label class="item" class:done={i.done}>
      <input type="checkbox" checked={i.done} onchange={() => toggleCourse(i)} /><span>{i.text}</span>
    </label>
  {/each}
  <form class="row" onsubmit={(e) => { e.preventDefault(); addCourse(article); article = ''; }}>
    <input class="quick" bind:value={article} placeholder="+ Ajouter un article" />
    {#if courseItems().some((i) => i.done)}
      <button type="button" class="mini" onclick={clearCourses}>Retirer les cochés</button>
    {/if}
  </form>
</article>

{#if !vault.unlocked && !exists() && !(app.repo && app.token)}
  <!-- Pas relié : le coffre existe peut-être ailleurs, on n'en crée pas un second. -->
  <div class="gate">
    <div class="big">🔗</div>
    <h3>Relie d'abord cet ordinateur</h3>
    <p class="muted">
      Ton coffre de notes est rangé dans ton dépôt GitHub. Relie Bim ici, puis ouvre le coffre avec
      ton code habituel. Sur ton téléphone : Réglages → Relier un autre appareil.
    </p>
    <button class="btn primary" onclick={liaison}>Relier avec un code de liaison</button>
  </div>
{:else if !vault.unlocked}
  <form class="gate" onsubmit={go}>
    <div class="big">🔒</div>
    <h3>{exists() ? 'Tes notes sont sous clé' : 'Crée ton coffre de notes'}</h3>
    <p class="muted">
      {exists()
        ? "Entre ton code pour les voir. Il n'est demandé qu'une fois par appareil."
        : 'Codes de bâtiment, adresses, mots de passe, jetons : tout est chiffré ici avec un code que toi seul connais, puis synchronisé avec le téléphone.'}
    </p>
    <input type="password" bind:value={code} placeholder="Code du coffre" autocomplete="off" />
    {#if !exists()}
      <input type="password" bind:value={again} placeholder="Le même code, une seconde fois" autocomplete="off" />
    {/if}
    {#if error}<p class="err">{error}</p>{/if}
    <button class="btn primary" disabled={vault.busy}>{vault.busy ? 'Un instant…' : exists() ? 'Ouvrir' : 'Créer le coffre'}</button>
    {#if !exists()}
      <p class="muted small">Retiens bien ce code : il n'est écrit nulle part. Si tu l'oublies, personne ne peut rouvrir le coffre.</p>
    {/if}
  </form>
{:else}
  <form class="bar" onsubmit={capture}>
    <input bind:value={fast} placeholder="Écrire une note, puis Entrée" />
    <button type="button" class="btn" onclick={() => edit(null)} title="Note détaillée">+ Détaillée</button>
    <button type="button" class="btn" onclick={lock} title="Fermer le coffre sur cet ordinateur">🔓</button>
  </form>
  {#if allNotes().length > 6}
    <div class="bar search"><input bind:value={query} placeholder="Chercher dans les notes" /></div>
  {/if}
  {#if vault.sync === 'error'}<p class="err pad">{vault.error} <button class="link" onclick={syncNotes}>Réessayer</button></p>{/if}
  {#if used.length > 1}
    <div class="cats">
      <button class:on={!cat} onclick={() => (cat = '')}>Toutes · {allNotes().length}</button>
      {#each used as c}
        <button class:on={cat === c} onclick={() => (cat = cat === c ? '' : c)}>
          {NOTE_ICON[c] ?? '🏷️'} {c} · {allNotes().filter((n) => n.cat === c).length}
        </button>
      {/each}
    </div>
  {/if}
  <div class="scroll">
    {#if !allNotes().length}
      <p class="muted empty">Aucune note pour l'instant.</p>
    {/if}
    {#each list as n (n.id)}
      <article>
        <button class="title" onclick={() => edit(n)} title="Modifier">
          <span>{NOTE_ICON[n.cat] ?? '🏷️'}</span>
          <b>{n.title || 'Sans titre'}</b>
          <small>{n.cat}{n.items.length ? ` · ${n.items.filter((i) => i.done).length}/${n.items.length}` : ''}{n.pinned ? ' · 📌' : ''}</small>
        </button>
        {#if n.body}
          <div class="row">
            <pre>{n.body}</pre>
            <button class="mini" onclick={() => copy(n.body, n.id + 'b')}>{copied === n.id + 'b' ? 'Copié' : 'Copier'}</button>
          </div>
        {/if}
        {#if n.secret}
          <div class="row">
            <code>{shown[n.id] ? n.secret : '••••••••••'}</code>
            <button class="mini" onclick={() => (shown[n.id] = !shown[n.id])}>{shown[n.id] ? 'Cacher' : 'Montrer'}</button>
            <button class="mini" onclick={() => copy(n.secret, n.id + 's')}>{copied === n.id + 's' ? 'Copié' : 'Copier'}</button>
          </div>
        {/if}
        {#if n.items.length}
          {#each [...n.items.filter((i) => !i.done), ...n.items.filter((i) => i.done)] as i (i.id)}
            <label class="item" class:done={i.done}>
              <input type="checkbox" checked={i.done} onchange={() => toggle(n, i)} /><span>{i.text}</span>
            </label>
          {/each}
          <form class="row" onsubmit={(e) => { e.preventDefault(); quickAdd(n); }}>
            <input class="quick" bind:value={quick[n.id]} placeholder="+ Ajouter à la liste" />
            {#if n.items.some((i) => i.done)}
              <button type="button" class="mini" onclick={() => clearDone(n)}>Retirer les cochés</button>
            {/if}
          </form>
        {/if}
      </article>
    {/each}
  </div>
{/if}

{#if editing}
  <div class="veil" onclick={() => (editing = null)} role="presentation"></div>
  <div class="panel" role="dialog" aria-label="Note">
    <input class="h" bind:value={editing.title} placeholder="Titre" />
    <textarea rows="4" bind:value={editing.body} placeholder="Le texte de la note (adresse, code de bâtiment…)"></textarea>
    <div class="cats wrap top">
      {#each noteCats() as c}
        <button class:on={editing.cat === c && !otherCat.trim()} onclick={() => { editing.cat = c; otherCat = ''; }}>{NOTE_ICON[c] ?? '🏷️'} {c}</button>
      {/each}
    </div>
    {#if ['Mots de passe', 'Jetons'].includes(editing.cat) || editing.secret}
      <input type="password" bind:value={editing.secret} autocomplete="new-password"
        placeholder={editing.cat === 'Jetons' ? 'Le jeton (masqué dans la liste)' : 'Le mot de passe (masqué dans la liste)'} />
    {/if}
    {#if !more}
      <button class="link left" onclick={() => (more = true)}>Plus d'options</button>
    {:else}
      <h4>Cases à cocher</h4>
      {#each editing.items as i (i.id)}
        <div class="row">
          <input type="checkbox" class="box" bind:checked={i.done} />
          <input bind:value={i.text} />
          <button class="mini" onclick={() => (editing.items = editing.items.filter((x) => x !== i))}>✕</button>
        </div>
      {/each}
      <form onsubmit={(e) => { e.preventDefault(); addLine(); }}>
        <input bind:value={line} placeholder="Ajouter une ligne (Entrée pour enchaîner)" />
      </form>
      <input bind:value={otherCat} placeholder="Ranger dans une nouvelle catégorie" />
      <label class="item pin"><input type="checkbox" bind:checked={editing.pinned} /><span>Épingler en haut</span></label>
    {/if}
    <div class="actions">
      {#if !fresh}<button class="btn" onclick={del}>Supprimer</button>{/if}
      <span class="grow"></span>
      <button class="btn" onclick={() => (editing = null)}>Annuler</button>
      <button class="btn primary" onclick={save}>{fresh ? 'Ajouter' : 'Enregistrer'}</button>
    </div>
  </div>
{/if}

<style>
  .courses { margin: 10px 12px 0; }
  .search { border-top: 0; padding-top: 0; }
  .top { padding-top: 6px; }
  .left { align-self: flex-start; color: var(--sub); padding: 6px 0; }
  .gate { display: flex; flex-direction: column; gap: 10px; padding: 26px 22px; align-items: stretch; text-align: center; overflow: auto; }
  .big { font-size: 34px; }
  h3 { margin: 0; font-size: 18px; }
  h4 { margin: 14px 0 4px; font-size: 12px; letter-spacing: .5px; text-transform: uppercase; color: var(--sub); }
  p { margin: 0; }
  .small { font-size: 12.5px; }
  .err { color: var(--p0); font-weight: 600; }
  .pad { padding: 0 14px 8px; }
  .link { color: inherit; text-decoration: underline; font-weight: 700; }
  .bar { display: flex; gap: 8px; padding: 10px 12px; border-top: 1px solid var(--line); }
  .bar .btn { flex: none; white-space: nowrap; }
  .cats { display: flex; gap: 6px; padding: 0 12px 10px; overflow-x: auto; }
  .cats.wrap { flex-wrap: wrap; padding: 0 0 8px; }
  .cats button {
    border: 1.5px solid var(--line); border-radius: 99px; padding: 5px 11px; font-size: 13px; font-weight: 600; white-space: nowrap;
  }
  .cats button.on { border-color: var(--accent); background: color-mix(in srgb, var(--accent) 20%, transparent); font-weight: 800; }
  .scroll { overflow: auto; flex: 1; min-height: 0; padding: 0 12px 12px; display: flex; flex-direction: column; gap: 10px; }
  .empty { padding: 30px; text-align: center; }
  article { border: 1px solid var(--line); border-radius: 12px; overflow: hidden; flex: none; }
  .title { display: flex; align-items: baseline; gap: 8px; width: 100%; text-align: left; padding: 9px 12px; background: var(--soft); }
  .title b { font-size: 15px; }
  .title small { color: var(--sub); margin-left: auto; white-space: nowrap; }
  .row { display: flex; align-items: center; gap: 8px; padding: 6px 12px; }
  pre { margin: 0; flex: 1; white-space: pre-wrap; word-break: break-word; font: inherit; user-select: text; }
  code { flex: 1; font-size: 14px; word-break: break-all; }
  .mini { font-size: 12.5px; font-weight: 700; color: var(--sub); border: 1px solid var(--line); border-radius: 8px; padding: 3px 8px; flex: none; }
  .mini:hover { color: var(--ink); border-color: var(--sub); }
  .item { display: flex; gap: 9px; align-items: center; padding: 5px 12px; cursor: pointer; }
  .item input, .box { width: 17px; height: 17px; accent-color: var(--ok); flex: none; }
  .item.done span { color: var(--sub); text-decoration: line-through; }
  .quick { border: 0; padding: 4px 0; background: none; }
  .pin { padding: 12px 0 0; }
  .veil { position: fixed; inset: 0; background: rgba(0, 0, 0, .35); z-index: 10; }
  .panel {
    position: fixed; top: 0; right: 0; bottom: 0; width: min(440px, 100vw); z-index: 11;
    background: var(--card); border-left: 1px solid var(--line); padding: 20px; overflow: auto;
    display: flex; flex-direction: column; gap: 6px;
  }
  .panel .row { padding: 2px 0; }
  .h { font-size: 18px; font-weight: 800; }
  .actions { display: flex; gap: 8px; margin-top: 18px; }
  .grow { flex: 1; }
</style>
