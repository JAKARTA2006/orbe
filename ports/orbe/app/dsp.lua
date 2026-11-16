-- dsp.lua : motor de áudio do ORBE (v2 — tabelas Lua, rápido com ou sem JIT)
-- Bolas quicando num anel disparam notas (FM), com drone, grãos,
-- eco, reverb (meia taxa) com shimmer e emulação de fita.

local sin, cos, floor, random, abs, exp, sqrt, pi =
  math.sin, math.cos, math.floor, math.random, math.abs, math.exp, math.sqrt, math.pi
local TWO_PI = 2 * pi
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local D = {}
D.__index = D

D.NOTES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
D.MODES = {
  { name = "MENOR",     iv = { 0, 2, 3, 5, 7, 8, 10 } },
  { name = "DORICO",    iv = { 0, 2, 3, 5, 7, 9, 10 } },
  { name = "FRIGIO",    iv = { 0, 1, 3, 5, 7, 8, 10 } },
  { name = "LIDIO",     iv = { 0, 2, 4, 6, 7, 9, 11 } },
  { name = "MAIOR",     iv = { 0, 2, 4, 5, 7, 9, 11 } },
  { name = "PENTA",     iv = { 0, 3, 5, 7, 10 } },
  { name = "HIRAJOSHI", iv = { 0, 2, 3, 7, 8 } },
}
D.TIMBRES = { "SINO", "VIDRO", "CORDA", "SOPRO" }
local TIMBRE = {
  { ratio = 3.5, idx = 2.2, idec = 1.2,  att = 0.004 },  -- SINO
  { ratio = 7.0, idx = 0.9, idec = 0.35, att = 0.002 },  -- VIDRO
  { ratio = 1.0, idx = 3.2, idec = 0.12, att = 0.002 },  -- CORDA
  { ratio = 1.0, idx = 0.9, idec = 4.0,  att = 0.35  },  -- SOPRO
}

local TAB = 2048
local MAXV = 8
local MAXB = 8
local MAXG = 4
local NOISE = 4096

local function mtof(m) return 440 * 2 ^ ((m - 69) / 12) end
local function zeros(n) local t = {}; for i = 1, n do t[i] = 0 end; return t end

function D.defaults()
  return {
    balls = 3, speed = 0.45, gravity = 0.0, spin = 0.25, timbre = 1, octave = 4, decay = 0.55,
    drone = 0.30, grains = 0.35, tape = 0.25, echo = 0.35, space = 0.65, shimmer = 0.40,
    volume = 0.80, root = 2, mode = 6, running = true, freeze = false, tiltX = 0, tiltY = 0,
  }
end

