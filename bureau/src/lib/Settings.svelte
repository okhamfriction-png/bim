<script>
  import { app, saveUi, link } from './store.svelte.js';

  let { close } = $props();
  let repo = $state(app.repo || 'okhamfriction-png/bim-data');
  let token = $state(app.token);

  const BLOCKS = [
    ['sprint', 'Sprint en cours', 'Les tâches du sprint, rangées par priorité'],
    ['backlog', 'Backlog', 'Les sprints à venir et les tâches hors sprint'],
    ['agenda', 'Agenda', 'Les blocs fixes et les dates de la semaine'],
  ];
  function toggle(k) {
    const b = app.ui.blocks;
    if (b[k] && Object.values(b).filter(Boolean).length === 1) return; // toujours au moins un bloc
    b[k] = !b[k];
    saveUi();
  }
  function theme(v) {
    app.ui.theme = v;
    saveUi();
  }
</script>

<div class="veil" onclick={close} role="presentation"></div>
<div class="panel" role="dialog" aria-label="Réglages">
  <div class="top">
    <h2>Réglages</h2>
    <button class="btn" onclick={close}>Fermer</button>
  </div>

  <h3>Blocs affichés</h3>
  {#each BLOCKS as [k, name, hint]}
    <label class="line">
      <input type="checkbox" checked={app.ui.blocks[k]} onchange={() => toggle(k)} />
      <span><b>{name}</b><small>{hint}</small></span>
    </label>
  {/each}

  <h3>Apparence</h3>
  <div class="seg">
    {#each [['system', 'Système'], ['light', 'Clair'], ['dark', 'Sombre']] as [v, n]}
      <button class:on={app.ui.theme === v} onclick={() => theme(v)}>{n}</button>
    {/each}
  </div>

  <h3>Synchronisation</h3>
  <p class="muted">Le même fichier que sur le téléphone, dans ton dépôt GitHub privé.</p>
  <label class="field">Dépôt<input bind:value={repo} autocomplete="off" placeholder="compte/bim-data" /></label>
  <label class="field">Jeton d'accès GitHub<input type="password" bind:value={token} autocomplete="off" /></label>
  <p class:err={app.sync === 'error'} class="state">
    {app.sync === 'ok' ? 'Synchronisé' : app.sync === 'sync' ? 'Synchronisation…' : app.sync === 'error' ? app.error : 'Pas encore relié : rien ne s\'affiche tant que le jeton manque.'}
  </p>
  <button class="btn primary" disabled={app.sync === 'sync'} onclick={() => link(repo, token)}>
    Relier et synchroniser
  </button>
</div>

<style>
  .veil { position: fixed; inset: 0; background: rgba(0, 0, 0, .35); z-index: 10; }
  .panel {
    position: fixed; top: 0; right: 0; bottom: 0; width: min(420px, 100vw); z-index: 11;
    background: var(--card); border-left: 1px solid var(--line); padding: 20px; overflow: auto;
    display: flex; flex-direction: column; gap: 8px;
  }
  .top { display: flex; justify-content: space-between; align-items: center; }
  h2 { margin: 0; font-size: 20px; }
  h3 { margin: 18px 0 2px; font-size: 12px; letter-spacing: .5px; text-transform: uppercase; color: var(--sub); }
  .line { display: flex; gap: 10px; align-items: center; padding: 6px 0; cursor: pointer; }
  .line input { width: 18px; height: 18px; accent-color: var(--accent); flex: none; }
  .line span { display: flex; flex-direction: column; }
  .line small { color: var(--sub); }
  .seg { display: flex; background: var(--soft); border: 1px solid var(--line); border-radius: 10px; padding: 2px; }
  .seg button { flex: 1; padding: 7px; border-radius: 8px; font-weight: 700; color: var(--sub); }
  .seg button.on { background: var(--card); color: var(--ink); box-shadow: var(--shadow); }
  .field { display: flex; flex-direction: column; gap: 4px; font-size: 12px; font-weight: 700; color: var(--sub); }
  .state { margin: 4px 0; font-weight: 600; color: var(--sub); }
  .state.err { color: var(--p0); }
  .primary { padding: 11px; }
  p { margin: 0; }
</style>
