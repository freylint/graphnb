#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./make.sh publish [notebook.ipynb] [--hide-code] [--to html|markdown] [--output name]
  ./make.sh readme [notebook.ipynb] [--hide-code]
  ./make.sh serve [--containerfile path] [--port 8080] [--image name] [--name container] [--detach] [--no-cache]

Examples:
  ./make.sh publish
  ./make.sh publish notebook.ipynb --hide-code
  ./make.sh publish notebook.ipynb --to html --output graphnb-public
  ./make.sh readme
  ./make.sh readme notebook.ipynb --hide-code
  ./make.sh serve
  ./make.sh serve --port 9090 --detach

Notes:
  - Default notebook: notebook.ipynb
  - Default format: html
  - --hide-code hides code inputs in the published output
  - readme writes markdown output to README.md
  - serve builds and runs the top-level Containerfile
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

resolve_nbconvert_runner() {
  if command -v jupyter >/dev/null 2>&1; then
    if jupyter nbconvert --help >/dev/null 2>&1; then
      echo "jupyter"
      return 0
    fi
  fi

  if command -v python3 >/dev/null 2>&1; then
    if python3 -m nbconvert --help >/dev/null 2>&1; then
      echo "python3"
      return 0
    fi
  fi

  echo ""
}

resolve_container_runtime() {
  if command -v podman >/dev/null 2>&1; then
    echo "podman"
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    echo "docker"
    return 0
  fi

  echo ""
}

publish_notebook() {
  local notebook="notebook.ipynb"
  local to_format="html"
  local output_name=""
  local hide_code="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hide-code)
        hide_code="true"
        shift
        ;;
      --to)
        if [[ $# -lt 2 ]]; then
          echo "Error: --to requires a value" >&2
          exit 1
        fi
        to_format="$2"
        shift 2
        ;;
      --output)
        if [[ $# -lt 2 ]]; then
          echo "Error: --output requires a value" >&2
          exit 1
        fi
        output_name="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [[ "$1" == *.ipynb && "$notebook" == "notebook.ipynb" ]]; then
          notebook="$1"
          shift
        else
          echo "Error: unknown option or argument: $1" >&2
          usage
          exit 1
        fi
        ;;
    esac
  done

  if [[ ! -f "$notebook" ]]; then
    echo "Error: notebook not found: $notebook" >&2
    exit 1
  fi

  local runner
  runner="$(resolve_nbconvert_runner)"
  if [[ -z "$runner" ]]; then
    echo "Error: nbconvert is not available. Install python3-nbconvert in the devcontainer." >&2
    exit 1
  fi

  local -a cmd
  if [[ "$runner" == "jupyter" ]]; then
    cmd=(jupyter nbconvert "$notebook" --to "$to_format")
  else
    cmd=(python3 -m nbconvert "$notebook" --to "$to_format")
  fi

  if [[ -n "$output_name" ]]; then
    cmd+=(--output "$output_name")
  fi

  if [[ "$hide_code" == "true" ]]; then
    cmd+=(--no-input)
  fi

  echo "Publishing $notebook as $to_format..."
  if [[ "$hide_code" == "true" ]]; then
    echo "Code inputs will be hidden in the output."
  fi

  "${cmd[@]}"
  echo "Publish complete."
}

readme_from_notebook() {
  local notebook="notebook.ipynb"
  local hide_code="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hide-code)
        hide_code="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [[ "$1" == *.ipynb && "$notebook" == "notebook.ipynb" ]]; then
          notebook="$1"
          shift
        else
          echo "Error: unknown option or argument: $1" >&2
          usage
          exit 1
        fi
        ;;
    esac
  done

  if [[ ! -f "$notebook" ]]; then
    echo "Error: notebook not found: $notebook" >&2
    exit 1
  fi

  local runner
  runner="$(resolve_nbconvert_runner)"
  if [[ -z "$runner" ]]; then
    echo "Error: nbconvert is not available. Install python3-nbconvert in the devcontainer." >&2
    exit 1
  fi

  local -a cmd
  if [[ "$runner" == "jupyter" ]]; then
    cmd=(jupyter nbconvert "$notebook" --to markdown --output README --output-dir .)
  else
    cmd=(python3 -m nbconvert "$notebook" --to markdown --output README --output-dir .)
  fi

  # Remove any cell that starts with the "hide-on-readme" marker comment.
  cmd+=(--RegexRemovePreprocessor.enabled=True)
  cmd+=(--RegexRemovePreprocessor.patterns)
  cmd+=('^\s*//\s*hide-on-readme')

  if [[ "$hide_code" == "true" ]]; then
    cmd+=(--no-input)
  fi

  echo "Generating README.md from $notebook..."
  echo "Cells marked with // hide-on-readme are excluded from README.md."
  if [[ "$hide_code" == "true" ]]; then
    echo "Code inputs will be hidden in README.md."
  fi

  "${cmd[@]}"
  echo "README generated: README.md"
}

serve_container() {
  local containerfile="Containerfile"
  local port="8080"
  local image="graphnb:serve"
  local name="graphnb-serve"
  local detach="false"
  local no_cache="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --containerfile)
        if [[ $# -lt 2 ]]; then
          echo "Error: --containerfile requires a value" >&2
          exit 1
        fi
        containerfile="$2"
        shift 2
        ;;
      --port)
        if [[ $# -lt 2 ]]; then
          echo "Error: --port requires a value" >&2
          exit 1
        fi
        port="$2"
        shift 2
        ;;
      --image)
        if [[ $# -lt 2 ]]; then
          echo "Error: --image requires a value" >&2
          exit 1
        fi
        image="$2"
        shift 2
        ;;
      --name)
        if [[ $# -lt 2 ]]; then
          echo "Error: --name requires a value" >&2
          exit 1
        fi
        name="$2"
        shift 2
        ;;
      --detach)
        detach="true"
        shift
        ;;
      --no-cache)
        no_cache="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Error: unknown option or argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ ! -f "$containerfile" ]]; then
    echo "Error: Containerfile not found: $containerfile" >&2
    exit 1
  fi

  local runtime
  runtime="$(resolve_container_runtime)"
  if [[ -z "$runtime" ]]; then
    echo "Error: neither podman nor docker is installed." >&2
    exit 1
  fi

  local -a build_cmd
  build_cmd=("$runtime" build -f "$containerfile" -t "$image")
  if [[ "$no_cache" == "true" ]]; then
    build_cmd+=(--no-cache)
  fi
  build_cmd+=(.)

  echo "Building image $image from $containerfile using $runtime..."
  "${build_cmd[@]}"

  # Replace any previous container with the same name to avoid name collisions.
  if "$runtime" ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
    echo "Removing existing container: $name"
    "$runtime" rm -f "$name" >/dev/null
  fi

  local -a run_cmd
  run_cmd=("$runtime" run --rm --name "$name" -p "${port}:80")
  if [[ "$detach" == "true" ]]; then
    run_cmd+=(-d)
  fi
  run_cmd+=("$image")

  echo "Starting container $name on http://localhost:$port"
  "${run_cmd[@]}"

  if [[ "$detach" == "true" ]]; then
    echo "Container is running in background."
    echo "Stop it with: $runtime rm -f $name"
  fi
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local command="$1"
  shift

  case "$command" in
    publish)
      publish_notebook "$@"
      ;;
    readme)
      readme_from_notebook "$@"
      ;;
    serve)
      serve_container "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "Error: unknown command: $command" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
