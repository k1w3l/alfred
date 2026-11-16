// QML-facing player for the bloub engine (MIT, jeremy-prt/bloub src/bot).
// Each agent owns a BotEngine. sample() stays a pure function of time;
// this file is only the clock and the cycle table.

import { BotEngine, type Look } from './engine/src/bot/engine'
import { blockAt } from './engine/src/bot/cycles'
import { EXPRESSION_BY_ID } from './engine/src/bot/expressions'
import { SHAPE_BY_ID } from './engine/src/bot/skins'
import { STATE_BY_ID, type StateId } from './engine/src/bot/states'

type Block = { state: StateId; duration: number }

// Cycles for the Alfred face. The engine eases every morph out (no spring,
// no overshoot on the body); personality lives in the order and the holds.
//
// Language: calm-sharp. One accent, then a longer rest (follow-through).
// A mark gets a short look first (anticipation), never a second copy of
// itself. Holds sit on a 0.1s grid, at or above MIN_BLOCK (0.6s) and each
// state's minDuration. A tape length is kept when that pose is the point.
// Sleep stays out of the activity cycles: that hop reads as a nap.
//
// Two adjacent blocks of one state (focus, curious, drowsy) are one hold to
// the engine, since setState ignores a switch to the current state. There
// that is the intent: a long look reads as a sustained mood, not a stutter.
//
// Scenes are grouped by what drives them: the idle family (chosen by time
// and valence, see idleKey), activity while a turn runs, outcomes that play
// once, glances, and the reaction clips that land on top of whatever runs.
const CYCLES: Record<string, Block[]> = {
  // Idle 1 — butler. Courtesy, a lean, a longer exhale, one glance.
  // Rests 2.8 / 1.6 / 3.2. Loop 12.8s.
  idle0: [
    { state: 'idle', duration: 2.8 },
    { state: 'wink', duration: 1.6 },
    { state: 'idle', duration: 1.6 },
    { state: 'egg', duration: 1.8 },
    { state: 'idle', duration: 3.2 },
    { state: 'wide', duration: 1.8 }
  ],
  // Idle 2 — curious. Look, lean, settle, a wink, then the brighter coda.
  // Holds 2.2 / 1.2 / 1.6 / 1.8. Loop 13.6s.
  idle1: [
    { state: 'idle', duration: 2.2 },
    { state: 'egg', duration: 1.8 },
    { state: 'idle', duration: 1.2 },
    { state: 'hexagon', duration: 1.6 },
    { state: 'idle', duration: 1.6 },
    { state: 'wink', duration: 1.6 },
    { state: 'idle', duration: 1.8 },
    { state: 'wide', duration: 1.8 }
  ],
  // Idle 3 — short fuse. Wink, glare, lean, then a lean-in before the
  // settle so the next wink lands late. Holds 1.6 / 1.2 / 2.2 / 2.2. Loop 14.0s.
  idle2: [
    { state: 'wink', duration: 1.6 },
    { state: 'idle', duration: 1.6 },
    { state: 'wide', duration: 1.8 },
    { state: 'idle', duration: 1.2 },
    { state: 'hexagon', duration: 1.6 },
    { state: 'idle', duration: 2.2 },
    { state: 'egg', duration: 1.8 },
    { state: 'idle', duration: 2.2 }
  ],
  // Activity while a turn runs. Focus is the work pose; one wide breaks it
  // up. No wink: winking while working reads as flippant. Loop 13.0s.
  working: [
    { state: 'focus', duration: 2.8 },
    { state: 'focus', duration: 2.8 },
    { state: 'idle', duration: 1.4 },
    { state: 'focus', duration: 2.8 },
    { state: 'wide', duration: 1.0 }
  ],
  // Before the first text: a speech bubble with three dots above the bloub.
  reasoning: [{ state: 'ponder', duration: 3.0 }],
  // Text is arriving: a small nod at each beat of the reply.
  speaking: [
    { state: 'idle', duration: 2.2 },
    { state: 'nod', duration: 0.6 },
    { state: 'idle', duration: 1.8 },
    { state: 'curious', duration: 1.2 },
    { state: 'nod', duration: 0.6 }
  ],
  // The mic is open: a lean in, then a wide ack. Idle is a short rest.
  listening: [
    { state: 'curious', duration: 2.4 },
    { state: 'curious', duration: 2.4 },
    { state: 'idle', duration: 1.4 },
    { state: 'wide', duration: 1.4 }
  ],
  // One bow after a finished turn, played once. The hop lands, the check settles.
  success: [
    { state: 'hop', duration: 1.6 },
    { state: 'cheer', duration: 2.0 }
  ],
  // A success after a rough streak: a relieved breath, then the check.
  relief: [
    { state: 'relieved', duration: 1.8 },
    { state: 'cheer', duration: 2.0 }
  ],
  // A startle, then the mark. The mood layer carries the after-effect.
  error: [
    { state: 'startle', duration: 0.9 },
    { state: 'oops', duration: 2.4 }
  ],
  // Waiting on the user: one wonder beat when the wait starts, then the same
  // question held (waiting) until the mood moves on. A pending question keeps asking.
  attention: [{ state: 'wonder', duration: 3.0 }],
  waiting: [{ state: 'wonder', duration: 3.0 }],
  // Looks. Consecutive glances alternate between these two (see glanceSeg).
  glance: [{ state: 'wide', duration: 1.1 }],
  glanceSoft: [{ state: 'curious', duration: 1.2 }],
  // Long idle: one yawn, then the drowsy loop (drowsyLoop2 below).
  tired: [{ state: 'yawn', duration: 2.0 }],
  // Loop 8.0s. The yawn ends on drowsy's first pose; the nod-off is sleepy.
  drowsyLoop2: [
    { state: 'drowsy', duration: 3.2 },
    { state: 'sleepy', duration: 2.4 },
    { state: 'sleepy', duration: 2.4 }
  ],
  // Idle for a while (past BORED_AFTER): a glance, a bored sigh, a settle.
  boredIdle: [
    { state: 'idle', duration: 2.4 },
    { state: 'bored', duration: 3.6 },
    { state: 'idle', duration: 2.0 }
  ],
  // Standby: the bloub dozes with a slow 'z Z'.
  asleep: [{ state: 'sleepy', duration: 2.4 }],
  // Low valence: the face hangs, with a short settle.
  downIdle: [
    { state: 'down', duration: 3.0 },
    { state: 'down', duration: 3.0 },
    { state: 'idle', duration: 1.8 }
  ],
  // High valence: a brighter coda with a wink and a hop.
  brightIdle: [
    { state: 'idle', duration: 2.2 },
    { state: 'wink', duration: 1.6 },
    { state: 'idle', duration: 1.8 },
    { state: 'hop', duration: 1.6 },
    { state: 'idle', duration: 1.6 }
  ],
  // The hero in flight between the bar icon and the pill. The travel body
  // is a loop; the blink on entry hides the morph.
  travel: [{ state: 'travel', duration: 1.0 }],
  // Reaction clips. Each one lands on top of the running cycle, then the
  // cycle resumes.
  tapTool: [{ state: 'nod', duration: 0.6 }],
  ouch: [{ state: 'startle', duration: 0.9 }],
  perk: [{ state: 'curious', duration: 1.2 }],
  // A click: a short surprised look. Plays over an idle or notification run.
  poke: [{ state: 'wide', duration: 0.6 }],
  // The assistant asked something: a wonder beat.
  question: [{ state: 'wonder', duration: 2.4 }],
  // The reply laughed, or the user thanked: a chevron laugh, a heart.
  laugh: [{ state: 'laugh', duration: 2.0 }],
  love: [{ state: 'love', duration: 2.0 }],
  // A pondering beat with no kind mapped to it yet.
  think: [{ state: 'ponder', duration: 3.0 }],
  // The badge is the signal. One block never re-enters, so the pop plays
  // on the way in and the pill holds. Another state would drop the badge.
  notification: [{ state: 'notify', duration: 2.2 }],
  // Collapse, hold, regrow (done at 2.4). The extra 0.2s is the face back
  // before the morph into rest.
  end: [{ state: 'burst', duration: 2.6 }]
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
  reasoning: 'reasoning',
  speaking: 'speaking',
  listening: 'listening',
  attention: 'attention',
  error: 'error',
  success: 'success',
  permission: 'attention'
}

