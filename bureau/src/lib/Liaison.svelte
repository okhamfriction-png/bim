<script>
  // Relier un appareil : « send » sur un appareil déjà relié (QR code + lien chiffrés + code
  // court), « receive » sur l'appareil à relier (coller le lien, taper le code court).
  import { untrack } from 'svelte';
  import qrcode from 'qrcode-generator';
  import { app, link } from './store.svelte.js';
  import { syncNotes, exists } from './notes.svelte.js';
  import { syncCourses } from './courses.svelte.js';
  import { makeLiaison, liaisonLink, readLiaison, findLiaison, newPin, showPin, MINUTES } from './liaison.js';

  let { mode, code: given = '', close, done = () => {} } = $props();

  // ---- Envoyer ----
  let now = $state(Date.now());
  let pin = $state('');
  let url = $state('');
  let expires = $state(0);
  let copied = $state(false);
  async function make() {
    url = '';
    const p = newPin();
    const c = await makeLiaison(app.repo, app.token, p);
    pin = p;
    url = liaisonLink(c);
    now = Date.now();
    expires = now + MINUTES * 60000;
  }
  if (mode === 'send') make();
  const tick = setInterval(() => (now = Date.now()), 10000);
  $effect(() => () => clearInterval(tick));
  const left = $derived(Math.ceil((expires - now) / 60000));
  const expired = $derived(!!url && left <= 0);
  const qr = $derived.by(() => {
    if (!url) return null;
    const q = qrcode(0, 'L');
    q.addData(url);
    q.make();
    const n = q.getModuleCount();
    let d = '';
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (q.isDark(y, x)) d += `M${x} ${y}h1v1h-1z`;
    return { n, d };
  });
  function copy() {
    navigator.clipboard?.writeText(url);
    copied = true;
    setTimeout(() => (copied = false), 1200);
  }

  // ---- Recevoir ----
  const start = untrack(() => given); // le composant est recréé pour chaque nouveau lien
  let pasted = $state(start);
  let typed = $state('');
  let error = $state('');
  let busy = $state(false);
  const hasCode = !!findLiaison(start);
  async function go(e) {
    e.preventDefault();
    if (busy) return;
    busy = true;
    error = '';
    try {
      const r = await readLiaison(pasted, typed);
      await link(r.repo, r.token);
      await syncNotes();
      syncCourses();
      if (app.sync !== 'ok') error = app.error;
      else {
        done(exists());
        close();
      }
    } catch (err) {
      error = err.message || `${err}`;
    }
    busy = false;
  }
</script>

<div class="veil" onclick={close} role="presentation"></div>
<div class="box" role="dialog" aria-label={mode === 'send' ? 'Relier un autre appareil' : 'Relier cet appareil'}>
  {#if mode === 'send'}
    <h2>Relier un autre appareil</h2>
    <p class="muted">
      Sur le nouvel appareil, scanne ce QR code avec l'appareil photo, ou ouvre le lien que tu
      t'envoies. Bim te demandera alors le code court ci-dessous.
    </p>
    {#if !qr}
      <p class="muted center">Un instant…</p>
    {:else}
      <div class="qr" class:off={expired}>
        <svg viewBox="-2 -2 {qr.n + 4} {qr.n + 4}" shape-rendering="crispEdges" aria-label="QR code de liaison">
          <rect x="-2" y="-2" width={qr.n + 4} height={qr.n + 4} fill="#fff" /><path d={qr.d} fill="#000" />
        </svg>
      </div>
      <small class="label">Code court</small>
      <div class="pin">{showPin(pin)}</div>
      <p class="center" class:err={expired} class:muted={!expired}>
        {expired ? 'Ce code a expiré.' : `Valable encore ${left} min. Tape-le à la main : ne l'envoie jamais avec le lien.`}
      </p>
      {#if expired}
        <button class="btn primary" onclick={make}>Nouveau code</button>
      {:else}
        <div class="row">
          {#if navigator.share}
            <button class="btn primary" onclick={() => navigator.share({ title: 'Relier Bim', text: url }).catch(() => {})}>Envoyer le lien</button>
          {/if}
          <button class="btn" class:primary={!navigator.share} onclick={copy}>{copied ? 'Lien copié' : 'Copier le lien'}</button>
        </div>
      {/if}
      <p class="muted small center">
        Le lien est chiffré : sans le code court, il ne dit rien. Ensuite, le coffre de notes s'ouvre
        sur le nouvel appareil avec ton code habituel.
      </p>
    {/if}
    <button class="btn" onclick={close}>Fermer</button>
  {:else}
    <form onsubmit={go}>
      <h2>Relier cet appareil</h2>
      <p class="muted">
        {hasCode
          ? "Tape le code court affiché sur l'appareil déjà relié."
          : "Sur ton téléphone (déjà relié) : Réglages → Relier un autre appareil. Colle ici le lien qu'il t'envoie, puis tape le code court."}
      </p>
      {#if !hasCode}
        <label class="field">Lien ou code de liaison
          <textarea bind:value={pasted} rows="3" autocomplete="off" spellcheck="false"></textarea>
        </label>
      {/if}
      <label class="field">Code court (6 caractères)
        <!-- svelte-ignore a11y_autofocus -->
        <input class="pinput" bind:value={typed} maxlength="7" autocomplete="off" spellcheck="false" autofocus={hasCode} />
      </label>
      {#if error}<p class="err">{error}</p>{/if}
      <button class="btn primary" disabled={busy}>{busy ? 'Un instant…' : 'Relier'}</button>
      <button type="button" class="btn" onclick={close}>Annuler</button>
    </form>
  {/if}
</div>

<style>
  .veil { position: fixed; inset: 0; background: rgba(0, 0, 0, .45); z-index: 20; }
  .box {
    position: fixed; z-index: 21; top: 50%; left: 50%; transform: translate(-50%, -50%);
    width: min(420px, calc(100vw - 32px)); max-height: calc(100vh - 32px); overflow: auto;
    background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 22px;
    box-shadow: var(--shadow); display: flex; flex-direction: column; gap: 10px;
  }
  form { display: flex; flex-direction: column; gap: 10px; }
  h2 { margin: 0; font-size: 20px; }
  p { margin: 0; line-height: 1.4; }
  .center { text-align: center; }
  .small { font-size: 12.5px; }
  .err { color: var(--p0); font-weight: 600; }
  .qr { align-self: center; width: 230px; height: 230px; padding: 10px; background: #fff; border-radius: 14px; }
  .qr.off { opacity: .25; }
  .qr svg { width: 100%; height: 100%; display: block; }
  .label { text-align: center; font-weight: 700; color: var(--sub); text-transform: uppercase; font-size: 12px; letter-spacing: .5px; }
  .pin { text-align: center; font: 900 34px/1.1 ui-monospace, Menlo, monospace; letter-spacing: 4px; user-select: all; }
  .row { display: flex; gap: 10px; }
  .row .btn { flex: 1; }
  .btn { padding: 11px; }
  .field { display: flex; flex-direction: column; gap: 4px; font-size: 12px; font-weight: 700; color: var(--sub); }
  textarea { font: 13px ui-monospace, Menlo, monospace; resize: vertical; }
  .pinput { font: 800 22px ui-monospace, Menlo, monospace; letter-spacing: 3px; text-transform: uppercase; }
</style>
