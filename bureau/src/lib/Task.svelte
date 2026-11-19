<script>
  import {
    PRIO, CATS, KINDS, iconOf, valueLabel, sprints, dateOf, catOf,
    complete, reopen, toggleSub, addSub, removeSub, remove, touch,
  } from './store.svelte.js';

  let { t, drag = true } = $props();
  let open = $state(false);
  let sub = $state('');
  const done = $derived(t.status === 'done');
  const label = $derived(valueLabel(t));
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
          {#each t.subs as s}
            <label class="sub" class:on={s.done}>
              <input type="checkbox" checked={s.done} onchange={() => toggleSub(t, s)} />
              <span>{s.title}</span>
              <button class="x" title="Retirer" aria-label="Retirer la sous-tâche" onclick={() => removeSub(t, s)}>×</button>
            </label>
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
  .sub.on span { color: var(--sub); text-decoration: line-through; }
  .x { color: var(--sub); font-size: 18px; padding: 0 6px; visibility: hidden; }
  .sub:hover .x { visibility: visible; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
  .grid label { display: flex; flex-direction: column; gap: 4px; font-size: 12px; font-weight: 700; color: var(--sub); }
  .grid .wide { grid-column: 1 / -1; }
  textarea { resize: vertical; }
  .actions { display: flex; gap: 8px; justify-content: flex-end; }
</style>
