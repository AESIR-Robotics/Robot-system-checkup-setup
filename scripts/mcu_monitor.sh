#!/usr/bin/env bash
set -euo pipefail

# mcu_monitor.sh
# Invocado por udev con el nombre del dispositivo (ej: ttyACM0)

DEV="${1:-}"

if [ -z "$DEV" ]; then
  echo "ERROR: no device name received"
  exit 1
fi


if [ -f /etc/robot_path.conf ]; then
  source /etc/robot_path.conf || true
fi

if [ -z "$ROBOT_PATH" ] || [ ! -d "$ROBOT_PATH" ]; then
  echo "ERROR: invalid ROBOT_PATH: $ROBOT_PATH"
  exit 1
fi

FIRMWARE="${ROBOT_PATH}/firmware"
TRIGGER="${FIRMWARE}/connect.txt"
FLASH_SCRIPT="${FIRMWARE}/flash.sh"

log() {
  echo "$(date '+%F %T') [$$] $*" 
}
log ""

DEVICE_PATH="/dev/$DEV"

if [ ! -e "$DEVICE_PATH" ]; then
  log "ERROR: device $DEVICE_PATH does not exist"
  exit 1
fi

log "MCU connected: $DEVICE_PATH"

# Get udev properties
if UDEV_PROPS=$(udevadm info -q property -n "$DEVICE_PATH" 2>/dev/null); then
  log "udev props: $(echo "$UDEV_PROPS" | grep -E "ID_VENDOR|ID_MODEL|ID_SERIAL" | tr '\n' ' | ')"
else
  log "WARN: could not retrieve udev properties"
fi

# Flash
if [ -f "$TRIGGER" ]; then
  log "Trigger detected -> attempting flash"

  if [ -x "$FLASH_SCRIPT" ]; then

    systemctl stop "mcu_monitor@${DEV}.service"
    sleep 1

    if "$FLASH_SCRIPT" "$DEV"; then
      log "Flash completed successfully"
    else
      log "Flash script failed"
    fi

    systemctl start "mcu_monitor@${DEV}.service"
    sleep 1

  else
    log "Flash script missing or not executable: $FLASH_SCRIPT"
  fi
fi

log "MCU ready: $DEVICE_PATH"

# Keep service alive
trap 'log "Terminated by user unknown device stats"; exit 0' SIGINT
trap 'log "MCU disconnected: $DEVICE_PATH"; exit 0' EXIT


sleep infinity &

wait $!