// Moods that run an activity loop instead of the idle rest.
const ACTIVITY: Record<string, string> = {
  busy: 'working',
  working: 'working',
  reasoning: 'reasoning',
  speaking: 'speaking'
}

function isActivity(mood: string): boolean {
  return Object.prototype.hasOwnProperty.call(ACTIVITY, mood)
}

// Moods that keep the agent attentive while they last. An outcome does not
// count: the caller keeps reporting "success" until the next send, and that
// must not hold off tiredness.
function isActive(mood: string): boolean {
  return isActivity(mood) || mood === 'listening' || mood === 'attention' || mood === 'permission'
}

// Moods that rest on the idle family once their scene has played.
const RESTING = ['idle', 'success', 'error']

const OUTCOME_CLIP: Record<string, string> = {
  success: 'success',
  error: 'error',
  permission: 'attention',
  attention: 'attention'
}

// Protected scenes play to their end: a reaction is dropped on them and a new
// mood queues behind them. `tired` is the yawn only; the drowsy loop after it
// is not protected.
const PROTECTED = ['end', 'success', 'relief', 'error', 'attention', 'travel', 'tired']
// A busy or listening entry waits for the close burst only. Attention is left
// out on purpose: a granted permission should start the work at once.
const ENTER_PROTECTED = ['end']

