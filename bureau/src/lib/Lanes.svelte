<script>
  import { PRIO, LANES, app, place, addTask } from './store.svelte.js';
  import Task from './Task.svelte';

  // `sprint` : lundi du sprint, ou null pour les tâches hors sprint.
  let { tasks, sprint, adder = true } = $props();
  let over = $state(-1);
  let title = $state('');
  let prio = $state(2);

  const lane = (i) => tasks.filter((t) => t.priority === i);

  function drop(e, i, before) {
    e.preventDefault();
    e.stopPropagation();
    over = -1;
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
    ondragleave={() => (over = -1)}
    ondrop={(e) => drop(e, i, null)}
  >
    <header style="--c: var(--p{i})">
      <span class="chip" style="background: var(--p{i})">{p}</span>
      <span class="name">{LANES[i]}</span>
      <span class="n">{lane(i).length || 'vide'}</span>
    </header>
    {#each lane(i) as t (t.id)}
      <div role="presentation" ondrop={(e) => drop(e, i, t)}>
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
  .name { flex: 1; font-size: 12.5px; font-weight: 800; color: var(--sub); }
  .n { font-size: 12.5px; font-weight: 700; color: var(--sub); }
</style>
