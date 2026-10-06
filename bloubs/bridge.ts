// QML-facing player for the bloub engine (MIT, jeremy-prt/bloub src/bot).
// Each agent owns a BotEngine. sample() stays a pure function of time;
// this file is only the clock and the cycle table.

import { BotEngine } from '../../misc/bloub/src/bot/engine'
import { blockAt } from '../../misc/bloub/src/bot/cycles'
import { EXPRESSION_BY_ID } from '../../misc/bloub/src/bot/expressions'
import { SHAPE_BY_ID } from '../../misc/bloub/src/bot/skins'
import type { StateId } from '../../misc/bloub/src/bot/states'

type Block = { state: StateId; duration: number }

// Cycles for the Alfred face. The engine eases every morph out (no spring,
// no overshoot on the body); personality lives in the order and the holds.
//
// Language: calm-sharp. One accent, then a longer rest (follow-through).
// A mark gets a short look first (anticipation), never a second copy of
// itself. Holds sit on a 0.1s grid, at or above MIN_BLOCK (0.6s) and each
// state's minDuration. A tape length is kept when that pose is the point
// (wink 1.6, wide 1.8, egg 1.8, hexagon 1.6, exclaim 2, alert 2.4, orbit
// 3.4, burst 2.6, comet 2.4, notify 2.2). Anything shorter is a choice.
// Sleep stays out: that hop reads as a nap.
//
// Adjacent blocks, and the wrap from last to first, never share a state:
// setState() ignores a switch to the current state, so a repeated notify
// or alert would not play again. Idle variants open on idle, so a one-shot
// that hands off to them must not end on idle.
const CYCLES: Record<string, Block[]> = {
  // Idle 1 — butler. Courtesy, a longer exhale, one glance across the room.
  // Rests 3.6 then 5.4. Loop 12.4s.
  idle0: [
    { state: 'idle', duration: 3.6 },
    { state: 'wink', duration: 1.6 },
    { state: 'idle', duration: 5.4 },
    { state: 'wide', duration: 1.8 }
  ],
  // Idle 2 — curious. Look, a short gap so the lean feels prepared, lean,
  // long settle, a brighter coda. Holds 2.4 / 1.2 / 4.2. Loop 13.0s.
  idle1: [
    { state: 'idle', duration: 2.4 },
    { state: 'egg', duration: 1.8 },
    { state: 'idle', duration: 1.2 },
    { state: 'hexagon', duration: 1.6 },
    { state: 'idle', duration: 4.2 },
    { state: 'wide', duration: 1.8 }
  ],
  // Idle 3 — short fuse. Wink, glare, lean, then a long settle so the next
  // wink lands late. Holds 1.8 / 1.2 / 4.6. Loop 12.6s.
  idle2: [
    { state: 'wink', duration: 1.6 },
    { state: 'idle', duration: 1.8 },
    { state: 'wide', duration: 1.8 },
    { state: 'idle', duration: 1.2 },
    { state: 'hexagon', duration: 1.6 },
    { state: 'idle', duration: 4.6 }
  ],
  // Hand-built only. The director does not schedule these.
  // Comet recomposes at 2.45; the last 0.05s finishes in the next fade.
  start: [{ state: 'comet', duration: 2.4 }],
  // Wind-up, then the bouquet. Its opacity hits 0 at t = 2.2.
  startWork: [
    { state: 'idle', duration: 1.0 },
    { state: 'play', duration: 2.2 }
  ],
  // Dots are the hero (~60%). The glance is short; their own face holds
  // longer. Re-entering thinking replays the 0.3s emerge. Loop 8.5s.
  working: [
    { state: 'thinking', duration: 5.2 },
    { state: 'wide', duration: 1.1 },
    { state: 'idle', duration: 2.2 }
  ],
  // Open eyes, then the mark for its measured hold. The next wide, on the
  // repeat, is the recovery. 2.9s, played three times.
  error: [
    { state: 'wide', duration: 0.9 },
    { state: 'exclaim', duration: 2 }
  ],
  // Look, then the full travel: out over 1.5s, back by 2.0, a 0.4s settle.
  // 3.3s, played three times.
  attention: [
    { state: 'wide', duration: 0.9 },
    { state: 'alert', duration: 2.4 }
  ],
  // One bow. Rings enter over 0.8s, the body has relaxed by 2.5s, and at
  // 3.4s the rings are nearly gone (their fade ends at 3.6). Played once:
  // repeating a finished scene reads as a stuck loop.
  success: [{ state: 'orbit', duration: 3.4 }],
  // The badge is the signal. One block never re-enters, so the pop plays
  // on the way in and the pill holds. Another state would drop the badge.
  notification: [{ state: 'notify', duration: 2.2 }],
  // Collapse, hold, regrow (done at 2.4). The extra 0.2s is the face back
  // before the morph into rest.
  end: [{ state: 'burst', duration: 2.6 }],
  // Attentive expression only survives on idle (other states bring their
  // own face). Lean in, come back sooner, small ack. Idle is 6.4 of 9.8s.
  listening: [
    { state: 'idle', duration: 3.8 },
    { state: 'egg', duration: 1.8 },
    { state: 'idle', duration: 2.6 },
    { state: 'wink', duration: 1.6 }
  ]
}

