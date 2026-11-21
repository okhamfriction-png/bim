// Sources de l'échauffement. « checked » = la page a été ouverte et lue le 21 novembre 2026 ;
// sinon le lien a été donné par Marouane et n'a pas été relu. Rien n'est cité de mémoire.
import 'defi_data.dart';

const methodText =
    'L\'échelle des genres vient des exercices préparatoires des écoles de rhétorique grecques '
    '(progymnasmata), pensés du plus simple au plus difficile : raconter (fable, récit), développer une parole '
    'donnée (anecdote, maxime), prendre position (réfutation, lieu commun, éloge ou blâme, comparaison), '
    'incarner et faire voir (éthopée, description), puis argumenter une question et une règle (thèse, '
    'proposition de loi). L\'ordre exact suivi ici est celui d\'Aphthonios ; Théon et Hermogène en donnent un '
    'autre, et les maîtres anciens en discutaient déjà.\n\n'
    'Pour Quintilien, improviser est le couronnement de la formation, et ce sont l\'émotion et les images '
    'gardées devant les yeux qui rendent éloquent. La voix et le corps viennent de l\'action oratoire : '
    'Démosthène la donnait pour première, deuxième et troisième qualité de l\'orateur.\n\n'
    'La progression par paliers suit la pratique délibérée (Ericsson) : un objectif précis, un retour immédiat, '
    'la même tâche répétée. La cible d\'un « euh » par minute et le silence à la place du « euh » viennent d\'un '
    'article de praticien (Zandan, 2018), pas d\'une étude scientifique ; une étude de 1995 nuance même ce '
    'conseil : c\'est la parole sans aucune pause qui y est la mieux notée.\n\n'
    'La contrainte « sans hésitation » rappelle le jeu radiophonique Just a Minute (BBC, 1967) et le rôle de '
    'compteur de « euh » chez Toastmasters. Garder un plan d\'étapes et improviser le reste vient de la '
    'commedia dell\'arte (canevas et lazzi).';

