import {
  COMET_DOT,
  COMET_RIBBONS,
  DOT_PEAK,
  DOT_R,
  DOT_X,
  NOTIF_ANGLE,
  NOTIF_DIST,
  NOTIF_MARGIN,
  NOTIF_POP,
  NOTIF_R,
  RINGS,
  SWOOSH,
  particles,
  type ArcSpec,
  type DotRender
} from './decor'
import { EYE_H, EYE_SPLIT, EYE_W, REST_GAZE, type HeadGaze } from './face'
import { TAU, clamp, easings, lerp } from './math'
import {
  circle,
  hullOfCircles,
  polyPath,
  profileFromPolygon,
  silhouette,
  type Point,
  type Silhouette
} from './shape'

export interface EyeCfg {
  /** largeur locale (axe court de la gelule), en unites de rayon de boule */
  w: number
  /** hauteur locale (axe long) */
  h: number
  /** 1 = ouvert, 0 = ferme */
  open: number
  /**
   * Inclinaison propre de la gelule, en degres, positif = le haut part a
   * droite. Appliquee APRES le repere tangent de la sphere. Sans elle, les deux
   * yeux penchent forcement du meme cote (le roulis de tete) et la colere comme
   * la tristesse, qui demandent des inclinaisons en miroir, sont hors de portee.
   */
  tilt?: number
}

export interface Pose {
  /** silhouette du corps, en unites de rayon de boule */
  sil: Silhouette
  /** decalage global du corps ET des yeux */
  offX: number
  offY: number
  gaze: HeadGaze
  /** demi-ecart des yeux sur la sphere, en degres */
  split: number
  /** [oeil interieur, oeil exterieur] */
  eyes: [EyeCfg, EyeCfg]
  /** opacite des yeux : sert aux etats sans visage */
  eyeAlpha: number
  /**
   * Echelle des yeux, position ET taille, autour du centre du corps. Les yeux ne
   * suivent pas `sil.sx/sy` : un etat qui retrecit le corps le declare ici, sinon
   * ils sortent de la silhouette. 1 = comme les autres etats.
   */
  eyeScale: number
  bodyAlpha: number
  dots: DotRender[]
  arcs: ArcSpec[]
  notif: { x: number; y: number; r: number; notch: number } | null
  /** true = le decor passe derriere le corps (particules de l'eclatement) */
  dotsBehind: boolean
}

const pair = (w: number, h: number): [EyeCfg, EyeCfg] => [
  { w, h, open: 1 },
  { w, h, open: 1 }
]

function base(over: Partial<Pose> = {}): Pose {
  return {
    sil: circle(1),
    offX: 0,
    offY: 0,
    gaze: { ...REST_GAZE },
    split: EYE_SPLIT,
    eyes: pair(EYE_W, EYE_H),
    eyeAlpha: 1,
    eyeScale: 1,
    bodyAlpha: 1,
    dots: [],
    arcs: [],
    notif: null,
    dotsBehind: false,
    ...over
  }
}

/* --------------------------------------------------- formes non radiales */

/**
 * Barre du "!" vertical : enveloppe convexe de deux cercles.
 * Mesure : cercle haut (0, -0.505) r 0.132, cercle bas (0, +0.130) r 0.075,
 * flancs rectilignes. Elle est donc tronconique (rapport haut/bas 1.76).
 */
const BAR_UPRIGHT_CY = -0.1875
const BAR_UPRIGHT = profileFromPolygon(
  hullOfCircles(0, -0.505, 0.132, 0, 0.13, 0.075),
  0,
  BAR_UPRIGHT_CY
)

/** Barre du "!" penche : capsule pure (largeur constante 0.269, longueur 0.776). */
const BAR_ITALIC = profileFromPolygon(hullOfCircles(0, -0.2535, 0.1345, 0, 0.2535, 0.1345), 0, 0)

const barUpright = (pose: Partial<Silhouette> = {}): Silhouette => ({
  radii: [...BAR_UPRIGHT],
  rot: 0,
  cx: 0,
  cy: BAR_UPRIGHT_CY,
  sx: 1,
  sy: 1,
  ...pose
})

const barItalic = (pose: Partial<Silhouette> = {}): Silhouette => ({
  radii: [...BAR_ITALIC],
  rot: 0,
  cx: 0,
  cy: 0,
  sx: 1,
  sy: 1,
  ...pose
})

/**
 * Le point du "!" penche n'est pas un disque : c'est une goutte, bout rond
 * (r 0.118) du cote de la barre et pointe effilee a l'oppose, longueur 0.300
 * dans l'axe du glyphe. Centree sur le barycentre du bout rond.
 */
const TEAR = polyPath(hullOfCircles(0, 0, 0.118, 0, 0.172, 0.012))

/**
 * Le triangle ne tourne pas sur lui-meme : son centre decrit un cercle de
 * rayon 0.213 autour de l'origine (mesure). C'est ce decalage qui donne
 * l'impression qu'il bascule au lieu de pivoter sur place.
 */
const TRI_ORBIT = 0.213

function spinningTriangle(rot: number): Silhouette {
  return silhouette('triangle', {
    rot,
    cx: -TRI_ORBIT * Math.sin(rot),
    cy: TRI_ORBIT * Math.cos(rot)
  })
}

/* ------------------------------------------------------------------ etats */

export type StateId =
  | 'idle'
  | 'thinking'
  | 'wink'
  | 'wide'
  | 'alert'
  | 'notify'
  | 'exclaim'
  | 'sleep'
  | 'egg'
  | 'hexagon'
  | 'play'
  | 'orbit'
  | 'burst'
  | 'comet'
  /** transition d'interface, pas une animation du catalogue : hors `SEQUENCE` */
  | 'swirl'
  /** etats choisis pour Alfred, hors catalogue, pas releves sur la video */
  | 'focus'
  | 'nod'
  | 'startle'
  | 'curious'
  | 'hop'
  | 'relieved'
  | 'down'
  | 'drowsy'
  | 'yawn'
  | 'travel'
  | 'ponder'
  /** sentiments en bulle, memes regles que `ponder` */
  | 'wonder'
  | 'oops'
  | 'bored'
  | 'sleepy'
  | 'laugh'
  | 'love'
  | 'cheer'

export interface StateDef {
  id: StateId
  /** duree de maintien quand la sequence complete est jouee */
  duration: number
  /**
   * duree en dessous de laquelle l'animation est coupee avant d'aboutir : le
   * "!" ne revient pas, le corps reste eclate. Elle se lit dans les constantes
   * de `pose` ci-dessous, elle ne se choisit pas. Absente = l'etat ignore le
   * temps ou boucle, n'importe quelle duree lui va (voir `MIN_BLOCK`).
   */
  minDuration?: number
  /** duree du morph d'entree */
  morph: number
  /** true = l'entree est masquee par un clignement, comme dans la video */
  blinkIn: boolean
  /**
   * true = le corps est la silhouette "au repos", donc remplacable par la forme
   * choisie dans le personnalisateur. Les etats qui dessinent leur propre forme
   * (le "!", les points, l'oeuf, le triangle...) valent false : c'est cette forme
   * la qui EST l'animation.
   */
  baseBody: boolean
  /**
   * true = l'etat porte le visage "au repos", donc remplacable par l'expression
   * choisie. Seul `idle` : les autres etats a visage ont une expression relevee
   * sur la video, c'est precisement ce qu'on reproduit.
   */
  baseFace: boolean
  pose(local: number): Pose
}

/** Onde de pulsation qui parcourt les trois points de gauche a droite. */
function dotPulse(t: number, index: number): number {
  const p = ((((t - index * 0.5) / 1.5) % 1) + 1) % 1
  const k = p < 0.5 ? 0.5 - 0.5 * Math.cos(p * TAU) : 0
  return clamp(k * 2)
}

