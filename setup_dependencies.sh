#!/bin/bash
set -euo pipefail

safe_install() {
    local src="$1"
    local dst_dir="$2"
    local mode="${3:-750}"
    local owner="${4:-robot}"
    local group="${5:-robotdata}"

    local filename
    filename=$(basename "$src")

    local dst="$dst_dir/$filename"

    # Obtener rutas absolutas reales
    local src_real dst_real
    src_real=$(realpath "$src")
    dst_real=$(realpath -m "$dst")

    if [[ "$src_real" == "$dst_real" ]]; then
        echo "Source and target identical for $filename — fixing permissions only"
        chmod "$mode" "$dst"
        chown "$owner:$group" "$dst"
        return 0
    fi

    install -m "$mode" -o "$owner" -g "$group" "$src" "$dst_dir/"
}

ROBOT_PATH="/opt/robot"
SERVICE_DIR="$ROBOT_PATH/scripts"
REMINDERS_DIR="$PWD/reminders"
SCRIPT_DIR="$PWD/scripts"

if [ "$EUID" -ne 0 ]; then
  echo "This script must be executed with sudo" >&2
  exit 1
fi

CURRENT_USER="${SUDO_USER:-$(logname)}"

echo "Creating service user and shared group..."

# Create shared group
if ! getent group robotdata >/dev/null; then
    groupadd robotdata
fi

# Create robot user if needed
if ! id -u robot >/dev/null 2>&1; then
    useradd -r -m -d /home/robot -s /usr/sbin/nologin robot
fi

# Add users to shared group
usermod -aG robotdata robot
usermod -aG robotdata "$CURRENT_USER"
usermod -aG dialout robot

echo "Creating directory structure..."

mkdir -p "$ROBOT_PATH"/{firmware,Repos,scripts}

chown -R robot:robotdata "$ROBOT_PATH"
chmod -R 2775 "$ROBOT_PATH"

echo "Copying scripts..."

safe_install "$SCRIPT_DIR/mcu_monitor.sh" "$SERVICE_DIR/" 
safe_install "$SCRIPT_DIR/update_repo.sh" "$SERVICE_DIR/"

echo "Fixing SSH for robot..."

install -d -m 700 -o robot -g robot /home/robot/.ssh

sudo -u robot ssh-keyscan github.com >> /home/robot/.ssh/known_hosts
chmod 644 /home/robot/.ssh/known_hosts
chown robot:robot /home/robot/.ssh/known_hosts

if [ ! -f /home/robot/.ssh/id_ed25519 ]; then
    sudo -u robot ssh-keygen -t ed25519 -N "" -f /home/robot/.ssh/id_ed25519
fi
echo "Public ssh key at /home/robot/.ssh/id_ed25519.pub: "
cat /home/robot/.ssh/id_ed25519.pub
echo "Add this key to your github username as a new SSH key (recommend creating a new user)"
echo "Also do not forget to set the origin remote with ssh: "
echo "git remote set-url origin git@github.com:[owner]/[repo].git"


echo "Installing system files..."

install -m 644 "$REMINDERS_DIR/mcu-monitor@.service" /etc/systemd/system/
install -m 644 "$REMINDERS_DIR/update-repo.service" /etc/systemd/system/

echo "Creating repository handler conf file..."

echo "ROBOT_PATH=\"$ROBOT_PATH\"" > /etc/robot_path.conf
chmod 644 /etc/robot_path.conf

echo "Creating env file..."

install -m 644 "$REMINDERS_DIR/robot_repos.conf" /etc/robot_repos.conf

echo "Installing polkit rule..."

mkdir -p /etc/polkit-1/rules.d
touch /etc/polkit-1/rules.d/49-mcu-monitor.rules
cat >/etc/polkit-1/rules.d/49-mcu-monitor.rules <<EOF
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units") {
        if (subject.user == "$CURRENT_USER") {
            var unit = action.lookup("unit");
            if (unit && unit.startsWith("mcu-monitor@")) {
                return polkit.Result.YES;
            }
        }
    }
});
EOF

systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger

cat <<EOF

Instalation complete.
- Scripts copied to: $ROBOT_PATH
- Installed systemd unit: /etc/systemd/system/mcu-monitor@.service
- Installed systemd unit: /etc/systemd/system/update-repo.service
- Udev rules installed in /etc/udev/rules.d/70-monitor.rules
- Installed configuration file: /etc/robot_repos.conf

Note: Services did not activate automatically. To activate the monitor
for a specific device (ex: ttyACM0), execute:
  systemctl enable --now mcu-monitor@ttyACM0.service

To use update-repo as a programmed service you can activate:
  systemctl enable --now update-repo.service

Log out and log in to apply changes if it is the first time run

EOF

