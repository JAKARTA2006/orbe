#!/bin/bash
# ORBE - bolas quicando num anel + texturas (LÖVE) para R36S
# Usa o motor LÖVE 11.5 que já vem no port do Balatro.

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/orbe"
LOVEDIR="/$directory/ports/balatro"

cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

mkdir -p "$GAMEDIR/saves"
export XDG_DATA_HOME="$GAMEDIR/saves"
export XDG_CONFIG_HOME="$GAMEDIR/saves"
export ORBE_CFG="$GAMEDIR/config.txt"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"
# deixa núcleos livres para a thread de áudio se o vídeo cair em renderização por software
export LP_NUM_THREADS=1

LOVE=""
if [ -f "$LOVEDIR/bin/love.${DEVICE_ARCH}" ]; then
  export LD_LIBRARY_PATH="$LOVEDIR/libs.${DEVICE_ARCH}:$LD_LIBRARY_PATH"
  LOVE="$LOVEDIR/bin/love.${DEVICE_ARCH}"
elif [ -f "$controlfolder/runtimes/love_11.5/love.txt" ]; then
  source "$controlfolder/runtimes/love_11.5/love.txt"
  LOVE="$LOVE_RUN"
elif command -v love >/dev/null 2>&1; then
  LOVE="love"
fi

if [ -z "$LOVE" ]; then
  echo "LOVE 11.5 nao encontrado (precisa do port Balatro ou do runtime love_11.5 do PortMaster)."
  exit 1
fi

echo "Usando LOVE: $LOVE"
pm_platform_helper "$LOVE" 2>/dev/null
"$LOVE" "$GAMEDIR/app"

type pm_finish >/dev/null 2>&1 && pm_finish
$ESUDO systemctl restart oga_events &
printf "\033c" > /dev/tty0