/*
 * Etats choisis pour Alfred, hors catalogue, pas releves sur la video.
 * Leurs constantes sont des choix de conception, pas des mesures.
 */

/** Phase d'un saut : etirement et decalage vertical. */
interface HopPhase {
  sx: number
  sy: number
  offY: number
}

const REPOS_SAUT: HopPhase = { sx: 1, sy: 1, offY: 0 }

/** Phase du saut ouvert a `debut` sur `longueur` s, ou null hors de sa fenetre. */
function hopPhase(t: number, debut: number, longueur: number, hauteur: number): HopPhase | null {
  const p = (t - debut) / longueur
  if (p < 0 || p > 1) return null
  // anticipation : la boule s'ecrase avant de partir
  if (p < 0.2) {
    const s = Math.sin((Math.PI * p) / 0.2)
    return { sx: 1 + 0.06 * s, sy: 1 - 0.1 * s, offY: 0 }
  }
  // en l'air : etirement vertical et decalage vers le haut
  if (p < 0.85) {
    const s = Math.sin((Math.PI * (p - 0.2)) / 0.65)
    return { sx: 1 - 0.04 * s, sy: 1 + 0.06 * s, offY: -hauteur * s }
  }
  // reception : ecrasement puis retour a la forme de repos
  const s = Math.sin((Math.PI * (p - 0.85)) / 0.15)
  return { sx: 1 + 0.06 * s, sy: 1 - 0.1 * s, offY: 0 }
}

const pairOpen = (w: number, h: number, open: number): [EyeCfg, EyeCfg] => [
  { w, h, open },
  { w, h, open }
]

/*
 * Constantes communes a `drowsy` et `yawn`. `yawn` finit exactement sur la pose
 * de `drowsy` a t = 0 : les deux les lisent ici, elles ne peuvent pas diverger.
 */
const DROWSY_SX = 1.04
const DROWSY_SY = 0.94
const DROWSY_CY = 0.05
const DROWSY_OPEN = 0.45
/** le regard tombe de cette valeur par rapport au repos (tangage negatif = vers le bas) */
const DROWSY_PITCH_DROP = 12
const DROWSY_ROLL = -13
/** tangage du coup d'oeil de `hop` : regard vers le haut, joyeux */
const HOP_PITCH = 2

/*
 * Etat `ponder` : la boule reflechit, une bulle de pensee flotte au-dessus d'elle
 * avec trois points qui pulsent. Toutes ces valeurs sont des choix de conception.
 * Unites : rayon de boule, y vers le bas.
 */
export const PONDER = {
  /** duree de l'etat, et periode de tout ce qui y oscille : la boucle tombe juste */
  duree: 3,
  /** echelle du corps : c'est la place laissee a la bulle au-dessus */
  echelle: 0.8,
  /** amplitude du souffle autour de l'echelle */
  souffle: 0.01,
  /** decalage du corps ET des yeux : bas de +0.24 pour degager le haut, gauche de 0.12 */
  decalage: { x: -0.12, y: 0.24 },
  /**
   * regard vers la bulle, en degres, relatif au repos (lacet a droite, tangage en haut).
   * Lacet 6 et non 14 : a 14 l'oeil exterieur tape le bord du corps reduit a 0,8, et la
   * table de decalage (`eyefit.ts`) le repousse de 0,9 unite, ce qui casse l'invariant
   * "choisir le cercle = ne rien choisir". Mesure : 14 -> 0,9 ; 10 -> 0,12 ; 6 -> 0.
   */
  regard: { yaw: 6, pitch: 4, roll: -6 },
  /** amplitude du balancement du regard, en degres : meme periode que la duree */
  balancement: 3,
  /** centre, largeur, hauteur et rayon des coins de la bulle */
  bulle: { x: 0.42, y: -1, l: 0.95, h: 0.52, coin: 0.2 },
  /** queue sous le bord bas : deux pieds sur le bord, pointe vers la tete */
  queue: { droite: -0.04, gauche: -0.22, pointe: { x: -0.3, y: 0.38 } },
  /** flottement de la bulle, periode 1.5 s (divise la duree) */
  flottement: 0.02,
  flottementPeriode: 1.5,
  /** les trois points : ecart, rayon de repos, gonflement a la pulsation, couleur claire */
  point: { ecart: 0.25, r: 0.075, gonflement: 0.35, couleur: '#f4f1ea' }
}

/**
 * Contour de la bulle, relatif a son centre : rectangle a coins arrondis, avec la
 * queue inseree dans le bord bas. Les coins sont echantillonnes : `polyPath` ne
 * trace que des segments. Parcouru dans le sens horaire a l'ecran.
 */
function contourBulle(p: typeof PONDER): Point[] {
  const { l, h, coin } = p.bulle
  const dl = l / 2
  const dh = h / 2
  const N = 8
  /** arc d'un coin, de `a0` a `a1` radians, centre (cx, cy) */
  const arc = (cx: number, cy: number, a0: number, a1: number): Point[] =>
    Array.from({ length: N + 1 }, (_, j) => {
      const a = a0 + ((a1 - a0) * j) / N
      return { x: cx + coin * Math.cos(a), y: cy + coin * Math.sin(a) }
    })
  return [
    ...arc(-dl + coin, -dh + coin, Math.PI, 1.5 * Math.PI),
    ...arc(dl - coin, -dh + coin, 1.5 * Math.PI, 2 * Math.PI),
    ...arc(dl - coin, dh - coin, 0, 0.5 * Math.PI),
    { x: p.queue.droite, y: dh },
    p.queue.pointe,
    { x: p.queue.gauche, y: dh },
    ...arc(-dl + coin, dh - coin, 0.5 * Math.PI, Math.PI)
  ]
}

/** Contour de la bulle, relatif a son centre, et son chemin rendu tel quel. */
export const PONDER_CONTOUR = contourBulle(PONDER)
const PONDER_BULLE_PATH = polyPath(PONDER_CONTOUR)

/*
 * Bulle de pensee partagee. `ponder` et les etats-sentiments (`wonder`, `bored`...)
 * posent tous la boule rapetissee sous une bulle d'encre ; seul le dessin dans la
 * bulle change. `glyphe(t)` le fournit en coordonnees ABSOLUES du repere de la
 * bulle (centre = PONDER.bulle, y vers le bas) : `bulleScene` retire le decalage du
 * corps, que le moteur rajoute a tous les points, et y ajoute le flottement.
 */

/** Couleur des glyphes : le papier, lisible sur la bulle d'encre (celle des points de `ponder`). */
const GLYPHE = PONDER.point.couleur
/** Epaisseur d'un trait de glyphe, en rayon de boule. Choix de dessin. */
const TRAIT = 0.07

const rad = (deg: number) => (deg * Math.PI) / 180

/**
 * Repere d'un glyphe : centre absolu, echelle et rotation (radians). Le dessin est
 * ecrit en coordonnees locales centrees sur le centre de la bulle, puis place ici.
 */
interface Repere {
  x: number
  y: number
  s: number
  rot: number
}

/** Repere au centre de la bulle, decale de (dx, dy) et mis a l'echelle `s`. */
const repere = (s = 1, rot = 0, dx = 0, dy = 0): Repere => ({
  x: PONDER.bulle.x + dx,
  y: PONDER.bulle.y + dy,
  s,
  rot
})

/** Position absolue d'un point local au glyphe. */
function placer(r: Repere, p: Point): Point {
  const c = Math.cos(r.rot)
  const s = Math.sin(r.rot)
  return { x: r.x + r.s * (p.x * c - p.y * s), y: r.y + r.s * (p.x * s + p.y * c) }
}

