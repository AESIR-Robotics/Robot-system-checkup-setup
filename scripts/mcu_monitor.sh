#!/bin/bash
set -euo pipefail

# mcu_monitor.sh
# Este script es invocado por udev con el nombre del dispositivo (ej: ttyACM0)
# Extrae el ID_VENDOR_ID e ID_MODEL_ID y llama al script de flash con esos valores.

DEV="${1:-}"
ROBOT_PATH="${ROBOT_PATH:-/opt/robot}"
FIRMWARE="${ROBOT_PATH}/firmware"
LOG_DIR="${ROBOT_PATH}/logs"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/mcu_monitor.log"
TRIGGER="${FIRMWARE}/connect.txt"
FLASH_SCRIPT="${FIRMWARE}/flash.sh"

log() {
  echo "$(date '+%F %T') $*" | tee -a "$LOG"
}

if [ -z "$DEV" ]; then
  log "ERROR: no device name recieved"
  exit 1
fi

log "MCU connected: /dev/$DEV"

# Obtener propiedades udev (ID_VENDOR_ID, ID_MODEL_ID, ID_VENDOR, ID_MODEL)
UDEV_PROPS=$(udevadm info -q property -n "/dev/$DEV" 2>/dev/null || true)
log "udev props: $(echo "$UDEV_PROPS" | tr '\n' ' | ')"

VID=$(echo "$UDEV_PROPS" | awk -F= '/^ID_VENDOR_ID=/ {print $2; exit}')
PID=$(echo "$UDEV_PROPS" | awk -F= '/^ID_MODEL_ID=/ {print $2; exit}')

if [ -z "$VID" ] || [ -z "$PID" ]; then
  log "WARN: couldnt get VID/PID from udev; trying to read ID_VENDOR/ID_MODEL"
  VID_RAW=$(echo "$UDEV_PROPS" | awk -F= '/^ID_VENDOR=/ {print $2; exit}')
  PID_RAW=$(echo "$UDEV_PROPS" | awk -F= '/^ID_MODEL=/ {print $2; exit}')
  log "ID_VENDOR=$VID_RAW ID_MODEL=$PID_RAW"
fi

# Si existe el trigger y hay firmware en la carpeta, iniciar flash automático
if [ -f "$TRIGGER" ]; then
  log "Trigger present -> initializing flash attempt"
  if [[ -x "$FLASH_SCRIPT" ]]; then
    # Llamamos al flash script pasando VID y PID (hex, sin 0x)
    if [ -n "$VID" ] && [ -n "$PID" ]; then
      log "Calling flash script with VID=$VID PID=$PID"
      "$FLASH_SCRIPT" "$DEV" "$VID" "$PID"
    fi
  else
    log "No flash script found, or not executable: $FLASH_SCRIPT"
  fi
fi


log "MCU at /dev/$DEV ready"

# Mantener el servicio vivo mientras el dispositivo exista
while [ -e "/dev/$DEV" ]; do
  sleep 2
done

log "MCU at /dev/$DEV disconnected"
