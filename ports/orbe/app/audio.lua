-- audio.lua : roda numa thread separada (outro núcleo do R36S)
-- 1) calibra: testa JIT ligado/desligado e escolhe taxa/qualidade que caiba na CPU
-- 2) gera o som continuamente, independente do desenho da tela
local cmd, state, hitsCh, info = ...

require("love.filesystem")
require("love.audio")
require("love.sound")
require("love.timer")
local ffi = require("ffi")
local D = require("dsp")
local now = love.timer.getTime

local BUF, NQ = 512, 5
local TARGET = 0.55

local function bench(sr, lite)
  local e = D.new(sr)
  e.lite = lite
  local L, R = {}, {}
  for _ = 1, 6 do e:render(BUF, L, R) end
  local nb = 14
  local t0 = now()
  for _ = 1, nb do e:render(BUF, L, R) end
  return (now() - t0) / (nb * BUF / sr)
end

-- ===== calibração =====
info:push({ kind = "calib", msg = "CALIBRANDO..." })
local jitName = "sem JIT"
local base
if jit then
  jit.on()
  local lOn = bench(22050, false)
  jit.off()
  local lOff = bench(22050, false)
  if lOn < lOff then jit.on(); base = lOn; jitName = "JIT" else base = lOff end
else
  base = bench(22050, false)
end

local SR, LITE, est = 22050, false, base
if base > TARGET then
  local cands = { { 16000, false }, { 16000, true }, { 11025, false }, { 11025, true } }
  for i, c in ipairs(cands) do
    local l = bench(c[1], c[2])
    SR, LITE, est = c[1], c[2], l
    if l <= TARGET or i == #cands then break end
  end
end

local eng = D.new(SR)
eng.lite = LITE
local src = love.audio.newQueueableSource(SR, 16, 2, 8)
local sd = love.sound.newSoundData(BUF, SR, 16, 2)
local ptr = ffi.cast("int16_t*", sd:getFFIPointer())
local L, R = {}, {}
local latency = NQ * BUF / SR
local renderTime, renderCount = 0, 0
local highCount = 0
local alive = true

local function report(load)
  info:push({ kind = "load", load = load, sr = SR, lite = eng.lite, jit = jitName, base = base })
end
report(est)

while alive do
  local m = cmd:pop()
  while m do
    if m.type == "params" then eng:setParams(m)
    elseif m.type == "shake" then eng:shake()
    elseif m.type == "quit" then alive = false
    end
    m = cmd:pop()
  end
  if not alive then break end

  local made = 0
  while src:getFreeBufferCount() > 8 - NQ and made < 3 do
    local t0 = now()
    eng:render(BUF, L, R)
    for i = 0, BUF - 1 do
      ptr[2 * i] = L[i] * 32000
      ptr[2 * i + 1] = R[i] * 32000
    end
    src:queue(sd)
    renderTime = renderTime + (now() - t0)
    renderCount = renderCount + 1
    made = made + 1

    local due = now() + latency
    local hits = eng.hits
    for k = 1, #hits do
      local h = hits[k]
      h.due = due
      hitsCh:push(h)
      hits[k] = nil
    end
    if state:getCount() < 6 then state:push(eng:snapshot(due)) end
  end
  if not src:isPlaying() then src:play() end

  if renderCount >= 40 then
    local load = renderTime / (renderCount * BUF / SR)
    renderTime, renderCount = 0, 0
    -- se a CPU apertar, entra no modo leve sozinho
    if load > 0.85 then highCount = highCount + 1 else highCount = 0 end
    if highCount >= 2 and not eng.lite then eng.lite = true; highCount = 0 end
    report(load)
  end
  love.timer.sleep(0.004)
end

src:stop()
