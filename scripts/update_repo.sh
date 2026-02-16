#!/usr/bin/env bash
set -euo pipefail

warn() {
    echo "[WARN] $1" >&2
}

error() {
    echo "[ERROR] $1" >&2
}

# Try to source system-wide ROBOT_PATH if available
if [ -f /etc/robot_path.conf ]; then
  # shellcheck disable=SC1090
  source /etc/robot_path.conf || true
fi

if [ -z "$ROBOT_PATH" ]; then
  echo "ERROR: ROBOT_PATH not set"
  exit 1
fi

REPO_LIST_FILE="${1:-${REPO_LIST_FILE:-/etc/robot_repos.conf}}"
REPOS_DIR="${REPOS_DIR:-${ROBOT_PATH}/Repos}"


echo ""
echo "====== $(date) ======"

if [ ! -f "$REPO_LIST_FILE" ]; then
  error "File in repository list not found: $REPO_LIST_FILE"
  exit 1
fi

until ping -c1 github.com &>/dev/null; do
    sleep 5
done

while read -r line || [ -n "$line" ]; do
  # strip comments and whitespace
  line="$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue

  # split into repo and optional branch
  read -r repo_rel repo_branch_cfg <<< "$line"

  # resolve path: allow absolute or relative
  if [[ "$repo_rel" = /* ]]; then
    repo_path="$repo_rel"
  else
    repo_path="${REPOS_DIR%/}/$repo_rel"
  fi

  target_branch="${repo_branch_cfg:-main}"
  echo "Processing repo: $repo_rel -> $repo_path (branch: $target_branch)"

  if [ ! -d "$repo_path/.git" ]; then
    warn "$repo_path is not a valid repository, skipping"
    continue
  fi

  cd "$repo_path" || continue
  echo "Fetching origin for $repo_rel"
  git fetch origin --prune || true

  LOCAL=$(git rev-parse @ 2>/dev/null || true)
  REMOTE=$(git rev-parse "origin/${target_branch}" 2>/dev/null || true)

  if [ -z "$REMOTE" ]; then
    warn "origin/${target_branch} doesnt exist for $repo_rel, creating local branch if necesary"
    git checkout "$target_branch" 2>/dev/null || git checkout -b "$target_branch" || true
    # no remote to reset to
    continue
  fi

  echo "Local: $LOCAL Remote: $REMOTE"

  if [ "$LOCAL" != "$REMOTE" ]; then
    echo "Changes detected in origin/${target_branch} for $repo_rel, updating..."
    do_checkout() { git checkout "$1" || git checkout -b "$1" || true; }
    do_checkout "$target_branch"
    git reset --hard "origin/${target_branch}" || true
    echo "Update complete for $repo_rel"
  else
    echo "$repo_rel is already updated"
  fi

  echo "============================================="

done < "$REPO_LIST_FILE"

echo "All updates complete"
