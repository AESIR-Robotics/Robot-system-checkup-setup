#!/bin/bash
set -euo pipefail

# setup_dependencies.sh
# Instala dependencias mínimas y coloca los archivos de 'reminders' en lugares
# estándar del sistema. Ejecutar con sudo.



# Use the directory where the user runs this script as the ROBOT_PATH.
# This allows users to clone the repo anywhere and run ./setup_dependencies.sh
ROBOT_PATH="$(pwd)"
REMINDERS_DIR="$ROBOT_PATH/reminders"
SCRIPT_DIR="$ROBOT_PATH/scripts"
SERVICE_DIR="/home/robot"

if [ "$EUID" -ne 0 ]; then
  echo "This script must be executed with sudo" >&2
  exit 1
fi

# echo "Installing basic dependencies..."
# apt update
# apt install -y git python3-pip avrdude teensy-loader-cli minicom || true

echo ""
echo "Creating user 'robot' (if it does not exist) and adding it to dialout group"
if ! id -u robot >/dev/null 2>&1; then
  useradd -r -m -d /home/robot -s /usr/sbin/nologin robot || true
fi

echo ""
echo "Creating structure in $ROBOT_PATH if not already there"
mkdir -p "$ROBOT_PATH/firmware"
mkdir -p "$ROBOT_PATH/logs"
mkdir -p "$ROBOT_PATH/Repos"

echo ""
echo "Copying scripts in $SERVICE_DIR"

cp -v "$SCRIPT_DIR/mcu_monitor.sh" "$SERVICE_DIR/mcu_monitor.sh" || true
cp -v "$SCRIPT_DIR/update_repo.sh" "$SERVICE_DIR/update_repo.sh" || true

chmod +x "$SERVICE_DIR/mcu_monitor.sh" || true
chmod +x "$SERVICE_DIR/update_repo.sh" || true
chown robot:robot "$SERVICE_DIR/mcu_monitor.sh" || true
chown robot:robot "$SERVICE_DIR/update_repo.sh" || true

echo ""
echo "Adding robot user to groups dialout and current user primary group"
usermod -aG dialout robot || true
usermod -aG "$(id -gn)" robot || true

echo ""
echo "Generando clave ssh para github"
mkdir -p /home/robot/.ssh
chmod -R 700 /home/robot/.ssh

sudo -u robot ssh-keyscan github.com >> /home/robot/.ssh/known_hosts
chmod 666 /home/robot/.ssh/known_hosts

if [ ! -f "/home/robot/.ssh/id_ed25519.pub" ]; then
    echo "Public ssh key generated for the robot user"
    ssh-keygen -t ed25519 -C "robot@dialout" -N "" -f /home/robot/.ssh/id_ed25519 || true
fi
echo "Public ssh key at /home/robot/.ssh/id_ed25519.pub: "
cat /home/robot/.ssh/id_ed25519.pub
echo "Add this key to your github username as a new SSH key (recommend creating a new user)"
echo "Also do not forget to set the origin remote with ssh: "
echo "git remote set-url origin git@github.com:[owner]/[repo].git"
echo "Lastly make sure the owner of the repository is the user 'robot' (man chown)"

echo ""
echo "Installing files in the system"
if [ -f "$REMINDERS_DIR/70-monitor.rules" ]; then
  cp -v "$REMINDERS_DIR/70-monitor.rules" /etc/udev/rules.d/70-monitor.rules
fi
if [ -f "$REMINDERS_DIR/mcu-monitor@.service" ]; then
  cp -v "$REMINDERS_DIR/mcu-monitor@.service" /etc/systemd/system/mcu-monitor@.service
fi
if [ -f "$REMINDERS_DIR/update-repo.service" ]; then
  cp -v "$REMINDERS_DIR/update-repo.service" /etc/systemd/system/update-repo.service
fi
if [ -f "$REMINDERS_DIR/robot_repos.conf" ]; then
  cp -v "$REMINDERS_DIR/robot_repos.conf" /etc/robot_repos.conf
  chmod 644 /etc/robot_repos.conf || true
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
chmod -R g+X "$ROBOT_PATH"

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

