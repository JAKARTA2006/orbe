# Instalação

## 1. Pré-requisito: LÖVE 11.5

O ORBE é um app [LÖVE](https://love2d.org) e precisa do motor **LÖVE 11.5** compilado para aarch64. O launcher (`ORBE.sh`) procura o motor nesta ordem:

1. **Port do Balatro**: `ports/balatro/bin/love.aarch64` + `ports/balatro/libs.aarch64/`. Se o Balatro já roda no seu console, não precisa fazer mais nada.
2. **Runtime do PortMaster**: `PortMaster/runtimes/love_11.5`. Para ter esse runtime, instale pelo PortMaster qualquer port que use LÖVE 11.5. O PortMaster baixa o runtime junto.
3. **`love` do sistema**, se existir no PATH.

> Se você usa o LÖVE do Balatro, **não apague o port do Balatro**, senão o ORBE para de abrir.

## 2. Copiar os arquivos

Tire o microSD do console e coloque num leitor de cartão no PC. A porta USB/OTG do R36S não funciona como pendrive. Na partição **EASYROMS**, copie:

```
EASYROMS/
└── ports/
    ├── ORBE.sh
    └── orbe/
        └── app/
            ├── audio.lua
            ├── conf.lua
            ├── dsp.lua
            └── main.lua
```

Como o ArkOS usa o sistema de arquivos FAT, não é preciso marcar o `.sh` como executável.

Alternativa sem tirar o cartão: copie os arquivos para um pendrive, ligue o pendrive no OTG do R36S e use o **File Manager** do ArkOS (em Options) para levá-los até `/roms/ports`.

## 3. Primeira execução

1. Abra **Ports → ORBE**. Se ele não aparecer, reinicie o console ou atualize a lista de jogos.
2. Durante alguns segundos aparece **"CALIBRANDO O AUDIO..."**. O app mede a velocidade do seu console e escolhe automaticamente:
   - JIT do LuaJIT **ligado ou desligado**, o que for mais rápido;
   - taxa de amostragem de **22, 16 ou 11 kHz**;
   - **modo leve**, se necessário.
3. O rodapé do painel mostra o resultado, por exemplo:
   ```
   cpu audio 48%  16k sem JIT  30fps
   ```

## Solução de problemas

| Sintoma | O que fazer |
|---|---|
| Não aparece em Ports | Confira se `ORBE.sh` está direto em `ports/` e não dentro de `ports/orbe/`. Reinicie o console. |
| Tela preta, volta ao menu | Abra `ports/orbe/log.txt` no PC. Se aparecer `LOVE 11.5 nao encontrado`, instale o Balatro ou o runtime `love_11.5` (veja o item 1). |
| Som picotando | Veja a linha `cpu audio` no painel. Acima de ~85%, o app entra sozinho no modo leve (aparece `LEVE`). Se continuar picotando, diminua **BOLAS**, **GRAOS** e **SHIMMER**. |
| `ERRO NO AUDIO` na tela | A thread de áudio parou. A mensagem completa também vai para `log.txt`. Abra uma *issue* com esse texto. |
| Mensagens `mali0 is not of a compatible version` no log | São normais em vários ports do ArkOS no R36S. O ORBE limita a tela a 30 fps e usa `LP_NUM_THREADS=1` para não disputar CPU com o áudio. |
| Quero voltar às configurações originais | Apague `ports/orbe/config.txt`. |

## Arquivos gerados no console

| Arquivo | Conteúdo |
|---|---|
| `ports/orbe/config.txt` | último estado (preset, tônica, escala, parâmetros) |
| `ports/orbe/log.txt` | log da última execução |
| `ports/orbe/saves/` | pasta de dados do LÖVE (normalmente vazia) |
