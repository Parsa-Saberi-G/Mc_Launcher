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


get_directory() {
    local type="$1"

    case "$type" in
        mod|mods)
            echo "$MODS_DIR"
            ;;

        shader|shaders)
            echo "$SHADERS_DIR"
            ;;

        resourcepack|resourcepacks)
            echo "$RESOURCEPACKS_DIR"
            ;;

        modpack|modpacks)
            echo "$MODPACKS_DIR"
            ;;

        world|worlds)
            echo "$WORLDS_DIR"
            ;;

        instance|instances)
            echo "$INSTANCES_DIR"
            ;;

        version|versions)
            echo "$VERSIONS_DIR"
            ;;

        *)
            return 1
            ;;
    esac
}


normalize_query() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]'
}


show_result() {
    local number="$1"
    local name="$2"
    local path="$3"
    local type="$4"

    echo
    echo -e "  ${GREEN}${number})${RESET} ${BOLD}${name}${RESET}"
    echo -e "     Type: ${type}"
    echo -e "     Path: ${DIM}${path}${RESET}"
}


search_files() {
    local type="$1"
    local query="$2"
    local directory="$3"

    [[ -d "$directory" ]] ||
        die "No installed $type directory exists."

    shopt -s nullglob

    local entries=("$directory"/*)
    local matches=()

    local normalized_query
    normalized_query="$(normalize_query "$query")"

    for entry in "${entries[@]}"; do
        local name
        name="$(basename "$entry")"

        local normalized_name
        normalized_name="$(normalize_query "$name")"

        if [[ -z "$normalized_query" ||
              "$normalized_name" == *"$normalized_query"* ]]; then
            matches+=("$entry")
        fi
    done

    if (( ${#matches[@]} == 0 )); then
        if [[ -n "$query" ]]; then
            die "No installed $type matching '$query' found."
        fi

        die "No installed $type found."
    fi

    echo
    echo -e "${BOLD}${CYAN}Search results${RESET}"
    echo
    echo -e "  Query: ${BOLD}${query:-*}${RESET}"
    echo -e "  Type:  ${type}"
    echo

    local i=0

    for entry in "${matches[@]}"; do
        ((i++))

        local name
        name="$(basename "$entry")"

        show_result "$i" "$name" "$entry" "$type"
    done

    echo
    echo -e "  ${RED}0)${RESET} Cancel"
    echo

    local selection

    while true; do
        read -r -p "Select result [1-${#matches[@]}, 0 to cancel]: " selection

        if [[ "$selection" == "0" ]]; then
            echo "Cancelled."
            return 0
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= ${#matches[@]} )); then

            local selected
            selected="${matches[$((selection - 1))]}"

            echo
            echo -e "${BOLD}${CYAN}Selected:${RESET}"
            echo "  $(basename "$selected")"
            echo "  $selected"
            echo

            return 0
        fi

        echo -e "${RED}Invalid selection.${RESET}"
    done
}


search_versions() {
    local query="$1"

    if [[ ! -d "$VERSIONS_DIR" ]]; then
        die "No installed Minecraft versions found."
    fi

    shopt -s nullglob

    local dirs=("$VERSIONS_DIR"/*)
    local matches=()

    local normalized_query
    normalized_query="$(normalize_query "$query")"

    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue

        local name
        name="$(basename "$dir")"

        local normalized_name
        normalized_name="$(normalize_query "$name")"

        if [[ -z "$normalized_query" ||
              "$normalized_name" == *"$normalized_query"* ]]; then
            matches+=("$dir")
        fi
    done

    if (( ${#matches[@]} == 0 )); then
        die "No installed Minecraft version matching '$query' found."
    fi

    echo
    echo -e "${BOLD}${CYAN}Minecraft version results${RESET}"
    echo

    local i=0

    for dir in "${matches[@]}"; do
        ((i++))

        local name
        name="$(basename "$dir")"

        local jar="$dir/$name.jar"
        local json="$dir/$name.json"

        echo -e "  ${GREEN}${i})${RESET} ${BOLD}${name}${RESET}"

        if [[ -f "$jar" && -f "$json" ]]; then
            echo -e "     Status: ${GREEN}Complete ✓${RESET}"
        else
            echo -e "     Status: ${YELLOW}Incomplete !${RESET}"
        fi

        [[ -f "$jar" ]] &&
            echo "     JAR: installed"

        echo
    done

    echo -e "  ${RED}0)${RESET} Cancel"
    echo

    local selection

    while true; do
        read -r -p "Select version [1-${#matches[@]}, 0 to cancel]: " selection

        if [[ "$selection" == "0" ]]; then
            echo "Cancelled."
            return 0
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= ${#matches[@]} )); then

            local selected
            selected="${matches[$((selection - 1))]}"

            echo
            echo -e "${BOLD}${CYAN}Selected:${RESET} $(basename "$selected")"
            echo

            return 0
        fi

        echo -e "${RED}Invalid selection.${RESET}"
    done
}


show_all_search() {
    local query="$1"

    echo
    echo -e "${BOLD}${CYAN}Searching all installed Minecraft content${RESET}"
    echo -e "${DIM}Query: ${query:-*}${RESET}"
    echo

    local found=0

    search_category() {
        local label="$1"
        local directory="$2"

        [[ -d "$directory" ]] || return 0

        shopt -s nullglob

        local entries=("$directory"/*)

        for entry in "${entries[@]}"; do
            local name
            name="$(basename "$entry")"

            local lower_name
            lower_name="$(normalize_query "$name")"

            local lower_query
            lower_query="$(normalize_query "$query")"

            if [[ -z "$lower_query" ||
                  "$lower_name" == *"$lower_query"* ]]; then

                ((found++))

                echo -e "  ${GREEN}$found)${RESET} ${BOLD}$name${RESET}"
                echo "     Type: $label"
                echo "     Path: $entry"
                echo
            fi
        done
    }

    search_category "mod" "$MODS_DIR"
    search_category "shader" "$SHADERS_DIR"
    search_category "resourcepack" "$RESOURCEPACKS_DIR"
    search_category "modpack" "$MODPACKS_DIR"
    search_category "world" "$WORLDS_DIR"
    search_category "instance" "$INSTANCES_DIR"
    search_category "version" "$VERSIONS_DIR"

    if (( found == 0 )); then
        die "No installed content matching '$query' found."
    fi

    echo -e "${DIM}Found $found result(s).${RESET}"
    echo
}


show_help() {
    cat <<EOF
Usage:

  mc find <type> [query]
  mc find [query]

Searches installed/local content only.

Types:

  mod
  shader
  resourcepack
  modpack
  world
  instance
  version

Examples:

  mc find mod sodium
  mc find mod
  mc find shader complementary
  mc find resourcepack faithful
  mc find modpack
  mc find world survival
  mc find version 1.21
  mc find sodium

Difference:

  mc find
      Searches locally installed content.

  mc search
      Searches online repositories such as Modrinth.
EOF
}


main() {
    local first="${1:-}"

    case "$first" in
        help|--help|-h)
            show_help
            return
            ;;

        mod|mods|shader|shaders|resourcepack|resourcepacks|modpack|modpacks|world|worlds|instance|instances|version|versions)
            local type="$first"
            shift

            local query="$*"
            local directory

            directory="$(get_directory "$type")" ||
                die "Unknown find type '$type'."

            case "$type" in
                version|versions)
                    search_versions "$query"
                    ;;
                *)
                    search_files "$type" "$query" "$directory"
                    ;;
            esac
            ;;

        "")
            show_all_search ""
            ;;

        *)
            show_all_search "$*"
            ;;
    esac
}


main "$@"