/**
 * Forme pleine : le contour `pts` (repere local), dont l'ancre est `ancre`. `d` est
 * donne SANS rotation, relatif a l'ancre : le rendu tourne le tout de `rot` autour
 * de l'ancre, exactement comme la pose le decrit.
 */
function forme(pts: Point[], ancre: Point, r: Repere, opacite = 1): DotRender {
  const c = placer(r, ancre)
  return {
    x: c.x,
    y: c.y,
    // `r` ne sert qu'au filtre du moteur (il ecarte les r nuls) : le trace vient de `d`
    r: 0.05 * r.s,
    opacity: opacite,
    color: GLYPHE,
    d: polyPath(pts.map((p) => ({ x: r.s * (p.x - ancre.x), y: r.s * (p.y - ancre.y) }))),
    rot: (r.rot * 180) / Math.PI
  }
}

/** Trait plein : capsule entre `a` et `b`, de largeur `w`. */
function trait(a: Point, b: Point, w: number, r: Repere, opacite = 1): DotRender {
  const pts = hullOfCircles(a.x, a.y, w / 2, b.x, b.y, w / 2, 24)
  return forme(pts, { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }, r, opacite)
}

/** Point rond de rayon `rayon`, centre local `c`. */
function point(c: Point, rayon: number, r: Repere, opacite = 1): DotRender {
  const p = placer(r, c)
  return { x: p.x, y: p.y, r: rayon * r.s, opacity: opacite, color: GLYPHE }
}

/**
 * Corps de la bulle : la boule rapetissee, son decalage et ses yeux, plus la bulle
 * et les glyphes. Les etats y ajoutent leur regard et leurs yeux.
 */
function bulleScene(
  t: number,
  opts: {
    /** duree de l'etat : la respiration du corps y tombe juste (boucle sans couture) */
    duree: number
    /** periode du flottement de la bulle, qui doit diviser la duree */
    flottementPeriode?: number
    /** dessin dans la bulle, en coordonnees absolues (voir `repere`) */
    glyphe?: (t: number) => DotRender[]
  }
): Pick<Pose, 'sil' | 'offX' | 'offY' | 'eyeScale' | 'dots'> {
  // souffle du corps : periode = duree, boucle sans couture
  const w = (TAU * t) / opts.duree
  const echelle = PONDER.echelle + PONDER.souffle * Math.sin(w)
  // la bulle flotte doucement ; les points, dedans, flottent avec elle
  const flotte =
    PONDER.flottement * Math.sin((TAU * t) / (opts.flottementPeriode ?? PONDER.flottementPeriode))
  // le moteur ajoute le decalage du corps a TOUS les points : on le retire ici pour
  // que la bulle soit posee en absolu sur (bulle.x, bulle.y), comme les constantes
  const dec = PONDER.decalage
  const bulle: DotRender = {
    x: PONDER.bulle.x - dec.x,
    y: PONDER.bulle.y + flotte - dec.y,
    // `r` ne sert qu'au filtre du moteur : le trace vient de `d`, la demi-hauteur suffit
    r: PONDER.bulle.h / 2,
    opacity: 1,
    d: PONDER_BULLE_PATH
  }
  const glyphes = (opts.glyphe?.(t) ?? []).map((g) => ({
    ...g,
    x: g.x - dec.x,
    y: g.y + flotte - dec.y
  }))
  return {
    sil: circle(1, { sx: echelle, sy: echelle }),
    offX: dec.x,
    offY: dec.y,
    // les yeux suivent la taille du corps, sinon ils sortent de la silhouette
    eyeScale: echelle,
    dots: [bulle, ...glyphes]
  }
}

/* ----------------------------------------------------- dessins de la bulle */

/** "?" : crochet = chaine de capsules sur un arc, tige, point. Choix de dessin. */
function dessinQuestion(r: Repere): DotRender[] {
  const C = { x: 0, y: -0.05 }
  const RAYON = 0.065
  const arc: Point[] = []
  for (let deg = 170; deg <= 380; deg += 30) {
    const a = rad(deg)
    arc.push({ x: C.x + RAYON * Math.cos(a), y: C.y + RAYON * Math.sin(a) })
  }
  const tige = { x: 0, y: 0.035 }
  const out: DotRender[] = []
  for (let i = 0; i < arc.length - 1; i++) out.push(trait(arc[i]!, arc[i + 1]!, TRAIT, r))
  out.push(trait(arc[arc.length - 1]!, tige, TRAIT, r))
  out.push(point({ x: 0, y: 0.1 }, 0.04, r))
  return out
}

/** "!" : barre effilee (cercle haut plus gros que le bas) et point. */
function dessinExclamation(r: Repere): DotRender[] {
  const barre = hullOfCircles(0, -0.11, 0.045, 0, 0.02, 0.03, 24)
  return [forme(barre, { x: 0, y: -0.045 }, r), point({ x: 0, y: 0.1 }, 0.042, r)]
}

/** Trois points de `ponder`, a l'intensite `opacites[i]` (pas de pulsation ici). */
function dessinTrois(r: Repere, opacites: number[]): DotRender[] {
  return opacites.map((o, i) =>
    point({ x: (i - 1) * PONDER.point.ecart, y: 0 }, PONDER.point.r, r, o)
  )
}

/** Un "z" : trois capsules (barre haute, diagonale, barre basse), de demi-taille `h`. */
function dessinZ(cx: number, cy: number, h: number, r: Repere, opacite: number): DotRender[] {
  return [
    trait({ x: cx - h, y: cy - h }, { x: cx + h, y: cy - h }, TRAIT, r, opacite),
    trait({ x: cx + h, y: cy - h }, { x: cx - h, y: cy + h }, TRAIT, r, opacite),
    trait({ x: cx - h, y: cy + h }, { x: cx + h, y: cy + h }, TRAIT, r, opacite)
  ]
}

/** "^^" : deux chevrons, chacun de deux capsules. */
function dessinChevrons(r: Repere): DotRender[] {
  const out: DotRender[] = []
  for (const cx of [-0.11, 0.11]) {
    const gauche = { x: cx - 0.075, y: 0.03 }
    const sommet = { x: cx, y: -0.05 }
    const droite = { x: cx + 0.075, y: 0.03 }
    out.push(trait(gauche, sommet, TRAIT, r), trait(sommet, droite, TRAIT, r))
  }
  return out
}

/**
 * Contour du coeur, sur la courbe parametrique x = 16 sin^3 t,
 * y = 13 cos t - 5 cos 2t - 2 cos 3t - cos 4t (y vers le haut), retournee pour
 * l'ecran et recentree. Largeur 0.36 : 32 unites de la courbe pour 0.36 de bulle.
 */
const COEUR_ECHELLE = 0.36 / 32
const COEUR: Point[] = Array.from({ length: 72 }, (_, i) => {
  const t = (TAU * i) / 72
  const x = 16 * Math.sin(t) ** 3
  const y = -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t)) - 2.5
  return { x: x * COEUR_ECHELLE, y: y * COEUR_ECHELLE }
})

/** Coeur plein, centre local. Son echelle vient du repere (battement). */
function dessinCoeur(r: Repere): DotRender[] {
  return [forme(COEUR, { x: 0, y: 0 }, r)]
}

/** Coche : trait court puis long, chacun de bout en bout (A, B, C) selon le progres. */
const COCHE = { a: { x: -0.1, y: 0 }, b: { x: -0.03, y: 0.07 }, c: { x: 0.11, y: -0.09 } }


/*
 * Constantes des etats-sentiments. Ce sont des choix de conception, pas des mesures.
 * Chaque duree est un multiple de la periode de ce qui y oscille : la boucle tombe juste.
 */

/** Yeux joyeux en tirets, comme `hop`. */
const TIRET = { w: 0.36, h: 0.095 }

