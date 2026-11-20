<script>
  import {
    app, sync, thisMonday, sprints, sprintTasks, looseTasks, doneThisWeek, dateOf, addDays,
    valueWeek, valueToday, bonus, BONUS_EVERY, targetOf, plannedIn, p0In,
  } from './lib/store.svelte.js';
  import Lanes from './lib/Lanes.svelte';
  import Task from './lib/Task.svelte';
  import Agenda from './lib/Agenda.svelte';
  import Settings from './lib/Settings.svelte';

  let settings = $state(!app.token);
  let showDone = $state(false);

  $effect(() => {
    document.documentElement.dataset.theme = app.ui.theme === 'system' ? '' : app.ui.theme;
  });
  sync();

  const now = $derived(new Date(app.now));
  const cur = $derived(thisMonday());
  const target = $derived(targetOf(cur));
  const value = $derived(valueWeek());
  const tokens = $derived(bonus());
  const fmtDate = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
  const fmtShort = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'short' });
  const range = (s) => `${fmtShort.format(dateOf(s))} – ${fmtShort.format(addDays(dateOf(s), 6))}`;
  const cols = $derived(Object.values(app.ui.blocks).filter(Boolean).length);
  const warn = (s) => plannedIn(s) < targetOf(s) || p0In(s) > 3;
  const plan = (s) =>
    `Prévu ${plannedIn(s)} pts · cible ${targetOf(s)}` +
    (plannedIn(s) < targetOf(s) ? ' · sous la cible' : '') +
    (p0In(s) > 3 ? ` · ${p0In(s)} P0 (3 max)` : '');
</script>