function D.new(sr)
  local self = setmetatable({}, D)
  self.sr = sr
  self.p = D.defaults()
  self.lite = false

  -- tabelas (índice 1..TAB+1)
  local sine, warm = {}, {}
  local peak = 0
  for i = 0, TAB do
    local ph = i / TAB * TWO_PI
    sine[i + 1] = sin(ph)
    local v = 0
    for h = 1, 8 do v = v + sin(ph * h) / (h ^ 1.5) end
    warm[i + 1] = v
    if abs(v) > peak then peak = abs(v) end
  end
  for i = 1, TAB + 1 do warm[i] = warm[i] / peak end
  self.sine, self.warm = sine, warm
  local win = {}
  for i = 0, 256 do win[i + 1] = 0.5 - 0.5 * cos(TWO_PI * i / 256) end
  self.win = win
  local noise = {}
  for i = 1, NOISE do noise[i] = random() * 2 - 1 end
  self.noise, self.nI = noise, 1

  -- vozes FM (estrutura de arrays)
  self.vOn, self.vAmp, self.vStage, self.vAtt, self.vDec = zeros(MAXV), zeros(MAXV), zeros(MAXV), zeros(MAXV), zeros(MAXV)
  self.vC, self.vCI, self.vM, self.vMI = zeros(MAXV), zeros(MAXV), zeros(MAXV), zeros(MAXV)
  self.vIdx, self.vIDec, self.vVel, self.vGL, self.vGR = zeros(MAXV), zeros(MAXV), zeros(MAXV), zeros(MAXV), zeros(MAXV)
  self.nextVoice = 1

  -- drone
  self.dP = zeros(5); for i = 1, 5 do self.dP[i] = random() end
  self.dInc, self.dTgt, self.dAmp, self.dLfo, self.dLr = zeros(3), zeros(3), zeros(3), zeros(3), zeros(3)
  for i = 1, 3 do self.dLfo[i] = random() * TWO_PI; self.dLr[i] = 0.04 + random() * 0.05 end
  self.drL, self.drR = 0, 0

  -- eco (ping-pong)
  self.dlN = floor(sr * 0.5)
  self.dlL, self.dlR = zeros(self.dlN), zeros(self.dlN)
  self.dlW = 1
  self.dlTL, self.dlTR = floor(sr * 0.5 * 0.375), floor(sr * 0.5 * 0.5625)
  self.elH, self.erH, self.vlP, self.vrP = 0, 0, 0, 0
  self.dlFL, self.dlFR = 0, 0

  -- grãos
  self.gbN = floor(sr * 3)
  self.gb = zeros(self.gbN)
  self.gbW = 1
  self.gOn, self.gPos, self.gInc, self.gLen, self.gT, self.gL, self.gR =
    zeros(MAXG), zeros(MAXG), zeros(MAXG), zeros(MAXG), zeros(MAXG), zeros(MAXG), zeros(MAXG)

  -- reverb em meia taxa (sr/2): 4 combs + 2 allpass por canal
  local s = (sr / 2) / 11025
  local combT = { 390, 416, 446, 474 }
  local apT = { 194, 154 }
  self.cB, self.cN, self.cI, self.cS = {}, {}, {}, {}
  self.aB, self.aN, self.aI = {}, {}, {}
  for ch = 0, 1 do
    for i = 1, 4 do
      local k = ch * 4 + i
      local n = floor((combT[i] + ch * 9) * s)
      self.cB[k], self.cN[k], self.cI[k], self.cS[k] = zeros(n), n, 1, 0
    end
    for i = 1, 2 do
      local k = ch * 2 + i
      local n = floor((apT[i] + ch * 5) * s)
      self.aB[k], self.aN[k], self.aI[k] = zeros(n), n, 1
    end
  end
  self.revInL, self.revPL, self.revPR, self.revCL, self.revCR = 0, 0, 0, 0, 0

  -- shimmer (meia taxa)
  self.shWin = 1024
  self.shB = zeros(2048)
  self.shW, self.shPh, self.shLp = 1, 0, 0

  -- fita
  self.tpN = 1024
  self.tpL, self.tpR = zeros(self.tpN), zeros(self.tpN)
  self.tpW = 1
  self.wow, self.flut, self.drift, self.driftGoal, self.driftT = 0, 0, 0, 0, 0
  self.toneL, self.toneR, self.hissLp, self.dly = 0, 0, 0, 100

  -- física
  self.ringAng = 0
  self.balls = {}
  for i = 1, MAXB do self.balls[i] = self:newBall() end
  self.hits = {}
  self.fade = 0
  self.pkL, self.pkR = 0, 0
  self.scope = zeros(96)
  self.scI, self.scD = 1, 0
  self:retune(true)
  return self
end

function D:newBall()
  local a = random() * TWO_PI
  local s = 0.3 + random() * 0.4
  return { x = (random() - 0.5) * 0.3, y = (random() - 0.5) * 0.3, vx = cos(a) * s, vy = sin(a) * s, cool = 0 }
end

function D:retune(instant)
  local base = 36 + self.p.root
  local notes = { base, base + 7, base + 12 }
  for i = 1, 3 do
    self.dTgt[i] = mtof(notes[i]) / self.sr
    if instant then self.dInc[i] = self.dTgt[i] end
  end
end

function D:setParams(t)
  local p = self.p
  local oldRoot, oldMode = p.root, p.mode
  for k, v in pairs(t) do if p[k] ~= nil then p[k] = v end end
  if p.root ~= oldRoot or p.mode ~= oldMode then self:retune(false) end
end

function D:shake()
  for i = 1, MAXB do
    local b = self.balls[i]
    local a = random() * TWO_PI
    b.vx, b.vy = b.vx + cos(a) * 0.8, b.vy + sin(a) * 0.8
  end
end