const SHAPE_ALIAS: Record<string, string> = {
  circle: 'cercle',
  cercle: 'cercle',
  squircle: 'squircle',
  diamond: 'hexagone',
  hexagon: 'hexagone',
  hexagone: 'hexagone',
  drop: 'goutte',
  droplet: 'goutte',
  goutte: 'goutte',
  cloud: 'nuage',
  nuage: 'nuage',
  triangle: 'triangle',
  pebble: 'galet',
  galet: 'galet',
  capsule: 'capsule'
}

const EXPRESSION_ALIAS: Record<string, string> = {
  soft: 'neutre',
  angry: 'colere',
  pause: 'blase',
  neutre: 'neutre',
  attentif: 'attentif',
  surpris: 'surpris',
  excite: 'excite',
  heureux: 'heureux',
  hilare: 'hilare',
  colere: 'colere',
  triste: 'triste',
  effraye: 'effraye',
  mefiant: 'mefiant',
  confus: 'confus',
  curieux: 'curieux',
  fier: 'fier',
  timide: 'timide',
  blase: 'blase',
  somnolent: 'somnolent'
}

const MOOD_CYCLE: Record<string, string> = {
  idle: 'idle',
  busy: 'working',
  working: 'working',
  listening: 'listening',
  attention: 'attention',
  error: 'error',
  success: 'success',
  permission: 'attention'
}

const OUTCOME_CLIP: Record<string, string> = {
  success: 'success',
  error: 'error',
  permission: 'attention',
  attention: 'attention'
}

// A finished scene plays once. A punctuation mark knocks three times.
function beatsOf(clip: string): number {
  return clip === 'success' ? 1 : 3
}

export type Segment = { cycle: string; repeat?: number }

// A compiled sequence: one-shot blocks laid end to end from `start`, then
// `loop` forever. Times are on the player clock (seconds).
type Timeline = {
  key: string
  start: number
  once: { state: StateId; at: number; duration: number; clip: string }[]
  onceEnd: number
  loop: Block[]
  loopClip: string
}

type Placed = { state: StateId; at: number; clip: string; index: number }

type Player = {
  engine: BotEngine
  shapeId: string
  expressionId: string
  timelineKey: string
  blockAt: number
  state: StateId
}

// One director per agent drives every directed slot of that agent (the
// compact ball and the current chip), so a flow started on the ball carries
// over to the chip when the pill opens.
type Director = {
  timeline: Timeline
  compact: boolean
  mood: string
  latched: string
  seen: number
}

const players = new Map<string, Player>()
const directors = new Map<string, Director>()
let timelineSerial = 0