/** Question : "?" qui bascule, tete penchee. */
const WONDER = {
  duree: 3,
  /** bascule du "?" autour du centre de la bulle, en degres, periode 1.5 s (divise 3) */
  bascule: 8,
  periode: 1.5,
  /** roulis de la tete, en degres, ajoute au repos */
  roulis: 10,
  /**
   * regard relatif au repos : vers le haut seulement. Un lacet de +4 avec le roulis et les
   * yeux agrandis faisait sortir l'oeil du cercle (`skins.test.ts`, forme choisie = rien).
   */
  regard: { yaw: 0, pitch: 4 },
  /** yeux un peu plus grands : on s'interroge */
  oeil: { w: 1.05, h: 1.1 }
}

/** Erreur : "!" qui surgit avec un depassement, puis tremble. */
const OOPS = {
  duree: 2.4,
  minDuration: 1.0,
  /** pic du surgissement : depassement PROPRE a cet etat, comme le ressort de `startle` */
  pic: 1.15,
  /** duree du surgissement, en secondes ; le pic est atteint a 70 % */
  surgissement: 0.35,
  /** secousse laterale, en rayon de boule, a 6 Hz, qui s'eteint avant 0.8 s */
  secousse: 0.02,
  frequence: 6,
  fin: 0.8,
  /** pupilles de choc, et regard leve de 4 degres de moins */
  oeil: { w: 0.95, h: 1.05 },
  regardPitch: -4
}

/** Ennui : trois points qui apparaissent un par un, soupir, regard detourne. */
const BORED = {
  duree: 3.6,
  /** periode du flottement : 1.2 s divise 3.6 */
  flottementPeriode: 1.2,
  /** apparition de chaque point, en secondes ; chacun fond en `fondu` */
  apparitions: [0.4, 1.2, 2.0],
  fondu: 0.3,
  /** les trois points s'effacent ensemble sur les 0.4 dernieres secondes : la boucle se referme */
  effacement: 0.4,
  /** soupir : le corps s'ecrase de 3 % en vertical, centre sur 2.4 s, sur 0.8 s */
  soupir: { centre: 2.4, demi: 0.4, profondeur: 0.03 },
  /** paupieres mi-closes */
  ouverture: 0.55,
  /** regard detourne : vers la gauche et vers le bas, relatif au repos */
  regard: { yaw: -6, pitch: -6 }
}

/** Fatigue : "z" qui derivent vers le haut-droit en se succedant. */
const SLEEPY = {
  duree: 2.4,
  /** periode du flottement : 1.2 s divise 2.4 */
  flottementPeriode: 1.2,
  /** petit z : de 0 a 1.4 s ; grand Z : de 0.9 a 2.4 s ; chacun fond sur `fondu` */
  petit: { debut: 0, fin: 1.4, de: { x: -0.16, y: 0.06 }, a: { x: -0.04, y: -0.03 }, h: 0.045 },
  grand: { debut: 0.9, fin: 2.4, de: { x: 0.02, y: 0.05 }, a: { x: 0.16, y: -0.05 }, h: 0.085 },
  fondu: 0.4,
  /** respiration lente, sur sy : +-2 %, periode = duree */
  respiration: 0.02,
  /** paupieres presque closes, regard tombe de 10 degres */
  ouverture: 0.12,
  regardPitch: -10
}

/** Rire : "^^" qui rebondit, corps qui sautille. */
const LAUGH = {
  duree: 2.0,
  /** periode du flottement : 1.0 s divise 2.0 */
  flottementPeriode: 1.0,
  /** rebond du glyphe, en rayon de boule, et du corps en plus, a 4 Hz (periode 0.25 divise 2.0) */
  rebond: 0.03,
  rebondCorps: 0.02,
  frequence: 4
}

/** Affection : coeur qui pulse. */
const LOVE = {
  duree: 2.0,
  /** periode du flottement : 1.0 s divise 2.0 */
  flottementPeriode: 1.0,
  /** pulsation 1 -> 1.12 a 1.5 Hz (periode 2/3 s, soit 3 cycles sur 2 s) */
  pulsation: 0.12,
  frequence: 1.5,
  /** regard legerement vers le haut */
  regardPitch: 2
}

/** Reussite : coche qui se dessine, petit saut, etincelles. Un coup unique. */
const CHEER = {
  duree: 2.0,
  minDuration: 1.0,
  /** saut du corps, en rayon de boule, pic a 0.4 s, retombe a 0.9 s */
  saut: 0.06,
  pic: 0.4,
  retombee: 0.9,
  /** le trait court se dessine de 0.15 a 0.35 s, le long de 0.35 a 0.65 s */
  court: { debut: 0.15, duree: 0.2 },
  long: { debut: 0.35, duree: 0.3 },
  /** etincelles qui scintillent aux coins, de 0.6 a 1.0 s, pour etre eteintes au minDuration */
  etincelles: { debut: 0.6, duree: 0.4, r: 0.03 }
}

/** Sortie du surgissement de `oops` : 0 -> 1.15 -> 1, en `surgissement` s. */
function surgissementOops(t: number): number {
  const p = clamp(t / OOPS.surgissement)
  if (p < 0.7) return OOPS.pic * easings.easeOutCubic(p / 0.7)
  return OOPS.pic - (OOPS.pic - 1) * easings.easeInOutCubic((p - 0.7) / 0.3)
}

/** Saut de `cheer` : monte a 1 a `pic`, retombe a 0 a `retombee`. */
function sautCheer(t: number): number {
  if (t < CHEER.pic) return easings.easeOutCubic(t / CHEER.pic)
  return 1 - easings.easeInOutCubic(clamp((t - CHEER.pic) / (CHEER.retombee - CHEER.pic)))
}


