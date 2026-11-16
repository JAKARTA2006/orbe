# Histórico de versões

## 1.0.0 — 2026-11-16

Primeira versão pública.

- Anel generativo com 1 a 8 bolas, física com gravidade e inclinação pelo analógico.
- 4 timbres FM (SINO, VIDRO, CORDA, SOPRO), 7 escalas e 12 tônicas.
- Texturas: drone, grãos, eco *ping-pong*, reverb com *shimmer* e emulação de fita.
- 6 presets e gerador de cenas aleatórias.
- Áudio numa thread própria, sincronizado com a imagem.
- Calibração automática (JIT, taxa de amostragem, modo leve) e modo leve automático por carga.
- Tela limitada a 30 fps e `LP_NUM_THREADS=1` para não disputar CPU com o áudio.
- Configurações salvas em `config.txt`.

### Antes da 1.0 (desenvolvimento)

- **DRONE FITA**: protótipo com camadas fixas (drone, brilho, fita, vento, espaço). Picotava porque o áudio era gerado no mesmo laço da tela.
- **ORBE v1**: primeira versão com anel e thread de áudio. No R36S chegava a 193% de CPU, porque o motor usava arrays FFI, que são lentos sem JIT.
- **ORBE v2**: motor reescrito com tabelas Lua e processamento em meia taxa (2 a 3 vezes mais leve), mais a calibração automática. Também corrige uma queda do áudio com notas agudas no timbre VIDRO.