function compile(sequence: Segment[], start: number, prefix: Timeline['once'] = []): Timeline {
  const once = prefix.slice()
  let at = once.length ? once[once.length - 1]!.at + once[once.length - 1]!.duration : start
  const last = sequence.length - 1
  for (let s = 0; s < last; s++) {
    const seg = sequence[s]!
    const blocks = CYCLES[seg.cycle]
    if (!blocks) continue
    const repeat = Math.max(1, Math.floor(Number(seg.repeat) || 1))
    for (let r = 0; r < repeat; r++) {
      for (const b of blocks) {
        once.push({ state: b.state, at, duration: b.duration, clip: seg.cycle })
        at += b.duration
      }
    }
  }
  const tail = sequence[last]
  const loopClip = tail && CYCLES[tail.cycle] ? tail.cycle : 'idle0'
  timelineSerial += 1
  return {
    key: 't' + timelineSerial,
    start: once.length ? once[0]!.at : start,
    once,
    onceEnd: at,
    loop: CYCLES[loopClip]!,
    loopClip
  }
}

function place(tl: Timeline, clock: number): Placed {
  if (clock < tl.onceEnd) {
    for (let i = tl.once.length - 1; i >= 0; i--) {
      const b = tl.once[i]!
      if (clock >= b.at || i === 0) return { state: b.state, at: b.at, clip: b.clip, index: i }
    }
  }
  const placed = blockAt(tl.loop, clock - tl.onceEnd)
  return {
    state: tl.loop[placed.index]!.state,
    at: clock - placed.elapsed,
    clip: tl.loopClip,
    index: tl.once.length + placed.index
  }
}

// The one-shot block playing now, with the rest of its clip run, so a new
// sequence can queue behind start/end instead of cutting them.
function runningPrefix(tl: Timeline, clock: number, clips: string[]): Timeline['once'] {
  if (clock >= tl.onceEnd) return []
  const placed = place(tl, clock)
  if (clips.indexOf(placed.clip) < 0) return []
  let i = placed.index
  while (i > 0 && tl.once[i - 1]!.clip === placed.clip) i--
  let j = placed.index
  while (j + 1 < tl.once.length && tl.once[j + 1]!.clip === placed.clip) j++
  return tl.once.slice(i, j + 1)
}

function restCycle(mood: string, idleVariant: number): string {
  if (mood === 'listening') return 'listening'
  if (mood === 'busy' || mood === 'working') return 'working'
  return cycleKeyOf('idle', idleVariant)
}

function tailOf(d: Director, idleVariant: number): string {
  if (d.mood === 'listening') return 'listening'
  if (d.mood === 'busy' || d.mood === 'working') return 'working'
  if (d.latched) return 'notification'
  return cycleKeyOf('idle', idleVariant)
}

/**
 * Plays `sequence` on an agent's directed slots from `nowMs`: every segment
 * but the last runs `repeat` times (default 1), the last one loops.
 */
export function play(agentKey: string, sequence: Segment[], nowMs: number, phase?: number) {
  const key = String(agentKey || 'blob')
  const clock = (Number(nowMs) || 0) / 1000 + (Number(phase) || 0)
  const d = directors.get(key)
  const tl = compile(sequence && sequence.length ? sequence : [{ cycle: 'idle0' }], clock)
  if (d) d.timeline = tl
  else directors.set(key, { timeline: tl, compact: false, mood: 'idle', latched: '', seen: clock })
  return tl.once.map((b) => b.clip + ':' + b.state + '@' + (b.at - clock).toFixed(2)).concat(['loop ' + tl.loopClip])
}

