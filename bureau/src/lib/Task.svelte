<script>
  import {
    PRIO, CATS, KINDS, iconOf, pointsLabel, unitsLabel, sprints, dateOf, catOf,
    complete, reopen, toggleSub, addSub, removeSub, remove, touch, whole, setPrise, priseSummary, noted, kindOf, BLOCK_FIELDS, blockSummary, hasData, setSubField,
  } from './store.svelte.js';

  let { t, drag = true } = $props();
  let open = $state(false);
  let sub = $state('');
  let noting = $state(-1); // bloc de rue dont on remplit le bilan
  const done = $derived(t.status === 'done');
  // « 0/3 blocs · reportée du sprint du 16 novembre (2 reports) »
  const label = $derived(
    [
      unitsLabel(t),
      t.meta?.reports && t.meta?.reporteDe
        ? `reportée du sprint du ${dateOf(t.meta.reporteDe).getDate()} ${dateOf(t.meta.reporteDe).toLocaleDateString('fr-FR', { month: 'long' })}` +
          (t.meta.reports > 1 ? ` (${t.meta.reports} reports)` : '')
        : '',
    ].filter(Boolean).join(' · '),
  );
  const points = $derived(pointsLabel(t));
  const sprintName = (s) => `Sprint du ${dateOf(s).getDate()}/${dateOf(s).getMonth() + 1}`;

  function submitSub(e) {
    e.preventDefault();
    addSub(t, sub);
    sub = '';
  }
</script>

<div
  class="task"
  class:done
  class:open
  draggable={drag && !open}
  ondragstart={(e) => {
    e.dataTransfer.setData('text/bim-task', t.id);
    e.dataTransfer.effectAllowed = 'move';
  }}
  role="listitem"
