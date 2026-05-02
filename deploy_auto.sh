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

pull_tool_image() {
  echo "Pulling tool image: $TOOL_IMAGE"
  podman pull "$TOOL_IMAGE"
}

run_make_with_container() {
  local variant="$1"
  pull_tool_image
  echo "Running make/ansible inside container image: $TOOL_IMAGE"
  podman run --rm \
    -v "$PWD":/workdir:Z \
    -w /workdir \
    "$TOOL_IMAGE" \
    bash -lc 'dnf install -y make ansible && make deploy DEPLOY_VARIANT="'$variant'"'
}

if [[ "$dry_run" == true ]]; then
  echo "Selected deploy variant: $variant"
  echo "Tool image: $TOOL_IMAGE"
  exit 0
fi

echo "Deploying variant: $variant"
run_make_with_container "$variant"
