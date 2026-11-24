// Tri d'une phrase dictée : le premier mot dit où elle va. Mêmes règles que lib/dictee.dart.
const WORDS = [
  ['liste de courses', 'courses'], ['nouvelle tâche', 'tache'], ['nouvelle tache', 'tache'], ['nouvelle note', 'note'],
  ['à faire', 'tache'], ['a faire', 'tache'], ['courses', 'courses'], ['course', 'courses'], ['achète', 'courses'],
  ['acheter', 'courses'], ['tâche', 'tache'], ['tache', 'tache'], ['rappel', 'tache'], ['notes', 'note'],
  ['note', 'note'], ['mémo', 'note'], ['memo', 'note'],
];
const cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);

/** Ce qu'une phrase dictée devient : [destination, texte sans le mot-clé]. */
export function route(said) {
  const s = said.trim();
  const low = s.toLowerCase();
  for (const [word, kind] of WORDS) {
    if (low === word) return [kind, ''];
    if (low.startsWith(word) && !/[a-zà-ÿ]/.test(low[word.length])) {
      return [kind, cap(s.slice(word.length).replace(/^[\s:,.-]+/, ''))];
    }
  }
  return ['note', cap(s)];
}
/** « pain, lait et œufs » → trois articles. */
export const splitArticles = (s) =>
  s.split(/,|;|(?<![a-zà-ÿ])et(?![a-zà-ÿ])|(?<![a-zà-ÿ])puis(?![a-zà-ÿ])/i).map((a) => cap(a.trim())).filter(Boolean);
