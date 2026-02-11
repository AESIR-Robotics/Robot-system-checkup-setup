#!/bin/bash
set -euo pipefail

# firmware/flash.sh
# Soporta flasheo basado en VID/PID. Busca el dispositivo en /dev y elige
# herramienta adecuada (teensy-loader-cli, avrdude, esptool) y el firmware
# apropiado dentro de $FIRMWARE.
DEV="${1:-}"
VID_ARG="${2:-}"
PID_ARG="${3:-}"
ROBOT_PATH="${ROBOT_PATH:-/opt/robot}"
FIRMWARE_DIR="${FIRMWARE_DIR:-${ROBOT_PATH}/firmware}"
LOG_DIR="${ROBOT_PATH}/logs"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/mcu_flash.log"

log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

detect_board_type() {
  local dev="$1"
  props=$(udevadm info -q property -n "$dev" 2>/dev/null || true)
  idvendor=$(echo "$props" | awk -F= '/^ID_VENDOR=/ {print tolower($2); exit}')
  idmodel=$(echo "$props" | awk -F= '/^ID_MODEL=/ {print tolower($2); exit}')
  idvid=$(echo "$props" | awk -F= '/^ID_VENDOR_ID=/ {print tolower($2); exit}')
  idpid=$(echo "$props" | awk -F= '/^ID_MODEL_ID=/ {print tolower($2); exit}')

  if [[ "$idvendor" == *"teensy"* ]] || [[ "$idvid" == "16c0" ]]; then
    echo "teensy"
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

ensure_teensy_loader() {
  if ! command -v teensy-loader-cli >/dev/null 2>&1; then
    log "teensy-loader-cli no encontrado, intentando instalar (apt)..."
    sudo apt update && sudo apt install -y teensy-loader-cli || true
    if command -v teensy-loader-cli >/dev/null 2>&1; then
      sudo setcap cap_sys_rawio+ep $(which teensy-loader-cli) || true
    fi
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
  log "Flash script iniciado"
  local dev="$DEV"

  if [ -z "$dev" ]; then
    log "ERROR: no se encontró dispositivo para flashear"
    return 1
  fi
  log "Dispositivo detectado: $dev"

  board=$(detect_board_type "$dev")
  log "Tipo detectado: $board"

  # Elegir firmware en carpeta
  firmware_bin=$(ls -t "$FIRMWARE_DIR"/*.bin 2>/dev/null | head -n1 || true)
  firmware_hex=$(ls -t "$FIRMWARE_DIR"/*.hex 2>/dev/null | head -n1 || true)

  case "$board" in
    teensy)
      ensure_teensy_loader
      if [ -z "$firmware_hex" ]; then
        log "ERROR: no se encontró archivo .hex en $FIRMWARE_DIR para Teensy"
        return 1
      fi
      log "Reseteando Teensy (si aplica)"
      teensy-loader-cli -b || true
      sleep 1
      log "Flasheando $firmware_hex en $dev"
      teensy-loader-cli -mmcu=auto -w "$firmware_hex" || {
        log "teensy-loader-cli falló, intentando sin -mmcu"
        teensy-loader-cli -w "$firmware_hex"
      }
      ;;
    esp32)
      ensure_esptool
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
      log "Flasheando ESP32 en puerto $dev con $firmware_bin"
      # Intentar comando común
      "$ESPL" --chip auto --port "$dev" --baud 460800 write_flash -z 0x1000 "$firmware_bin"
      ;;
    arduino)
      ensure_avrdude
      if [ -z "$firmware_hex" ]; then
        log "ERROR: no se encontró archivo .hex en $FIRMWARE_DIR para Arduino"
        return 1
      fi
      # Intentar flasheo con avrdude (asumiendo bootloader Arduino UNO/328p)
      log "Flasheando Arduino en $dev con $firmware_hex"
      avrdude -v -patmega328p -carduino -P"$dev" -b115200 -D -Uflash:w:"$firmware_hex":i || {
        log "avrdude falló, inténtelo manualmente o especifique el MCU/programmer correcto"
        return 1
      }
      ;;
    *)
      log "Tipo desconocido, aplicando heurística: preferir .bin->ESP, .hex->teensy/avr"
      if [ -n "$firmware_bin" ]; then
        ensure_esptool
        ESPL=$(command -v esptool.py || command -v esptool || echo "")
        if [ -n "$ESPL" ]; then
          log "Usando esptool para flashear $firmware_bin"
          "$ESPL" --chip auto --port "$dev" --baud 460800 write_flash -z 0x1000 "$firmware_bin"
        else
          log "esptool no disponible"
          return 1
        fi
      elif [ -n "$firmware_hex" ]; then
        # try teensy first
        ensure_teensy_loader
        if command -v teensy-loader-cli >/dev/null 2>&1; then
          teensy-loader-cli -b || true
          sleep 1
          teensy-loader-cli -mmcu=auto -w "$firmware_hex" || teensy-loader-cli -w "$firmware_hex"
        else
          ensure_avrdude
          avrdude -v -patmega328p -carduino -P"$dev" -b115200 -D -Uflash:w:"$firmware_hex":i || true
        fi
      else
        log "No se encontraron binarios/hex para flashear en $FIRMWARE_DIR"
        return 1
      fi
      ;;
  esac

  log "Flasheo finalizado"
}

main