// Mood model. Energy relaxes toward REST_ENERGY and valence toward 0, with
// time constant MOOD_TAU; busy work drains energy. All of it is a function of
// the clock the director is given, never of Date.now().
const REST_ENERGY = 0.8
const REST_VALENCE = 0
const MOOD_TAU = 240
const BUSY_DRAIN_PER_MIN = 0.02
const BORED_AFTER = 120
const TIRED_AFTER = 300
const SLEEP_AFTER = 600
const LOW_ENERGY = 0.3
const SAD = -0.4
const HAPPY = 0.4

// Flight gaze: the eyes lead the body toward the target, so the morph is short.
const FLIGHT_GAZE_MORPH = 0.12
const HANDBACK_MORPH = 0.25

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

type Placed = { state: StateId; at: number; end: number; clip: string; index: number }

type Player = {
  engine: BotEngine
  shapeId: string
  expressionId: string
  timelineKey: string
  blockAt: number
  state: StateId
  // True while the hero is in flight; the gaze is then the flight's target.
  flying: boolean
  lookX: number
  lookY: number
  // Pointer gaze last sent to the engine: on, and the angles it aimed at.
  pointerOn: boolean
  pointerYaw: number
  pointerPitch: number
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
  idleVariant: number
  energy: number
  valence: number
  lastAt: number
  lastActiveAt: number
  // Counts glances, so consecutive looks alternate between the two.
  glances: number
  // Next idle check: the idle loop can drift to tired, down or bright on a block edge.
  nextCheck: number
  // Last time each reaction clip played, for its minimum gap.
  reactedAt: Record<string, number>
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
      if (clock >= b.at || i === 0) {
        return { state: b.state, at: b.at, end: b.at + b.duration, clip: b.clip, index: i }
      }
    }
  }
  const placed = blockAt(tl.loop, clock - tl.onceEnd)
  const block = tl.loop[placed.index]!
  const at = clock - placed.elapsed
  return {
    state: block.state,
    at,
    end: at + block.duration,
    clip: tl.loopClip,
    index: tl.once.length + placed.index
  }
}

