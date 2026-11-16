-- ORBE — sintetizador generativo de bolas quicando + texturas (inspirado no ORBIX)
-- LÖVE 11.x para R36S. O áudio roda em thread própria (audio.lua).

local D = require("dsp")

local W, H = 640, 480
local CX, CY, RR = 215, 262, 188
local lg = love.graphics

local P = D.defaults()
P.preset = 1
local cmd, state, hitsCh, info, thread
local cpu = 0
local audioInfo
local calibrating = true
local snaps = {}
local cur                       -- snapshot exibido
local hitsQ = {}
local ripples = {}
local segGlow, glowN = {}, 0
local trails = {}
local sel = 1
local held = {}
local rep = 0
local showHelp = false
local toast, toastT = nil, 0
local fonts = {}
local dirty, sendDirty, saveT = false, true, 0
local cfgPath = os.getenv("ORBE_CFG") or "config.txt"
local trig = { triggerleft = false, triggerright = false }
local combo = false
local errMsg
local bg
local t = 0
local shotFrames = os.getenv("ORBE_SHOT") and tonumber(os.getenv("ORBE_SHOT_FRAMES") or "240") or nil

-- ===== presets (variações) =====
local PRESETS = {
  { name = "ORBIX",        timbre = 1, balls = 3, speed = 0.45, gravity = 0.0, spin = 0.25, octave = 4, decay = 0.55,
    drone = 0.25, grains = 0.35, tape = 0.20, echo = 0.35, space = 0.65, shimmer = 0.45, mode = 6, root = 2 },
  { name = "DUNA",         timbre = 3, balls = 2, speed = 0.35, gravity = 0.35, spin = 0.10, octave = 3, decay = 0.50,
    drone = 0.55, grains = 0.50, tape = 0.35, echo = 0.25, space = 0.75, shimmer = 0.20, mode = 3, root = 2 },
  { name = "BLADE RUNNER", timbre = 4, balls = 4, speed = 0.25, gravity = 0.0, spin = 0.15, octave = 4, decay = 0.80,
    drone = 0.45, grains = 0.40, tape = 0.45, echo = 0.55, space = 0.80, shimmer = 0.30, mode = 1, root = 9 },
  { name = "CRISTAL",      timbre = 2, balls = 5, speed = 0.70, gravity = 0.0, spin = 0.50, octave = 5, decay = 0.45,
    drone = 0.15, grains = 0.30, tape = 0.10, echo = 0.40, space = 0.85, shimmer = 0.75, mode = 4, root = 4 },
  { name = "FITA VELHA",   timbre = 1, balls = 3, speed = 0.35, gravity = 0.15, spin = 0.20, octave = 4, decay = 0.60,
    drone = 0.35, grains = 0.60, tape = 0.85, echo = 0.40, space = 0.60, shimmer = 0.25, mode = 6, root = 7 },
  { name = "OCEANO",       timbre = 4, balls = 6, speed = 0.20, gravity = 0.55, spin = 0.05, octave = 3, decay = 0.90,
    drone = 0.30, grains = 0.70, tape = 0.25, echo = 0.30, space = 0.90, shimmer = 0.40, mode = 7, root = 0 },
}

-- ===== linhas de parâmetros =====
local ROWS = {
  { key = "timbre",  name = "TIMBRE",     kind = "enum", list = D.TIMBRES },
  { key = "balls",   name = "BOLAS",      kind = "int", min = 1, max = 8 },
  { key = "speed",   name = "VELOCIDADE" },
  { key = "gravity", name = "GRAVIDADE" },
  { key = "spin",    name = "GIRO" },
  { key = "octave",  name = "OITAVA",     kind = "int", min = 2, max = 5 },
  { key = "decay",   name = "DECAY" },
  { key = "drone",   name = "DRONE" },
  { key = "grains",  name = "GRAOS" },
  { key = "tape",    name = "FITA" },
  { key = "echo",    name = "ECO" },
  { key = "space",   name = "ESPACO" },
  { key = "shimmer", name = "SHIMMER" },
  { key = "volume",  name = "VOLUME" },
}