function direct(agentKey: string, clock: number, mood: string, compact: boolean, idleVariant: number): Director {
  let d = directors.get(agentKey)
  if (!d) {
    const first = mood === 'permission' ? 'notification' : restCycle(mood, idleVariant)
    d = {
      timeline: compile([{ cycle: first }], 0),
      compact,
      mood,
      latched: mood === 'permission' ? 'attention' : '',
      seen: clock
    }
    directors.set(agentKey, d)
    return d
  }
  // Nothing drew this agent for a while (HUD hidden). A missed close does not
  // deserve an end.
  const stale = clock - d.seen > 1.5
  d.seen = clock

  const wasCompact = d.compact
  const wasMood = d.mood
  d.compact = compact
  d.mood = mood
  const busy = mood === 'busy' || mood === 'working'

  if (compact !== wasCompact) {
    if (compact) {
      if (mood !== wasMood && OUTCOME_CLIP[mood] && !busy) {
        d.latched = OUTCOME_CLIP[mood]!
        d.timeline = compile([{ cycle: d.latched, repeat: beatsOf(d.latched) }, { cycle: tailOf(d, idleVariant) }], clock)
        return d
      }
      // otherwise the ball keeps whatever loop was running
      const tail = tailOf(d, idleVariant)
      if (d.timeline.loopClip !== tail) {
        const keep = runningPrefix(d.timeline, clock, ['success', 'error', 'attention'])
        d.timeline = compile([{ cycle: tail }], clock, keep)
      }
      return d
    }
    if (!stale) {
      // opening the pill is the acknowledgement
      d.latched = ''
      d.timeline = compile([{ cycle: 'end' }, { cycle: tailOf(d, idleVariant) }], clock)
      return d
    }
    d.latched = ''
    d.timeline = compile([{ cycle: tailOf(d, idleVariant) }], clock)
    return d
  }

  if (mood === wasMood) return d
  const prefix = runningPrefix(d.timeline, clock, ['end'])

  if (busy) {
    d.latched = ''
    d.timeline = compile([{ cycle: 'working' }], clock, prefix)
    return d
  }
  if (mood === 'listening' || wasMood === 'listening') {
    d.timeline = compile([{ cycle: tailOf(d, idleVariant) }], clock, prefix)
    return d
  }
  const outcome = OUTCOME_CLIP[mood]
  if (outcome) {
    // Seen with the pill open, the outcome needs no notification afterwards.
    d.latched = compact ? outcome : ''
    d.timeline = compile([{ cycle: outcome, repeat: beatsOf(outcome) }, { cycle: tailOf(d, idleVariant) }], clock, prefix)
    return d
  }
  // Back to idle: a latched notification waits for the pill to open, and an
  // outcome run already playing finishes first.
  if (d.latched) return d
  const keep = runningPrefix(d.timeline, clock, ['end', 'success', 'error', 'attention'])
  d.timeline = compile([{ cycle: tailOf(d, idleVariant) }], clock, keep)
  return d
}

function shapeIdOf(raw: string): string {
  const id = SHAPE_ALIAS[String(raw || '').toLowerCase()] || 'cercle'
  return SHAPE_BY_ID.has(id) ? id : 'cercle'
}

function expressionIdOf(expression: string, eyes: string, mood: string): string {
  if (String(mood || '') === 'listening') return 'attentif'
  const fromExpr = EXPRESSION_ALIAS[String(expression || '').toLowerCase()]
  if (fromExpr && EXPRESSION_BY_ID.has(fromExpr)) return fromExpr
  const fromEyes = EXPRESSION_ALIAS[String(eyes || '').toLowerCase()]
  if (fromEyes && EXPRESSION_BY_ID.has(fromEyes)) return fromEyes
  return 'neutre'
}

function cycleKeyOf(mood: string, idleVariant: number): string {
  const moodKey = MOOD_CYCLE[String(mood || 'idle')] || 'idle0'
  if (moodKey !== 'idle') return moodKey
  const variant = ((Number(idleVariant) || 0) % 3 + 3) % 3
  return 'idle' + variant
}

function hexOf(value: string): string {
  const raw = String(value || '').replace('#', '').trim()
  if (raw.length === 8) return '#' + raw.slice(2, 8)
  if (raw.length === 6) return '#' + raw
  return '#0a0a0c'
}

function circlePath(cx: number, cy: number, r: number): string {
  const d = r * 2
  return `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${d} 0a${r} ${r} 0 1 0 ${-d} 0`
}