<div class="app">
  <header>
    <span class="logo">bim</span>
    <span class="date">{fmtDate.format(now)}</span>
    <div class="value" title="Points de valeur gagnés cette semaine">
      <span><b>{value}</b> / {target} pts <small>+{valueToday()} aujourd'hui</small></span>
      <div class="bar"><i style="width: {target ? Math.min(100, (100 * value) / target) : 0}%"></i></div>
      <span class="bonus" class:has={tokens.left > 0} title="Un jeton tous les {BONUS_EVERY} points d'abordage de rue ; il se dépense dans l'appli du téléphone">
        🎟️ {tokens.left > 0 ? `${tokens.left} jeton${tokens.left > 1 ? 's' : ''} bonus à dépenser` : `Jeton bonus : ${tokens.progress} / ${BONUS_EVERY} pts de rue`}
      </span>
    </div>
    <span class="grow"></span>
    <button class="sync {app.sync}" onclick={sync} title={app.sync === 'error' ? app.error : 'Synchroniser'}>
      <i></i>{app.sync === 'ok' ? 'Synchronisé' : app.sync === 'sync' ? 'Synchro…' : app.sync === 'error' ? 'Erreur de synchro' : 'Non relié'}
    </button>
    <a class="btn" href="../?mobile=1" title="L'appli complète, au format téléphone">Version mobile</a>
    <button class="btn" onclick={() => (settings = true)}>Réglages</button>
  </header>

  <main style="grid-template-columns: repeat({cols}, minmax(0, 1fr))">
    {#if app.ui.blocks.sprint}
      <section class="block">
        <div class="head accent">
          <div>
            <h2>Sprint en cours</h2>
            <span class="muted">{range(cur)}</span>
          </div>
          <span class="plan" class:warn={warn(cur)}>{plan(cur)}</span>
        </div>
        <div class="scroll">
          <Lanes tasks={sprintTasks(cur)} sprint={cur} />
          {#if doneThisWeek().length}
            <button class="fold" onclick={() => (showDone = !showDone)}>
              {showDone ? '▾' : '▸'} Faites cette semaine · {doneThisWeek().length}
            </button>
            {#if showDone}
              {#each doneThisWeek() as t (t.id)}<Task {t} drag={false} />{/each}
            {/if}
          {/if}
        </div>
      </section>
    {/if}

    {#if app.ui.blocks.backlog}
      <section class="block">
        <div class="head"><div><h2>Backlog</h2><span class="muted">Sprints à venir et hors sprint</span></div></div>
        <div class="scroll">
          {#each sprints().filter((s) => s !== cur) as s (s)}
            <div class="sub">
              <b>Sprint du {range(s)}</b>
              <span class="plan" class:warn={warn(s)}>{plan(s)}</span>
            </div>
            <Lanes tasks={sprintTasks(s)} sprint={s} adder={false} />
          {/each}
          <div class="sub"><b>Hors sprint</b><span class="muted">{looseTasks().length} tâches</span></div>
          <Lanes tasks={looseTasks()} sprint={null} />
        </div>
      </section>
    {/if}

    {#if app.ui.blocks.agenda}
      <section class="block">
        <div class="head"><div><h2>Agenda</h2><span class="muted">Blocs fixes et dates</span></div></div>
        <Agenda />
      </section>
    {/if}
  </main>
</div>

{#if settings}<Settings close={() => (settings = false)} />{/if}

<style>
  .app { height: 100%; display: flex; flex-direction: column; }
  header { display: flex; align-items: center; gap: 16px; padding: 12px 20px; }
  .logo {
    background: var(--accent); color: var(--on-accent); font-weight: 900; font-size: 18px;
    padding: 3px 11px; border-radius: 9px; letter-spacing: -.5px;
  }
  .date { font-weight: 800; font-size: 16px; text-transform: capitalize; }
  .value { min-width: 220px; display: flex; flex-direction: column; gap: 4px; font-size: 13.5px; }
  .value b { font-size: 16px; }
  .value small { color: var(--sub); margin-left: 8px; }
  .bonus { color: var(--sub); font-size: 12.5px; }
  .bonus.has { color: #d97706; font-weight: 800; }
  .bar { height: 6px; border-radius: 99px; background: var(--line); overflow: hidden; }
  .bar i { display: block; height: 100%; background: var(--ok); border-radius: 99px; transition: width .3s; }
  .grow { flex: 1; }
  a.btn { text-decoration: none; color: inherit; }
  .sync { display: flex; align-items: center; gap: 7px; font-size: 13px; font-weight: 700; color: var(--sub); }
  .sync i { width: 9px; height: 9px; border-radius: 50%; background: var(--p4); }
  .sync.ok i { background: var(--ok); }
  .sync.sync i { background: var(--accent); }
  .sync.error i { background: var(--p0); }
  .sync.error { color: var(--p0); }
  main { flex: 1; min-height: 0; display: grid; gap: 16px; padding: 0 20px 20px; }
  .block {
    background: var(--card); border: 1px solid var(--line); border-radius: 16px; overflow: hidden;
    display: flex; flex-direction: column; min-height: 0; box-shadow: var(--shadow);
  }
  .head { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 11px 14px; background: var(--soft); }
  .head.accent { background: color-mix(in srgb, var(--accent) 14%, var(--card)); }
  h2 { margin: 0; font-size: 16px; }
  .plan { font-size: 12.5px; font-weight: 700; color: var(--sub); text-align: right; }
  .plan.warn { color: var(--p0); }
  .scroll { overflow: auto; flex: 1; min-height: 0; }
  .sub {
    display: flex; justify-content: space-between; align-items: center; gap: 10px;
    padding: 9px 14px; border-top: 1px solid var(--line); background: var(--soft);
  }
  .fold {
    width: 100%; text-align: left; padding: 9px 14px; border-top: 1px solid var(--line);
    font-weight: 700; font-size: 13px; color: var(--sub); background: var(--soft);
  }
  @media (max-width: 900px) {
    main { grid-template-columns: 1fr !important; overflow: auto; }
    .block { min-height: 70vh; }
    .value { display: none; }
  }
</style>
