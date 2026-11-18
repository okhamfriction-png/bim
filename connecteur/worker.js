// Connecteur Bim pour les conversations Claude (claude.ai, appli mobile).
// Petit serveur MCP (HTTP, sans état) : Claude y ajoute et lit les tâches du backlog,
// qui vit dans backlog.json d'un dépôt GitHub privé.
//
// Secrets attendus (jamais dans le dépôt) :
//   GITHUB_TOKEN  jeton GitHub limité au dépôt de données (Contents : lecture et écriture)
//   BIM_REPO      "compte/bim-data"
//   BIM_KEY       clé secrète placée dans l'adresse du connecteur : /mcp/<BIM_KEY>

const CATS = ["Mission", "Contenu", "Destiny", "Personnel", "Parking"];

const TOOLS = [
  {
    name: "ajouter_tache",
    description:
      "Ajoute une tâche au backlog Bim de l'utilisateur. À utiliser dès que la conversation fait " +
      "apparaître quelque chose qu'il doit faire lui-même (rappeler, envoyer, tourner, publier, " +
      "réviser, préparer…). Une tâche par action, titre court à l'infinitif, sans horaire ni échéance. " +
      "Catégories : Mission (recruteurs, ESN, candidatures, entretiens, révision technique), " +
      "Contenu (vidéos et réseaux), Destiny (théâtre), Personnel (tout le reste), " +
      "Parking (idée à ne pas traiter maintenant). Dis ensuite en une ligne ce qui a été ajouté.",
    inputSchema: {
      type: "object",
      properties: {
        titre: { type: "string", description: "Titre court à l'infinitif" },
        categorie: { type: "string", enum: CATS },
        priorite: {
          type: "integer",
          minimum: 0,
          maximum: 4,
          description: "P0 (le plus urgent) à P4 ; 2 par défaut",
        },
        note: {
          type: "string",
          description: "Descriptif affiché quand il déplie la tâche : script entier, plan, contexte",
        },
        liens: { type: "array", items: { type: "string" }, description: "Adresses utiles" },
        appel: {
          type: "boolean",
          description: "Vrai pour un appel ou un entretien de mission : la tâche passe devant tout",
        },
        source: {
          type: "string",
          description: "Nom de la conversation ou du projet d'où vient la tâche (ex. « Coach Java »)",
        },
      },
      required: ["titre", "categorie"],
    },
  },
  {
    name: "lister_taches",
    description:
      "Liste les tâches ouvertes du backlog Bim (priorité, catégorie, sprint). À consulter avant " +
      "d'ajouter une tâche pour éviter un doublon, ou quand l'utilisateur demande où il en est.",
    inputSchema: { type: "object", properties: {} },
  },
];

const enc = (s) => {
  const b = new TextEncoder().encode(s);
  let bin = "";
  for (let i = 0; i < b.length; i += 0x8000) bin += String.fromCharCode(...b.subarray(i, i + 0x8000));
  return btoa(bin);
};
const dec = (b64) =>
  new TextDecoder().decode(Uint8Array.from(atob(b64.replace(/\n/g, "")), (c) => c.charCodeAt(0)));

