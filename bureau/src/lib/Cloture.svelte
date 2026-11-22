<script>
  // Clôture d'un sprint en trois étapes, comme dans l'appli du téléphone (lib/cloture.dart).
  import {
    PRIO, catOf, dateOf, addDays, plannedOf, unitsLabel, targetOf, sprintComplete, sprintUnfinished,
    closureDraft, closeSprint, nextSprint, reportsOf, setResult,
  } from './store.svelte.js';
  import Bilan from './Bilan.svelte';

  let { sprint, close } = $props();
  let step = $state(0);
  let choices = $state({}); // tâche → report | parking | drop
  let prios = $state({}); // priorité choisie pour une tâche reportée
  let keep = $state('');
  let decisions = $state('');

  const fmt = new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'long' });
  const range = (s) => `${fmt.format(dateOf(s))} au ${fmt.format(addDays(dateOf(s), 6))}`;
  const pts = (n) => `${n} pt${n > 1 ? 's' : ''}`;
  const done = $derived(sprintComplete(sprint));
  const rest = $derived(sprintUnfinished(sprint));
  const chosen = $derived(rest.filter((t) => choices[t.id]).length);
  const ready = $derived(chosen === rest.length);
  const TITLES = ['Terminé', 'Non terminé', 'Bilan'];
  const CHOICES = [
    ['report', '↪ Reporter au sprint suivant'],
    ['parking', '🅿️ Parking'],
    ['drop', '⛔ Abandonner'],
  ];

  function pick(t, c) {
    choices[t.id] = c;
    if (c !== 'report') delete prios[t.id];
  }
  function validate() {
    if (closeSprint(sprint, $state.snapshot(choices), $state.snapshot(prios), keep, decisions)) close();
  }
</script>