export const STATES: StateDef[] = [
  {
    id: 'idle',
    duration: 2.4,
    morph: 0.45,
    blinkIn: false,
    baseFace: true,
    baseBody: true,
    pose: () => base()
  },

  {
    id: 'thinking',
    duration: 2.6,
    morph: 0.4,
    baseFace: false,
    baseBody: false,
    blinkIn: true,
    pose: (t) => {
      const mid = dotPulse(t, 1)
      // Les points lateraux sortent des flancs de la boule : dans la video ils
      // restent fusionnes avec elle 1-2 frames avant de se detacher.
      const emerge = 0.3 + 0.7 * easings.easeOutCubic(clamp(t / 0.3))
      return base({
        // la boule DEVIENT le point du milieu : le morph reste continu
        sil: circle(DOT_R * (1 + (DOT_PEAK - 1) * mid), { cx: DOT_X[1]! }),
        eyeAlpha: 0,
        dots: [0, 2].map((i) => {
          const k = dotPulse(t, i)
          return {
            x: DOT_X[i]! * emerge,
            y: 0,
            r: DOT_R * (1 + (DOT_PEAK - 1) * k),
            opacity: 0.55 + 0.45 * k
          }
        })
      })
    }
  },

  {
    id: 'wink',
    duration: 1.6,
    morph: 0.3,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: () =>
      base({
        gaze: { yaw: -5.37, pitch: 4.55, roll: 6.7 },
        split: 16.25,
        // L'oeil ferme n'est pas l'oeil ouvert ecrase : c'est un tiret
        // horizontal PLUS LARGE que l'oeil ouvert (0.447 contre 0.236).
        eyes: [
          { w: 0.236, h: 0.464, open: 1 },
          { w: 0.447, h: 0.089, open: 1 }
        ]
      })
  },

  {
    id: 'wide',
    duration: 1.8,
    morph: 0.55,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: () =>
      base({
        gaze: { yaw: 6.92, pitch: -21.96, roll: 11.6 },
        split: 18.43,
        eyes: pair(0.356, 0.875)
      })
  },

  {
    id: 'alert',
    duration: 2.4,
    // le "!" revient en place a 1.6 + 0.4
    minDuration: 2,
    morph: 0.45,
    baseFace: false,
    baseBody: false,
    blinkIn: false,
    pose: (t) => {
      // Course mesuree : -0.087 -> +0.732 en 1.5 s, ease-in-out, micro-overshoot.
      const p = clamp(t / 1.5)
      const travel = easings.easeInOutCubic(p) * 0.82 - 0.087
      const back = t > 1.6 ? clamp((t - 1.6) / 0.4) : 0
      const x = travel * (1 - back) + 0.1 * back
      // Vibration secondaire a 2.5 Hz, barre et point en opposition de phase.
      const buzz = Math.sin(t * 2.5 * TAU) * 0.005
      const tilt = (17.7 * Math.PI) / 180
      return base({
        sil: barItalic({ rot: tilt, cx: x, cy: -0.325 - buzz }),
        eyeAlpha: 0,
        dots: [
          {
            // le point suit l'axe du glyphe, a 0.580 du centre de la barre
            x: x - Math.sin(tilt) * 0.58,
            y: -0.325 + Math.cos(tilt) * 0.58 + buzz * 2.8,
            r: 0.118,
            d: TEAR,
            rot: (tilt * 180) / Math.PI,
            opacity: 1
          }
        ]
      })
    }
  },

  {
    id: 'notify',
    duration: 2.2,
    morph: 0.5,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // Pop du point bleu : pic a +14 % vers 0.3 s puis stabilisation.
      const p = clamp(t / 0.45)
      const pop = 1 + (NOTIF_POP - 1) * Math.sin(p * Math.PI) * (1 - p * 0.35)
      const r = NOTIF_R * (p < 1 ? pop : 1)
      const a = (NOTIF_ANGLE * Math.PI) / 180
      return base({
        // le regard part a l'oppose de la pastille
        gaze: { yaw: -21.94, pitch: -5.82, roll: -12.2 },
        split: 18.89,
        eyes: pair(0.505, 0.498),
        notif: {
          x: Math.cos(a) * NOTIF_DIST,
          y: Math.sin(a) * NOTIF_DIST,
          r,
          notch: r + NOTIF_MARGIN
        }
      })
    }
  },

  {
    id: 'exclaim',
    duration: 2,
    morph: 0.45,
    baseFace: false,
    baseBody: false,
    blinkIn: false,
    pose: () =>
      base({
        sil: barUpright(),
        eyeAlpha: 0,
        dots: [{ x: -0.012, y: 0.526, r: 0.113, opacity: 1 }]
      })
  },

  {
    id: 'sleep',
    duration: 2.4,
    morph: 0.5,
    baseFace: false,
    baseBody: false,
    blinkIn: false,
    pose: (t) =>
      base({
        // Rebond vertical mesure : +-0.19 autour de +0.11, periode 0.6 s.
        sil: circle(0.1585, { cy: 0.11 + Math.sin(t * (TAU / 0.6)) * 0.19 }),
        eyeAlpha: 0
      })
  },

  {
    id: 'egg',
    duration: 1.8,
    morph: 0.4,
    baseFace: false,
    baseBody: false,
    blinkIn: true,
    pose: () =>
      base({
        sil: silhouette('egg'),
        gaze: { yaw: 19.97, pitch: 26.01, roll: -17.1 },
        // les yeux se resserrent comme le corps
        split: 11.07,
        eyes: pair(0.164, 0.385)
      })
  },

  {
    id: 'hexagon',
    duration: 1.6,
    morph: 0.4,
    baseFace: false,
    baseBody: false,
    blinkIn: true,
    pose: () =>
      base({
        sil: silhouette('hexagon'),
        gaze: { yaw: 23.11, pitch: 24.42, roll: -13.3 },
        split: 13.37,
        eyes: pair(0.177, 0.411)
      })
  },

  {
    id: 'play',
    duration: 2,
    morph: 0.5,
    baseFace: false,
    baseBody: false,
    blinkIn: true,
    pose: (t) => {
      // Le triangle reste quasi immobile pendant que le bouquet le traverse.
      const fade = clamp(t / 0.35) * clamp((2.2 - t) / 0.5)
      return base({
        sil: spinningTriangle(0),
        gaze: { yaw: 12, pitch: -8, roll: -6 },
        split: 15,
        eyes: pair(0.18, 0.34),
        // le bouquet balaie de la droite vers la gauche par-dessus le triangle
        arcs: SWOOSH.map((s, i) => ({
          id: `sw${i}`,
          seed: { ...s, cx: 0.45 - t * 0.42 },
          t,
          opacity: fade
        }))
      })
    }
  },

  {
    id: 'orbit',
    duration: 3.4,
    // le corps a fini de se relacher du triangle vers la boule a 1.6 + 0.9
    minDuration: 2.5,
    morph: 0.6,
    baseFace: false,
    baseBody: false,
    blinkIn: false,
    pose: (t) => {
      // Rotation mesuree : rampe sur 0.35 s puis 1.25 tour/s (sens antihoraire).
      const ramp = easings.easeInOutCubic(clamp(t / 0.35))
      const rot = -TAU * 1.25 * t * ramp
      // Le corps se relache du triangle vers la boule pendant l'orbite.
      const back = easings.easeInOutCubic(clamp((t - 1.6) / 0.9))
      const tri = spinningTriangle(rot)
      const ball = circle(1, { rot })
      const sil: Silhouette = {
        radii: tri.radii.map((r, i) => r + (ball.radii[i]! - r) * back),
        rot,
        cx: tri.cx * (1 - back),
        cy: tri.cy * (1 - back),
        sx: 1,
        sy: 1
      }
      const fade = clamp(t / 0.8) * clamp((3.6 - t) / 0.9)
      return base({
        sil,
        // les yeux filent autour de la sphere ~3x plus vite que la silhouette
        gaze: {
          yaw: REST_GAZE.yaw + Math.sin(t * 6.5) * 65 * (1 - back),
          pitch: -4 + back * 32,
          roll: -13
        },
        eyes: pair(0.18, 0.34 + back * 0.07),
        // les anneaux entrent un par un sur 0.8 s
        arcs: RINGS.map((s, i) => ({
          id: `rg${i}`,
          seed: s,
          t,
          opacity: fade * clamp((t - i * 0.13) / 0.3)
        }))
      })
    }
  },

  {
    /**
     * Entree dans la vue des reglages.
     *
     * SEUL etat qui n'est pas releve sur la video : il est CHOISI, comme la
     * couleur `--ink`. Il emprunte le vocabulaire d'`orbit` — les memes anneaux,
     * avec leurs parametres mesures — mais coupe court : 1 s au lieu de 3,4, la
     * moitie des anneaux, et aucun triangle.
     *
     * Les deux drapeaux a `true` sont tout l'interet de cet etat :
     *
     * - `baseBody` laisse la forme choisie remplacer le corps, donc la vue peut
     *   imposer le cercle et le galet ou la goutte y MORPHENT au lieu de sauter ;
     * - `baseFace` fait porter le visage de repos, donc le suivi du curseur
     *   s'applique des cette entree. Un etat qui aurait sa propre pose de regard
     *   (comme `orbit`) rendrait la main a l'etat suivant en pleine course, et
     *   les yeux sauteraient d'un coup a la reprise.
     *
     * Il n'est volontairement PAS dans `SEQUENCE` : ce n'est pas une animation du
     * catalogue, c'est une transition d'interface.
     */
    id: 'swirl',
    // un peu plus que le tour du regard (`TURN_TIME`, 1,1 s) : les yeux doivent
    // etre poses a gauche avant que les anneaux ne s'effacent
    duration: 1.3,
    minDuration: 1.3,
    morph: 0.3,
    baseFace: true,
    baseBody: true,
    // le morph de forme est masque par un clignement, comme partout ailleurs
    blinkIn: true,
    pose: (t) =>
      base({
        // trois anneaux sur les six d'`orbit` : la moitie du bouquet suffit a le
        // reconnaitre, et c'est autant d'arcs en moins a rasteriser par image
        arcs: RINGS.slice(0, 3).map((s, i) => ({
          id: `sw${i}`,
          seed: s,
          t,
          // ils entrent l'un apres l'autre puis s'effacent avant la fin du bloc,
          // pour que la reprise au repos se fasse sur une image deja propre
          opacity: clamp((t - i * 0.06) / 0.14) * clamp((1.22 - t) / 0.34)
        }))
      })
  },

  {
    id: 'burst',
    duration: 2.6,
    // le corps est recompose a 1.7 + 0.7
    minDuration: 2.4,
    morph: 0.4,
    baseFace: false,
    baseBody: false,
    blinkIn: false,
    pose: (t) => {
      // Effondrement mesure : 1.0 -> 0.166 en 0.7 s, ease-out, sans rebond.
      const collapse = 1 - 0.834 * easings.easeOutQuint(clamp(t / 0.7))
      const regrow = easings.easeOutQuint(clamp((t - 1.7) / 0.7))
      return base({
        sil: circle(collapse + (1 - collapse) * regrow),
        eyeAlpha: clamp((t - 1.85) / 0.4),
        dots: particles(t, 1),
        dotsBehind: true
      })
    }
  },

  {
    id: 'comet',
    duration: 2.4,
    // le point se recompose a 1.85 + 0.6 = 2.45, soit 0.05 s apres la coupe de
    // la video : ce reliquat se termine pendant le fondu suivant, comme dans la
    // reference. On ne descend donc pas sous la duree mesuree.
    minDuration: 2.4,
    morph: 0.45,
    baseFace: false,
    baseBody: false,
    blinkIn: false,
    pose: (t) => {
      const collapse = 1 - (1 - COMET_DOT) * easings.easeOutQuint(clamp(t / 0.55))
      const regrow = easings.easeOutQuint(clamp((t - 1.85) / 0.6))
      const fade = clamp((t - 0.15) / 0.25) * clamp((1.95 - t) / 0.3)
      return base({
        // Le point derive de 0.035 vers le bas puis remonte (wobble mesure).
        sil: circle(collapse + (1 - collapse) * regrow, {
          cy: Math.sin(clamp(t / 1.7) * Math.PI) * 0.035
        }),
        eyeAlpha: clamp((t - 2) / 0.35),
        arcs: COMET_RIBBONS.map((s, i) => ({ id: `cm${i}`, seed: s, t, opacity: fade }))
      })
    }
  },

  // ---- etats choisis pour Alfred, hors catalogue, pas releves sur la video ----

  {
    id: 'focus',
    duration: 2.8,
    morph: 0.45,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // respiration et balancement du regard, periode 2.8 s = duree : boucle sans couture
      const w = (TAU * t) / 2.8
      const breath = Math.sin(w)
      return base({
        sil: circle(1, { sx: 1.02 - 0.008 * breath, sy: 0.97 + 0.01 * breath }),
        gaze: { yaw: REST_GAZE.yaw + 6 * Math.sin(w), pitch: REST_GAZE.pitch - 8, roll: -6 },
        split: EYE_SPLIT,
        // yeux plus hauts que plisses, inclinaisons en miroir de `triste` : froncement de concentration
        eyes: [
          { w: EYE_W, h: EYE_H * 0.62, open: 1, tilt: 8 },
          { w: EYE_W, h: EYE_H * 0.62, open: 1, tilt: -8 }
        ]
      })
    }
  },

  {
    id: 'nod',
    duration: 0.6,
    minDuration: 0.6,
    morph: 0.2,
    blinkIn: false,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // un seul coup de tete : le creux culmine vers 0.25 s puis revient avant 0.5 s
      const k = Math.sin(Math.PI * clamp(t / 0.5))
      return base({
        sil: circle(1, { sx: 1 + 0.03 * k, sy: 1 - 0.06 * k, cy: 0.03 * k }),
        // le regard descend : tangage negatif, sens verifie (positif = vers le haut)
        gaze: { ...REST_GAZE, pitch: REST_GAZE.pitch - 10 * k }
      })
    }
  },

  {
    id: 'startle',
    duration: 0.9,
    minDuration: 0.9,
    morph: 0.12,
    blinkIn: false,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // latence de reaction : rien ne bouge avant 0.12 s
      const c = easings.easeOutCubic(clamp((t - 0.12) / 0.18))
      // ressort amorti : le SEUL depassement autorise, propre a cet etat (cf. math.ts)
      const u = t - 0.3
      const d = Math.exp(-6 * u) * Math.cos(TAU * 2.2 * u)
      // sursaut puis rebond : `c` jusqu'a 0.3 s, puis le ressort
      const sq = t < 0.3 ? c : d
      // yeux en pupilles de choc : `c` pendant le sursaut, tenus jusqu'a 0.45 s, retour au repos d'ici 0.9 s
      const eyeK = t < 0.45 ? c : 1 - easings.easeOutCubic(clamp((t - 0.45) / 0.45))
      return base({
        // squash modere (sy 0.92 au pic) : la boule ne doit pas s'ecraser davantage
        sil: circle(1, { sx: 1 + 0.05 * sq, sy: 1 - 0.08 * sq, cy: 0.03 * sq }),
        // regard baisse (-6 au pic) : le regard vers le haut, avec yeux ecarquilles,
        // sortait de la boule dans la sweep de confinement (cf. les commentaires du recap)
        gaze: { ...REST_GAZE, pitch: REST_GAZE.pitch - 6 * c },
        eyes: pairOpen(lerp(EYE_W, EYE_W * 0.95, eyeK), lerp(EYE_H, EYE_W * 1.05, eyeK), 1)
      })
    }
  },

  {
    id: 'curious',
    duration: 2.4,
    morph: 0.5,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // la tete penche doucement, periode = duree : boucle sans couture
      const roll = 12 + 3 * Math.sin((TAU * t) / 2.4)
      return base({
        sil: circle(1, { rot: ((roll * Math.PI) / 180) * 0.5 }),
        offX: 0.04,
        // regard absolu, pas releve : un regard vers le haut ferait sortir les yeux de la
        // marge du cercle et casserait `cercle == rien` (cf. skins.test.ts)
        gaze: { yaw: 10, pitch: -6, roll },
        // un oeil un peu plus grand que l'autre : on regarde de biais
        eyes: [
          { w: EYE_W, h: EYE_H * 1.1, open: 1 },
          { w: EYE_W * 1.15, h: EYE_H * 1.3, open: 1 }
        ]
      })
    }
  },

  {
    id: 'hop',
    duration: 1.6,
    minDuration: 1.4,
    morph: 0.35,
    blinkIn: false,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // deux sauts : le premier monte a 0.18, le second a 0.10
      const saut = hopPhase(t, 0, 0.6, 0.18) ?? hopPhase(t, 0.65, 0.6, 0.1) ?? REPOS_SAUT
      // yeux joyeux en tirets fermes pendant tout le saut : entree en 0.12 s, retour sur 1.25..1.4 s
      const m = Math.min(
        easings.easeOutCubic(clamp(t / 0.12)),
        1 - easings.easeOutCubic(clamp((t - 1.25) / 0.15))
      )
      return base({
        sil: circle(1, { sx: saut.sx, sy: saut.sy }),
        offY: saut.offY,
        gaze: { ...REST_GAZE, pitch: REST_GAZE.pitch + HOP_PITCH },
        eyes: pairOpen(lerp(EYE_W, 0.36, m), lerp(EYE_H, 0.095, m), 1)
      })
    }
  },

  {
    id: 'relieved',
    duration: 1.8,
    minDuration: 1.6,
    morph: 0.45,
    blinkIn: false,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      let echelle: number
      let cy = 0
      if (t < 0.6) {
        // inspiration : la boule gonfle
        echelle = 1 + 0.06 * easings.easeInOutCubic(t / 0.6)
      } else if (t < 1.4) {
        // expiration : elle se degonfle et s'abaisse
        const e = easings.easeInOutCubic((t - 0.6) / 0.8)
        echelle = lerp(1.06, 0.96, e)
        cy = 0.03 * e
      } else {
        // retour au repos
        const s = easings.easeOutCubic(clamp((t - 1.4) / 0.2))
        echelle = lerp(0.96, 1, s)
        cy = 0.03 * (1 - s)
      }
      // paupieres : ouvertes, fermees de 0.7 a 1.2 s, rouvertes a 1.5 s (rampes lineaires)
      const ouvert =
        t < 0.5 ? 1 : t < 0.7 ? 1 - (t - 0.5) / 0.2 : t < 1.2 ? 0 : t < 1.5 ? (t - 1.2) / 0.3 : 1
      return base({
        sil: circle(1, { sx: echelle, sy: echelle, cy }),
        // regard qui tombe legerement : un regard vers le haut depasserait la boule
        gaze: { ...REST_GAZE, pitch: REST_GAZE.pitch - 6 },
        eyes: pairOpen(EYE_W, EYE_H, ouvert)
      })
    }
  },

  {
    id: 'down',
    duration: 3,
    morph: 0.6,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // respiration lente, periode = duree : boucle sans couture
      const breath = Math.sin((TAU * t) / 3)
      return base({
        sil: circle(1, { sx: 1.05, sy: 0.92 + 0.01 * breath, cy: 0.06 }),
        // regard vers le bas : valeur absolue, tangage negatif
        gaze: { yaw: REST_GAZE.yaw - 6, pitch: -22, roll: -4 },
        // tristesse : inclinaisons en miroir, meme signe que `triste` (oeil interieur -28)
        eyes: [
          { w: EYE_W * 0.95, h: EYE_H * 0.8, open: 1, tilt: -12 },
          { w: EYE_W * 0.95, h: EYE_H * 0.8, open: 1, tilt: 12 }
        ]
      })
    }
  },

  {
    id: 'drowsy',
    duration: 3.2,
    morph: 0.6,
    blinkIn: false,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // respiration lente, periode = duree : boucle sans couture
      const breath = Math.sin((TAU * t) / 3.2)
      // paupieres lourdes, avec un clignement lent entre 1.8 et 2.6 s
      const lent = t >= 1.8 && t <= 2.6 ? 0.4 * Math.sin((Math.PI * (t - 1.8)) / 0.8) : 0
      return base({
        sil: circle(1, { sx: DROWSY_SX, sy: DROWSY_SY + 0.015 * breath, cy: DROWSY_CY }),
        eyes: pairOpen(EYE_W, EYE_H, DROWSY_OPEN - lent),
        gaze: {
          yaw: REST_GAZE.yaw,
          pitch: REST_GAZE.pitch - DROWSY_PITCH_DROP,
          roll: DROWSY_ROLL + 6 * Math.sin((TAU * t) / 3.2)
        }
      })
    }
  },

  {
    id: 'yawn',
    duration: 2,
    minDuration: 1.6,
    morph: 0.45,
    blinkIn: false,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // etirement : la boule s'allonge en hauteur, se resserre, les yeux se ferment
      const etire = easings.easeInOutCubic(clamp(t / 0.8))
      // retour vers la somnolence, qui commence a 1.1 s
      const retour = easings.easeInOutCubic(clamp((t - 1.1) / 0.5))
      const avant = t < 1.1
      return base({
        sil: circle(1, {
          sx: avant ? lerp(1, 0.94, etire) : lerp(0.94, DROWSY_SX, retour),
          sy: avant ? lerp(1, 1.12, etire) : lerp(1.12, DROWSY_SY, retour),
          cy: avant ? 0 : lerp(0, DROWSY_CY, retour)
        }),
        eyes: pairOpen(
          EYE_W,
          EYE_H,
          avant
            ? lerp(1, 0.1, easings.easeInOutCubic(clamp(t / 0.5)))
            : lerp(0.1, DROWSY_OPEN, retour)
        ),
        gaze: {
          yaw: REST_GAZE.yaw,
          pitch: REST_GAZE.pitch - DROWSY_PITCH_DROP * retour,
          roll: DROWSY_ROLL
        }
      })
    }
  },

  {
    id: 'travel',
    duration: 1,
    morph: 0.15,
    blinkIn: true,
    // en vol le corps est toujours une boule etiree, quel que soit l'etat d'origine
    baseFace: false,
    baseBody: false,
    pose: () =>
      base({
        sil: circle(1, { sx: 0.95, sy: 1.06 }),
        gaze: { ...REST_GAZE },
        eyes: pair(EYE_W, EYE_H)
      })
  },

  {
    id: 'ponder',
    duration: PONDER.duree,
    morph: 0.45,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // balancement du regard : periode = duree, boucle sans couture
      const w = (TAU * t) / PONDER.duree
      return base({
        ...bulleScene(t, {
          duree: PONDER.duree,
          // les trois points pulsent comme `thinking` : meme onde, meme periode de 1.5 s
          glyphe: (u) =>
            [0, 1, 2].map((i) => {
              const k = dotPulse(u, i)
              return point(
                { x: (i - 1) * PONDER.point.ecart, y: 0 },
                PONDER.point.r * (1 + PONDER.point.gonflement * k),
                repere(),
                0.5 + 0.5 * k
              )
            })
        }),
        gaze: {
          yaw: REST_GAZE.yaw + PONDER.regard.yaw + PONDER.balancement * Math.sin(w),
          pitch: REST_GAZE.pitch + PONDER.regard.pitch,
          roll: PONDER.regard.roll
        },
        eyes: pair(EYE_W, EYE_H)
      })
    }
  },

  // ---- sentiments en bulle : memes regles que `ponder`, seul le dessin change ----

  {
    id: 'wonder',
    duration: WONDER.duree,
    morph: 0.45,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      const bascule = rad(WONDER.bascule) * Math.sin((TAU * t) / WONDER.periode)
      return base({
        ...bulleScene(t, {
          duree: WONDER.duree,
          flottementPeriode: WONDER.periode,
          glyphe: () => dessinQuestion(repere(1, bascule))
        }),
        gaze: {
          yaw: REST_GAZE.yaw + WONDER.regard.yaw,
          pitch: REST_GAZE.pitch + WONDER.regard.pitch,
          // inclinaison de la tete : dix degres de plus que le repos
          roll: REST_GAZE.roll + WONDER.roulis
        },
        eyes: pair(EYE_W * WONDER.oeil.w, EYE_H * WONDER.oeil.h)
      })
    }
  },

  {
    id: 'oops',
    duration: OOPS.duree,
    minDuration: OOPS.minDuration,
    morph: 0.45,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      const pop = surgissementOops(t)
      // secousse apres le surgissement, qui s'eteint avant 0.8 s
      const secousse =
        t < OOPS.surgissement
          ? 0
          : OOPS.secousse *
            clamp((OOPS.fin - t) / (OOPS.fin - OOPS.surgissement)) *
            Math.sin(TAU * OOPS.frequence * (t - OOPS.surgissement))
      return base({
        ...bulleScene(t, {
          duree: OOPS.duree,
          glyphe: () => dessinExclamation(repere(pop, 0, secousse))
        }),
        gaze: { ...REST_GAZE, pitch: REST_GAZE.pitch + OOPS.regardPitch },
        eyes: pair(EYE_W * OOPS.oeil.w, EYE_W * OOPS.oeil.h)
      })
    }
  },

  {
    id: 'bored',
    duration: BORED.duree,
    morph: 0.45,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // le soupir : cloche de 0.8 s centree sur 2.4 s, nulle aux deux bouts de la boucle
      const u = clamp((t - (BORED.soupir.centre - BORED.soupir.demi)) / (2 * BORED.soupir.demi))
      const soupir = 1 - BORED.soupir.profondeur * Math.sin(Math.PI * u)
      const effacement = clamp((BORED.duree - t) / BORED.effacement)
      const scene = bulleScene(t, {
        duree: BORED.duree,
        flottementPeriode: BORED.flottementPeriode,
        glyphe: () =>
          dessinTrois(
            repere(),
            BORED.apparitions.map((debut) => clamp((t - debut) / BORED.fondu) * effacement)
          )
      })
      return base({
        ...scene,
        sil: { ...scene.sil, sy: scene.sil.sy * soupir },
        gaze: {
          yaw: REST_GAZE.yaw + BORED.regard.yaw,
          pitch: REST_GAZE.pitch + BORED.regard.pitch,
          roll: REST_GAZE.roll
        },
        eyes: pairOpen(EYE_W, EYE_H, BORED.ouverture)
      })
    }
  },

  {
    id: 'sleepy',
    duration: SLEEPY.duree,
    morph: 0.45,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      const respire = 1 + SLEEPY.respiration * Math.sin((TAU * t) / SLEEPY.duree)
      const { petit, grand } = SLEEPY
      const vie = (z: typeof petit | typeof grand) => {
        const u = clamp((t - z.debut) / (z.fin - z.debut))
        const opacite = clamp((t - z.debut) / SLEEPY.fondu) * clamp((z.fin - t) / SLEEPY.fondu)
        return {
          x: lerp(z.de.x, z.a.x, u),
          y: lerp(z.de.y, z.a.y, u),
          opacite
        }
      }
      const p = vie(petit)
      const g = vie(grand)
      const scene = bulleScene(t, {
        duree: SLEEPY.duree,
        flottementPeriode: SLEEPY.flottementPeriode,
        glyphe: () => [
          ...dessinZ(p.x, p.y, petit.h, repere(), p.opacite),
          ...dessinZ(g.x, g.y, grand.h, repere(), g.opacite)
        ]
      })
      return base({
        ...scene,
        sil: { ...scene.sil, sy: scene.sil.sy * respire },
        gaze: { ...REST_GAZE, pitch: REST_GAZE.pitch + SLEEPY.regardPitch },
        eyes: pairOpen(EYE_W, EYE_H, SLEEPY.ouverture)
      })
    }
  },

  {
    id: 'laugh',
    duration: LAUGH.duree,
    morph: 0.45,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      const rebond = Math.sin(TAU * LAUGH.frequence * t)
      const scene = bulleScene(t, {
        duree: LAUGH.duree,
        flottementPeriode: LAUGH.flottementPeriode,
        glyphe: () => dessinChevrons(repere(1, 0, 0, LAUGH.rebond * rebond))
      })
      return base({
        ...scene,
        offY: scene.offY + LAUGH.rebondCorps * rebond,
        gaze: { ...REST_GAZE },
        eyes: pairOpen(TIRET.w, TIRET.h, 1)
      })
    }
  },

  {
    id: 'love',
    duration: LOVE.duree,
    morph: 0.45,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // battement : 0 -> 1 -> 0 a 1.5 Hz, nul aux deux bouts de la boucle
      const battement = 0.5 - 0.5 * Math.cos(TAU * LOVE.frequence * t)
      const echelle = 1 + LOVE.pulsation * battement
      return base({
        ...bulleScene(t, {
          duree: LOVE.duree,
          flottementPeriode: LOVE.flottementPeriode,
          glyphe: () => dessinCoeur(repere(echelle))
        }),
        gaze: { ...REST_GAZE, pitch: REST_GAZE.pitch + LOVE.regardPitch },
        eyes: pairOpen(TIRET.w, TIRET.h, 1)
      })
    }
  },

  {
    id: 'cheer',
    duration: CHEER.duree,
    minDuration: CHEER.minDuration,
    morph: 0.45,
    blinkIn: true,
    baseFace: false,
    baseBody: true,
    pose: (t) => {
      // coche : le trait court puis le long, chacun s'allonge par son bout
      const pc = easings.easeOutCubic(clamp((t - CHEER.court.debut) / CHEER.court.duree))
      const pl = easings.easeOutCubic(clamp((t - CHEER.long.debut) / CHEER.long.duree))
      const { a, b, c } = COCHE
      const bout = { x: b.x + (c.x - b.x) * pl, y: b.y + (c.y - b.y) * pl }
      const milieu = { x: a.x + (b.x - a.x) * pc, y: a.y + (b.y - a.y) * pc }
      // etincelles : un seul battement, eteint avant le coup
      const scin = clamp((t - CHEER.etincelles.debut) / CHEER.etincelles.duree)
      const scintille = Math.sin(Math.PI * scin)
      const scene = bulleScene(t, {
        duree: CHEER.duree,
        glyphe: () => [
          trait(a, milieu, TRAIT, repere(), clamp((t - CHEER.court.debut) / 0.02)),
          trait(b, bout, TRAIT, repere(), clamp((t - CHEER.long.debut) / 0.02)),
          point({ x: 0.25, y: -0.12 }, CHEER.etincelles.r, repere(), scintille),
          point({ x: -0.25, y: 0.1 }, CHEER.etincelles.r, repere(), scintille)
        ]
      })
      return base({
        ...scene,
        offY: scene.offY - CHEER.saut * sautCheer(t),
        gaze: { ...REST_GAZE },
        eyes: pairOpen(TIRET.w, TIRET.h, 1)
      })
    }
  }

]

