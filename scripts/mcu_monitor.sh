#!/bin/bash
set -euo pipefail

# mcu_monitor.sh
# Invocado por udev con el nombre del dispositivo (ej: ttyACM0)

DEV="${1:-}"
ROBOT_PATH="${ROBOT_PATH:-/opt/robot}"
FIRMWARE="${ROBOT_PATH}/firmware"
LOG_DIR="${ROBOT_PATH}/logs"
LOG="${LOG_DIR}/mcu_monitor.log"
TRIGGER="${FIRMWARE}/connect.txt"
FLASH_SCRIPT="${FIRMWARE}/flash.sh"

if [ -z "$DEV" ]; then
  echo "ERROR: no device name received"
  exit 1
fi

if [ -z "$ROBOT_PATH" ] || [ ! -d "$ROBOT_PATH" ]; then
  echo "ERROR: invalid ROBOT_PATH: $ROBOT_PATH"
  exit 1
fi

mkdir -p "$LOG_DIR"

log() {
  echo "$(date '+%F %T') [$$] $*" | tee -a "$LOG"
}

DEVICE_PATH="/dev/$DEV"

if [ ! -e "$DEVICE_PATH" ]; then
  log "ERROR: device $DEVICE_PATH does not exist"
  exit 1
fi

log "MCU connected: $DEVICE_PATH"

# Get udev properties

if UDEV_PROPS=$(udevadm info -q property -n "$DEVICE_PATH" 2>/dev/null); then
  log "udev props: $(echo "$UDEV_PROPS" | tr '\n' ' | ')"
else
  log "WARN: could not retrieve udev properties"
fi

# Flash

if [ -f "$TRIGGER" ]; then
  log "Trigger detected -> attempting flash"

  if [ -x "$FLASH_SCRIPT" ]; then
    if "$FLASH_SCRIPT" "$DEV"; then
      log "Flash completed successfully"
    else
      log "Flash script failed"
    fi
  else
    log "Flash script missing or not executable: $FLASH_SCRIPT"
  fi
fi

log "MCU ready: $DEVICE_PATH"

# Keep service alive
trap 'log "MCU disconnected: $DEVICE_PATH"; exit 0' SIGTERM
