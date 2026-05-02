#!/usr/bin/env bash
set -euo pipefail

# Helper script to choose the correct Make deploy variant based on the host GPU.
# Usage:
#   ./deploy_auto.sh [server|client] [--dry-run]

role="server"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    server|client)
      role="$1"
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./deploy_auto.sh [server|client] [--dry-run]

Automatically selects the correct deploy variant based on available GPU hardware.
If an NVIDIA GPU is detected, this script deploys the `*-nvidia` variant.
Otherwise it deploys the base `server` or `client` variant.

Examples:
  ./deploy_auto.sh
  ./deploy_auto.sh client
  ./deploy_auto.sh server --dry-run
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

variant="${role}"

if command -v nvidia-smi >/dev/null 2>&1; then
  variant="${role}-nvidia"
else
  if command -v lspci >/dev/null 2>&1; then
    if lspci | grep -i -E 'NVIDIA|GeForce|Quadro|RTX|Tesla' >/dev/null 2>&1; then
      variant="${role}-nvidia"
    fi
  fi
fi

if ! command -v podman >/dev/null 2>&1; then
  echo "Error: podman is required to pull make/ansible container images." >&2
  exit 1
fi

TOOL_IMAGE="registry.fedoraproject.org/fedora:latest"
TOOL_ROOT="$PWD/.toolroot"

prepare_tool_root() {
  if [[ ! -x "$TOOL_ROOT/usr/bin/make" || ! -x "$TOOL_ROOT/usr/bin/ansible-playbook" ]]; then
    echo "Preparing tool root at $TOOL_ROOT"
    rm -rf "$TOOL_ROOT"
    mkdir -p "$TOOL_ROOT"
    podman run --rm \
      -v "$PWD":/workdir:Z \
      -w /workdir \
      "$TOOL_IMAGE" \
      bash -lc 'set -e; dnf install -y --installroot=/workdir/.toolroot --releasever=$(rpm -E %fedora) --setopt=install_weak_deps=False --nodocs make ansible; for f in /workdir/.toolroot/usr/bin/ansible*; do [ -f "$f" ] && sed -i "1s|^#!.*python3$|#!/usr/bin/env python3|" "$f"; done'
  fi
}

run_make_with_container() {
  local variant="$1"
  prepare_tool_root
  echo "Running make/ansible using tools from $TOOL_ROOT"
  local python_paths
  python_paths=$(printf "%s:" "$TOOL_ROOT"/usr/lib/python3.* 2>/dev/null | sed 's/:$//')
  PATH="$TOOL_ROOT/usr/bin:$PATH" \
    LD_LIBRARY_PATH="$TOOL_ROOT/usr/lib64:$TOOL_ROOT/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    PYTHONHOME="$TOOL_ROOT/usr" \
    PYTHONPATH="$python_paths${PYTHONPATH:+:$PYTHONPATH}" \
    make deploy DEPLOY_VARIANT="$variant"
}














if [[ "$dry_run" == true ]]; then
  echo "Selected deploy variant: $variant"
  echo "Tool image: $TOOL_IMAGE"
  echo "Tool root: $TOOL_ROOT"
  exit 0
fi

echo "Deploying variant: $variant"
run_make_with_container "$variant"
