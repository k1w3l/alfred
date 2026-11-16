import { describe, expect, it } from 'vitest'
import { BotEngine } from './engine'
import { PONDER, PONDER_CONTOUR, SEQUENCE, STATE_BY_ID, type Pose, type StateId } from './states'
import type { DotRender } from './decor'

/** Les etats choisis pour Alfred : hors catalogue, donc jamais dans `SEQUENCE`. */
const NOUVEAUX: StateId[] = [
  'focus',
  'nod',
  'startle',
  'curious',
  'hop',
  'relieved',
  'down',
  'drowsy',
  'yawn',
  'travel',
  'ponder',
  'wonder',
  'oops',
  'bored',
  'sleepy',
  'laugh',
  'love',
  'cheer'
]
/** Etats qui bouclent : leur fin doit retomber exactement sur leur debut. */
const BOUCLES: StateId[] = [
  'focus',
  'curious',
  'down',
  'drowsy',
  'travel',
  'ponder',
  'wonder',
  'bored',
  'sleepy',
  'laugh',
  'love'
]
/** Coups uniques : au `minDuration`, le corps doit etre revenu au repos. */
const COUPS: StateId[] = ['nod', 'startle', 'hop', 'relieved']

const def = (id: StateId) => STATE_BY_ID.get(id)!

/** Toutes les valeurs numeriques d'une pose, pour verifier qu'aucune n'est NaN ou infinie. */
function valeurs(p: Pose): number[] {
  const yeux = p.eyes.flatMap((e) => [e.w, e.h, e.open, e.tilt ?? 0])
  return [
    p.sil.rot,
    p.sil.cx,
    p.sil.cy,
    p.sil.sx,
    p.sil.sy,
    ...p.sil.radii,
    p.offX,
    p.offY,
    p.gaze.yaw,
    p.gaze.pitch,
    p.gaze.roll,
    p.split,
    ...yeux,
    p.eyeAlpha,
    p.eyeScale,
    p.bodyAlpha
  ]
}

/** Les champs qui doivent boucler, avec leur nom pour le message d'erreur. */
function champsBoucle(p: Pose): Array<[string, number]> {
  return [
    ['sil.sx', p.sil.sx],
    ['sil.sy', p.sil.sy],
    ['sil.cy', p.sil.cy],
    ['sil.rot', p.sil.rot],
    ['offX', p.offX],
    ['offY', p.offY],
    ['gaze.yaw', p.gaze.yaw],
    ['gaze.pitch', p.gaze.pitch],
    ['gaze.roll', p.gaze.roll],
    ['oeil0.w', p.eyes[0].w],
    ['oeil0.h', p.eyes[0].h],
    ['oeil0.open', p.eyes[0].open],
    ['oeil0.tilt', p.eyes[0].tilt ?? 0],
    ['oeil1.w', p.eyes[1].w],
    ['oeil1.h', p.eyes[1].h],
    ['oeil1.open', p.eyes[1].open],
    ['oeil1.tilt', p.eyes[1].tilt ?? 0],
    ['eyeScale', p.eyeScale]
  ]
}

