#!/bin/bash
set -euo pipefail

# firmware/flash.sh
# Soporta flasheo basado en VID/PID. Busca el dispositivo en /dev y elige
# herramienta adecuada (teensy_loader_cli, avrdude, esptool) y el firmware
# apropiado dentro de $FIRMWARE.
DEV="${1:-}"
USER_FW="${2:-}"
if [ -z "$ROBOT_PATH" ]; then
  echo "ERROR: ROBOT_PATH not set"
  exit 1
fi

FIRMWARE_DIR="${ROBOT_PATH}/firmware/send"

if [ ! -d $FIRMWARE_DIR]; then
  echo "ERROR: directory ${FIRMWARE_DIR} not found"
  exit 1
fi

log() { echo "$(date '+%F %T') $*" ; }

detect_board_type() {
  local dev="$1"
  props=$(udevadm info -q property -n "$dev" 2>/dev/null || true)
  idvendor=$(echo "$props" | awk -F= '/^ID_VENDOR=/ {print tolower($2); exit}')
  idmodel=$(echo "$props" | awk -F= '/^ID_MODEL=/ {print tolower($2); exit}')
  idvid=$(echo "$props" | awk -F= '/^ID_VENDOR_ID=/ {print tolower($2); exit}')
  idpid=$(echo "$props" | awk -F= '/^ID_MODEL_ID=/ {print tolower($2); exit}')

  if [[ "$idpid" == "0483" ]] || [[ "$idvid" == "16c0" ]]; then
    echo "teensy TEENSY40"
    return
  fi
  if [[ "$idmodel" == *"esp"* ]] || [[ "$idvendor" == *"esp"* ]] || [[ "$idvendor" == *"espressif"* ]]; then
    echo "esp32"
    return
  fi
  if [[ "$idvendor" == *"arduino"* ]] || [[ "$idmodel" == *"arduino"* ]] || [[ "$idpid" == "0043" ]] || [[ "$idpid" == "6001" ]]; then
    echo "arduino"
    return
  fi
  # fallback: if .bin present prefer esp32, if .hex prefer avrdude/teensy
  echo "unknown"
}

ensure_teensy() {
  if ! command -v teensy_loader_cli >/dev/null 2>&1; then
    log "teensy_loader_cli no encontrado, instalando..."
    sudo apt update && sudo apt install -y teensy-loader-cli || true
  fi
}

ensure_avrdude() {
  if ! command -v avrdude >/dev/null 2>&1; then
    log "avrdude no encontrado, instalando..."
    sudo apt update && sudo apt install -y avrdude || true
  fi
}

ensure_esptool() {
  if ! command -v esptool.py >/dev/null 2>&1 && ! command -v esptool >/dev/null 2>&1; then
    log "esptool no encontrado, instalando via pip (user)..."
    if command -v pip3 >/dev/null 2>&1; then
      pip3 install --user esptool || true
    else
      sudo apt update && sudo apt install -y python3-pip && pip3 install --user esptool || true
    fi
  fi
}

main() {
  log "Initializing flash script"

  info_brd=$(detect_board_type "$DEV")
  log "Tipo detectado: $info_brd"

  read -r board mmcu <<< "$info_brd"

  firmware_hex=""
  firmware_bin=""

  if [[ -n "$USER_FW" ]]; then

    # Si no existe como ruta directa, buscar dentro de FIRMWARE_DIR
    if [[ ! -f "$USER_FW" ]]; then
      if [[ -f "$FIRMWARE_DIR/$USER_FW" ]]; then
        USER_FW="$FIRMWARE_DIR/$USER_FW"
      else 
        log "ERROR: archivo especificado no existe: $USER_FW"
        return 1
      fi
    fi

    ext="${USER_FW##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

    case "$ext" in
      hex)
        firmware_hex="$USER_FW"
        ;;
      bin)
        firmware_bin="$USER_FW"
        ;;
      *)
        log "ERROR: extensión no soportada. Use .hex o .bin"
        return 1
        ;;
    esac

  else
    firmware_hex=$(find "$FIRMWARE_DIR" -type f -name "*.hex" -printf "%T@ %p\n" 2>/dev/null \
      | sort -nr | head -n 1 | cut -d' ' -f2-)

    firmware_bin=$(find "$FIRMWARE_DIR" -type f -name "*.bin" -printf "%T@ %p\n" 2>/dev/null \
      | sort -nr | head -n 1 | cut -d' ' -f2-)
  fi

  log "Firmware seleccionado:"
  [[ -n "$firmware_hex" ]] && log "HEX: $firmware_hex"
  [[ -n "$firmware_bin" ]] && log "BIN: $firmware_bin"
  
  case "$board" in
    teensy)
      if [ -z "$info_brd" ]; then
        log "ERROR: no mmcu version detected"
        return 1
      fi

      if [ -z "$firmware_hex" ]; then
        log "ERROR: no se encontró archivo .hex en $FIRMWARE_DIR para Teensy"
        return 1
      fi
      log "Flasheando $firmware_hex en $DEV"
      teensy_loader_cli -s -mmcu="$mmcu" -wv "$firmware_hex" 
      ;;
    esp32)
      # ensure_esptool
      if [ -z "$firmware_bin" ]; then
        log "ERROR: no se encontró archivo .bin en $FIRMWARE_DIR para ESP32"
        return 1
      fi
      # esptool puede estar en ~/.local/bin
      ESPL=$(command -v esptool.py || command -v esptool || echo "")
      if [ -z "$ESPL" ]; then
        log "ERROR: esptool no está disponible"
        return 1
      fi
      log "Flasheando ESP32 en puerto $DEV con $firmware_bin"
      # Intentar comando común
      "$ESPL" --chip esp32c3 --port "$DEV" erase_flash
      "$ESPL" --chip esp32c3 --port "$DEV" --baud 460800 write_flash -z 0x0 "$firmware_bin"
      ;;
    arduino)
      # ensure_avrdude
      if [ -z "$firmware_hex" ]; then
        log "ERROR: no se encontró archivo .hex en $FIRMWARE_DIR para Arduino"
        return 1
      fi
      # Intentar flasheo con avrdude (asumiendo bootloader Arduino UNO/328p)
      log "Flasheando Arduino en $DEV con $firmware_hex"
      avrdude -v -patmega328p -carduino -P"$DEV" -b115200 -D -Uflash:w:"$firmware_hex":i || {
        log "avrdude falló, inténtelo manualmente o especifique el MCU/programmer correcto"
        return 1
      }
      ;;
    *)
      log "Unknown device"
      ;;
  esac

  log "Finishing flash"
}

main