async function gh(env, method, body) {
  const base = env.GITHUB_API || "https://api.github.com";
  return fetch(`${base}/repos/${env.BIM_REPO}/contents/backlog.json`, {
    method,
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "bim-connecteur",
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

async function load(env) {
  const r = await gh(env, "GET");
  if (r.status === 404) return { doc: { version: 2, tasks: [], schedule: {} }, sha: null };
  if (!r.ok) throw new Error(`GitHub a répondu ${r.status} à la lecture`);
  const j = await r.json();
  return { doc: JSON.parse(dec(j.content)), sha: j.sha };
}

const isOpen = (t) => !t.deleted && t.status === "todo";
const cat = (t) => (CATS.includes(t.domain) ? t.domain : t.domain === "Travail" ? "Mission" : "Personnel");

async function ajouter(env, a) {
  const titre = String(a.titre || "").trim();
  if (!titre) throw new Error("Il manque le titre.");
  if (!CATS.includes(a.categorie)) throw new Error(`Catégorie inconnue. Choix : ${CATS.join(", ")}.`);
  const p = Number.isInteger(a.priorite) ? Math.min(4, Math.max(0, a.priorite)) : 2;
  for (let essai = 0; essai < 4; essai++) {
    const { doc, sha } = await load(env);
    doc.tasks = doc.tasks || [];
    if (doc.tasks.some((t) => isOpen(t) && t.title.trim().toLowerCase() === titre.toLowerCase())) {
      return `Déjà dans le backlog : ${titre}`;
    }
    const now = Date.now();
    doc.tasks.push({
      id: Array.from(crypto.getRandomValues(new Uint8Array(8)), (x) =>
        "abcdefghijklmnopqrstuvwxyz0123456789"[x % 36]).join(""),
      title: titre,
      note: String(a.note || ""),
      domain: a.categorie,
      priority: p,
      source: String(a.source || "Chat Claude"),
      links: Array.isArray(a.liens) ? a.liens.map(String) : [],
      rank: Math.max(0, ...doc.tasks.map((t) => t.rank || 0)) + 1,
      status: "todo",
      createdAt: now,
      updatedAt: now,
      doneAt: null,
      pickedOn: null,
      call: a.appel === true && a.categorie === "Mission",
      sprint: null,
      deleted: false,
    });
    const body = { message: `bim : + ${titre.slice(0, 60)}`, content: enc(JSON.stringify(doc, null, 1)) };
    if (sha) body.sha = sha;
    const r = await gh(env, "PUT", body);
    if (r.ok) return `Ajoutée au backlog Bim (${a.categorie}, P${p}) : ${titre}`;
    if (r.status !== 409 && r.status !== 422) throw new Error(`GitHub a refusé l'écriture (${r.status})`);
  }
  throw new Error("Conflit de synchro répété, réessaie.");
}

async function lister(env) {
  const { doc } = await load(env);
  const monday = (() => {
    const d = new Date();
    d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
    return d.toISOString().slice(0, 10);
  })();
  const tasks = (doc.tasks || []).filter(isOpen).sort(
    (a, b) => (a.priority ?? 2) - (b.priority ?? 2) || CATS.indexOf(cat(a)) - CATS.indexOf(cat(b)));
  if (!tasks.length) return "Le backlog est vide.";
  return tasks
    .map((t) => {
      const extra = [
        t.call ? "appel ou entretien" : "",
        t.sprint && t.sprint >= monday ? `sprint du ${t.sprint}` : "hors sprint",
        t.source ? `via ${t.source}` : "",
      ].filter(Boolean).join(" · ");
      return `P${t.priority ?? 2} [${cat(t)}] ${t.title} (${extra})`;
    })
    .join("\n");
}

async function rpc(env, m) {
  const ok = (result) => ({ jsonrpc: "2.0", id: m.id, result });
  const ko = (code, message) => ({ jsonrpc: "2.0", id: m.id ?? null, error: { code, message } });
  switch (m.method) {
    case "initialize":
      return ok({
        protocolVersion: m.params?.protocolVersion || "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "bim", title: "Bim", version: "1.0.0" },
        instructions:
          "Backlog personnel Bim. Ajoute une tâche dès que l'utilisateur a quelque chose à faire lui-même.",
      });
    case "ping":
      return ok({});
    case "tools/list":
      return ok({ tools: TOOLS });
    case "tools/call": {
      const { name, arguments: args = {} } = m.params || {};
      try {
        const text =
          name === "ajouter_tache" ? await ajouter(env, args)
          : name === "lister_taches" ? await lister(env)
          : null;
        if (text === null) return ko(-32602, `Outil inconnu : ${name}`);
        return ok({ content: [{ type: "text", text }], isError: false });
      } catch (e) {
        return ok({ content: [{ type: "text", text: `Échec : ${e.message}` }], isError: true });
      }
    }
    default:
      return m.id === undefined ? null : ko(-32601, `Méthode inconnue : ${m.method}`);
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!env.BIM_KEY || env.BIM_KEY.length < 24 || url.pathname !== `/mcp/${env.BIM_KEY}`) {
      return new Response("Introuvable", { status: 404 });
    }
    if (request.method !== "POST") {
      return new Response("Ce connecteur n'accepte que POST", { status: 405, headers: { Allow: "POST" } });
    }
    let msg;
    try {
      msg = await request.json();
    } catch {
      return Response.json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "JSON invalide" } }, { status: 400 });
    }
    const list = Array.isArray(msg) ? msg : [msg];
    const out = [];
    for (const m of list) {
      const r = await rpc(env, m);
      if (r && m.id !== undefined) out.push(r);
    }
    if (!out.length) return new Response(null, { status: 202 });
    return Response.json(Array.isArray(msg) ? out : out[0]);
  },
};
