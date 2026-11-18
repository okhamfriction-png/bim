// Test local : faux GitHub en mémoire, vrai protocole du connecteur.  node test.mjs
import worker from "./worker.js";
import assert from "node:assert/strict";

let file = null, sha = 0, conflictOnce = true;
globalThis.fetch = async (url, init) => {
  assert.match(String(url), /repos\/moi\/bim-data\/contents\/backlog\.json$/);
  assert.equal(init.headers.Authorization, "Bearer jeton-de-test");
  if (init.method === "GET") {
    if (!file) return new Response("{}", { status: 404 });
    return Response.json({ sha: String(sha), content: file });
  }
  const b = JSON.parse(init.body);
  if (file && b.sha !== String(sha)) return new Response("{}", { status: 409 });
  if (conflictOnce && file) { conflictOnce = false; sha++; return new Response("{}", { status: 409 }); }
  file = b.content; sha++;
  return Response.json({}, { status: 200 });
};

const env = { GITHUB_TOKEN: "jeton-de-test", BIM_REPO: "moi/bim-data", BIM_KEY: "x".repeat(32), GITHUB_API: "http://faux" };
const call = async (body, path = `/mcp/${env.BIM_KEY}`, method = "POST") => {
  const r = await worker.fetch(new Request(`http://local${path}`, { method, body: method === "POST" ? JSON.stringify(body) : undefined }), env);
  return { status: r.status, json: r.status === 200 ? await r.json() : null };
};
const tool = async (name, args) => (await call({ jsonrpc: "2.0", id: 9, method: "tools/call", params: { name, arguments: args } })).json.result;

assert.equal((await call({}, "/mcp/mauvaise-cle")).status, 404);
assert.equal((await call(null, undefined, "GET")).status, 405);
const init = await call({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {} } });
assert.equal(init.json.result.serverInfo.name, "bim");
assert.equal((await call({ jsonrpc: "2.0", method: "notifications/initialized" })).status, 202);
const tl = await call({ jsonrpc: "2.0", id: 2, method: "tools/list" });
assert.deepEqual(tl.json.result.tools.map((t) => t.name), ["ajouter_tache", "lister_taches"]);

assert.match((await tool("lister_taches", {})).content[0].text, /vide/);
let r = await tool("ajouter_tache", { titre: "Rappeler l'ESN Zenika", categorie: "Mission", priorite: 0, appel: true, source: "Mission IT" });
assert.equal(r.isError, false); assert.match(r.content[0].text, /Mission, P0/);
r = await tool("ajouter_tache", { titre: "Écrire le script « statut »", categorie: "Contenu", note: "HOOK : …\nCTA : …" });
assert.equal(r.isError, false, "le conflit 409 doit être rattrapé");
r = await tool("ajouter_tache", { titre: "rappeler l'esn zenika", categorie: "Mission" });
assert.match(r.content[0].text, /Déjà/);
r = await tool("ajouter_tache", { titre: "X", categorie: "Sport" });
assert.equal(r.isError, true);
const doc = JSON.parse(Buffer.from(file, "base64").toString("utf8"));
assert.equal(doc.tasks.length, 2);
assert.equal(doc.tasks[0].call, true); assert.equal(doc.tasks[1].priority, 2);
assert.equal(doc.tasks[1].title, "Écrire le script « statut »");
const l = (await tool("lister_taches", {})).content[0].text;
assert.match(l.split("\n")[0], /^P0 \[Mission\] Rappeler/);
console.log("Tous les tests passent.\n" + l);