describe('etats choisis pour Alfred', () => {
  it('produit uniquement des nombres finis sur toute leur duree', () => {
    for (const id of NOUVEAUX) {
      const d = def(id)
      for (let t = 0; t <= d.duration + 1e-9; t += 0.05) {
        for (const v of valeurs(d.pose(t))) {
          expect(Number.isFinite(v), `${id} a t=${t.toFixed(2)}`).toBe(true)
        }
      }
    }
  })

  it('boucle sans couture : pose(0) et pose(duration) coincident', () => {
    for (const id of BOUCLES) {
      const d = def(id)
      const debut = champsBoucle(d.pose(0))
      const fin = champsBoucle(d.pose(d.duration))
      for (let i = 0; i < debut.length; i++) {
        const [nom, a] = debut[i]!
        const b = fin[i]![1]
        expect(Math.abs(a - b), `${id} ${nom}`).toBeLessThan(1e-6)
      }
    }
  })

  it('un coup unique revient au repos a son minDuration', () => {
    for (const id of COUPS) {
      const d = def(id)
      const p = d.pose(d.minDuration!)
      expect(Math.abs(p.sil.sx - 1), `${id} sx`).toBeLessThan(0.01)
      expect(Math.abs(p.sil.sy - 1), `${id} sy`).toBeLessThan(0.01)
      expect(Math.abs(p.sil.cy), `${id} cy`).toBeLessThan(0.01)
      expect(Math.abs(p.offY), `${id} offY`).toBeLessThan(0.01)
    }
  })

  it('le bâillement finit exactement sur la somnolence', () => {
    const fin = def('yawn').pose(1.6)
    const debut = def('drowsy').pose(0)
    const ecart = (a: number, b: number) => Math.abs(a - b)
    expect(ecart(fin.sil.sx, debut.sil.sx), 'sx').toBeLessThan(0.005)
    expect(ecart(fin.sil.sy, debut.sil.sy), 'sy').toBeLessThan(0.005)
    expect(ecart(fin.sil.cy, debut.sil.cy), 'cy').toBeLessThan(0.005)
    expect(ecart(fin.eyes[0].open, debut.eyes[0].open), 'open gauche').toBeLessThan(0.005)
    expect(ecart(fin.eyes[1].open, debut.eyes[1].open), 'open droit').toBeLessThan(0.005)
    expect(ecart(fin.gaze.pitch, debut.gaze.pitch), 'pitch').toBeLessThan(0.005)
    expect(ecart(fin.gaze.roll, debut.gaze.roll), 'roll').toBeLessThan(0.005)
  })

  it('n appartient pas au catalogue', () => {
    for (const id of NOUVEAUX) expect(SEQUENCE.includes(id), id).toBe(false)
  })
})

/** Le cadre rendu va de -1,58 a +1,58 ; la marge de 0,03 garde la bulle hors du bord. */
const CADRE = 1.55