local C = {
  amber = { 1.0, 0.66, 0.25 }, teal = { 0.30, 0.88, 0.85 }, magenta = { 0.95, 0.38, 0.68 },
  dim = { 0.46, 0.48, 0.60 }, white = { 0.92, 0.92, 0.96 }, panel = { 0.07, 0.08, 0.13 },
}
local function setc(c, a) lg.setColor(c[1], c[2], c[3], a or 1) end
local function say(s) toast, toastT = s, 2.2 end
local function clamp(x, a, b) return x < a and a or (x > b and b or x) end

-- cor de cada grau da escala (gradiente âmbar -> magenta -> ciano)
local function segColor(k, n)
  local u = (k % (n / 2)) / math.max(1, n / 2 - 1)
  local hi = k >= n / 2
  local r = 1.0 - u * 0.65
  local g = 0.60 - u * 0.15 + u * u * 0.4
  local b = 0.25 + u * 0.65
  if hi then r, g, b = r * 0.75 + 0.2, g * 0.9 + 0.1, b * 0.9 + 0.1 end
  return r, g, b
end

-- ===== config =====
local function saveCfg()
  local f = io.open(cfgPath, "w")
  if not f then return end
  for k, v in pairs(P) do
    if type(v) == "number" then f:write(k, "=", string.format("%.4f", v), "\n")
    elseif type(v) == "boolean" and k ~= "running" and k ~= "freeze" then f:write(k, "=", tostring(v), "\n") end
  end
  f:close()
  dirty = false
end

