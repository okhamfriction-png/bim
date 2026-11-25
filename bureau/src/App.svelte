<script>
  import {
    app, sync, thisMonday, sprints, sprintTasks, looseTasks, doneThisWeek, dateOf, addDays,
    valueWeek, valueToday, healthTotal, HEALTH, santeLabel, bonus, BONUS_EVERY, targetOf, plannedIn, p0In,
    current, closedSprints, closureOf, velocityLabel, saveUi,
  } from './lib/store.svelte.js';
  import Cloture from './lib/Cloture.svelte';
  import Historique from './lib/Historique.svelte';
  import Kpi from './lib/Kpi.svelte';
  import Sante from './lib/Sante.svelte';
  import Panier from './lib/Panier.svelte';
  import Dictee from './lib/Dictee.svelte';
  import Lanes from './lib/Lanes.svelte';
  import Task from './lib/Task.svelte';
  import Agenda from './lib/Agenda.svelte';
  import Settings from './lib/Settings.svelte';
  import Notes from './lib/Notes.svelte';
  import Liaison from './lib/Liaison.svelte';
  import { findLiaison } from './lib/liaison.js';

  // Ouvert depuis un lien de liaison (…#relier=bim1.…) : on demande le code court, et on
  // retire aussitôt le code de l'adresse.
  const given = findLiaison(location.hash);
  if (given) window.history.replaceState(null, '', location.pathname + location.search);
  let liaison = $state(given ? { mode: 'receive', code: given } : null); // { mode: send | receive, code? }
  let settings = $state(!app.token && !given);
  let notice = $state('');
  // Lien collé dans un onglet Bim déjà ouvert : seul le fragment change, la page ne se recharge pas.
  window.addEventListener('hashchange', () => {
    const c = findLiaison(location.hash);
    if (!c) return;
    window.history.replaceState(null, '', location.pathname + location.search);
    settings = false;
    liaison = { mode: 'receive', code: c };
  });
  function openLiaison(mode) {
    settings = false;
    liaison = { mode };
  }
  function linked(vaultFound) {
    notice = vaultFound
      ? 'Relié. Ton coffre de notes s\'ouvre avec ton code habituel, dans Notes.'
      : 'Relié.';
    setTimeout(() => (notice = ''), 7000);
  }
  let showDone = $state(false);
  let closing = $state(null); // sprint en cours de clôture
  let history = $state(false);
  let dictating = $state(false);
  let toast = $state('');
  function said(msg) {
    toast = msg;
    setTimeout(() => (toast = ''), 3500);
  }

  $effect(() => {
    let t = app.ui.theme;
    if (t === 'auto') {
      // Mode horaire : sombre entre les deux heures choisies.
      const h = new Date(app.now).getHours();
      const { darkFrom: d, lightFrom: l } = app.ui;
      const dark = d === l ? false : d > l ? h >= d || h < l : h >= d && h < l;
      t = dark ? 'dark' : 'light';
    }
    document.documentElement.dataset.theme = t === 'system' ? '' : t;
  });
  sync();

  const now = $derived(new Date(app.now));
  const cur = $derived(current());
  const target = $derived(targetOf(cur));
  const value = $derived(valueWeek());
  const sante = $derived(healthTotal(cur));
  const tokens = $derived(bonus());
  const fmtDate = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
  const fmtShort = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'short' });
  const range = (s) => `${fmtShort.format(dateOf(s))} – ${fmtShort.format(addDays(dateOf(s), 6))}`;
  // Onglets : un bloc seul, ou « Tout » pour ceux cochés dans les réglages.
  const TABS = [['sprint', 'Sprint'], ['backlog', 'Backlog'], ['agenda', 'Agenda'], ['notes', 'Notes'], ['kpi', 'KPI']];
  const show = (k) => (app.ui.focus ? app.ui.focus === k : app.ui.blocks[k]);
  const cols = $derived(TABS.filter(([k]) => show(k)).length);
  function focus(k) {
    app.ui.focus = k;
    saveUi();
  }
  const fmtLong = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long' });
  // Un sprint se clôture une fois commencé : celui en cours, ou un sprint passé resté ouvert.
  const closable = (s) => s <= thisMonday();
  const lastClosed = $derived(closedSprints()[0]);
  // Le logo rafraîchit tout : il envoie et récupère les données, puis recharge la page.
  let refreshing = $state(false);
  async function refresh() {
    refreshing = true;
    try {
      await sync();
    } catch {}
    location.reload();
  }
  const warn = (s) => plannedIn(s) < targetOf(s) || p0In(s) > 3;
  const plan = (s) =>
    `Prévu ${plannedIn(s)} pts · cible ${targetOf(s)}` +
    (plannedIn(s) < targetOf(s) ? ' · sous la cible' : '') +
    (velocityLabel() ? ` · ${velocityLabel()}` : '') +
    (p0In(s) > 3 ? ` · ${p0In(s)} P0 (3 max)` : '');
</script>