function D:noteOn(midi, vel, pan)
  local p = self.p
  local tb = TIMBRE[p.timbre] or TIMBRE[1]
  local maxv = self.lite and 5 or MAXV
  local v
  for i = 1, maxv do if self.vOn[i] == 0 then v = i; break end end
  if not v then
    v = self.nextVoice
    self.nextVoice = self.nextVoice % maxv + 1
  end
  local sr = self.sr
  local f = mtof(midi)
  while f > sr * 0.3 do f = f * 0.5 end
  local mi = f * tb.ratio / sr
  while mi > 0.42 do mi = mi * 0.5 end
  local dsec = 1.2 + p.decay * 7
  if p.timbre == 3 then dsec = dsec * 0.6 end
  self.vOn[v] = 1
  self.vCI[v] = f / sr
  self.vMI[v] = mi
  self.vC[v], self.vM[v] = 0, 0
  self.vIdx[v] = tb.idx * (0.6 + 0.4 * vel) * 0.159
  self.vIDec[v] = exp(-1 / (tb.idec * sr))
  self.vDec[v] = exp(-6.9 / (dsec * sr))
  self.vAtt[v] = 1 / (tb.att * sr)
  self.vAmp[v] = 0
  self.vStage[v] = 1
  self.vVel[v] = vel * (p.timbre == 4 and 0.55 or 0.8) * (midi > 84 and 0.7 or 1) * 0.32
  self.vGL[v] = 0.5 - pan * 0.45
  self.vGR[v] = 0.5 + pan * 0.45
end