describe('ponder : la bulle reste dans le cadre', () => {
  it('bulle, points et corps tiennent dans le cadre, bornes calculees sur les constantes', () => {
    const P = PONDER
    // la bulle flotte de +-flottement autour de son centre, son contour est celui du `d` rendu
    const xs = PONDER_CONTOUR.map((p) => p.x)
    const ys = PONDER_CONTOUR.map((p) => p.y)
    const bulleX = [P.bulle.x + Math.min(...xs), P.bulle.x + Math.max(...xs)]
    const bulleY = [
      P.bulle.y - P.flottement + Math.min(...ys),
      P.bulle.y + P.flottement + Math.max(...ys)
    ]
    // les points pulsent jusqu'a 1 + gonflement fois leur rayon
    const rMax = P.point.r * (1 + P.point.gonflement)
    const pointsX = [-1, 0, 1].map((i) => P.bulle.x + i * P.point.ecart)
    // le corps, rapetisse de souffle, decale de decalage
    const echelleMax = P.echelle + P.souffle
    const corpsX = [P.decalage.x - echelleMax, P.decalage.x + echelleMax]
    const corpsY = [P.decalage.y - echelleMax, P.decalage.y + echelleMax]

    expect(bulleX[1], 'bulle x max').toBeLessThanOrEqual(CADRE)
    expect(bulleY[0], 'bulle y min').toBeGreaterThanOrEqual(-CADRE)
    expect(Math.max(...pointsX) + rMax, 'points x max').toBeLessThanOrEqual(CADRE)
    expect(Math.min(...pointsX) - rMax, 'points x min').toBeGreaterThanOrEqual(-CADRE)
    expect(P.bulle.y - P.flottement - rMax, 'points y min').toBeGreaterThanOrEqual(-CADRE)
    expect(corpsX[0], 'corps x min').toBeGreaterThanOrEqual(-CADRE)
    expect(corpsX[1], 'corps x max').toBeLessThanOrEqual(CADRE)
    expect(corpsY[1], 'corps y max').toBeLessThanOrEqual(CADRE)
    // les points restent dans la bulle, et la queue pointe vers la tete sans la toucher
    expect(Math.max(...pointsX) + rMax, 'points dans la bulle').toBeLessThan(bulleX[1]!)
    const tete = P.decalage.y - echelleMax
    const pointe = P.bulle.y + Math.max(...ys)
    expect(pointe, 'queue au-dessus de la tete').toBeLessThan(tete)
  })

  it('les points du moteur, rendus, ne sortent pas du cadre', () => {
    // meme controle sur la sortie reelle du moteur : `d` est en unites de rayon, x/y/r en unites de viewBox
    const R = 100
    for (let t = 0; t <= PONDER.duree + 1e-9; t += 0.05) {
      const f = new BotEngine(R, 'ponder').sample(t)
      for (const dot of f.dots) {
        let x0 = dot.x - dot.r
        let x1 = dot.x + dot.r
        let y0 = dot.y - dot.r
        let y1 = dot.y + dot.r
        if (dot.d) {
          // le chemin est en unites de rayon : on le ramene au viewBox, sans rotation (ponder n'en a pas)
          const nums = dot.d.match(/-?\d*\.?\d+/g)!.map(Number)
          const xs = nums.filter((_, i) => i % 2 === 0).map((v) => dot.x + v * R)
          const ys = nums.filter((_, i) => i % 2 === 1).map((v) => dot.y + v * R)
          x0 = Math.min(...xs)
          x1 = Math.max(...xs)
          y0 = Math.min(...ys)
          y1 = Math.max(...ys)
        }
        const lim = CADRE * R
        expect(x1, `t=${t.toFixed(2)} x max`).toBeLessThanOrEqual(lim)
        expect(x0, `t=${t.toFixed(2)} x min`).toBeGreaterThanOrEqual(-lim)
        expect(y1, `t=${t.toFixed(2)} y max`).toBeLessThanOrEqual(lim)
        expect(y0, `t=${t.toFixed(2)} y min`).toBeGreaterThanOrEqual(-lim)
      }
    }
  })
})

/** Etats-sentiments : `ponder` avec un autre dessin dans la bulle. */
const SENTIMENTS: StateId[] = ['wonder', 'oops', 'bored', 'sleepy', 'laugh', 'love', 'cheer']
/** Les coups uniques : leur fin doit etre stable (corps, yeux, dessin). */
const SENTIMENTS_COUPS: StateId[] = ['oops', 'cheer']

/**
 * Bornes d'un point rendu, en unites de viewBox. Un `d` est en unites de rayon, relatif a
 * son origine : on le tourne de `rot` comme le rendu, puis on le met a l'echelle `R`.
 */
function bornes(dot: DotRender, R: number): [number, number, number, number] {
  if (!dot.d) return [dot.x - dot.r, dot.x + dot.r, dot.y - dot.r, dot.y + dot.r]
  const nums = dot.d.match(/-?\d*\.?\d+/g)!.map(Number)
  const th = ((dot.rot ?? 0) * Math.PI) / 180
  const c = Math.cos(th)
  const sn = Math.sin(th)
  const xs: number[] = []
  const ys: number[] = []
  for (let i = 0; i < nums.length; i += 2) {
    const px = nums[i]! * R
    const py = nums[i + 1]! * R
    xs.push(dot.x + px * c - py * sn)
    ys.push(dot.y + px * sn + py * c)
  }
  return [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)]
}