<div class="app">
  <header>
    <button class="logo" class:spin={refreshing} onclick={refresh} disabled={refreshing}
      title="Synchroniser puis recharger toute la page" aria-label="Rafraîchir Bim">bim <i>↻</i></button>
    <span class="date">{fmtDate.format(now)}</span>
    <div class="value" title="Points de valeur gagnés cette semaine">
      <span><b>{value}</b> / {target} pts <small>+{valueToday()} aujourd'hui</small></span>
      <div class="bar"><i style="width: {target ? Math.min(100, (100 * value) / target) : 0}%"></i></div>
      <span class="bonus" class:has={tokens.left > 0} title="Un jeton tous les {BONUS_EVERY} points d'abordage de rue ; il se dépense dans l'appli du téléphone">
        🎟️ {tokens.left > 0 ? `${tokens.left} jeton${tokens.left > 1 ? 's' : ''} bonus à dépenser` : `Jeton bonus : ${tokens.progress} / ${BONUS_EVERY} pts de rue`}
      </span>
    </div>
    <nav class="tabs" aria-label="Blocs affichés">
      <button class:on={!app.ui.focus} onclick={() => focus('')} title="Les blocs cochés dans les réglages">Tout</button>
      {#each TABS as [k, name]}
        <button class:on={app.ui.focus === k} onclick={() => focus(k)}>{name}</button>
      {/each}
    </nav>
    <span class="grow"></span>
    <button class="sync {app.sync}" onclick={sync} title={app.sync === 'error' ? app.error : 'Synchroniser'}>
      <i></i>{app.sync === 'ok' ? 'Synchronisé' : app.sync === 'sync' ? 'Synchro…' : app.sync === 'error' ? 'Erreur de synchro' : 'Non relié'}
    </button>
    <a class="btn" href="../?mobile=1" title="L'appli complète, au format téléphone">Version mobile</a>
    <button class="btn" onclick={() => (dictating = true)} title="Dicter une note, une tâche, des courses">🎤 Dicter</button>
    <button class="btn" onclick={() => (settings = true)}>Réglages</button>
  </header>

  <main style="grid-template-columns: repeat({cols}, minmax(0, 1fr))">
    {#if show('sprint')}
      <section class="block">
        <div class="head accent">
          <div>
            <h2>Sprint en cours</h2>
            <span class="muted">{range(cur)}</span>
          </div>
          <span class="plan" class:warn={warn(cur)}>{plan(cur)}</span>
          {#if closable(cur)}<button class="btn primary" onclick={() => (closing = cur)}>Clôturer le sprint</button>{/if}
        </div>
        <div class="score" title="Points gagnés cette semaine, sur la cible du sprint">
          <span class="ball">🏀</span>
          <div class="num">{#key value}<b>{value}</b>{/key}<span>/ {target} pts</span></div>
          <div class="track">
            <div class="bar"><i style="width: {target ? Math.min(100, (100 * value) / target) : 0}%"></i></div>
            <small>+{valueToday()} aujourd'hui · reste {Math.max(0, target - value)} pour la cible</small>
          </div>
          <span class="chip">❤️ Santé {sante}/{7 * HEALTH.length}</span>
        </div>
        {#if lastClosed}
          <div class="sub closed">
            <span>🔒 <b>Sprint du {fmtLong.format(dateOf(lastClosed))} clôturé</b> · {closureOf(lastClosed).points} / {closureOf(lastClosed).target} pts{closureOf(lastClosed).sante ? ` · Santé ${santeLabel(closureOf(lastClosed))}` : ''}</span>
            <button class="btn" onclick={() => (history = true)}>Historique</button>
          </div>
        {/if}
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
          <Sante sprint={cur} />
        </div>
      </section>
    {/if}

    {#if show('backlog')}
      <section class="block">
        <div class="head"><div><h2>Backlog</h2><span class="muted">Sprints à venir et hors sprint</span></div></div>
        <div class="scroll">
          {#each sprints().filter((s) => s !== cur) as s (s)}
            <div class="sub">
              <b>{s < cur ? 'Sprint à clôturer · ' : 'Sprint du '}{range(s)}</b>
              <span class="plan" class:warn={warn(s)}>{plan(s)}</span>
              {#if closable(s)}<button class="btn primary" onclick={() => (closing = s)}>Clôturer</button>{/if}
            </div>
            <Lanes tasks={sprintTasks(s)} sprint={s} adder={false} />
          {/each}
          <div class="sub"><b>Hors sprint</b><span class="muted">{looseTasks().length} tâches</span></div>
          <Lanes tasks={looseTasks()} sprint={null} />
        </div>
      </section>
    {/if}

    {#if show('agenda')}
      <section class="block">
        <div class="head"><div><h2>Agenda</h2><span class="muted">Blocs fixes, dates et rappels</span></div></div>
        <Agenda {said} />
      </section>
    {/if}

    {#if show('kpi')}
      <section class="block">
        <div class="head"><div><h2>Tableau de bord</h2><span class="muted">Ce qui a été fait, ou pas</span></div></div>
        <Kpi />
      </section>
    {/if}

    {#if show('notes')}
      <section class="block">
        <div class="head"><div><h2>Notes</h2><span class="muted">Courses et coffre chiffré, partagés avec le téléphone</span></div></div>
        <Notes liaison={() => openLiaison('receive')} />
      </section>
    {/if}
  </main>
</div>

{#if settings}<Settings close={() => (settings = false)} liaison={openLiaison} />{/if}
{#if liaison}{#key liaison}<Liaison mode={liaison.mode} code={liaison.code} close={() => (liaison = null)} done={linked} />{/key}{/if}
{#if notice}<div class="notice" role="status">{notice}</div>{/if}
{#if closing}<Cloture sprint={closing} close={() => (closing = null)} />{/if}
{#if history}<Historique close={() => (history = false)} />{/if}
{#if dictating}<Dictee close={() => (dictating = false)} done={said} />{/if}
{#if toast}<div class="toast">{toast}</div>{/if}
<Panier />

<style>
  .app { height: 100%; display: flex; flex-direction: column; }
  header { display: flex; align-items: center; gap: 16px; padding: 12px 20px; }
  .logo {
    background: var(--accent); color: var(--on-accent); font-weight: 900; font-size: 18px;
    padding: 3px 11px; border-radius: 9px; letter-spacing: -.5px; display: inline-flex; align-items: center; gap: 6px;
  }
  .logo i { font-style: normal; font-size: 15px; display: inline-block; }
  .logo:hover i { transform: rotate(60deg); transition: transform .2s; }
  .logo.spin i { animation: turn .7s linear infinite; }
  @keyframes turn { to { transform: rotate(360deg); } }
  .date { font-weight: 800; font-size: 16px; text-transform: capitalize; }
  .value { min-width: 220px; display: flex; flex-direction: column; gap: 4px; font-size: 13.5px; }
  .value b { font-size: 16px; }
  .value small { color: var(--sub); margin-left: 8px; }
  .bonus { color: var(--sub); font-size: 12.5px; }
  .bonus.has { color: #d97706; font-weight: 800; }
  .bar { height: 6px; border-radius: 99px; background: var(--line); overflow: hidden; }
  .bar i { display: block; height: 100%; background: var(--ok); border-radius: 99px; transition: width .3s; }
  .grow { flex: 1; }
  .toast {
    position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%); z-index: 40; max-width: 80vw;
    background: var(--ink); color: var(--bg); padding: 10px 16px; border-radius: 12px; font-weight: 700;
  }
  .tabs { display: flex; gap: 2px; padding: 3px; background: var(--line); border-radius: 11px; }
  .tabs button { padding: 6px 13px; border-radius: 8px; font-size: 13.5px; font-weight: 800; color: var(--sub); }
  .tabs button.on { background: var(--card); color: var(--ink); }
  .closed { font-size: 13.5px; }
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
  .score { display: flex; align-items: center; gap: 14px; padding: 12px 16px; border-bottom: 1px solid var(--line); }
  .score .ball { font-size: 34px; line-height: 1; }
  .score .num { display: flex; align-items: baseline; gap: 7px; white-space: nowrap; }
  .score .num b { font-size: 40px; font-weight: 900; line-height: 1; color: var(--ok); display: inline-block; animation: bump .5s ease; }
  .score .num span { font-size: 16px; font-weight: 700; color: var(--sub); }
  .score .track { flex: 1; min-width: 80px; display: flex; flex-direction: column; gap: 5px; }
  .score .track .bar { height: 10px; border-radius: 99px; background: var(--line); overflow: hidden; }
  .score .track .bar i { display: block; height: 100%; border-radius: 99px; background: var(--ok); transition: width .6s ease; }
  .score small { color: var(--sub); font-size: 12.5px; }
  .score .chip { font-weight: 800; font-size: 13.5px; white-space: nowrap; padding: 5px 10px; border-radius: 99px; border: 1px solid var(--line); }
  @keyframes bump { 0% { transform: scale(1.5); } 100% { transform: scale(1); } }
  .scroll { overflow: auto; flex: 1; min-height: 0; }
  .sub {
    display: flex; justify-content: space-between; align-items: center; gap: 10px;
    padding: 9px 14px; border-top: 1px solid var(--line); background: var(--soft);
  }
  .fold {
    width: 100%; text-align: left; padding: 9px 14px; border-top: 1px solid var(--line);
    font-weight: 700; font-size: 13px; color: var(--sub); background: var(--soft);
  }
  .notice {
    position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%); z-index: 30;
    background: var(--ink); color: var(--card); padding: 12px 18px; border-radius: 12px;
    font-weight: 700; box-shadow: var(--shadow);
  }
  @media (max-width: 900px) {
    main { grid-template-columns: 1fr !important; overflow: auto; }
    .block { min-height: 70vh; }
    .value { display: none; }
  }
</style>
