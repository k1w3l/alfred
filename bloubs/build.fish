#!/usr/bin/env fish
# Bundle bloub's framework-free engine into a QML .pragma library.
set root (dirname (dirname (status filename)))
cd $root
npx --yes esbuild bloubs/bridge.ts \
  --bundle \
  --format=iife \
  --global-name=Bloub \
  --target=es2017 \
  --charset=utf8 \
  --legal-comments=none \
  --banner:js='.pragma library' \
  --footer:js='function tick(id, nowMs, shapeId, expressionId, mood, idleVariant, phase, fill, eyes, flow) { return Bloub.tick(id, nowMs, shapeId, expressionId, mood, idleVariant, phase, fill, eyes, flow) }
function play(agentKey, sequence, nowMs, phase) { return Bloub.play(agentKey, sequence, nowMs, phase) }
function release(id) { return Bloub.release(id) }' \
  --outfile=BloubEngine.js
