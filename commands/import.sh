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


import_file() {
    local type="$1"
    local source="$2"
    local destination="$3"

    mkdir -p "$destination"

    local filename
    filename="$(basename "$source")"

    local target="$destination/$filename"

    if [[ -e "$target" ]]; then
        echo -e "${YELLOW}Warning:${RESET} '$filename' already exists."
        echo
        read -r -p "Overwrite it? [y/N]: " answer

        case "${answer,,}" in
            y|yes)
                ;;
            *)
                echo "Cancelled."
                return
                ;;
        esac
    fi

    cp -f -- "$source" "$target" ||
        die "Failed to import '$source'."

    success "Imported $type: $filename"
}


import_world() {
    local source="$1"
    local destination="$2"

    mkdir -p "$destination"

    local name
    name="$(basename "$source")"

    local target="$destination/$name"

    if [[ -e "$target" ]]; then
        die "World '$name' already exists."
    fi

    cp -a -- "$source" "$target" ||
        die "Failed to import world."

    success "Imported world: $name"
}


show_help() {
    cat <<EOF
Usage:

  mc import <type> <path>

Types:

  mod
  shader
  resourcepack
  modpack
  world

Examples:

  mc import mod ./sodium.jar
  mc import shader ./shader.zip
  mc import resourcepack ./faithful.zip
  mc import modpack ./my-pack.mrpack
  mc import world ./MyWorld

EOF
}


main() {
    local type="${1:-}"
    local source="${2:-}"

    if [[ "$type" == "--help" ||
          "$type" == "-h" ||
          -z "$type" ]]; then
        show_help
        return
    fi

    [[ -n "$source" ]] ||
        die "Missing import path."

    source="${source/#\~/$HOME}"

    [[ -e "$source" ]] ||
        die "File or directory '$source' does not exist."

    local destination

    destination="$(get_directory "$type")" ||
        die "Unknown import type '$type'."

    case "$type" in
        world|worlds)
            [[ -d "$source" ]] ||
                die "A world must be imported from a directory."

            import_world "$source" "$destination"
            ;;

        *)
            [[ -f "$source" ]] ||
                die "$type imports require a file."

            import_file "$type" "$source" "$destination"
            ;;
    esac
}


main "$@"