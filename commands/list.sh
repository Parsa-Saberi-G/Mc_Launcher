#!/bin/bash

set -o pipefail

GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"

MODS_DIR="$GAME_DIR/mods"
SHADERS_DIR="$GAME_DIR/shaderpacks"
RESOURCEPACKS_DIR="$GAME_DIR/resourcepacks"
MODPACKS_DIR="$GAME_DIR/modpacks"
WORLDS_DIR="$GAME_DIR/saves"
INSTANCES_DIR="$GAME_DIR/instances"
VERSIONS_DIR="$GAME_DIR/versions"

if [[ -t 1 ]]; then
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    BLUE='\033[34m'
    MAGENTA='\033[35m'
    CYAN='\033[36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    BOLD=''
    DIM=''
    RESET=''
fi


die() {
    echo -e "${RED}Error:${RESET} $*" >&2
    exit 1
}


human_size() {
    local bytes="${1:-0}"

    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "Unknown"
        return
    fi

    if (( bytes < 1024 )); then
        echo "${bytes} B"
    elif (( bytes < 1024 * 1024 )); then
        awk "BEGIN {printf \"%.1f KiB\", $bytes / 1024}"
    elif (( bytes < 1024 * 1024 * 1024 )); then
        awk "BEGIN {printf \"%.1f MiB\", $bytes / 1024 / 1024}"
    else
        awk "BEGIN {printf \"%.2f GiB\", $bytes / 1024 / 1024 / 1024}"
    fi
}


directory_size() {
    local dir="$1"

    [[ -d "$dir" ]] || {
        echo 0
        return
    }

    du -sb "$dir" 2>/dev/null | awk '{print $1}'
}


print_header() {
    local title="$1"

    echo
    echo -e "${BOLD}${CYAN}$title${RESET}"
    printf '%*s\n' 72 '' | tr ' ' '─'
}


list_files() {
    local title="$1"
    local directory="$2"
    local extension_filter="${3:-}"

    print_header "$title"

    if [[ ! -d "$directory" ]]; then
        echo -e "  ${YELLOW}Not installed / directory does not exist.${RESET}"
        echo
        return
    fi

    shopt -s nullglob

    local files=("$directory"/*)
    local found=0
    local number=0

    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue

        if [[ -n "$extension_filter" ]]; then
            [[ "${file,,}" == *"$extension_filter" ]] || continue
        fi

        ((number++))
        ((found++))

        local name
        name="$(basename "$file")"

        local size
        size="$(human_size "$(stat -c%s "$file" 2>/dev/null || echo 0)")"

        echo -e "  ${GREEN}$number)${RESET} ${BOLD}$name${RESET}"
        echo "     Size: $size"
    done

    if (( found == 0 )); then
        echo "  Nothing installed."
    else
        echo
        echo "  Total: $found"
        echo "  Size:  $(human_size "$(directory_size "$directory")")"
    fi

    echo
}


list_directories() {
    local title="$1"
    local directory="$2"

    print_header "$title"

    if [[ ! -d "$directory" ]]; then
        echo -e "  ${YELLOW}Not installed / directory does not exist.${RESET}"
        echo
        return
    fi

    shopt -s nullglob

    local dirs=("$directory"/*)
    local found=0
    local number=0

    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue

        ((number++))
        ((found++))

        local name
        name="$(basename "$dir")"

        local size
        size="$(human_size "$(directory_size "$dir")")"

        echo -e "  ${GREEN}$number)${RESET} ${BOLD}$name${RESET}"
        echo "     Size: $size"
    done

    if (( found == 0 )); then
        echo "  Nothing installed."
    else
        echo
        echo "  Total: $found"
        echo "  Size:  $(human_size "$(directory_size "$directory")")"
    fi

    echo
}


list_versions() {
    print_header "Installed Minecraft Versions"

    if [[ ! -d "$VERSIONS_DIR" ]]; then
        echo "  No Minecraft versions installed."
        echo
        return
    fi

    shopt -s nullglob

    local dirs=("$VERSIONS_DIR"/*)
    local found=0
    local number=0

    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue

        ((number++))
        ((found++))

        local name
        name="$(basename "$dir")"

        local jar="$dir/$name.jar"
        local json="$dir/$name.json"

        if [[ -f "$jar" && -f "$json" ]]; then
            echo -e "  ${GREEN}$number)${RESET} ${BOLD}$name${RESET} ${GREEN}✓${RESET}"
        elif [[ -d "$dir" ]]; then
            echo -e "  ${YELLOW}$number)${RESET} ${BOLD}$name${RESET} ${YELLOW}! incomplete${RESET}"
        fi

        if [[ -f "$jar" ]]; then
            echo "     JAR: $(human_size "$(stat -c%s "$jar" 2>/dev/null || echo 0)")"
        fi
    done

    if (( found == 0 )); then
        echo "  No Minecraft versions installed."
    else
        echo
        echo "  Total: $found"
    fi

    echo
}


list_all() {
    echo
    echo -e "${BOLD}${CYAN}Minecraft Installation${RESET}"
    echo
    echo "  Game directory:"
    echo "    $GAME_DIR"

    list_versions

    list_files "Installed Mods" "$MODS_DIR" ".jar"

    list_files "Installed Shaders" "$SHADERS_DIR"

    list_files "Installed Resourcepacks" "$RESOURCEPACKS_DIR"

    list_files "Installed Modpacks" "$MODPACKS_DIR"

    list_directories "Minecraft Worlds" "$WORLDS_DIR"

    list_directories "Minecraft Instances" "$INSTANCES_DIR"
}


show_help() {
    cat <<EOF
Usage:

  mc list
  mc list all

  mc list mods
  mc list shaders
  mc list resourcepacks
  mc list modpacks
  mc list worlds
  mc list instances
  mc list versions

Commands:

  all
      List everything installed.

  mods
      List installed mods.

  shaders
      List installed shaderpacks.

  resourcepacks
      List installed resourcepacks.

  modpacks
      List installed modpacks.

  worlds
      List Minecraft worlds.

  instances
      List launcher instances.

  versions
      List installed Minecraft versions.

Examples:

  mc list
  mc list mods
  mc list versions
  mc list worlds
  mc list shaders
EOF
}


main() {
    local type="${1:-all}"

    case "$type" in
        all)
            list_all
            ;;

        mods|mod)
            list_files "Installed Mods" "$MODS_DIR" ".jar"
            ;;

        shaders|shader)
            list_files "Installed Shaders" "$SHADERS_DIR"
            ;;

        resourcepacks|resourcepack|resources)
            list_files "Installed Resourcepacks" "$RESOURCEPACKS_DIR"
            ;;

        modpacks|modpack)
            list_files "Installed Modpacks" "$MODPACKS_DIR"
            ;;

        worlds|world)
            list_directories "Minecraft Worlds" "$WORLDS_DIR"
            ;;

        instances|instance)
            list_directories "Minecraft Instances" "$INSTANCES_DIR"
            ;;

        versions|version)
            list_versions
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            die "Unknown list type '$type'. Try 'mc list --help'."
            ;;
    esac
}


main "$@"