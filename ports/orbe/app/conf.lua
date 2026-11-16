function love.conf(t)
  t.identity = "orbe"
  t.version = "11.5"
  t.console = false
  t.window.title = "ORBE"
  t.window.width = 640
  t.window.height = 480
  t.window.resizable = false
  t.window.vsync = 1
  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
  t.audio.mic = false
end
