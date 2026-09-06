#!/bin/bash
# MC Launcher shared UI
MC_COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MC_COMMAND_DIR/ui.sh"


set -o pipefail

# ============================================================
# MC LAUNCHER — REMOVE
# ============================================================

GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"

# ============================================================
# Colors
# ============================================================

if [[ -t 1 ]]; then
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    CYAN='\033[36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    DIM=''
    RESET=''
fi

# ============================================================
# Helpers
# ============================================================

die() {
    mc_error $*" >&2
    exit 1
}

success() {
    mc_ok $*" >&2
}

warn() {
    mc_warn $*" >&2
}

# ============================================================
# Type -> Directory
# ============================================================

get_directory() {
    local type="$1"

    case "$type" in
        mod)
            echo "$GAME_DIR/mods"
            ;;

        shader)
            echo "$GAME_DIR/shaderpacks"
            ;;

        resourcepack)
            echo "$GAME_DIR/resourcepacks"
            ;;

        modpack)
            echo "$GAME_DIR/modpacks"
            ;;

        world)
            echo "$GAME_DIR/saves"
            ;;

        instance)
            echo "$GAME_DIR/instances"
            ;;

        *)
            return 1
            ;;
    esac
}

# ============================================================
# Usage
# ============================================================

show_help() {
    cat >&2 <<EOF
Usage:

  mc remove <type> [name]

Types:

  mod
  shader
  resourcepack
  modpack
  world
  instance

Examples:

  mc remove mod sodium
  mc remove shader complementary
  mc remove resourcepack faithful
  mc remove modpack "My Pack"
  mc remove world survival

Without a name:

  mc remove mod

will show all installed mods.
EOF
}

# ============================================================
# Select File
# ============================================================

select_item() {
    local type="$1"
    local query="$2"
    local directory="$3"

    [[ -d "$directory" ]] ||
        die "No installed $type directory exists."

    shopt -s nullglob

    local files=("$directory"/*)

    local matches=()

    for file in "${files[@]}"; do

        [[ -e "$file" ]] || continue

        local name
        name="$(basename "$file")"

        if [[ -z "$query" ]]; then
            matches+=("$file")
            continue
        fi

        if [[ "${name,,}" == *"${query,,}"* ]]; then
            matches+=("$file")
        fi

    done

    if (( ${#matches[@]} == 0 )); then

        if [[ -n "$query" ]]; then
            die "No installed $type matching '$query' found."
        fi

        die "No installed $type found."

    fi

    echo >&2
    echo -e "${BOLD}Installed ${type}s:${RESET}" >&2
    echo >&2

    for i in "${!matches[@]}"; do

        local name
        name="$(basename "${matches[$i]}")"

        if [[ -d "${matches[$i]}" ]]; then
            echo -e \
                "  ${CYAN}$((i + 1)))${RESET} ${BOLD}${name}/${RESET}" \
                >&2
        else
            echo -e \
                "  ${CYAN}$((i + 1)))${RESET} ${BOLD}${name}${RESET}" \
                >&2
        fi

    done

    echo >&2
    echo -e "  ${RED}0)${RESET} Cancel" >&2
    echo >&2

    local selection

    while true; do

        read -r \
            -p "Select a ${type} [1-${#matches[@]}, 0 to cancel]: " \
            selection

        if [[ "$selection" == "0" ]]; then
            echo "Cancelled." >&2
            return 1
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= ${#matches[@]} )); then

            SELECTED_ITEM="${matches[$((selection - 1))]}"

            return 0
        fi

        echo \
            -e "${RED}Invalid selection.${RESET}" \
            >&2

    done
}

# ============================================================
# Confirm Removal
# ============================================================

confirm_remove() {
    local type="$1"
    local item="$2"

    local name
    name="$(basename "$item")"

    echo >&2
    echo -e "${BOLD}Selected:${RESET} $name" >&2
    echo -e "Type: $type" >&2
    echo -e "Path: $item" >&2
    echo >&2

    read -r \
        -p "Remove '$name'? [y/N]: " \
        answer

    case "${answer,,}" in
        y|yes)
            return 0
            ;;

        *)
            echo "Cancelled." >&2
            return 1
            ;;
    esac
}

# ============================================================
# Main
# ============================================================

main() {

    local type="${1:-}"

    if [[ -z "$type" ||
          "$type" == "--help" ||
          "$type" == "-h" ]]; then

        show_help
        exit 0

    fi

    shift

    local directory

    directory="$(get_directory "$type")" || {
        echo -e \
            "${RED}Error:${RESET} Unknown remove type '$type'." \
            >&2

        echo >&2
        show_help

        exit 1
    }

    # Everything after the type becomes the search query.
    local query="$*"

    select_item \
        "$type" \
        "$query" \
        "$directory" || exit 0

    if ! confirm_remove \
        "$type" \
        "$SELECTED_ITEM"; then

        exit 0
    fi

    echo >&2
    echo "Removing $(basename "$SELECTED_ITEM")..."

    rm -rf -- "$SELECTED_ITEM" || {
        die "Failed to remove '$SELECTED_ITEM'."
    }

    success "Removed $(basename "$SELECTED_ITEM")"
}

main "$@"