describe('etats-sentiments : bulle, glyphes et corps dans le cadre', () => {
  it('chaque point rendu, corps compris, tient dans le cadre a chaque instant', () => {
    const R = 100
    const lim = CADRE * R
    for (const id of SENTIMENTS) {
      const d = def(id)
      for (let t = 0; t <= d.duration + 1e-9; t += 0.02) {
        const f = new BotEngine(R, id).sample(t)
        const at = `${id} t=${t.toFixed(2)}`
        for (const dot of f.dots) {
          const [x0, x1, y0, y1] = bornes(dot, R)
          expect(x1, `${at} x max`).toBeLessThanOrEqual(lim)
          expect(x0, `${at} x min`).toBeGreaterThanOrEqual(-lim)
          expect(y1, `${at} y max`).toBeLessThanOrEqual(lim)
          expect(y0, `${at} y min`).toBeGreaterThanOrEqual(-lim)
        }
        // le corps : tous les points du contour, courbes de controle comprises (borne large)
        const coords = (f.bodyPath.match(/-?\d*\.?\d+/g) ?? []).map(Number)
        for (let i = 0; i < coords.length; i += 2) {
          expect(Math.abs(coords[i]!), `${at} corps x`).toBeLessThanOrEqual(lim)
          expect(Math.abs(coords[i + 1]!), `${at} corps y`).toBeLessThanOrEqual(lim)
        }
      }
    }
  })
})

describe('etats-sentiments : boucles et coups', () => {
  it('une boucle referme son dessin : chaque point de la pose revient a son point de depart', () => {
    for (const id of SENTIMENTS.filter((s) => BOUCLES.includes(s))) {
      const d = def(id)
      const debut = d.pose(0).dots
      const fin = d.pose(d.duration).dots
      expect(fin.length, `${id} nombre de points`).toBe(debut.length)
      for (let i = 0; i < debut.length; i++) {
        const a = debut[i]!
        const b = fin[i]!
        const at = `${id} point ${i}`
        // un point invisible aux deux bouts (opacite nulle) peut se deplacer sans que la boucle se voie
        if (a.opacity > 1e-6 || b.opacity > 1e-6) {
          expect(Math.abs(a.x - b.x), `${at} x`).toBeLessThan(1e-6)
          expect(Math.abs(a.y - b.y), `${at} y`).toBeLessThan(1e-6)
          expect(a.d, `${at} forme`).toBe(b.d)
        }
        expect(Math.abs(a.r - b.r), `${at} r`).toBeLessThan(1e-6)
        expect(Math.abs(a.opacity - b.opacity), `${at} opacite`).toBeLessThan(1e-6)
      }
    }
  })

  it('un coup de sentiment se pose sur sa fin : corps stable a minDuration et a duration', () => {
    for (const id of SENTIMENTS_COUPS) {
      const d = def(id)
      const a = d.pose(d.minDuration!)
      const b = d.pose(d.duration)
      expect(Math.abs(a.sil.sx - b.sil.sx), `${id} sx`).toBeLessThan(0.01)
      expect(Math.abs(a.sil.sy - b.sil.sy), `${id} sy`).toBeLessThan(0.01)
      expect(Math.abs(a.offY - b.offY), `${id} offY`).toBeLessThan(0.01)
      expect(a.eyes, `${id} yeux`).toEqual(b.eyes)
      // le dessin de la bulle : memes formes, memes echelles et intensites a la fin
      const dessinA = a.dots.slice(1)
      const dessinB = b.dots.slice(1)
      expect(dessinA.length, `${id} nombre de glyphes`).toBe(dessinB.length)
      for (let i = 0; i < dessinA.length; i++) {
        expect(dessinA[i]!.d, `${id} glyphe ${i} forme`).toBe(dessinB[i]!.d)
        expect(Math.abs(dessinA[i]!.r - dessinB[i]!.r), `${id} glyphe ${i} taille`).toBeLessThan(1e-6)
        expect(Math.abs(dessinA[i]!.opacity - dessinB[i]!.opacity), `${id} glyphe ${i} opacite`).toBeLessThan(0.01)
      }
    }
  })
})

