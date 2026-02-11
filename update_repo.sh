#!/bin/bash
set -euo pipefail

# update_repo.sh
# Actualiza varios repositorios listados en un archivo de configuración.
# Uso:
#   update_repo.sh [REPO_LIST_FILE] [BRANCH_OVERRIDE]
# Donde REPO_LIST_FILE (por defecto /etc/robot_repos.conf) contiene líneas:
#   repo_relative_path [branch]
# Repos se resuelven contra $REPOS_DIR (por defecto $ROBOT_PATH/Repos)

# Try to source system-wide ROBOT_PATH if available
if [ -f /etc/robot_path.conf ]; then
  # shellcheck disable=SC1090
  source /etc/robot_path.conf || true
fi

ROBOT_PATH="${ROBOT_PATH:-}"
REPO_LIST_FILE="${1:-${REPO_LIST_FILE:-/etc/robot_repos.conf}}"
BRANCH_OVERRIDE="${2:-${BRANCH_OVERRIDE:-}}"
REPOS_DIR="${REPOS_DIR:-${ROBOT_PATH}/Repos}"

LOG_DIR="${ROBOT_PATH}/logs"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/update_repo.log"

exec >> "$LOG" 2>&1
echo "====== $(date) ======"
echo "ROBOT_PATH=$ROBOT_PATH REPOS_DIR=$REPOS_DIR REPO_LIST_FILE=$REPO_LIST_FILE BRANCH_OVERRIDE=$BRANCH_OVERRIDE"

if [ ! -f "$REPO_LIST_FILE" ]; then
  echo "ERROR: archivo de lista de repositorios no encontrado: $REPO_LIST_FILE"
  exit 1
fi

until ping -c1 github.com &>/dev/null; do
    echo "Esperando conectividad a github.com..."
    sleep 5
done

while read -r line || [ -n "$line" ]; do
  # strip comments and whitespace
  line="$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue

  # split into repo and optional branch
  repo_rel=$(echo "$line" | awk '{print $1}')
  repo_branch_cfg=$(echo "$line" | awk '{print $2}')

  # resolve path: allow absolute or relative
  if [[ "$repo_rel" = /* ]]; then
    repo_path="$repo_rel"
  else
    repo_path="${REPOS_DIR%/}/$repo_rel"
  fi

  target_branch="${BRANCH_OVERRIDE:-${repo_branch_cfg:-main}}"

  echo "Processing repo: $repo_rel -> $repo_path (branch: $target_branch)"

  if [ ! -d "$repo_path/.git" ]; then
    echo "WARN: $repo_path no es un repo git válido, saltando"
    continue
  fi

  cd "$repo_path" || continue
  echo "Fetching origin for $repo_rel"
  git fetch origin --prune || true

  LOCAL=$(git rev-parse @ 2>/dev/null || true)
  REMOTE=$(git rev-parse "origin/${target_branch}" 2>/dev/null || true)

  if [ -z "$REMOTE" ]; then
    echo "Advertencia: origin/${target_branch} no existe para $repo_rel, creando branch local si es necesario"
    git checkout "$target_branch" 2>/dev/null || git checkout -b "$target_branch" || true
    # no remote to reset to
    continue
  fi

  echo "Local: $LOCAL Remote: $REMOTE"

  if [ "$LOCAL" != "$REMOTE" ]; then
    echo "Cambios detectados en origin/${target_branch} para $repo_rel, actualizando..."
    do_checkout() { git checkout "$1" || git checkout -b "$1" || true; }
    do_checkout "$target_branch"
    git reset --hard "origin/${target_branch}" || true
    echo "Actualización completada para $repo_rel"
  else
    echo "$repo_rel ya está actualizado"
  fi

done < "$REPO_LIST_FILE"

echo "Todas las actualizaciones completadas"
