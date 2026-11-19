<script>
  import { PRIO, LANES, app, place, addTask, lanePoints } from './store.svelte.js';
  import Task from './Task.svelte';

  // `sprint` : lundi du sprint, ou null pour les tâches hors sprint.
  let { tasks, sprint, adder = true } = $props();
  let over = $state(-1);
  let mark = $state(null); // où la tâche glissée tomberait : { id, after }
  let title = $state('');
  let prio = $state(2);

  const lane = (i) => tasks.filter((t) => t.priority === i);

  // Moitié haute d'une ligne : avant elle ; moitié basse : après.
  function hover(e, t) {
    e.preventDefault();
    const r = e.currentTarget.getBoundingClientRect();
    mark = { id: t.id, after: e.clientY > r.top + r.height / 2 };
  }
  function dropOn(e, i, t) {
    const after = mark?.id === t.id && mark.after;
    const l = lane(i);
    drop(e, i, after ? l[l.indexOf(t) + 1] ?? null : t);
  }
  function drop(e, i, before) {
    e.preventDefault();
    e.stopPropagation();
    over = -1;
    mark = null;
    const t = app.doc.tasks.find((x) => x.id === e.dataTransfer.getData('text/bim-task'));
    if (t && t !== before) place(t, i, sprint, before, lane(i));
  }
  function submit(e) {
    e.preventDefault();
    addTask(title, { priority: prio, sprint });
    title = '';
  }
</script>

{#if adder}
  <form class="adder" onsubmit={submit}>
    <input placeholder="Ajouter une tâche" bind:value={title} />
    <select bind:value={prio} aria-label="Priorité">
      {#each PRIO as p, i}<option value={i}>{p}</option>{/each}
    </select>
  </form>
{/if}
{#each PRIO as p, i}
  <section
    class="lane"
    class:over={over === i}
    role="list"
    ondragover={(e) => { e.preventDefault(); over = i; }}
    ondragleave={() => { over = -1; mark = null; }}
    ondrop={(e) => drop(e, i, null)}
  >
    <header style="--c: var(--p{i})">
      <span class="chip" style="background: var(--p{i})">{p}</span>
      <span class="name">{LANES[i]}</span>
      <span class="n">{lane(i).length ? lanePoints(lane(i)) : 'vide'}</span>
    </header>
    {#each lane(i) as t (t.id)}
      <div
        role="presentation"
        class="slot"
        class:before={mark?.id === t.id && !mark.after}
        class:after={mark?.id === t.id && mark.after}
        ondragover={(e) => hover(e, t)}
        ondrop={(e) => dropOn(e, i, t)}
      >
        <Task {t} />
      </div>
    {/each}
  </section>
{/each}

<style>
  .adder { display: flex; gap: 8px; padding: 10px 12px; border-top: 1px solid var(--line); }
  .adder select { width: 70px; }
  .lane.over header { outline: 2px solid var(--accent); outline-offset: -2px; }
  header {
    display: flex; align-items: center; gap: 9px; padding: 5px 12px;
    border-top: 1px solid var(--line);
    background: color-mix(in srgb, var(--c) 10%, var(--soft));
  }
  .slot { position: relative; }
  .slot.before::before, .slot.after::after {
    content: ''; position: absolute; left: 0; right: 0; height: 3px; background: var(--accent); z-index: 2;
  }
  .slot.before::before { top: -1px; }
  .slot.after::after { bottom: -2px; }
  .name { flex: 1; font-size: 12.5px; font-weight: 800; color: var(--sub); }
  .n { font-size: 12.5px; font-weight: 700; color: var(--sub); }
</style>
