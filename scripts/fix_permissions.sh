#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  bash scripts/fix_permissions.sh <path> [<path> ...]

Applies shared-group friendly permissions:
  - chmod -R g=u
  - setgid on directories
  - ug+x on script-like files (*.sh, *.py, *.nf)
EOF
    exit 1
}

[[ $# -ge 1 ]] || usage

for target in "$@"; do
    [[ -e "${target}" ]] || continue

    chmod -R g=u "${target}"

    if [[ -d "${target}" ]]; then
        find "${target}" -type d -exec chmod g+s {} +
        find "${target}" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.nf' \) -exec chmod ug+x {} +
    elif [[ -f "${target}" ]]; then
        case "${target}" in
            *.sh|*.py|*.nf)
                chmod ug+x "${target}"
                ;;
        esac
    fi
done