function D:noteForAngle(a)
  local iv = D.MODES[self.p.mode].iv
  local nseg = #iv * 2
  local seg = floor(a / TWO_PI * nseg) % nseg
  local oct = floor(seg / #iv)
  local deg = seg % #iv
  return 12 * (self.p.octave + 1) + self.p.root + iv[deg + 1] + 12 * oct, seg, nseg
end

function D:physics(dt)
  local p = self.p
  self.ringAng = (self.ringAng + dt * p.spin * 1.1) % TWO_PI
  local S = 0.2 + p.speed * 1.3
  local gx = p.tiltX * 1.6
  local gy = p.gravity * 1.8 + p.tiltY * 1.6
  local lim = 1 - 0.045
  for i = 1, p.balls do
    local b = self.balls[i]
    b.vx = b.vx + gx * dt
    b.vy = b.vy + gy * dt
    local sp = sqrt(b.vx * b.vx + b.vy * b.vy)
    if sp > 1e-4 then
      local k = 1 + (S / sp - 1) * 0.015
      b.vx, b.vy = b.vx * k, b.vy * k
    else
      b.vx = S
    end
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    if b.cool > 0 then b.cool = b.cool - dt end
    local d = sqrt(b.x * b.x + b.y * b.y)
    if d > lim then
      local nx, ny = b.x / d, b.y / d
      local vn = b.vx * nx + b.vy * ny
      if vn > 0 then
        b.vx = b.vx - 2 * vn * nx
        b.vy = b.vy - 2 * vn * ny
        local j = (random() - 0.5) * 0.12
        local c, s = cos(j), sin(j)
        b.vx, b.vy = b.vx * c - b.vy * s, b.vx * s + b.vy * c
        if b.cool <= 0 then
          b.cool = 0.07
          local wa = atan2(ny, nx)
          local la = (wa - self.ringAng) % TWO_PI
          local midi, seg, nseg = self:noteForAngle(la)
          local vel = vn / S
          if vel > 1 then vel = 1 elseif vel < 0.25 then vel = 0.25 end
          self:noteOn(midi, vel, nx)
          local h = self.hits
          h[#h + 1] = { a = wa, seg = seg, nseg = nseg, vel = vel, ball = i }
        end
      end
      b.x, b.y = nx * lim, ny * lim
    end
  end
end

local function softclip(x)
  if x > 3 then return 1 elseif x < -3 then return -1 end
  local x2 = x * x
  return x * (27 + x2) / (27 + 9 * x2)
end

-- render: preenche outL/outR (índices 0..n-1) com n amostras
function D:render(n, outL, outR)
  local sr, p = self.sr, self.p
  local sine, warm, win, noise = self.sine, self.warm, self.win, self.noise
  local SUB = 128
  local lite = self.lite
  local running = p.running

  local droneLvl = p.drone * 0.16
  local echoAmt = p.echo
  local grainAmt = p.grains
  local space = p.space
  local shimAmt = lite and 0 or p.shimmer
  local tape = p.tape
  local vol = p.volume * 2.4
  local maxv = lite and 5 or MAXV
  local maxg = lite and 2 or MAXG

  -- drone por bloco
  local fcD = 1 - exp(-TWO_PI * (180 + p.drone * 500) / (sr * 0.5))
  local dInc, dTgt, dAmp, dLfo, dLr = self.dInc, self.dTgt, self.dAmp, self.dLfo, self.dLr
  for i = 1, 3 do
    dInc[i] = dInc[i] + (dTgt[i] - dInc[i]) * 0.05
    dLfo[i] = dLfo[i] + n / sr * TWO_PI * dLr[i]
    dAmp[i] = (i == 1 and 1 or (i == 2 and 0.7 or 0.45)) * (0.65 + 0.35 * sin(dLfo[i])) * droneLvl
  end
  local dp = self.dP
  local p1, p2, p3, p4, p5 = dp[1], dp[2], dp[3], dp[4], dp[5]
  local i1, i2, i3 = dInc[1] * 2, dInc[2] * 2, dInc[3] * 2
  local i1b, i2b = i1 * 1.003, i2 * 0.9965
  local a1, a2, a3 = dAmp[1], dAmp[2], dAmp[3]
  local drL, drR = self.drL, self.drR

  -- vozes
  local vOn, vAmp, vStage, vAtt, vDec = self.vOn, self.vAmp, self.vStage, self.vAtt, self.vDec
  local vC, vCI, vM, vMI = self.vC, self.vCI, self.vM, self.vMI
  local vIdx, vIDec, vVel, vGL, vGR = self.vIdx, self.vIDec, self.vVel, self.vGL, self.vGR

  -- eco
  local dlL, dlR, dlN, dlW = self.dlL, self.dlR, self.dlN, self.dlW
  local dlTL, dlTR = self.dlTL, self.dlTR
  local dlFb = 0.3 + echoAmt * 0.35
  local dlFL, dlFR = self.dlFL, self.dlFR

  -- grãos
  local gb, gbN, gbW = self.gb, self.gbN, self.gbW
  local freeze = p.freeze
  local gOn, gPos, gInc, gLen, gT, gL, gR = self.gOn, self.gPos, self.gInc, self.gLen, self.gT, self.gL, self.gR

  -- reverb (meia taxa)
  local cB, cN, cI, cS = self.cB, self.cN, self.cI, self.cS
  local aB, aN, aI = self.aB, self.aN, self.aI
  local room = 0.80 + space * 0.155
  local damp = 0.22 + (1 - p.shimmer) * 0.2
  local undamp = 1 - damp
  local wet = space * 0.9 * 1.1 * 0.03
  local revInL = self.revInL
  local revPL, revPR, revCL, revCR = self.revPL, self.revPR, self.revCL, self.revCR
  local shB, shWin, shW, shPh, shLp = self.shB, self.shWin, self.shW, self.shPh, self.shLp
  local shStep = 1 / shWin

  -- fita
  local tpL, tpR, tpN, tpW = self.tpL, self.tpR, self.tpN, self.tpW
  local wow, flut = self.wow, self.flut
  local wowInc, flutInc = TWO_PI * 0.45 / sr * 16, TWO_PI * 5.8 / sr * 16
  self.driftT = self.driftT - n / sr
  if self.driftT <= 0 then self.driftT = 0.7 + random() * 2.5; self.driftGoal = random() * 2 - 1 end
  self.drift = self.drift + (self.driftGoal - self.drift) * 0.03
  local drift = self.drift
  local tpDepth = tape * 50
  local hissLvl = tape * 0.010
  local drive = 1 + tape * 1.8
  local fcT = 1 - exp(-TWO_PI * (9000 - tape * 6000) / sr)
  local toneL, toneR, hissLp, dly = self.toneL, self.toneR, self.hissLp, self.dly
  local nI = self.nI
  local doTape = tape > 0.005

  local elH, erH, vlP, vrP = self.elH, self.erH, self.vlP, self.vrP
  local fade = self.fade
  local fadeT = running and 1 or 0
  local pkL, pkR = self.pkL * 0.85, self.pkR * 0.85
  local scope, scI, scD = self.scope, self.scI, self.scD
  local odd = self.odd or false

  for base = 0, n - 1, SUB do
    if running then self:physics(SUB / sr) end
    -- novos grãos
    if grainAmt > 0.01 and random() < 0.05 + grainAmt * 0.25 then
      for gi = 1, maxg do
        if gOn[gi] == 0 then
          local r = random()
          local pitch = (r < 0.45) and 1 or (r < 0.7 and 0.5 or (r < 0.88 and 2 or 1.5))
          pitch = pitch * (1 + (random() - 0.5) * 0.006)
          local len = floor(sr * (0.12 + random() * 0.35))
          local back = floor(sr * (0.25 + random() * 2.2)) + floor(len * pitch)
          if back > gbN - 4 then back = gbN - 4 end
          gOn[gi], gInc[gi], gLen[gi], gT[gi] = 1, pitch, len, 0
          local pos = gbW - back
          if pos < 1 then pos = pos + gbN end
          gPos[gi] = pos
          local pan = random() * 1.6 - 0.8
          gL[gi], gR[gi] = (0.5 - pan * 0.5) * grainAmt * 1.4, (0.5 + pan * 0.5) * grainAmt * 1.4
          break
        end
      end
    end

    local last = base + SUB - 1
    if last > n - 1 then last = n - 1 end
    for i = base, last do
      if fade ~= fadeT then
        fade = fade + (fadeT - fade) * 0.0003
        if abs(fade - fadeT) < 0.0001 then fade = fadeT end
      end

      -- ===== notas FM =====
      local vl, vr = 0, 0
      for v = 1, maxv do
        if vOn[v] == 1 then
          local a = vAmp[v]
          if vStage[v] == 1 then
            a = a + vAtt[v]
            if a >= 1 then a = 1; vStage[v] = 2 end
          else
            a = a * vDec[v]
            if a < 0.0004 then vOn[v] = 0 end
          end
          vAmp[v] = a
          local m = vM[v] + vMI[v]
          if m >= 1 then m = m - floor(m) end
          vM[v] = m
          local c = vC[v] + vCI[v]
          if c >= 1 then c = c - floor(c) end
          vC[v] = c
          local idx = vIdx[v] * vIDec[v]
          vIdx[v] = idx
          local pp = c + sine[floor(m * TAB) + 1] * idx
          pp = pp - floor(pp)
          local s = sine[floor(pp * TAB) + 1] * a * vVel[v]
          vl = vl + s * vGL[v]
          vr = vr + s * vGR[v]
        end
      end

      local dl, dr = vl + drL, vr + drR
      local el, er = elH, erH

      -- ===== grãos =====
      if not freeze then
        gb[gbW] = (dl + dr) * 0.5 + (el + er) * 0.3
        gbW = gbW + 1; if gbW > gbN then gbW = 1 end
      end
      local gl, gr = 0, 0
      for g = 1, maxg do
        if gOn[g] == 1 then
          local pos = gPos[g]
          local ip = floor(pos)
          local t = gT[g]
          local s = gb[ip] * win[floor(t / gLen[g] * 256) + 1]
          gl = gl + s * gL[g]
          gr = gr + s * gR[g]
          pos = pos + gInc[g]; if pos >= gbN + 1 then pos = pos - gbN end
          gPos[g] = pos
          t = t + 1
          if t >= gLen[g] then gOn[g] = 0 end
          gT[g] = t
        end
      end

      -- ===== reverb + shimmer (a cada 2 amostras) =====
      local inp = (dl + dr) * 0.5 + (gl + gr) * 0.6 + (el + er) * 0.5
      local revL, revR
      if odd then
        -- drone (meia taxa)
        if droneLvl > 0.0005 then
          p1 = p1 + i1;  if p1 >= 1 then p1 = p1 - 1 end
          p2 = p2 + i1b; if p2 >= 1 then p2 = p2 - 1 end
          p3 = p3 + i2;  if p3 >= 1 then p3 = p3 - 1 end
          p4 = p4 + i2b; if p4 >= 1 then p4 = p4 - 1 end
          p5 = p5 + i3;  if p5 >= 1 then p5 = p5 - 1 end
          local x = (warm[floor(p1 * TAB) + 1] + warm[floor(p2 * TAB) + 1]) * a1
          local y = (warm[floor(p3 * TAB) + 1] + warm[floor(p4 * TAB) + 1]) * a2
          local z = sine[floor(p5 * TAB) + 1] * a3
          drL = drL + ((x * 0.6 + y * 0.4 + z) - drL) * fcD
          drR = drR + ((x * 0.4 + y * 0.6 + z) - drR) * fcD
        end
        -- eco ping-pong (meia taxa)
        local rl = dlW - dlTL; if rl < 1 then rl = rl + dlN end
        local rr = dlW - dlTR; if rr < 1 then rr = rr + dlN end
        local e1, e2 = dlL[rl], dlR[rr]
        dlFL = dlFL + (e1 - dlFL) * 0.6
        dlFR = dlFR + (e2 - dlFR) * 0.6
        dlL[dlW] = (vl + vlP) * 0.5 * echoAmt + dlFR * dlFb
        dlR[dlW] = (vr + vrP) * 0.5 * echoAmt + dlFL * dlFb
        dlW = dlW + 1; if dlW > dlN then dlW = 1 end
        elH, erH = e1 * 0.8, e2 * 0.8

        inp = (inp + revInL) * 0.25 + shLp * shimAmt * 0.55
        local rL, rR, o, k, j = 0, 0
        -- canal L
        for c = 1, 4 do
          local buf, j2 = cB[c], cI[c]
          o = buf[j2]
          local st = o * undamp + cS[c] * damp
          cS[c] = st
          buf[j2] = inp + st * room
          j2 = j2 + 1; if j2 > cN[c] then j2 = 1 end
          cI[c] = j2
          rL = rL + o
        end
        for c = 5, 8 do
          local buf, j2 = cB[c], cI[c]
          o = buf[j2]
          local st = o * undamp + cS[c] * damp
          cS[c] = st
          buf[j2] = inp + st * room
          j2 = j2 + 1; if j2 > cN[c] then j2 = 1 end
          cI[c] = j2
          rR = rR + o
        end
        for c = 1, 2 do
          local buf, j2 = aB[c], aI[c]
          o = buf[j2]; buf[j2] = rL + o * 0.5; rL = o - rL
          j2 = j2 + 1; if j2 > aN[c] then j2 = 1 end; aI[c] = j2
        end
        for c = 3, 4 do
          local buf, j2 = aB[c], aI[c]
          o = buf[j2]; buf[j2] = rR + o * 0.5; rR = o - rR
          j2 = j2 + 1; if j2 > aN[c] then j2 = 1 end; aI[c] = j2
        end
        -- shimmer: oitava acima
        if shimAmt > 0.01 then
          shB[shW] = (rL + rR) * 0.015
          shPh = shPh + shStep; if shPh >= 1 then shPh = shPh - 1 end
          local ph2 = shPh + 0.5; if ph2 >= 1 then ph2 = ph2 - 1 end
          local ra = shW - floor((1 - shPh) * shWin); if ra < 1 then ra = ra + 2048 end
          local rb = shW - floor((1 - ph2) * shWin); if rb < 1 then rb = rb + 2048 end
          local gA = 1 - abs(2 * shPh - 1)
          local shv = shB[ra] * gA + shB[rb] * (1 - gA)
          shLp = shLp + (shv - shLp) * 0.3
          shW = shW + 1; if shW > 2048 then shW = 1 end
        end
        revPL, revPR, revCL, revCR = revCL, revCR, rL * wet, rR * wet
        revL, revR = (revPL + revCL) * 0.5, (revPR + revCR) * 0.5
      else
        revInL = inp
        vlP, vrP = vl, vr
        revL, revR = revCL, revCR
      end
      odd = not odd

      -- ===== mix =====
      local L = dl * 0.85 + gl + el * echoAmt + revL
      local R = dr * 0.85 + gr + er * echoAmt + revR

      -- ===== fita =====
      if doTape then
        tpL[tpW] = L; tpR[tpW] = R
        if i % 16 == 0 then
          wow = wow + wowInc; if wow > TWO_PI then wow = wow - TWO_PI end
          flut = flut + flutInc; if flut > TWO_PI then flut = flut - TWO_PI end
          dly = 100 + tpDepth * (sin(wow) + 0.12 * sin(flut) + 0.5 * drift)
        end
        local rp = tpW - dly
        if rp < 1 then rp = rp + tpN end
        local ip = floor(rp)
        local fr = rp - ip
        local i2x = ip + 1; if i2x > tpN then i2x = 1 end
        L = tpL[ip] + (tpL[i2x] - tpL[ip]) * fr
        R = tpR[ip] + (tpR[i2x] - tpR[ip]) * fr
        tpW = tpW + 1; if tpW > tpN then tpW = 1 end
        local w = noise[nI]
        nI = nI + 1; if nI > NOISE then nI = 1 end
        hissLp = hissLp + (w - hissLp) * 0.5
        local h = (w - hissLp) * hissLvl
        L = softclip(L * drive) / drive + h
        R = softclip(R * drive) / drive + h * 0.8
        toneL = toneL + (L - toneL) * fcT
        toneR = toneR + (R - toneR) * fcT
        L, R = toneL, toneR
      end

      local g = vol * fade
      L = L * g; R = R * g
      if L > 3 then L = 1 elseif L < -3 then L = -1 else local x2 = L * L; L = L * (27 + x2) / (27 + 9 * x2) end
      if R > 3 then R = 1 elseif R < -3 then R = -1 else local x2 = R * R; R = R * (27 + x2) / (27 + 9 * x2) end
      outL[i], outR[i] = L, R
      if L > pkL then pkL = L elseif -L > pkL then pkL = -L end
      if R > pkR then pkR = R elseif -R > pkR then pkR = -R end
      scD = scD + 1
      if scD >= 6 then
        scD = 0
        scope[scI] = (L + R) * 0.5
        scI = scI + 1; if scI > 96 then scI = 1 end
      end
    end
  end

  dp[1], dp[2], dp[3], dp[4], dp[5] = p1, p2, p3, p4, p5
  self.drL, self.drR = drL, drR
  self.dlW, self.dlFL, self.dlFR = dlW, dlFL, dlFR
  self.gbW = gbW
  self.revInL, self.revPL, self.revPR, self.revCL, self.revCR = revInL, revPL, revPR, revCL, revCR
  self.elH, self.erH, self.vlP, self.vrP = elH, erH, vlP, vrP
  self.shW, self.shPh, self.shLp = shW, shPh, shLp
  self.tpW, self.wow, self.flut, self.dly = tpW, wow, flut, dly
  self.toneL, self.toneR, self.hissLp, self.nI = toneL, toneR, hissLp, nI
  self.fade = fade
  self.odd = odd
  self.scI, self.scD = scI, scD
  -- proteção contra NaN
  if pkL ~= pkL or pkR ~= pkR or toneL ~= toneL then
    self:clearBuffers(); pkL, pkR = 0, 0
  end
  self.pkL, self.pkR = pkL, pkR
end

function D:clearBuffers()
  for k = 1, 8 do local b = self.cB[k]; for i = 1, #b do b[i] = 0 end; self.cS[k] = 0 end
  for k = 1, 4 do local b = self.aB[k]; for i = 1, #b do b[i] = 0 end end
  for i = 1, 2048 do self.shB[i] = 0 end
  for i = 1, self.dlN do self.dlL[i] = 0; self.dlR[i] = 0 end
  for i = 1, self.tpN do self.tpL[i] = 0; self.tpR[i] = 0 end
  self.shLp, self.dlFL, self.dlFR, self.toneL, self.toneR, self.drL, self.drR = 0, 0, 0, 0, 0, 0, 0
  self.revInL, self.revPL, self.revPR, self.revCL, self.revCR = 0, 0, 0, 0, 0
end

-- estado para a tela (tabela plana)
function D:snapshot(due)
  local t = { due = due, ang = self.ringAng, n = self.p.balls, pl = self.pkL, pr = self.pkR }
  for i = 1, self.p.balls do
    local b = self.balls[i]
    t[#t + 1] = b.x; t[#t + 1] = b.y; t[#t + 1] = b.vx; t[#t + 1] = b.vy
  end
  t.sc0 = #t
  local sc, si = self.scope, self.scI
  for k = 0, 95 do t[#t + 1] = sc[(si - 1 + k) % 96 + 1] end
  return t
end

return D