<div class="veil" onclick={close} role="presentation"></div>
<div class="panel" role="dialog" aria-label="Clôture du sprint">
  <div class="top">
    <div>
      <h2>Clôture · {TITLES[step]}</h2>
      <span class="muted">Sprint du {range(sprint)} · étape {step + 1} sur 3</span>
    </div>
    <button class="btn" onclick={close}>Fermer</button>
  </div>
  <div class="steps">{#each [0, 1, 2] as i}<i class:on={i <= step}></i>{/each}</div>

  <div class="scroll">
    {#if step === 0}
      <p class="muted">
        {done.length
          ? `${done.length} tâche${done.length > 1 ? 's' : ''} terminée${done.length > 1 ? 's' : ''}, ${pts(done.reduce((a, t) => a + plannedOf(t), 0))}. Tu peux encore corriger un résultat.`
          : 'Aucune tâche terminée dans ce sprint.'}
      </p>
      {#each done as t (t.id)}
        <div class="card">
          <div class="line">
            <span class="ok">✓</span><b>{t.title}</b>
            <span class="pts" class:none={!plannedOf(t)}>{plannedOf(t) ? pts(plannedOf(t)) : 'sans points'}</span>
          </div>
          {#if unitsLabel(t)}<span class="muted small">{unitsLabel(t)}</span>{/if}
          <input value={t.result ?? ''} placeholder="Résultat" onchange={(e) => setResult(t, e.target.value)} />
        </div>
      {/each}
    {:else if step === 1}
      <p class="muted">
        {rest.length
          ? `Pour chaque tâche, choisis ce qu'elle devient. Rien n'est reporté tout seul. Sprint suivant : ${range(nextSprint(sprint))}. Décidées : ${chosen} sur ${rest.length}.`
          : 'Tout est terminé : rien à décider.'}
      </p>
      {#each rest as t (t.id)}
        <div class="card" class:todo={!choices[t.id]}>
          <div class="line">
            <span class="chip" style="background: var(--p{prios[t.id] ?? t.priority})">{PRIO[prios[t.id] ?? t.priority]}</span>
            <b>{t.title}</b>
          </div>
          <span class="muted small">
            {[
              catOf(t),
              t.subs?.length ? `${t.subs.filter((x) => x.done).length}/${t.subs.length} sous-tâches` : '',
              t.status === 'done' ? 'cochée, mais il reste des sous-tâches' : '',
              plannedOf(t) ? `0 sur ${pts(plannedOf(t))}` : '',
            ].filter(Boolean).join(' · ')}
          </span>
          {#if reportsOf(t) >= 2}
            <span class="alert">⚠️ Déjà reportée {reportsOf(t)} fois</span>
          {:else if reportsOf(t) === 1}
            <span class="muted small">Déjà reportée une fois</span>
          {/if}
          <div class="picks">
            {#each CHOICES as [k, label]}
              <button class="pick {k}" class:on={choices[t.id] === k} onclick={() => pick(t, k)}>{label}</button>
            {/each}
          </div>
          {#if choices[t.id] === 'report'}
            <div class="picks">
              <span class="muted small">Priorité</span>
              {#each PRIO as name, i}
                <button class="chip" class:dim={(prios[t.id] ?? t.priority) !== i} style="background: var(--p{i})"
                  onclick={() => (prios[t.id] = i)}>{name}</button>
              {/each}
            </div>
          {/if}
        </div>
      {/each}
    {:else}
      <Bilan b={closureDraft(sprint, $state.snapshot(choices))} />
      <textarea rows="3" bind:value={keep} placeholder="Ce que je retiens"></textarea>
      <textarea rows="3" bind:value={decisions} placeholder="Décisions pour le sprint suivant"></textarea>
      <p class="muted small">Une fois le sprint clôturé, ses points et ce bilan sont figés. Le sprint suivant devient le sprint en cours.</p>
    {/if}
  </div>

  <div class="actions">
    {#if step > 0}<button class="btn" onclick={() => step--}>Retour</button>{/if}
    <span class="grow"></span>
    {#if step === 1 && !ready}<span class="warn">{rest.length - chosen} sans choix</span>{/if}
    {#if step < 2}
      <button class="btn primary" disabled={step === 1 && !ready} onclick={() => step++}>Suivant</button>
    {:else}
      <button class="btn primary" disabled={!ready} onclick={validate}>Clôturer le sprint</button>
    {/if}
  </div>
</div>

<style>
  .veil { position: fixed; inset: 0; background: rgba(0, 0, 0, .4); z-index: 20; }
  .panel {
    position: fixed; top: 0; right: 0; bottom: 0; width: min(620px, 100vw); z-index: 21;
    background: var(--bg); border-left: 1px solid var(--line); display: flex; flex-direction: column;
  }
  .top { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 16px 20px 8px; }
  h2 { margin: 0; font-size: 18px; }
  p { margin: 0; line-height: 1.35; }
  .small { font-size: 12.5px; }
  .steps { display: flex; gap: 6px; padding: 0 20px 10px; }
  .steps i { flex: 1; height: 5px; border-radius: 99px; background: var(--line); }
  .steps i.on { background: var(--accent); }
  .scroll { flex: 1; min-height: 0; overflow: auto; padding: 4px 20px 16px; display: flex; flex-direction: column; gap: 10px; }
  .card {
    background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 12px 14px;
    display: flex; flex-direction: column; gap: 6px; flex: none;
  }
  .card.todo { border: 1.5px solid var(--accent); }
  .line { display: flex; align-items: baseline; gap: 9px; }
  .line b { flex: 1; font-size: 15px; }
  .ok { color: var(--ok); font-weight: 900; }
  .pts { font-weight: 800; white-space: nowrap; }
  .pts.none { color: var(--sub); font-weight: 600; }
  .chip { color: #fff; font-size: 11.5px; font-weight: 900; padding: 2px 6px; border-radius: 6px; flex: none; }
  .chip.dim { opacity: .35; }
  .alert { color: var(--p0); font-weight: 800; background: color-mix(in srgb, var(--p0) 14%, transparent); border-radius: 9px; padding: 6px 10px; }
  .picks { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; padding-top: 4px; }
  .pick { border: 1.5px solid var(--line); border-radius: 99px; padding: 6px 12px; font-size: 13.5px; font-weight: 600; }
  .pick.on { font-weight: 800; }
  .pick.report.on { border-color: #0ea5e9; background: color-mix(in srgb, #0ea5e9 20%, transparent); }
  .pick.parking.on { border-color: var(--p4); background: color-mix(in srgb, var(--p4) 22%, transparent); }
  .pick.drop.on { border-color: var(--p0); background: color-mix(in srgb, var(--p0) 18%, transparent); }
  .actions { display: flex; align-items: center; gap: 10px; padding: 12px 20px; border-top: 1px solid var(--line); }
  .grow { flex: 1; }
  .warn { color: var(--p0); font-weight: 700; }
  .btn:disabled { opacity: .45; cursor: default; }
</style>
