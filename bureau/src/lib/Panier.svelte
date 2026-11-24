<script>
  // Un panier de basket à chaque point gagné (points du sprint, ou case Santé tenue).
  import { untrack } from 'svelte';
  import { app, valueWeek, healthTotal, current } from './store.svelte.js';

  let shot = $state(null); // { id, text }
  let prev = null, prevH = null, n = 0, timer;
  $effect(() => {
    const v = valueWeek();
    const hs = healthTotal(current());
    // Pas de panier pour des points arrivés par la synchro d'un autre appareil.
    const quiet = untrack(() => app.sync === 'sync');
    if (prev !== null && !quiet) {
      if (v > prev) fire(`+${v - prev} pt${v - prev > 1 ? 's' : ''}`);
      else if (hs > prevH) fire(`+${hs - prevH} Santé`);
    }
    prev = v;
    prevH = hs;
  });
  function fire(text) {
    clearTimeout(timer);
    shot = { id: ++n, text };
    timer = setTimeout(() => (shot = null), 2100);
  }
</script>

{#if shot}
  {#key shot.id}
    <div class="panier" aria-hidden="true">
      <div class="court">
        <div class="board"><i></i></div>
        <div class="fly"><div class="ball">🏀</div></div>
        <div class="rim"></div>
        <div class="net"></div>
        <div class="gain">{shot.text}</div>
      </div>
    </div>
  {/key}
{/if}
<span class="sr" role="status">{shot ? `Panier : ${shot.text}` : ''}</span>

<style>
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); }
  .panier {
    position: fixed; inset: 0; z-index: 60; pointer-events: none; display: grid; place-items: center;
    background: rgba(0, 0, 0, .38); animation: veil 2.1s ease both;
  }
  .court { position: relative; width: 340px; height: 420px; }
  .board {
    position: absolute; left: 95px; top: 40px; width: 150px; height: 100px; border-radius: 8px;
    background: #fff; border: 3px solid #94a3b8;
  }
  .board i { position: absolute; left: 44px; bottom: 6px; width: 56px; height: 40px; border: 3px solid #f97316; }
  .rim {
    position: absolute; left: 122px; top: 136px; width: 96px; height: 14px; border-radius: 50%;
    border: 5px solid #f97316; z-index: 3;
  }
  .net {
    position: absolute; left: 130px; top: 148px; width: 80px; height: 62px; z-index: 3; transform-origin: top;
    background: repeating-linear-gradient(60deg, transparent 0 9px, rgba(255, 255, 255, .85) 9px 11px),
      repeating-linear-gradient(-60deg, transparent 0 9px, rgba(255, 255, 255, .85) 9px 11px);
    clip-path: polygon(0 0, 100% 0, 80% 100%, 20% 100%);
    animation: net 2.1s ease both;
  }
  /* La balle : X régulier sur l'enveloppe, Y en cloche sur la balle. */
  .fly { position: absolute; left: 138px; top: 110px; z-index: 2; animation: fly-x 2.1s linear both; }
  .ball { font-size: 60px; line-height: 1; animation: fly-y 2.1s both; }
  .gain {
    position: absolute; left: 0; right: 0; top: 250px; text-align: center; font-size: 54px; font-weight: 900;
    color: #facc15; text-shadow: 0 3px 0 rgba(0, 0, 0, .45); animation: gain 2.1s both;
  }
  @keyframes veil { 0% { opacity: 0; } 10%, 82% { opacity: 1; } 100% { opacity: 0; } }
  @keyframes fly-x { 0% { transform: translateX(-200px); } 50%, 100% { transform: translateX(0); } }
  @keyframes fly-y {
    0% { transform: translateY(270px) rotate(0); animation-timing-function: cubic-bezier(.2, .7, .4, 1); }
    34% { transform: translateY(-150px) rotate(-200deg); animation-timing-function: cubic-bezier(.6, 0, .9, .5); }
    50% { transform: translateY(0) rotate(-320deg); animation-timing-function: ease-in; }
    68% { transform: translateY(190px) rotate(-380deg); opacity: 1; }
    76%, 100% { transform: translateY(230px) rotate(-400deg); opacity: 0; }
  }
  @keyframes net { 0%, 48% { transform: scaleY(1); } 56% { transform: scaleY(1.3); } 64% { transform: scaleY(.9); } 72%, 100% { transform: scaleY(1); } }
  @keyframes gain {
    0%, 50% { opacity: 0; transform: scale(.3); }
    60% { opacity: 1; transform: scale(1.25); }
    68%, 85% { opacity: 1; transform: scale(1); }
    100% { opacity: 0; transform: scale(1) translateY(-20px); }
  }
  @media (prefers-reduced-motion: reduce) {
    .fly, .net { animation: none; }
    .ball { animation: none; transform: translateY(40px); }
  }
</style>