// The unfinished run of the last scene in `clips`, with the unfinished blocks
// that lead into it, so a new sequence queues behind it instead of cutting it.
// A scene still waiting in the queue counts too: a mood that flickers back to
// rest must not drop an outcome that was queued behind a glance.
function pendingScene(tl: Timeline, clock: number, clips: string[]): Timeline['once'] {
  let end = -1
  for (let i = 0; i < tl.once.length; i++) {
    const b = tl.once[i]!
    if (clips.indexOf(b.clip) >= 0 && b.at + b.duration > clock) end = i
  }
  if (end < 0) return []
  let start = end
  while (start > 0 && tl.once[start - 1]!.at + tl.once[start - 1]!.duration > clock) start--
  return tl.once.slice(start, end + 1)
}

// The block playing now, held to its state's minimum duration. Cutting it
// sooner would show the state for less time than it was made to last.
function heldBlock(tl: Timeline, clock: number): Timeline['once'] {
  const placed = place(tl, clock)
  const min = STATE_BY_ID.get(placed.state)?.minDuration ?? 0
  if (clock - placed.at >= min) return []
  return [{ state: placed.state, at: placed.at, duration: min, clip: placed.clip }]
}

// A protected clip plays out first; otherwise the current block is held.
function queueOf(tl: Timeline, clock: number, clips: string[]): Timeline['once'] {
  const run = pendingScene(tl, clock, clips)
  return run.length ? run : heldBlock(tl, clock)
}

// The rest of the block playing now, so a new loop starts on a block edge.
function boundaryOf(tl: Timeline, clock: number): Timeline['once'] {
  const placed = place(tl, clock)
  return [{ state: placed.state, at: placed.at, duration: placed.end - placed.at, clip: placed.clip }]
}

function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v
}

function newDirector(clock: number, compact: boolean, mood: string, timeline: Timeline, idleVariant: number): Director {
  return {
    timeline,
    compact,
    mood,
    latched: '',
    seen: clock,
    idleVariant,
    energy: REST_ENERGY,
    valence: REST_VALENCE,
    lastAt: clock,
    lastActiveAt: clock,
    glances: 0,
    nextCheck: clock + 1,
    reactedAt: {}
  }
}

function firstCycle(mood: string, idleVariant: number): string {
  if (mood === 'listening') return 'listening'
  if (mood === 'attention' || mood === 'permission') return 'waiting'
  if (isActivity(mood)) return ACTIVITY[mood]!
  return cycleKeyOf('idle', idleVariant)
}

// Looks alternate, so the same glance never plays twice in a row.
function glanceSeg(d: Director): Segment {
  d.glances += 1
  return { cycle: d.glances % 2 === 1 ? 'glance' : 'glanceSoft' }
}

// A director that was asleep or drowsy starts its next sequence with a glance.
function sleeping(d: Director): boolean {
  return d.timeline.loopClip === 'asleep' || d.timeline.loopClip === 'drowsyLoop2'
}

function wakeSeq(d: Director): Segment[] {
  return sleeping(d) ? [glanceSeg(d)] : []
}

// The idle loop the mood and the clock call for. Time spent idle makes the
// agent tired, then asleep; low energy makes it tired at once. Past
// BORED_AFTER it is bored. Valence picks the sad or bright idle.
function idleKey(d: Director, idleVariant: number, clock: number): string {
  const idleFor = clock - d.lastActiveAt
  if (idleFor > SLEEP_AFTER) return 'asleep'
  if (idleFor > TIRED_AFTER || d.energy < LOW_ENERGY) return 'drowsyLoop2'
  if (idleFor > BORED_AFTER) return 'boredIdle'
  if (d.valence < SAD) return 'downIdle'
  if (d.valence > HAPPY) return 'brightIdle'
  return cycleKeyOf('idle', idleVariant)
}

