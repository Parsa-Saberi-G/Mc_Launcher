#!/bin/bash

set -o pipefail

GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"

if [[ -t 1 ]]; then
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    CYAN='\033[36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    RESET=''
fi


die() {
    echo -e "${RED}Error:${RESET} $*" >&2
    exit 1
}


success() {
    echo -e "${GREEN}✓${RESET} $*"
}


get_directory() {
    case "$1" in
        mod|mods)
            echo "$GAME_DIR/mods"
            ;;
        shader|shaders)
            echo "$GAME_DIR/shaderpacks"
            ;;
        resourcepack|resourcepacks)
            echo "$GAME_DIR/resourcepacks"
            ;;
        modpack|modpacks)
            echo "$GAME_DIR/modpacks"
            ;;
        world|worlds)
            echo "$GAME_DIR/saves"
            ;;
        *)
            return 1
            ;;
    esac
}


find_item() {
    local type="$1"
    local name="$2"
    local directory="$3"

    [[ -d "$directory" ]] ||
        die "No installed $type directory exists."

    if [[ -e "$directory/$name" ]]; then
        echo "$directory/$name"
        return 0
    fi

    shopt -s nullglob

    local matches=()

    for item in "$directory"/*; do
        local item_name
        item_name="$(basename "$item")"

        if [[ "${item_name,,}" == *"${name,,}"* ]]; then
            matches+=("$item")
        fi
    done

    if (( ${#matches[@]} == 0 )); then
        die "No installed $type matching '$name' found."
    fi

    if (( ${#matches[@]} == 1 )); then
        echo "${matches[0]}"
        return 0
    fi

    echo
    echo "Multiple matches:"
    echo

    local i=0

    for item in "${matches[@]}"; do
        ((i++))
        echo "  $i) $(basename "$item")"
    done

    echo
    echo "  0) Cancel"
    echo

    local selection

    while true; do
        read -r -p "Select [1-${#matches[@]}]: " selection

        if [[ "$selection" == "0" ]]; then
            exit 0
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= ${#matches[@]} )); then
            echo "${matches[$((selection - 1))]}"
            return 0
        fi

        echo -e "${RED}Invalid selection.${RESET}"
    done
}


export_world() {
    local source="$1"
    local output="$2"

    mkdir -p "$output"

    local name
    name="$(basename "$source")"

    local archive="$output/${name}.tar.gz"

    tar -czf "$archive" -C "$(dirname "$source")" "$name" ||
        die "Failed to export world."

    success "Exported world:"
    echo "  $archive"
}


export_file() {
    local source="$1"
    local output="$2"

    mkdir -p "$output"

    cp -f -- "$source" "$output/" ||
        die "Failed to export file."

    success "Exported:"
    echo "  $output/$(basename "$source")"
}


show_help() {
    cat <<EOF
Usage:

  mc export <type> <name> [output]

Types:

  mod
  shader
  resourcepack
  modpack
  world

Examples:

  mc export mod sodium ./backup
  mc export shader complementary ./backup
  mc export resourcepack faithful ./backup
  mc export world survival ./backup

If output is omitted:

  ./mc-export/

is used.

EOF
}


main() {
    local type="${1:-}"
    local name="${2:-}"
    local output="${3:-./mc-export}"

    if [[ "$type" == "--help" ||
          "$type" == "-h" ||
          -z "$type" ]]; then
        show_help
        return
    fi

    [[ -n "$name" ]] ||
        die "Missing item name."

    local directory
    directory="$(get_directory "$type")" ||
        die "Unknown export type '$type'."

    local item
    item="$(find_item "$type" "$name" "$directory")"

    [[ -e "$item" ]] ||
        die "Selected item does not exist."

    output="${output/#\~/$HOME}"

    case "$type" in
        world|worlds)
            export_world "$item" "$output"
            ;;

        *)
            export_file "$item" "$output"
            ;;
    esac
}


main "$@"