function dotRecord(dot: {
  x: number
  y: number
  r: number
  opacity: number
  color?: string
  depth?: number
  d?: string
  rot?: number
}, ink: string) {
  const opacity = dot.opacity * (dot.depth === undefined ? 1 : Math.max(0, Math.min(1, dot.depth)))
  const color = dot.color || ink
  if (dot.d) {
    const rot = ((dot.rot || 0) * Math.PI) / 180
    const c = Math.cos(rot) * 100
    const s = Math.sin(rot) * 100
    return {
      path: dot.d,
      ma: c,
      mb: s,
      mc: -s,
      md: c,
      me: dot.x,
      mf: dot.y,
      color,
      opacity,
      span: 1.6
    }
  }
  return {
    path: circlePath(dot.x, dot.y, Math.max(dot.r, 0.01)),
    ma: 1,
    mb: 0,
    mc: 0,
    md: 1,
    me: 0,
    mf: 0,
    color,
    opacity,
    // Circumference in the same space as `path`, so the rim dash fits the dot.
    span: Math.PI * 2 * Math.max(dot.r, 0.01)
  }
}

// Chord length of the silhouette. The path is a loop of cubics; the last
// control point of each curve is the anchor the dash period has to follow,
// including the tiny centre dot of `thinking`.
function pathSpan(path: string): number {
  const nums = path.match(/-?\d*\.?\d+/g)
  if (!nums || nums.length < 4) return 620
  const pts: { x: number; y: number }[] = [{ x: Number(nums[0]), y: Number(nums[1]) }]
  for (let i = 2; i + 5 < nums.length; i += 6) pts.push({ x: Number(nums[i + 4]), y: Number(nums[i + 5]) })
  let span = 0
  for (let i = 1; i < pts.length; i++) span += Math.hypot(pts[i]!.x - pts[i - 1]!.x, pts[i]!.y - pts[i - 1]!.y)
  if (pts.length > 2) span += Math.hypot(pts[0]!.x - pts[pts.length - 1]!.x, pts[0]!.y - pts[pts.length - 1]!.y)
  return span > 8 ? span : 620
}

function arcRecord(arc: { front?: string; back?: string; width: number; opacity: number; grad: { stops: string[] } }, which: 'front' | 'back') {
  const path = which === 'front' ? arc.front || '' : arc.back || ''
  const stops = arc.grad.stops || []
  const color = stops[Math.floor(stops.length / 2)] || stops[0] || '#f4f1ea'
  return { path, width: arc.width, color, opacity: path ? arc.opacity : 0 }
}

function parseMatrix(matrix: string) {
  const body = matrix.slice(matrix.indexOf('(') + 1, matrix.indexOf(')'))
  const p = body.split(',').map(Number)
  return { ma: p[0] || 1, mb: p[1] || 0, mc: p[2] || 0, md: p[3] || 1, me: p[4] || 0, mf: p[5] || 0 }
}

const freeTimelines = new Map<string, Timeline>()

// Free-running cycles stay on the wall clock, so `phase` keeps agents apart.
function freeTimeline(cycleKey: string): Timeline {
  let tl = freeTimelines.get(cycleKey)
  if (!tl) {
    const loop = CYCLES[cycleKey] ? cycleKey : 'idle0'
    tl = { key: 'free:' + loop, start: 0, once: [], onceEnd: 0, loop: CYCLES[loop]!, loopClip: loop }
    freeTimelines.set(cycleKey, tl)
  }
  return tl
}

export function release(id: string) {
  players.delete(String(id || ''))
}

// Editor draft and swatches. A fixed idle pose at clock 0: the chosen
// expression and shape show, and the idle cycle does not.
// A fresh engine, never stored in `players` and never passed through `direct`,
// so a still face cannot evict a live agent or reset that agent's engine.
function stillTick(shapeId: string, expressionId: string, fill: string) {
  const shape = SHAPE_BY_ID.get(shapeId)
  const expression = EXPRESSION_BY_ID.get(expressionId) || null
  const engine = new BotEngine(100, 'idle', shape ? shape.radii : null, expression)
  engine.reset('idle', 0)
  return present(engine.sample(0), fill, 'idle', 'idle')
}