// The loop the director settles on once the current mood has played out.
// A pending question holds the waiting loop until the mood moves on.
function restKey(d: Director, idleVariant: number, clock: number): string {
  if (d.mood === 'listening') return 'listening'
  if (isActivity(d.mood)) return ACTIVITY[d.mood]!
  if (d.latched) return 'notification'
  if (d.mood === 'attention' || d.mood === 'permission') return 'waiting'
  return idleKey(d, idleVariant, clock)
}

// The segments that end a sequence. The yawn runs once, on the way into the
// drowsy loop; a loop that is already drowsy does not yawn again.
function restSeg(d: Director, idleVariant: number, clock: number): Segment[] {
  const key = restKey(d, idleVariant, clock)
  if (key === 'drowsyLoop2' && d.timeline.loopClip !== 'drowsyLoop2') {
    return [{ cycle: 'tired' }, { cycle: key }]
  }
  return [{ cycle: key }]
}

// The scene a mood change plays. A success after a rough streak is relief.
// Read before applyMoodEvent, so the event does not decide its own scene.
function outcomeClip(d: Director, mood: string): string {
  if (mood === 'success') return d.valence < -0.2 ? 'relief' : 'success'
  return OUTCOME_CLIP[mood] || ''
}

function applyMoodEvent(d: Director, mood: string) {
  if (mood === 'success') {
    d.valence = clamp(d.valence + 0.35, -1, 1)
    d.energy = clamp(d.energy + 0.1, 0, 1)
  } else if (mood === 'error') {
    d.valence = clamp(d.valence - 0.3, -1, 1)
  }
}

// Free-running chips (tray, other agents) have no flow, so an outcome would
// loop forever. They show one badge instead. Attention keeps looping (wonder):
// a pending request deserves it. Reasoning keeps its ponder loop.
function freeKey(mood: string, idleVariant: number): string {
  if (mood === 'success' || mood === 'error') return 'notification'
  if (mood === 'speaking') return 'working'
  if (mood === 'attention' || mood === 'permission') return 'waiting'
  return cycleKeyOf(mood, idleVariant)
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
  else directors.set(key, newDirector(clock, false, 'idle', tl, 0))
  return tl.once.map((b) => b.clip + ':' + b.state + '@' + (b.at - clock).toFixed(2)).concat(['loop ' + tl.loopClip])
}

