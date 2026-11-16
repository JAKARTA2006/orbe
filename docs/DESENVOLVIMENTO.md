# Desenvolvimento

## Rodar no PC

Instale o [LÖVE 11.5](https://love2d.org) e rode:

```bash
love ports/orbe/app
```

| Tecla | Botão do console |
|---|---|
| Setas | direcional |
| `Z` / `X` / `C` / `V` | A / B / X / Y |
| `A` / `S` | L1 / R1 (tônica) |
| `Q` / `W` | L3 / R3 (escala) |
| `Enter` | START |
| `Shift direito` | SELECT |
| `Esc` | sair |

### Variáveis de ambiente

| Variável | Uso |
|---|---|
| `ORBE_CFG` | caminho do arquivo de configuração (padrão: `config.txt` na pasta atual) |
| `ORBE_FPS` | limite de quadros por segundo (padrão: 30) |
| `ORBE_SHOT` / `ORBE_SHOT_FRAMES` | salva uma captura de tela PNG depois de N quadros e fecha o app (útil para gerar imagens) |

Exemplo para gerar a captura da documentação num servidor sem tela:

```bash
ORBE_SHOT=docs/img/tela.png ORBE_SHOT_FRAMES=300 ALSOFT_DRIVERS=null \
  xvfb-run -s "-screen 0 640x480x24" love ports/orbe/app
```

## Ferramentas (sem LÖVE, só LuaJIT)

O `dsp.lua` não depende do LÖVE, então dá para testar o motor direto com `luajit`:

```bash
# renderiza 60 s em WAV (SR opcional: 22050, 16000, 11025)
SR=16000 luajit tools/render.lua ports/orbe/app saida.wav 60

# mesma coisa, passando pelos 4 presets principais
luajit tools/render.lua ports/orbe/app tour.wav 80 tour

# teste de estresse (todas as combinações, parâmetros no máximo)
luajit tools/stress.lua ports/orbe/app
luajit -joff tools/stress.lua ports/orbe/app     # sem JIT, como pode rodar no R36S

# carga de CPU de cada camada
luajit -joff tools/perf.lua ports/orbe/app 16000
```

## Como estender

### Novo preset

Em `main.lua`, acrescente uma entrada na tabela `PRESETS`:

```lua
{ name = "NEBLINA", timbre = 4, balls = 2, speed = 0.15, gravity = 0.2, spin = 0.05, octave = 3, decay = 1.0,
  drone = 0.6, grains = 0.8, tape = 0.3, echo = 0.2, space = 0.95, shimmer = 0.5, mode = 2, root = 5 },
```

Os campos são os mesmos parâmetros do painel. Os valores vão de 0 a 1, exceto `timbre` (1 a 4), `balls` (1 a 8), `octave` (2 a 5), `mode` (índice em `D.MODES`) e `root` (0 = C … 11 = B).

### Nova escala

Em `dsp.lua`, acrescente na tabela `D.MODES` os intervalos em semitons a partir da tônica:

```lua
{ name = "ARABE", iv = { 0, 1, 4, 5, 7, 8, 11 } },
```

O anel se redesenha sozinho com `2 × #iv` segmentos.

### Novo timbre

Em `dsp.lua`, acrescente o nome em `D.TIMBRES` e a definição FM correspondente em `TIMBRE`:

```lua
{ ratio = 1.41, idx = 1.8, idec = 0.6, att = 0.01 },  -- razão, índice, queda do índice (s), ataque (s)
```

Razões inteiras (1, 2, 3…) soam harmônicas, e as não inteiras (1,41; 3,5…) soam metálicas ou de sino.

## Formato do `config.txt`

Texto simples, uma linha `chave=valor` por parâmetro. É gravado ao sair e a cada ~8 s depois de alguma mudança:

```
preset=1.0000
root=2.0000
mode=6.0000
timbre=1.0000
balls=3.0000
...
```

## Comunicação entre threads

| Canal | Direção | Mensagens |
|---|---|---|
| `cmd` | interface → áudio | `{type="params", ...}` com todos os parâmetros, `{type="shake"}`, `{type="quit"}` |
| `state` | áudio → interface | instantâneo com `due`, ângulo do anel, `x, y, vx, vy` de cada bola, picos L/R e 96 pontos do osciloscópio (a partir de `sc0`) |
| `hitsCh` | áudio → interface | `{a, seg, nseg, vel, ball, due}` para cada batida |
| `info` | áudio → interface | `{kind="calib"}` durante a calibração; `{kind="load", load, sr, lite, jit}` a cada ~1 s |