function present(
  frame: ReturnType<BotEngine['sample']>,
  fill: string,
  clip: string,
  state: StateId
) {
  const ink = hexOf(fill)
  const eyes = []
  for (let i = 0; i < frame.eyes.length; i++) {
    const eye = frame.eyes[i]!
    eyes.push({ path: eye.d, alpha: eye.alpha, ...parseMatrix(eye.matrix) })
  }
  const arcsBack = []
  const arcsFront = []
  for (let i = 0; i < frame.arcs.length; i++) {
    const arc = frame.arcs[i]!
    arcsBack.push(arcRecord(arc, 'back'))
    arcsFront.push(arcRecord(arc, 'front'))
  }
  const dots = []
  for (let i = 0; i < frame.dots.length; i++) dots.push(dotRecord(frame.dots[i]!, ink))

  return {
    body: frame.bodyPath,
    alpha: frame.bodyAlpha,
    eyes,
    arcsBack,
    arcsFront,
    dots,
    dotsBehind: frame.dotsBehind,
    span: pathSpan(frame.bodyPath),
    notif: frame.notif ? circlePath(frame.notif.x, frame.notif.y, frame.notif.r) : '',
    clip,
    state
  }
}

export function tick(
  id: string,
  nowMs: number,
  shapeRaw: string,
  expressionRaw: string,
  mood: string,
  idleVariant: number,
  phase: number,
  fill: string,
  eyesRaw: string,
  flow?: string
) {
  const key = String(id || 'blob')
  const shapeId = shapeIdOf(shapeRaw)
  const expressionId = expressionIdOf(expressionRaw, eyesRaw, mood)
  // flow '' = free-running mood cycle (tray, other chips); 'compact'/'open'
  // = directed by the agent's flow (ball, current chip); 'still' = fixed idle
  // pose, off the player map.
  const flowMode = String(flow || '')
  if (flowMode === 'still') return stillTick(shapeId, expressionId, fill)
  const clock = (Number(nowMs) || 0) / 1000 + (Number(phase) || 0)
  let timeline: Timeline
  if (flowMode === 'compact' || flowMode === 'open') {
    const agentKey = key.indexOf('/') >= 0 ? key.slice(0, key.lastIndexOf('/')) : key
    timeline = direct(agentKey, clock, String(mood || 'idle'), flowMode === 'compact', idleVariant).timeline
  } else {
    timeline = freeTimeline(cycleKeyOf(mood, idleVariant))
  }
  const placed = place(timeline, clock)
  const start = placed.at
  let player = players.get(key)
  const shape = SHAPE_BY_ID.get(shapeId)
  const expression = EXPRESSION_BY_ID.get(expressionId) || null

  if (!player) {
    const engine = new BotEngine(100, placed.state, shape ? shape.radii : null, expression)
    player = { engine, shapeId, expressionId, timelineKey: timeline.key, blockAt: start, state: placed.state }
    engine.reset(placed.state, start)
    players.set(key, player)
    if (players.size > 24) {
      const oldest = players.keys().next().value
      if (oldest && oldest !== key) players.delete(oldest)
    }
  } else {
    if (player.shapeId !== shapeId) {
      player.shapeId = shapeId
      player.engine.setShape(shape ? shape.radii : null, clock)
    }
    if (player.expressionId !== expressionId) {
      player.expressionId = expressionId
      player.engine.setExpression(expression, clock)
    }
    const free = timeline.key.indexOf('free:') === 0
    if (player.timelineKey !== timeline.key && free) {
      player.engine.reset(placed.state, start)
    } else if (player.timelineKey !== timeline.key || player.blockAt !== start) {
      // directed hand-overs blend; a repeat of the same state keeps running
      if (player.state !== placed.state) player.engine.setState(placed.state, start)
    }
    player.timelineKey = timeline.key
    player.blockAt = start
    player.state = placed.state
  }

  return present(player.engine.sample(clock), fill, placed.clip, placed.state)
}