const sources = <Source>[
  Source('Structure',
      'George A. Kennedy (trad.), Progymnasmata: Greek Textbooks of Prose Composition and Rhetoric, Society of Biblical Literature, 2003. Exercices de difficulté croissante ; tableau des ordres chez Théon, Hermogène, Aphthonios et Nicolaos (p. xiii). L\'ordre en 14 exercices est celui d\'Aphthonios seul.',
      'https://www.sbl-site.org/wp-content/uploads/2024/11/KennedyProgymnasmata.pdf',
      checked: true),
  Source('Structure',
      'Gideon O. Burton, « Rhetorical Pedagogy: progymnasmata », Silva Rhetoricae, Brigham Young University (année non indiquée). Liste les 14 exercices dans le même ordre, sans dire qu\'ils vont du facile au difficile.',
      'https://rhetoric.byu.edu/Pedagogy/Progymnasmata/Progymnasmata.htm',
      checked: true),
  Source('Improvisation, émotion et images',
      'Quintilien, Institution oratoire, X, 7, 1-7, trad. H. E. Butler, 1920-1922. L\'improvisation est le couronnement de l\'étude.',
      'https://cts.perseids.org/read/latinLit/phi1002/phi001/perseus-eng2/10.7.1-10.7.7',
      checked: true),
  Source('Improvisation, émotion et images',
      'Quintilien, Institution oratoire, X, 7, 15-29, trad. H. E. Butler, 1920-1922. Le sentiment et la force de l\'imagination rendent éloquent ; la pratique quotidienne construit l\'aisance.',
      'https://cts.perseids.org/read/latinLit/phi1002/phi001/perseus-eng2/10.7.15-10.7.29',
      checked: true),
  Source('Voix et corps',
      'Vies des dix orateurs (texte transmis sous le nom de Plutarque, Moralia), « Démosthène », trad. H. N. Fowler, 1936, reproduite sur un blog personnel. L\'action citée trois fois ; ce texte ne parle pas des cailloux.',
      'https://nemoslibrary.com/2015/12/18/moralia-life-of-demosthenes-the-orator/',
      checked: true),
  Source('Voix et corps',
      'Plutarque, Vie de Démosthène, 10-11, trad. B. Perrin, 1919. Les cailloux dans la bouche, la voix travaillée en courant et en montant, le grand miroir.',
      'https://cts.perseids.org/read/greekLit/tlg0007/tlg054/perseus-eng2/10.1-11.2',
      checked: true),
  Source('Personnages',
      'Kennedy 2003 : Théon ch. 8 (prosopopée), Hermogène ch. 9 et Aphthonios ch. 11 (éthopée). Composer les paroles qu\'une personne donnée dirait dans une situation donnée.',
      'https://www.sbl-site.org/wp-content/uploads/2024/11/KennedyProgymnasmata.pdf',
      checked: true),
  Source('Images',
      'Kennedy 2003 : Théon ch. 7, Hermogène ch. 10, Aphthonios ch. 12. L\'ekphrasis est une description qui met la chose sous les yeux, avec clarté et vivacité.',
      'https://www.sbl-site.org/wp-content/uploads/2024/11/KennedyProgymnasmata.pdf',
      checked: true),
  Source('Carte d\'ensemble',
      'Gideon O. Burton, « The Canons of Rhetoric », Silva Rhetoricae, Brigham Young University (année non indiquée). Les cinq parties : invention, disposition, style, mémoire, action. La page ne dit pas « romaine ».',
      'https://rhetoric.byu.edu/Canons/Canons.htm',
      checked: true),
  Source('Méthode de progression',
      'K. Anders Ericsson, réponse à Macnamara et Hambrick, Psychological Research 85, 2021. Rappelle les critères d\'origine de la pratique délibérée (Ericsson, Krampe et Tesch-Römer, 1993). Seul le résumé a été lu ; l\'article de 1993 lui-même n\'a pas été consulté.',
      'https://pmc.ncbi.nlm.nih.gov/articles/PMC8049893/',
      checked: true),
  Source('Les « euh » et le silence',
      'Noah Zandan, « How to Stop Saying "Um," "Ah," and "You Know" », Harvard Business Review, 2018. Remplacer le mot de remplissage par une pause ; environ cinq par minute en moyenne, un comme idéal. Article de praticien, chiffres de son entreprise.',
      'https://foodsci.rutgers.edu/Graduate/PDF/GettingPastUmm.pdf',
      checked: true),
  Source('Les « euh » et le silence',
      'J. H. N. Lee et A. Papafragou, « Disfluency in Spontaneous Speech: Social Attribution and Behavioral Consequences », Cognitive Science Society, 2026. Les « euh » font paraître moins prêt et moins sûr ; l\'effet dépend du contexte.',
      'https://escholarship.org/uc/item/8579j2fh',
      checked: true),
  Source('Les « euh » et le silence',
      'Nicholas Christenfeld, « Does it hurt to say um? », Journal of Nonverbal Behavior 19, 1995. Résumé lu : les « euh » ne viennent pas de l\'anxiété ; les pauses pleines sont mieux notées que les silences, et la parole sans pause est la mieux notée. Ne soutient donc pas « le silence à la place du euh ».',
      'https://link.springer.com/article/10.1007/BF02175503',
      checked: true),
  Source('La contrainte « sans hésitation »',
      '« Just a Minute », Wikipédia en anglais. Première diffusion sur BBC Radio 4 le 22 décembre 1967 ; parler une minute sans hésitation, répétition ni digression. Le site de la BBC n\'a pas pu être ouvert.',
      'https://en.wikipedia.org/wiki/Just_a_Minute',
      checked: true),
  Source('La contrainte « sans hésitation »',
      'Toastmasters International, « Ah-Counter » (année non indiquée). Ce rôle note les mots et sons de remplissage et les pauses trop longues.',
      'https://www.toastmasters.org/membership/club-meeting-roles/ah-counter',
      checked: true),
  Source('Canevas et improvisation',
      '« Canovaccio », Wikipédia en anglais. Un scénario réduit à la liste des actes et des scènes, le reste improvisé, avec les lazzi. Britannica et le Met n\'ont pas pu être ouverts.',
      'https://en.wikipedia.org/wiki/Canovaccio',
      checked: true),
  Source('Rue et vente', 'Howard (1990), effet du « comment allez-vous ? » avant une demande.',
      'https://bakadesuyo.com/?p=17122'),
  Source('Rue et vente', 'Guéguen et Pascual (2000), « vous êtes libre de… ».',
      'https://changingminds.org/techniques/general/sequential/but_you_are_free.htm'),
  Source('Rue et vente', 'Meineri et Guéguen, demander la disponibilité avant de parler.',
      'https://hal.archives-ouvertes.fr/hal-01980941v1'),
  Source('Rue et vente', 'Étude PFRA, 180 approches par signature dans la rue.',
      'https://www.thirdsector.co.uk/street-fundraisers-approach-180-people-every-sign-up-according-research/fundraising/article/1135077'),
  Source('Rue et vente', 'Baromètre ASTP 2026, bouche-à-oreille premier canal du théâtre.',
      'https://www.artcena.fr/en/node/4632813'),
  Source('Rue et vente', 'Témoignage du Fringe d\'Édimbourg, l\'heure avant le spectacle.',
      'https://www.solopress.com/blog/business-marketing/promoting-a-show-at-the-edinburgh-fringe/'),
  Source('Rue et vente', 'Camuffo et al., tester ses hypothèses sur le terrain.',
      'https://www.physicianleaders.org/articles/why-entrepreneurs-should-think-like-scientists'),
  Source('Rue et vente', 'Pencavel, productivité et heures de travail.', 'https://docs.iza.org/dp8129.pdf'),
  Source('Rue et vente', 'Azoulay et al., âge et expérience des fondateurs.',
      'https://www.nber.org/digest/jul18/when-it-comes-entrepreneurs-youth-isnt-everything'),
  Source('Rue et vente', 'Jahoda, fonctions latentes du travail (méta-analyse 2023).',
      'https://pmc.ncbi.nlm.nih.gov/articles/PMC10017486'),
  Source('Rue et vente', 'Petriglieri, Ashford et Wrzesniewski (2018), le cadre que se construisent les indépendants.',
      'https://positiveorgs.bus.umich.edu/?p=16345'),
];