>
  <div class="row">
    <button class="main" onclick={() => (open = !open)} title="Ouvrir la tâche">
      <span class="icon">{iconOf(t)}</span>
      <span class="text">
        <span class="title">{t.title}</span>
        {#if label || t.note}
          <span class="meta">{label}{label && t.note ? ' · ' : ''}{t.note ? t.note.split('\n')[0] : ''}</span>
        {/if}
      </span>
    </button>
    {#if points}<span class="pts">{points}</span>{/if}
    <span class="chip" style="background: var(--p{t.priority})">{PRIO[t.priority]}</span>
    <button
      class="check"
      class:on={done}
      title={done ? 'Remettre à faire' : 'Terminé'}
      aria-label={done ? 'Remettre à faire' : 'Terminé'}
      onclick={() => (done ? reopen(t) : complete(t))}
    >{done ? '✓' : ''}</button>
  </div>

  {#if open}
    <div class="body">
      {#if t.subs?.length}
        <div class="subs">
          {#each t.subs as s, i}
            <label class="sub" class:on={s.done}>
              <input type="checkbox" checked={s.done} onchange={() => toggleSub(t, s)} />
              <span>{s.title}</span>
              {#if whole(t)}
                <button class="res" class:has={noted(s)} title="Résultats de la prise"
                  onclick={(e) => { e.preventDefault(); noting = noting === i ? -1 : i; }}>
                  {priseSummary(s)}
                </button>
              {/if}
              {#if kindOf(t) === 'rue'}
                <button class="res" class:has={hasData(s)} title="Bilan du bloc"
                  onclick={(e) => { e.preventDefault(); noting = noting === i ? -1 : i; }}>
                  {hasData(s) ? blockSummary(s) || 'Noté' : 'Résultat'}
                </button>
              {/if}
              <button class="x" title="Retirer" aria-label="Retirer la sous-tâche" onclick={() => removeSub(t, s)}>×</button>
            </label>
            {#if noting === i && whole(t)}
              <div class="bilan">
                <label>Secondes tenues
                  <input type="number" min="0" value={s.data?.duree ?? ''}
                    onchange={(e) => setPrise(t, s, 'duree', e.currentTarget.value)} />
                </label>
                <label class="yes"><input type="checkbox" checked={s.data?.levierOk === true}
                  onchange={(e) => setPrise(t, s, 'levierOk', e.currentTarget.checked)} /> Levier du jour joué</label>
              </div>
            {:else if noting === i}
              <div class="bilan">
                {#each BLOCK_FIELDS as [key, label, isNum]}
                  <label class:wide={!isNum}>{label}
                    <input type={isNum ? 'number' : 'text'} min="0" value={s.data?.[key] ?? ''}
                      onchange={(e) => setSubField(t, s, key, isNum, e.currentTarget.value)} />
                  </label>
                {/each}
              </div>
            {/if}
          {/each}
        </div>
      {/if}
      <form onsubmit={submitSub}>
        <input placeholder="Ajouter une sous-tâche" bind:value={sub} />
      </form>

      <div class="grid">
        <label class="wide">Titre
          <input bind:value={t.title} onchange={() => touch(t)} />
        </label>
        <label class="wide">Descriptif
          <textarea rows="3" bind:value={t.note} onchange={() => touch(t)}></textarea>
        </label>
        <label>Priorité
          <select bind:value={t.priority} onchange={() => touch(t)}>
            {#each PRIO as p, i}<option value={i}>{p}</option>{/each}
          </select>
        </label>
        <label>Catégorie
          <select value={catOf(t)} onchange={(e) => { t.domain = e.currentTarget.value; touch(t); }}>
            {#each CATS as c}<option>{c}</option>{/each}
          </select>
        </label>
        <label>Type de points
          <select value={t.kind ?? ''} onchange={(e) => { t.kind = e.currentTarget.value; touch(t); }}>
            <option value="">Aucun</option>
            {#each Object.entries(KINDS) as [k, v]}<option value={k}>{v.name}</option>{/each}
          </select>
        </label>
        <label>Sprint
          <select value={t.sprint ?? ''} onchange={(e) => { t.sprint = e.currentTarget.value || null; touch(t); }}>
            <option value="">Hors sprint</option>
            {#each sprints() as s}<option value={s}>{sprintName(s)}</option>{/each}
          </select>
        </label>
        <label class="wide">Résultat (facultatif)
          <input value={t.result ?? ''} maxlength="60" placeholder="Ex. : 2 venus"
            onchange={(e) => { t.result = e.currentTarget.value.trim(); touch(t); }} />
        </label>
      </div>
      <div class="actions">
        <button class="btn" onclick={() => remove(t)}>Supprimer</button>
        <button class="btn" onclick={() => (open = false)}>Fermer</button>
      </div>
    </div>
  {/if}
</div>

<style>
  .task { border-top: 1px solid var(--line); background: var(--card); }
  .task.done:not(.open) { opacity: .55; }
  .row { display: flex; align-items: center; gap: 10px; padding: 7px 12px 7px 10px; }
  .main { display: flex; align-items: center; gap: 10px; flex: 1; min-width: 0; text-align: left; }
  .icon {
    width: 32px; height: 32px; flex: none; border-radius: 9px; background: var(--soft);
    display: grid; place-items: center; font-size: 16px;
  }
  .text { display: flex; flex-direction: column; min-width: 0; }
  .title { font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .done .title { text-decoration: line-through; }
  .meta { font-size: 12.5px; color: var(--sub); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .pts {
    flex: none; font-size: 12.5px; font-weight: 800; padding: 2px 8px; border-radius: 6px;
    color: var(--ok); background: color-mix(in srgb, var(--ok) 14%, var(--card));
  }
  .check {
    width: 24px; height: 24px; flex: none; border-radius: 50%; border: 2px solid var(--sub);
    display: grid; place-items: center; font-weight: 900; font-size: 13px;
  }
  .check:hover { border-color: var(--ok); }
  .check.on { background: var(--ok); border-color: var(--ok); color: #fff; }
  .body { padding: 4px 14px 14px 52px; display: flex; flex-direction: column; gap: 10px; }
  .subs { display: flex; flex-direction: column; }
  .sub { display: flex; align-items: center; gap: 9px; padding: 4px 0; }
  .sub input { width: 17px; height: 17px; accent-color: var(--ok); flex: none; }
  .sub span { flex: 1; }
  .res { flex: none; font-size: 12px; font-weight: 700; padding: 1px 9px; border: 1px solid var(--line); border-radius: 99px; color: var(--sub); }
  .res.has { color: var(--ink); }
  .bilan .yes { flex-direction: row; align-items: center; gap: 6px; }
  .bilan .yes input { width: 16px; height: 16px; flex: none; }
  .bilan { display: grid; grid-template-columns: repeat(5, 1fr); gap: 8px; padding: 6px 0 10px 26px; }
  .bilan label { display: flex; flex-direction: column; gap: 3px; font-size: 11.5px; font-weight: 700; color: var(--sub); }
  .bilan label.wide { grid-column: span 5; }
  .bilan input { width: 100%; }
  .sub input.score { width: 92px; height: auto; flex: none; padding: 2px 6px; font-size: 12.5px; }
  .sub.on span { color: var(--sub); text-decoration: line-through; }
  .x { color: var(--sub); font-size: 18px; padding: 0 6px; visibility: hidden; }
  .sub:hover .x { visibility: visible; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .grid label { display: flex; flex-direction: column; gap: 4px; font-size: 12px; font-weight: 700; color: var(--sub); }
  .grid .wide { grid-column: 1 / -1; }
  textarea { resize: vertical; }
  .actions { display: flex; gap: 8px; justify-content: flex-end; }
</style>