function direct(agentKey: string, clock: number, mood: string, compact: boolean, idleVariant: number): Director {
  let d = directors.get(agentKey)
  if (!d) {
    const first = mood === 'permission' ? 'notification' : firstCycle(mood, idleVariant)
    d = newDirector(clock, compact, mood, compile([{ cycle: first }], 0), idleVariant)
    if (mood === 'permission') d.latched = 'attention'
    directors.set(agentKey, d)
    return d
  }
  // Nothing drew this agent for a while (HUD hidden). A missed close does not
  // deserve an end, and time spent unseen does not drain energy.
  const stale = clock - d.seen > 1.5
  d.seen = clock
  d.idleVariant = idleVariant

  const wasCompact = d.compact
  const wasMood = d.mood
  const wasActive = isActivity(wasMood)
  const busy = isActivity(mood)

  // Mood model: relax toward rest over the stretch since the last call, then
  // drain it if the agent was busy over that stretch.
  const dt = Math.max(0, clock - d.lastAt)
  d.lastAt = clock
  if (dt > 0) {
    const k = 1 - Math.exp(-dt / MOOD_TAU)
    d.energy += (REST_ENERGY - d.energy) * k
    d.valence += (REST_VALENCE - d.valence) * k
    if (wasActive && !stale) d.energy -= (BUSY_DRAIN_PER_MIN * dt) / 60
    d.energy = clamp(d.energy, 0, 1)
  }

  const changed = mood !== wasMood
  const outcome = changed ? outcomeClip(d, mood) : ''
  if (changed) applyMoodEvent(d, mood)
  d.compact = compact
  d.mood = mood
  if (changed || isActive(mood)) d.lastActiveAt = clock

  if (compact !== wasCompact) {
    if (compact) {
      if (outcome) {
        d.latched = outcome
        d.timeline = compile(
          [{ cycle: outcome }, ...restSeg(d, idleVariant, clock)],
          clock,
          queueOf(d.timeline, clock, PROTECTED)
        )
        return d
      }
      // otherwise the ball keeps whatever loop was running, unless its mood moved on
      if (d.timeline.loopClip !== restKey(d, idleVariant, clock)) {
        d.timeline = compile(restSeg(d, idleVariant, clock), clock, queueOf(d.timeline, clock, PROTECTED))
      }
      return d
    }
    if (!stale) {
      // Opening acknowledges a latched outcome with the burst. Any other
      // open is a look across: the burst collapses the body, which read as
      // the face vanishing and coming back.
      const ack = d.latched !== ''
      d.latched = ''
      d.timeline = compile(
        [ack ? { cycle: 'end' } : glanceSeg(d), ...restSeg(d, idleVariant, clock)],
        clock,
        queueOf(d.timeline, clock, ENTER_PROTECTED)
      )
      return d
    }
    d.latched = ''
    d.timeline = compile(restSeg(d, idleVariant, clock), clock, queueOf(d.timeline, clock, PROTECTED))
    return d
  }

  if (!changed) {
    // Idle drifts with time and valence. It is checked once a second, and it
    // changes only on a block edge, so the face never jumps mid-block.
    if (RESTING.indexOf(mood) >= 0 && !d.latched && clock >= d.nextCheck) {
      d.nextCheck = clock + 1
      if (clock >= d.timeline.onceEnd && restKey(d, idleVariant, clock) !== d.timeline.loopClip) {
        d.timeline = compile(restSeg(d, idleVariant, clock), clock, boundaryOf(d.timeline, clock))
      }
    }
    return d
  }

  if (busy) {
    d.latched = ''
    // Entering the activity glances first; moving between activities does not.
    const seq: Segment[] = wasActive
      ? [{ cycle: ACTIVITY[mood]! }]
      : [glanceSeg(d), { cycle: ACTIVITY[mood]! }]
    d.timeline = compile(seq, clock, queueOf(d.timeline, clock, ENTER_PROTECTED))
    return d
  }
  if (outcome) {
    const wake = wakeSeq(d)
    d.latched = compact ? outcome : ''
    d.timeline = compile(
      [...wake, { cycle: outcome }, ...restSeg(d, idleVariant, clock)],
      clock,
      queueOf(d.timeline, clock, ENTER_PROTECTED)
    )
    return d
  }
  if (mood === 'listening' || wasMood === 'listening') {
    const enter = mood === 'listening'
    d.timeline = compile(
      enter ? [glanceSeg(d), { cycle: 'listening' }] : restSeg(d, idleVariant, clock),
      clock,
      queueOf(d.timeline, clock, ENTER_PROTECTED)
    )
    return d
  }
  // Back to rest. A latched notification waits for the pill to open, and a
  // protected scene already playing finishes first.
  if (d.latched) return d
  const run = pendingScene(d.timeline, clock, PROTECTED)
  if (run.length) {
    d.timeline = compile(restSeg(d, idleVariant, clock), clock, run)
  } else {
    d.timeline = compile([glanceSeg(d), ...restSeg(d, idleVariant, clock)], clock, heldBlock(d.timeline, clock))
  }
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

// Reactions: the clip to play, and the minimum gap before that clip plays
// again. The gap is per clip, so a hover and a typed key share one perk.
// `queue` reactions wait behind a protected scene instead of being dropped.
// `valence` and `energy` are the mood nudge the beat gives when it plays.
const REACTIONS: Record<string, { clip: string; gap: number; queue?: boolean; valence?: number; energy?: number }> = {
  tool: { clip: 'tapTool', gap: 1.5 },
  toolError: { clip: 'ouch', gap: 2 },
  typed: { clip: 'perk', gap: 4 },
  hover: { clip: 'perk', gap: 4 },
  poke: { clip: 'poke', gap: 0.8 },
  question: { clip: 'question', gap: 6, queue: true },
  laugh: { clip: 'laugh', gap: 8, queue: true, valence: 0.15, energy: 0.05 },
  love: { clip: 'love', gap: 8, queue: true, valence: 0.2 }
}

/**
 * A small beat on top of the agent's running cycle. Returns false when the
 * reaction is dropped: unknown kind, no director yet, or inside its gap. On a
 * protected scene a queued kind waits for the scene to end; any other kind is
 * dropped.
 */
export function react(agentKey: string, kind: string, nowMs: number): boolean {
  const key = String(agentKey || '')
  const spec = Object.prototype.hasOwnProperty.call(REACTIONS, kind) ? REACTIONS[kind] : undefined
  const d = key ? directors.get(key) : undefined
  if (!spec || !d) return false
  const clock = (Number(nowMs) || 0) / 1000
  const last = d.reactedAt[spec.clip]
  if (last !== undefined && clock - last < spec.gap) return false
  const protectedNow = PROTECTED.indexOf(place(d.timeline, clock).clip) >= 0
  if (protectedNow && !spec.queue) return false
  const wake = wakeSeq(d)
  d.reactedAt[spec.clip] = clock
  d.lastActiveAt = clock
  if (kind === 'tool') d.energy = clamp(d.energy - 0.01, 0, 1)
  if (spec.valence) d.valence = clamp(d.valence + spec.valence, -1, 1)
  if (spec.energy) d.energy = clamp(d.energy + spec.energy, 0, 1)
  // Queued behind the unfinished scene, or cutting in on the held block.
  const prefix = protectedNow ? pendingScene(d.timeline, clock, PROTECTED) : heldBlock(d.timeline, clock)
  d.timeline = compile([...wake, { cycle: spec.clip }, ...restSeg(d, d.idleVariant, clock)], clock, prefix)
  return true
}

// Gaze for a flight: a unit heading in screen coordinates (y down). Positive
// pitch looks up, so the eyes point at the bar or the pill.
function gazeToward(fx: number, fy: number): Look {
  return { yaw: fx * 38, pitch: -fy * 30, mix: 1, spin: 0, wander: 0 }
}

// The gaze handed back at the end of a flight: no target, drift resumes.
const HANDBACK: Look = { yaw: 0, pitch: 0, mix: 0, spin: 0, wander: 1 }

// Pointer gaze: the eyes lean toward the pointer while it is fresh. Full
// deflection needs the pointer six blob-widths away, so the look stays soft.
// The angles are re-sent only when they move by more than POINTER_STEP degrees.
const POINTER_REACH = 6
const POINTER_YAW = 34
const POINTER_PITCH = 26
const POINTER_MIX = 0.8
const POINTER_MORPH = 0.18
const POINTER_RELEASE_MORPH = 0.6
const POINTER_STEP = 0.5
// A gaze script must end in mix 0: this one hands the eyes back to drift.
const POINTER_OFF: Look = { yaw: 0, pitch: 0, mix: 0, spin: 0, wander: 1 }

// Target angles (degrees) for a pointer offset in px from the blob centre, or
// null when there is no usable size or offset.
function pointerGaze(lookX: number, lookY: number, size: number): { yaw: number; pitch: number } | null {
  if (!(size > 0) || !Number.isFinite(lookX) || !Number.isFinite(lookY)) return null
  const reach = size * POINTER_REACH
  return {
    yaw: clamp(lookX / reach, -1, 1) * POINTER_YAW,
    // Screen y points down; positive pitch looks up.
    pitch: -clamp(lookY / reach, -1, 1) * POINTER_PITCH
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
  flow?: string,
  flight?: string,
  flightX?: number,
  flightY?: number,
  lookX?: number,
  lookY?: number,
  lookActive?: number,
  size?: number
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
  const directed = flowMode === 'compact' || flowMode === 'open'
  // The hero climbs out of the bar or lands on it. Only directed slots fly.
  const flightMode = String(flight || '')
  const flying = directed && (flightMode === 'open' || flightMode === 'close')
  const fx = Number(flightX) || 0
  const fy = Number(flightY) || 0
  let timeline: Timeline
  if (directed) {
    const agentKey = key.indexOf('/') >= 0 ? key.slice(0, key.lastIndexOf('/')) : key
    // Still called while flying, so the mood model keeps counting.
    timeline = direct(agentKey, clock, String(mood || 'idle'), flowMode === 'compact', idleVariant).timeline
  } else {
    timeline = freeTimeline(freeKey(String(mood || 'idle'), idleVariant))
  }
  const placed = place(timeline, clock)
  const start = placed.at
  const state: StateId = flying ? 'travel' : placed.state
  let player = players.get(key)
  const shape = SHAPE_BY_ID.get(shapeId)
  const expression = EXPRESSION_BY_ID.get(expressionId) || null

  if (!player) {
    const engine = new BotEngine(100, state, shape ? shape.radii : null, expression)
    player = {
      engine,
      shapeId,
      expressionId,
      timelineKey: timeline.key,
      blockAt: start,
      state,
      flying: false,
      lookX: NaN,
      lookY: NaN,
      pointerOn: false,
      pointerYaw: 0,
      pointerPitch: 0
    }
    engine.reset(state, start)
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
    if (!flying) {
      if (player.flying) {
        // Flight is over: hand the gaze back and let the placed state take
        // over. The state change is always monotonic in the clock.
        player.flying = false
        player.engine.setLook(HANDBACK, clock, HANDBACK_MORPH)
        player.engine.setState(placed.state, clock)
        player.state = placed.state
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
  }

  // While flying the regular hand-over is skipped, so the travel body is not
  // replaced; the gaze follows the target and eases in on entry.
  if (flying) {
    if (!player.flying) {
      player.engine.setState('travel', clock)
      player.flying = true
      player.state = 'travel'
      // The flight's gaze replaces the pointer gaze; the pointer look is sent
      // again once the flight hands back.
      player.pointerOn = false
    }
    if (fx !== player.lookX || fy !== player.lookY) {
      player.lookX = fx
      player.lookY = fy
      player.engine.setLook(gazeToward(fx, fy), clock, FLIGHT_GAZE_MORPH)
    }
  }

  // The pointer gaze yields to a flight. Otherwise it follows the pointer while
  // fresh, and releases to rest when the pointer goes stale.
  if (!flying) {
    const aim = Number(lookActive) === 1 ? pointerGaze(Number(lookX), Number(lookY), Number(size)) : null
    if (aim) {
      if (
        !player.pointerOn ||
        Math.abs(aim.yaw - player.pointerYaw) > POINTER_STEP ||
        Math.abs(aim.pitch - player.pointerPitch) > POINTER_STEP
      ) {
        player.pointerOn = true
        player.pointerYaw = aim.yaw
        player.pointerPitch = aim.pitch
        player.engine.setLook(
          { yaw: aim.yaw, pitch: aim.pitch, mix: POINTER_MIX, spin: 0, wander: 0 },
          clock,
          POINTER_MORPH
        )
      }
    } else if (player.pointerOn) {
      player.pointerOn = false
      player.engine.setLook(POINTER_OFF, clock, POINTER_RELEASE_MORPH)
    }
  }

  return present(player.engine.sample(clock), fill, placed.clip, state)
}
