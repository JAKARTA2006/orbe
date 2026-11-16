-- perf.lua: mede a carga de CPU de cada camada do motor
-- uso: luajit [-joff] tools/perf.lua ports/orbe/app [taxa]
package.path = arg[1] .. "/?.lua;" .. package.path
local D = require("dsp")
local sr = tonumber(arg[2] or 22050)
local function run(label, params, lite)
  math.randomseed(7)
  local e = D.new(sr); e.lite = lite or false
  e:setParams(params or {})
  local L, R = {}, {}
  local n = 512
  for b = 1, 40 do e:render(n, L, R) end  -- aquece
  local nb = math.floor(4 * sr / n)
  local dt = 1e9
  for rep = 1, 4 do
    local t0 = os.clock()
    for b = 1, nb do e:render(n, L, R) end
    dt = math.min(dt, (os.clock() - t0) * 2.5)
  end
  print(string.format("%-28s %5.1fx tempo real  (carga %.1f%%)", label, 10 / dt, dt / 10 * 100))
end
run("completo", {})
run("sem drone", { drone = 0 })
run("sem graos", { grains = 0 })
run("sem fita", { tape = 0 })
run("sem shimmer", { shimmer = 0 })
run("sem eco", { echo = 0 })
run("sem bolas/notas", { balls = 1, speed = 0 })
run("lite", {}, true)
run("tudo minimo", { drone = 0, grains = 0, tape = 0, shimmer = 0, echo = 0 })