local function loadCfg()
  local f = io.open(cfgPath, "r")
  if not f then return end
  for line in f:lines() do
    local k, v = line:match("^(%w+)=(.+)$")
    if k and P[k] ~= nil and type(P[k]) == "number" then
      local n = tonumber(v)
      if n then P[k] = n end
    end
  end
  f:close()
  P.tiltX, P.tiltY = 0, 0
  for _, r in ipairs(ROWS) do
    if r.kind == "int" then P[r.key] = clamp(math.floor(P[r.key] + 0.5), r.min, r.max)
    elseif r.kind == "enum" then P[r.key] = clamp(math.floor(P[r.key] + 0.5), 1, #r.list)
    else P[r.key] = clamp(P[r.key], 0, 1) end
  end
  P.root = math.floor(P.root) % 12
  P.mode = clamp(math.floor(P.mode), 1, #D.MODES)
  P.preset = clamp(math.floor(P.preset or 1), 1, #PRESETS)
end

local function touch() dirty = true; sendDirty = true end

local function applyPreset(i)
  P.preset = i
  for k, v in pairs(PRESETS[i]) do if k ~= "name" then P[k] = v end end
  touch()
  say("PRESET: " .. PRESETS[i].name)
end

local function newScene()
  P.timbre = math.random(1, #D.TIMBRES)
  P.balls = math.random(2, 6)
  P.speed = 0.15 + math.random() * 0.6
  P.gravity = math.random() < 0.5 and 0 or math.random() * 0.6
  P.spin = math.random() * 0.5
  P.octave = math.random(3, 5)
  P.decay = 0.3 + math.random() * 0.6
  P.drone = math.random() * 0.55
  P.grains = 0.15 + math.random() * 0.6
  P.tape = math.random() * 0.6
  P.echo = 0.15 + math.random() * 0.5
  P.space = 0.5 + math.random() * 0.45
  P.shimmer = math.random() * 0.75
  if math.random() < 0.5 then P.mode = math.random(1, #D.MODES) end
  touch()
  say("NOVA CENA: " .. D.TIMBRES[P.timbre] .. " / " .. D.MODES[P.mode].name)
end

-- ===== LÖVE =====
function love.load()
  love.mouse.setVisible(false)
  math.randomseed(os.time())
  loadCfg()
  fonts.s = lg.newFont(11)
  fonts.m = lg.newFont(13)
  fonts.b = lg.newFont(22)
  fonts.h = lg.newFont(34)
  fonts.key = lg.newFont(120)

  cmd = love.thread.newChannel()
  state = love.thread.newChannel()
  hitsCh = love.thread.newChannel()
  info = love.thread.newChannel()
  thread = love.thread.newThread("audio.lua")
  thread:start(cmd, state, hitsCh, info)

  for i = 1, 8 do trails[i] = {} end
  say("ORBE  -  SELECT = ajuda")
end

local function sendParams()
  local m = { type = "params" }
  for k, v in pairs(P) do if type(v) ~= "string" then m[k] = v end end
  cmd:push(m)
  sendDirty = false
end

local function adjustRow(dir, fine)
  local r = ROWS[sel]
  if r.kind == "enum" then
    P[r.key] = (P[r.key] - 1 + dir) % #r.list + 1
    say(r.name .. ": " .. r.list[P[r.key]])
  elseif r.kind == "int" then
    P[r.key] = clamp(P[r.key] + dir, r.min, r.max)
  else
    P[r.key] = clamp(P[r.key] + dir * (fine or 0.02), 0, 1)
  end
  touch()
end

local function changeRoot(d) P.root = (P.root + d) % 12; touch(); say("TONICA: " .. D.NOTES[P.root + 1]) end
local function changeMode(d) P.mode = (P.mode - 1 + d) % #D.MODES + 1; touch(); say("MODO: " .. D.MODES[P.mode].name) end

local function quit()
  saveCfg()
  if cmd then cmd:push({ type = "quit" }) end
  if thread then thread:wait() end
  love.event.quit()
end

local function press(b)
  if b == "back" then held.back = true; combo = false; return end
  if b == "start" and held.back then combo = true; quit(); return end
  if showHelp then showHelp = false; return end
  if b == "dpup" then sel = (sel - 2) % #ROWS + 1; held.up = true; rep = 0.35
  elseif b == "dpdown" then sel = sel % #ROWS + 1; held.down = true; rep = 0.35
  elseif b == "dpleft" then adjustRow(-1); held.left = true; rep = 0.35
  elseif b == "dpright" then adjustRow(1); held.right = true; rep = 0.35
  elseif b == "a" then cmd:push({ type = "shake" }); say("CHACOALHAR")
  elseif b == "b" then newScene()
  elseif b == "x" then P.freeze = not P.freeze; sendDirty = true; say(P.freeze and "GRAOS CONGELADOS" or "GRAOS LIVRES")
  elseif b == "y" then applyPreset(P.preset % #PRESETS + 1)
  elseif b == "leftshoulder" then changeRoot(-1)
  elseif b == "rightshoulder" then changeRoot(1)
  elseif b == "leftstick" then changeMode(-1)
  elseif b == "rightstick" then changeMode(1)
  elseif b == "start" then P.running = not P.running; sendDirty = true; say(P.running and "TOCANDO" or "PAUSA")
  elseif b == "guide" then quit()
  end
end

local function release(b)
  if b == "back" then
    held.back = false
    if not combo then showHelp = not showHelp end
    combo = false
  elseif b == "dpup" then held.up = false
  elseif b == "dpdown" then held.down = false
  elseif b == "dpleft" then held.left = false
  elseif b == "dpright" then held.right = false
  end
end

function love.gamepadpressed(_, b) press(b) end
function love.gamepadreleased(_, b) release(b) end
function love.gamepadaxis(_, axis, v)
  if trig[axis] ~= nil then
    local on = v > 0.5
    if on and not trig[axis] then changeMode(axis == "triggerleft" and -1 or 1) end
    trig[axis] = on
  end
end

local keymap = {
  up = "dpup", down = "dpdown", left = "dpleft", right = "dpright", z = "a", x = "b", c = "x", v = "y",
  a = "leftshoulder", s = "rightshoulder", q = "leftstick", w = "rightstick",
  ["return"] = "start", rshift = "back", escape = "guide",
}
function love.keypressed(k) if keymap[k] then press(keymap[k]) end end
function love.keyreleased(k) if keymap[k] then release(keymap[k]) end end

local frameStart = 0
local FPS = tonumber(os.getenv("ORBE_FPS") or "30")
local fpsShow, fpsAcc, fpsN = 0, 0, 0

function love.update(dt)
  t = t + dt
  fpsAcc, fpsN = fpsAcc + dt, fpsN + 1
  if fpsAcc >= 1 then fpsShow = fpsN / fpsAcc; fpsAcc, fpsN = 0, 0 end
  local err = thread and thread:getError()
  if err and not errMsg then errMsg = err; print("ERRO AUDIO: " .. err) end

  -- repetição do direcional
  if held.up or held.down or held.left or held.right then
    rep = rep - dt
    if rep <= 0 then
      rep = 0.06
      if held.up then sel = (sel - 2) % #ROWS + 1
      elseif held.down then sel = sel % #ROWS + 1
      elseif held.left then adjustRow(-1)
      elseif held.right then adjustRow(1) end
    end
  end

  -- analógicos: esquerdo inclina a gravidade, direito ajusta o parâmetro
  local tx, ty = 0, 0
  for _, js in ipairs(love.joystick.getJoysticks()) do
    if js:isGamepad() then
      local lx, ly = js:getGamepadAxis("leftx"), js:getGamepadAxis("lefty")
      if math.abs(lx) > 0.2 then tx = lx end
      if math.abs(ly) > 0.2 then ty = ly end
      local rx = js:getGamepadAxis("rightx")
      if math.abs(rx) > 0.25 and ROWS[sel].kind == nil then adjustRow(rx > 0 and 1 or -1, math.abs(rx) * dt * 0.6) end
    end
  end
  if math.abs(tx - P.tiltX) > 0.02 or math.abs(ty - P.tiltY) > 0.02 then
    P.tiltX, P.tiltY = tx, ty; sendDirty = true
  end

  if sendDirty then sendParams() end
  if dirty then saveT = saveT + dt; if saveT > 8 then saveT = 0; saveCfg() end end

  -- estado vindo da thread (alinhado com o som)
  local now = love.timer.getTime()
  local s = state:pop()
  while s do snaps[#snaps + 1] = s; s = state:pop() end
  while #snaps > 0 and snaps[1].due <= now do cur = table.remove(snaps, 1) end
  if #snaps > 12 then cur = table.remove(snaps, 1) end
  local h = hitsCh:pop()
  while h do hitsQ[#hitsQ + 1] = h; h = hitsCh:pop() end
  while #hitsQ > 0 and hitsQ[1].due <= now do
    local hh = table.remove(hitsQ, 1)
    if hh.nseg ~= glowN then glowN = hh.nseg; segGlow = {} end
    segGlow[hh.seg] = 1
    ripples[#ripples + 1] = { a = hh.a, r = 0, life = 1, v = hh.vel, seg = hh.seg, n = hh.nseg }
  end
  if #hitsQ > 40 then hitsQ = {} end
  local c = info:pop()
  while c do
    if type(c) == "table" then
      if c.kind == "load" then cpu = c.load; audioInfo = c; calibrating = false
      elseif c.kind == "calib" then calibrating = true end
    end
    c = info:pop()
  end

  for k, g in pairs(segGlow) do segGlow[k] = g - dt * 0.9; if segGlow[k] <= 0 then segGlow[k] = nil end end
  for i = #ripples, 1, -1 do
    local r = ripples[i]
    r.life = r.life - dt * 0.7
    r.r = r.r + dt * 60
    if r.life <= 0 then table.remove(ripples, i) end
  end
  if toastT > 0 then toastT = toastT - dt end
end

-- ===== desenho =====
local function buildBg()
  local ok = pcall(function()
    bg = lg.newCanvas(W, H)
    lg.setCanvas(bg)
    lg.clear(0.02, 0.025, 0.05, 1)
    for i = 0, H, 6 do
      local k = i / H
      lg.setColor(0.03 + 0.05 * k, 0.03 + 0.01 * k, 0.07 + 0.04 * k, 1)
      lg.rectangle("fill", 0, i, W, 6)
    end
    math.randomseed(3)
    for _ = 1, 140 do
      lg.setColor(0.7, 0.75, 1, 0.08 + math.random() * 0.25)
      lg.points(math.random() * W, math.random() * H)
    end
    math.randomseed(os.time())
    -- painel direito
    lg.setColor(C.panel[1], C.panel[2], C.panel[3], 0.85)
    lg.rectangle("fill", 418, 8, 214, H - 36, 10)
    lg.setColor(0, 0, 0, 0.16)
    for y = 0, H, 3 do lg.rectangle("fill", 0, y, W, 1) end
    lg.setCanvas()
  end)
  if not ok then lg.setCanvas(); bg = nil end
end

local function drawRing()
  local ang = cur and cur.ang or 0
  local iv = D.MODES[P.mode].iv
  local n = #iv * 2
  -- anéis internos
  setc(C.dim, 0.10)
  lg.circle("line", CX, CY, RR * 0.66, 64)
  lg.circle("line", CX, CY, RR * 0.33, 48)
  -- tônica no centro
  lg.setFont(fonts.key); setc(C.teal, 0.07)
  lg.printf(D.NOTES[P.root + 1], CX - 150, CY - 72, 300, "center")
  -- segmentos
  local gap = 0.035
  for k = 0, n - 1 do
    local a1 = ang + k / n * 2 * math.pi + gap
    local a2 = ang + (k + 1) / n * 2 * math.pi - gap
    local r, g, b = segColor(k, n)
    local glow = (glowN == n and segGlow[k]) or 0
    lg.setLineWidth(10 + glow * 6)
    lg.setColor(r, g, b, 0.10 + glow * 0.35)
    lg.arc("line", "open", CX, CY, RR + 2, a1, a2, 8)
    lg.setLineWidth(4 + glow * 3)
    lg.setColor(r, g, b, 0.45 + glow * 0.55)
    lg.arc("line", "open", CX, CY, RR, a1, a2, 8)
    -- marca da tônica
    if k % #iv == 0 then
      local am = ang + k / n * 2 * math.pi
      setc(C.white, 0.7)
      lg.setLineWidth(2)
      lg.line(CX + math.cos(am) * (RR - 12), CY + math.sin(am) * (RR - 12), CX + math.cos(am) * (RR - 4), CY + math.sin(am) * (RR - 4))
    end
  end
  lg.setLineWidth(1)

  -- ondas nos pontos de batida
  for _, rp in ipairs(ripples) do
    local x, y = CX + math.cos(rp.a) * RR, CY + math.sin(rp.a) * RR
    local r, g, b = segColor(rp.seg, rp.n)
    lg.setColor(r, g, b, rp.life * 0.8)
    lg.setLineWidth(2)
    lg.circle("line", x, y, 4 + rp.r * (0.5 + rp.v), 24)
    lg.setColor(r, g, b, rp.life * 0.5)
    lg.circle("fill", x, y, 6 * rp.life + 2)
  end
  lg.setLineWidth(1)

  -- bolas (extrapoladas a partir do último estado)
  if cur then
    local dtx = clamp(love.timer.getTime() - cur.due, 0, 0.08)
    for i = 1, cur.n do
      local o = (i - 1) * 4
      local x, y, vx, vy = cur[o + 1], cur[o + 2], cur[o + 3], cur[o + 4]
      if x then
        x, y = x + vx * dtx, y + vy * dtx
        local d = math.sqrt(x * x + y * y)
        if d > 0.955 then x, y = x / d * 0.955, y / d * 0.955 end
        local px, py = CX + x * RR, CY + y * RR
        local tr = trails[i]
        tr[#tr + 1] = px; tr[#tr + 1] = py
        if #tr > 24 then table.remove(tr, 1); table.remove(tr, 1) end
        if #tr >= 4 then
          setc(C.amber, 0.18); lg.setLineWidth(3); lg.line(tr); lg.setLineWidth(1)
        end
        setc(C.amber, 0.18); lg.circle("fill", px, py, 14, 20)
        setc(C.amber, 0.95); lg.circle("fill", px, py, 6, 16)
        setc(C.white, 0.9); lg.circle("fill", px - 1.5, py - 1.5, 2, 8)
      end
    end
    for i = cur.n + 1, 8 do trails[i] = {} end
  end
end

local function drawPanel()
  local x0 = 430
  lg.setFont(fonts.b); setc(C.amber)
  lg.print("ORBE", x0, 14)
  lg.setFont(fonts.s); setc(C.dim)
  lg.print(PRESETS[P.preset] and PRESETS[P.preset].name or "", x0 + 74, 22)

  lg.setFont(fonts.h); setc(C.teal)
  lg.print(D.NOTES[P.root + 1], x0, 42)
  lg.setFont(fonts.m); setc(C.teal, 0.85)
  lg.print(D.MODES[P.mode].name, x0 + 62, 48)
  lg.setFont(fonts.s); setc(P.running and C.amber or C.dim)
  lg.print(P.running and (P.freeze and "TOCANDO  *GRAOS FIXOS" or "TOCANDO") or "PAUSA", x0 + 62, 66)

  -- osciloscópio
  local sx, sy, sw, sh = x0, 88, 190, 34
  lg.setColor(0, 0, 0, 0.4); lg.rectangle("fill", sx, sy, sw, sh, 4)
  if cur and cur.sc0 then
    local pts = {}
    for k = 1, 96 do
      local v = cur[cur.sc0 + k] or 0
      pts[#pts + 1] = sx + (k - 1) / 95 * sw
      pts[#pts + 1] = sy + sh / 2 - clamp(v * sh * 0.9, -sh / 2 + 1, sh / 2 - 1)
    end
    setc(C.amber, 0.9); lg.line(pts)
    local pl, pr = cur.pl or 0, cur.pr or 0
    setc(C.teal, 0.8)
    lg.rectangle("fill", sx + sw + 4, sy + sh - sh * clamp(pl, 0, 1), 4, sh * clamp(pl, 0, 1))
    lg.rectangle("fill", sx + sw + 10, sy + sh - sh * clamp(pr, 0, 1), 4, sh * clamp(pr, 0, 1))
  end

  -- parâmetros
  local y = 130
  local rh = 21.5
  for i, r in ipairs(ROWS) do
    local isSel = (i == sel)
    if isSel then setc(C.amber, 0.14); lg.rectangle("fill", x0 - 6, y - 2, 200, rh, 4) end
    lg.setFont(fonts.s)
    setc(isSel and C.amber or C.white, isSel and 1 or 0.75)
    lg.print(r.name, x0, y + 2)
    local v = P[r.key]
    if r.kind == "enum" then
      setc(C.teal); lg.printf(r.list[v], x0 + 80, y + 2, 110, "right")
    elseif r.kind == "int" then
      setc(C.teal); lg.printf(tostring(math.floor(v)), x0 + 80, y + 2, 110, "right")
      for k = r.min, r.max do
        local on = k <= v
        lg.setColor(C.teal[1], C.teal[2], C.teal[3], on and 0.8 or 0.18)
        lg.rectangle("fill", x0 + 82 + (k - r.min) * 11, y + 6, 8, 6, 2)
      end
    else
      lg.setColor(0.25, 0.26, 0.33, 0.8); lg.rectangle("fill", x0 + 82, y + 6, 108, 6, 3)
      setc(isSel and C.amber or C.teal, 0.9); lg.rectangle("fill", x0 + 82, y + 6, 108 * v, 6, 3)
    end
    y = y + rh
  end
  lg.setFont(fonts.s); setc(C.dim, 0.7)
  if audioInfo then
    local sr = math.floor(audioInfo.sr / 1000 + 0.5)
    lg.print(string.format("cpu audio %d%%  %dk %s%s  %dfps", math.floor(cpu * 100 + 0.5), sr,
      audioInfo.jit or "", audioInfo.lite and " LEVE" or "", math.floor(fpsShow + 0.5)), x0, H - 46)
  else
    lg.print("calibrando audio...", x0, H - 46)
  end
end

local function drawHelp()
  lg.setColor(0, 0, 0, 0.88); lg.rectangle("fill", 30, 30, W - 60, H - 60, 10)
  setc(C.amber); lg.rectangle("line", 30, 30, W - 60, H - 60, 10)
  lg.setFont(fonts.b); lg.printf("AJUDA", 30, 40, W - 60, "center")
  lg.setFont(fonts.m); setc(C.white)
  local L = {
    "CIMA / BAIXO ......... escolher parametro",
    "ESQ / DIR ............ ajustar (ou analogico DIREITO)",
    "ANALOGICO ESQUERDO ... inclina a gravidade do anel",
    "A .................... chacoalhar as bolas",
    "B .................... nova cena (variacao aleatoria)",
    "X .................... congelar / soltar os graos",
    "Y .................... proximo preset",
    "L1 / R1 .............. tonica -/+ (afine com o FM-1)",
    "L2 / R2  (ou L3/R3) .. modo / escala",
    "START ................ tocar / pausar",
    "SELECT + START ....... sair (salva tudo)",
    "",
    "Presets: ORBIX, DUNA, BLADE RUNNER, CRISTAL, FITA VELHA, OCEANO",
  }
  for i, s in ipairs(L) do lg.print(s, 56, 80 + (i - 1) * 25) end
end

function love.draw()
  if bg == nil and bg ~= false then buildBg(); if not bg then bg = false end end
  local sw, sh = lg.getDimensions()
  local s = math.min(sw / W, sh / H)
  lg.push()
  lg.translate((sw - W * s) / 2, (sh - H * s) / 2)
  lg.scale(s)
  if bg then lg.setColor(1, 1, 1, 1); lg.draw(bg, 0, 0) else lg.clear(0.03, 0.03, 0.06) end
  drawRing()
  drawPanel()
  lg.setFont(fonts.s); setc(C.dim, 0.9)
  lg.printf("^v param  <> ajusta  A chacoalha  B cena  X congela  Y preset  L1/R1 tonica  L2/R2 modo  SELECT ajuda",
    4, H - 17, W - 8, "center")
  if toastT > 0 and toast then
    local a = math.min(1, toastT)
    lg.setFont(fonts.m)
    lg.setColor(0, 0, 0, 0.7 * a); lg.rectangle("fill", CX - 140, 24, 280, 24, 6)
    setc(C.amber, a); lg.printf(toast, CX - 140, 29, 280, "center")
  end
  if calibrating and not errMsg then
    lg.setFont(fonts.m); setc(C.amber, 0.6 + 0.4 * math.sin(t * 4))
    lg.printf("CALIBRANDO O AUDIO...", CX - 150, CY + 60, 300, "center")
  end
  if errMsg then
    lg.setColor(0, 0, 0, 0.9); lg.rectangle("fill", 10, 150, W - 20, 180)
    lg.setColor(1, 0.3, 0.3); lg.setFont(fonts.s)
    lg.printf("ERRO NO AUDIO:\n" .. errMsg, 20, 160, W - 40)
  end
  if showHelp then drawHelp() end
  lg.pop()
  -- limita a ~30 quadros/s para sobrar CPU para o áudio
  local elapsed = love.timer.getTime() - frameStart
  local wait = 1 / FPS - elapsed
  if wait > 0 then love.timer.sleep(wait) end
  frameStart = love.timer.getTime()
  if shotFrames then
    shotFrames = shotFrames - 1
    if shotFrames == 0 then
      lg.captureScreenshot(function(img)
        local f = io.open(os.getenv("ORBE_SHOT"), "wb"); f:write(img:encode("png"):getString()); f:close()
        quit()
      end)
    end
  end
end

function love.quit()
  if dirty then saveCfg() end
  if cmd then cmd:push({ type = "quit" }) end
  return false
end
