// Rappels : « préparer la tablette dimanche 11h » → le texte, le jour, l'heure.
// Mêmes règles que lib/rappels.dart.
const L = '(?<![a-zà-ÿ0-9])'; // pas au milieu d'un mot
const R = '(?![a-zà-ÿ0-9])';
const DAYS = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const MONTHS = ['janvier', 'f[ée]vrier', 'mars', 'avril', 'mai', 'juin', 'juillet', 'ao[ûu]t', 'septembre', 'octobre', 'novembre', 'd[ée]cembre'];
const cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : s);
const same = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

/** Ce qui n'est pas dit reste null : { text, day (Date), minutes }. */
export function parseReminder(said, now = new Date()) {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const plus = (d) => new Date(today.getFullYear(), today.getMonth(), today.getDate() + d);
  let s = ` ${said.trim()} `;
  let minutes = null;
  let day = null;
  const take = (pattern) => {
    const m = new RegExp(pattern, 'i').exec(s);
    if (m) s = `${s.slice(0, m.index)} ${s.slice(m.index + m[0].length)}`;
    return m;
  };
  let m = take(`${L}(?:[àa] |vers |pour )?(\\d{1,2}) ?(?:heures?|h|:) ?(\\d{2})?${R}`);
  if (m) {
    const h = +m[1], mn = +(m[2] ?? 0);
    if (h < 24 && mn < 60) minutes = h * 60 + mn;
  } else if (take(`${L}(?:[àa] |vers |pour )?midi${R}`)) {
    minutes = 720;
  }
  if (take(`${L}(?:apr[èe]s[- ]demain)${R}`)) {
    day = plus(2);
  } else if (take(`${L}demain(?: matin| soir| apr[èe]s[- ]midi)?${R}`)) {
    day = plus(1);
  } else if (take(`${L}ce soir${R}`)) {
    day = today;
    minutes ??= 1200;
  } else if (take(`${L}(?:aujourd['’]hui|ce matin|cet apr[èe]s[- ]midi|tout [àa] l['’]heure)${R}`)) {
    day = today;
  } else if ((m = take(`${L}(?:le |pour )?(${DAYS.join('|')})( prochain)?${R}`))) {
    let d = (DAYS.indexOf(m[1].toLowerCase()) - ((today.getDay() + 6) % 7) + 7) % 7;
    const passed = minutes != null && minutes <= now.getHours() * 60 + now.getMinutes();
    if (d === 0 && (m[2] || passed)) d = 7;
    day = plus(d);
  } else if ((m = take(`${L}(?:le )?(\\d{1,2})(?:er)? (${MONTHS.join('|')})${R}`))) {
    const mo = MONTHS.findIndex((x) => new RegExp(`^${x}$`, 'i').test(m[2]));
    day = new Date(today.getFullYear(), mo, +m[1]);
    if (day < today) day = new Date(today.getFullYear() + 1, mo, +m[1]);
  } else if ((m = take(`${L}(?:le )?(\\d{1,2})/(\\d{1,2})${R}`))) {
    day = new Date(today.getFullYear(), +m[2] - 1, +m[1]);
    if (day < today) day = new Date(today.getFullYear() + 1, +m[2] - 1, +m[1]);
  } else if ((m = take(`${L}le (\\d{1,2})(?:er)?${R}`))) {
    day = new Date(today.getFullYear(), today.getMonth(), +m[1]);
    if (day < today) day = new Date(today.getFullYear(), today.getMonth() + 1, +m[1]);
  }
  const text = s
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/(?:[\s,;:.-]|(?<![a-zà-ÿ])(?:à|a|le|pour|vers))+$/i, '')
    .replace(/^(?:de |d['’])/i, '')
    .trim();
  return { text: cap(text), day, minutes };
}

/** Heure proposée quand la phrase n'en dit pas : la prochaine heure pleine aujourd'hui, 9 h sinon. */
export const defaultTime = (day, now = new Date()) => (same(day, now) ? Math.min(23, now.getHours() + 1) * 60 : 540);

const fmt = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
const hm = (m) => (m % 60 === 0 ? `${Math.floor(m / 60)} h` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')}`);
/** « dimanche 29 novembre à 11 h », avec aujourd'hui et demain dits simplement. */
export function when(day, minutes) {
  const now = new Date();
  const name = same(day, now) ? "aujourd'hui"
    : same(day, new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)) ? 'demain' : fmt.format(day);
  return `${name} à ${hm(minutes)}`;
}
