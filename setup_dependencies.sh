#!/bin/bash
set -euo pipefail

# setup_dependencies.sh
# Instala dependencias mínimas y coloca los archivos de 'reminders' en lugares
# estándar del sistema. Ejecutar con sudo.

REMINDERS_DIR="$(dirname "$0")/reminders"

# Use the directory where the user runs this script as the ROBOT_PATH.
# This allows users to clone the repo anywhere and run ./setup_dependencies.sh
INSTALL_DIR="${INSTALL_DIR:-$(pwd)}"
ROBOT_PATH="$INSTALL_DIR"

if [ "$EUID" -ne 0 ]; then
  echo "Este script debe ejecutarse con sudo" >&2
  exit 1
fi

echo "Instalando dependencias básicas..."
apt update
apt install -y git python3-pip avrdude teensy-loader-cli minicom || true

echo "Creando estructura en $ROBOT_PATH"
mkdir -p "$ROBOT_PATH"
mkdir -p "$ROBOT_PATH/firmware"
mkdir -p "$ROBOT_PATH/logs"
mkdir -p "$ROBOT_PATH/Repos"

echo "Copiando/asegurando scripts en $ROBOT_PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -v "$SCRIPT_DIR/mcu_monitor.sh" "$ROBOT_PATH/" || true
cp -v "$SCRIPT_DIR/update_repo.sh" "$ROBOT_PATH/" || true
cp -v "$SCRIPT_DIR/firmware/flash.sh" "$ROBOT_PATH/firmware/" || true
chmod +x "$ROBOT_PATH/mcu_monitor.sh" || true
chmod +x "$ROBOT_PATH/update_repo.sh" || true
chmod +x "$ROBOT_PATH/firmware/flash.sh" || true

echo "Creando usuario 'robot' (si no existe) y añadiéndolo al grupo dialout"
if ! id -u robot >/dev/null 2>&1; then
  useradd -m -s /bin/bash robot || true
fi
usermod -aG dialout robot || true

echo "Instalando archivos de reminders en el sistema"
if [ -f "$REMINDERS_DIR/70-monitor.rules" ]; then
  cp -v "$REMINDERS_DIR/70-monitor.rules" /etc/udev/rules.d/70-monitor.rules
fi
if [ -f "$REMINDERS_DIR/mcu-monitor@.service" ]; then
  cp -v "$REMINDERS_DIR/mcu-monitor@.service" /etc/systemd/system/mcu-monitor@.service
fi
if [ -f "$REMINDERS_DIR/update-repo.service" ]; then
  cp -v "$REMINDERS_DIR/update-repo.service" /etc/systemd/system/update-repo.service
fi

if [ -f "$REMINDERS_DIR/connect.txt" ]; then
  cp -v "$REMINDERS_DIR/connect.txt" "$ROBOT_PATH/firmware/connect.txt"
fi

echo ""
echo "Creating system file with ROBOT_PATH and permanent export"
echo "ROBOT_PATH=\"$ROBOT_PATH\"" > /etc/robot_path.conf
cat > /etc/profile.d/robot_path.sh <<EOF
# robot path exported for interactive shells
export ROBOT_PATH="$ROBOT_PATH"
EOF
chmod 644 /etc/robot_path.conf /etc/profile.d/robot_path.sh

echo ""
echo "Adjusting permissions and capabilities"
if command -v teensy-loader-cli >/dev/null 2>&1; then
  setcap cap_sys_rawio+ep "$(command -v teensy-loader-cli)" || true
fi

echo ""
echo "Creating repository template: /etc/robot_repos.conf"
if [ ! -f /etc/robot_repos.conf ]; then
  cat > /etc/robot_repos.conf <<'EOF'
# List of repositories to update by the update_repo.sh service
# Format: <path_relative_or_absolute> [branch]
# If the path is relative it will be interpreted as $ROBOT_PATH/Repos
# Examples:
# mylib main
# robots/controls develop
# /var/git/special_repo release

# Add here your repositories
# example_repo main
EOF
  chmod 644 /etc/robot_repos.conf || true
fi

echo ""
echo "Reloading rules udev y systemd"
udevadm control --reload-rules || true
udevadm trigger --action=add || true
systemctl daemon-reload || true

cat <<EOF

Instalation complete.
- Scripts copied to: $ROBOT_PATH
- Installed systemd unit: /etc/systemd/system/mcu-monitor@.service
- Installed systemd unit: /etc/systemd/system/update-repo.service
- Udev rules installed in /etc/udev/rules.d/70-monitor.rules

Note: Services did not activate automatically. To activate the monitor
for a specific device (ex: ttyACM0), execute:
  systemctl enable --now mcu-monitor@ttyACM0.service

To use update-repo as a programmed service you can activate:
  systemctl enable --now update-repo.service

EOF

exit 0

