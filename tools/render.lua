-- render.lua: renderiza o motor do ORBE em WAV sem o LÖVE
-- uso: [SR=16000] luajit tools/render.lua ports/orbe/app saida.wav <segundos> [tour]
package.path = arg[1] .. "/?.lua;" .. package.path
local ffi = require("ffi")
local D = require("dsp")
local out, secs = arg[2], tonumber(arg[3] or 30)
local sr = tonumber(os.getenv("SR") or 22050)
math.randomseed(7)
local e = D.new(sr)
local n = 512
local L, R = ffi.new("double[?]", n), ffi.new("double[?]", n)
local total = math.floor(secs * sr / n)
local pcm = ffi.new("int16_t[?]", total * n * 2)
local hits = 0
local t0 = os.clock()
local tr = 0
for b = 0, total - 1 do
  local t = b * n / sr
  if arg[4] == "tour" then
    if t > 20 and t < 20.1 then e:setParams({ timbre = 3, mode = 3, root = 2, octave = 3, drone = 0.5, gravity = 0.3, tape = 0.4, balls = 2 }) end
    if t > 40 and t < 40.1 then e:setParams({ timbre = 4, mode = 1, root = 9, balls = 4, speed = 0.3, echo = 0.5, space = 0.8, shimmer = 0.3, gravity = 0 }) end
    if t > 60 and t < 60.1 then e:setParams({ timbre = 2, mode = 4, root = 4, balls = 5, speed = 0.7, spin = 0.5, shimmer = 0.75, octave = 5, drone = 0.15 }) end
  end
  local c0 = os.clock()
  e:render(n, L, R)
  tr = tr + (os.clock() - c0)
  hits = hits + #e.hits; e.hits = {}
  for i = 0, n - 1 do
    pcm[(b * n + i) * 2] = math.floor(L[i] * 32000)
    pcm[(b * n + i) * 2 + 1] = math.floor(R[i] * 32000)
  end
end
local bytes = total * n * 4
local function u32(x) return string.char(x % 256, math.floor(x / 256) % 256, math.floor(x / 65536) % 256, math.floor(x / 16777216) % 256) end
local function u16(x) return string.char(x % 256, math.floor(x / 256) % 256) end
local f = io.open(out, "wb")
f:write("RIFF", u32(36 + bytes), "WAVE", "fmt ", u32(16), u16(1), u16(2), u32(sr), u32(sr * 4), u16(4), u16(16), "data", u32(bytes), ffi.string(pcm, bytes))
f:close()
io.stderr:write(string.format("%.0fs áudio, render puro %.2fs -> %.0fx tempo real, %d notas\n", secs, tr, secs / tr, hits))
