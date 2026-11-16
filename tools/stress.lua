-- stress.lua: testa todas as combinações com parâmetros no máximo
-- uso: luajit [-joff] tools/stress.lua ports/orbe/app
package.path = arg[1] .. "/?.lua;" .. package.path
local D = require("dsp")
for _, sr in ipairs({11025, 16000, 22050}) do
  local e = D.new(sr); local L, R = {}, {}
  for tb = 1, 4 do for oct = 2, 5 do for mode = 1, 7 do
    e:setParams({ timbre = tb, octave = oct, mode = mode, root = (tb * 5 + oct) % 12, balls = 8, speed = 1, gravity = 1, spin = 1, decay = 1, drone = 1, grains = 1, tape = 1, echo = 1, space = 1, shimmer = 1, volume = 1, tiltX = 1, tiltY = -1 })
    for _ = 1, 6 do e:render(512, L, R) end
    for i = 0, 511 do assert(L[i] == L[i] and math.abs(L[i]) <= 1.0001, "valor ruim") end
  end end end
  e.lite = true; for _ = 1, 50 do e:render(512, L, R) end
  e:setParams({ running = false }); for _ = 1, 50 do e:render(512, L, R) end
  print("stress ok", sr)
end