export const STATE_BY_ID = new Map(STATES.map((s) => [s.id, s]))

/** Ordre de lecture de la sequence complete, calque sur la video de reference. */
/**
 * Date, en temps local, ou chaque etat est le plus lisible : c'est la pose que
 * montrent les vignettes et la planche. Rendu deterministe, donc comparable
 * d'une execution a l'autre. Le type force a couvrir tout nouvel etat.
 */
export const POSES: Record<StateId, number> = {
  idle: 1,
  thinking: 1.1,
  wink: 0.8,
  wide: 0.8,
  alert: 0.75,
  notify: 0.9,
  exclaim: 0.8,
  sleep: 0.45,
  egg: 0.8,
  hexagon: 0.8,
  play: 0.9,
  orbit: 1.2,
  swirl: 0.5,
  burst: 0.45,
  comet: 1.15,
  // etats choisis pour Alfred (hors catalogue)
  focus: 0.9,
  nod: 0.25,
  startle: 0.3,
  curious: 0.6,
  hop: 0.3,
  relieved: 0.6,
  down: 1.5,
  drowsy: 0.6,
  yawn: 0.8,
  travel: 0.5,
  ponder: 0.9,
  wonder: 0.9,
  oops: 0.5,
  bored: 2.6,
  sleepy: 1.6,
  laugh: 0.5,
  love: 0.35,
  cheer: 0.8
}

export const SEQUENCE: StateId[] = [
  'idle',
  'thinking',
  'wink',
  'wide',
  'alert',
  'notify',
  'exclaim',
  'sleep',
  'egg',
  'hexagon',
  'play',
  'orbit',
  'burst',
  'comet'
]
