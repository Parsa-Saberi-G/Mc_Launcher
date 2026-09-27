#!/bin/bash

set -o pipefail

MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"
DATA_DIR="$MC_DIR/data"
VERSIONS_DB="$DATA_DIR/versions.json"

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
    WHITE='\033[37m'
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
    WHITE=''
    BOLD=''
    DIM=''
    RESET=''
fi


die() {
    echo -e "${RED}Error:${RESET} $*" >&2
    exit 1
}


warn() {
    echo -e "${YELLOW}Warning:${RESET} $*" >&2
}


line() {
    printf '%*s\n' 64 '' | tr ' ' '─'
}


section() {
    echo
    echo -e "${BOLD}${CYAN}$1${RESET}"
    line
}


require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command '$1' is not installed."
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


count_files() {
    local dir="$1"

    [[ -d "$dir" ]] || {
        echo 0
        return
    }

    find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l
}


count_directories() {
    local dir="$1"

    [[ -d "$dir" ]] || {
        echo 0
        return
    }

    find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l
}


directory_size() {
    local dir="$1"

    [[ -d "$dir" ]] || {
        echo 0
        return
    }

    du -sb "$dir" 2>/dev/null | awk '{print $1}'
}


get_mod_loader() {
    local file="$1"
    local name

    name="$(basename "$file" | tr '[:upper:]' '[:lower:]')"

    case "$name" in
        *fabric*)
            echo "Fabric"
            ;;
        *quilt*)
            echo "Quilt"
            ;;
        *forge*)
            echo "Forge"
            ;;
        *neoforge*)
            echo "NeoForge"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}


show_general_info() {
    require_command jq

    echo
    echo -e "${BOLD}${CYAN}Minecraft Launcher${RESET}"
    echo

    echo -e "${BOLD}Launcher:${RESET}"
    echo "  Name:       mc"
    echo "  Version:    0.1.0"
    echo "  Project:    $MC_DIR"
    echo "  Game dir:   $GAME_DIR"

    section "Minecraft Installation"

    if [[ -d "$GAME_DIR" ]]; then
        echo -e "  Status:     ${GREEN}Installed${RESET}"
    else
        echo -e "  Status:     ${YELLOW}Not initialized${RESET}"
    fi

    echo "  Versions:   $(count_directories "$VERSIONS_DIR")"
    echo "  Mods:       $(count_files "$MODS_DIR")"
    echo "  Shaders:    $(count_files "$SHADERS_DIR")"
    echo "  Resourcepacks: $(count_files "$RESOURCEPACKS_DIR")"
    echo "  Modpacks:   $(count_files "$MODPACKS_DIR")"
    echo "  Worlds:     $(count_directories "$WORLDS_DIR")"
    echo "  Instances:  $(count_directories "$INSTANCES_DIR")"

    section "Disk Usage"

    echo "  Minecraft:  $(human_size "$(directory_size "$GAME_DIR")")"

    if [[ -d "$MODS_DIR" ]]; then
        echo "  Mods:       $(human_size "$(directory_size "$MODS_DIR")")"
    fi

    if [[ -d "$SHADERS_DIR" ]]; then
        echo "  Shaders:    $(human_size "$(directory_size "$SHADERS_DIR")")"
    fi

    if [[ -d "$RESOURCEPACKS_DIR" ]]; then
        echo "  Resources:  $(human_size "$(directory_size "$RESOURCEPACKS_DIR")")"
    fi

    section "Database"

    if [[ -f "$VERSIONS_DB" ]]; then
        local versions
        versions="$(jq '.versions | length' "$VERSIONS_DB" 2>/dev/null || echo 0)"

        local release
        release="$(jq -r '.latest.release // "Unknown"' "$VERSIONS_DB" 2>/dev/null)"

        local snapshot
        snapshot="$(jq -r '.latest.snapshot // "Unknown"' "$VERSIONS_DB" 2>/dev/null)"

        echo -e "  Status:     ${GREEN}Available${RESET}"
        echo "  Versions:   $versions"
        echo "  Release:    $release"
        echo "  Snapshot:   $snapshot"
        echo "  File:       $VERSIONS_DB"
    else
        echo -e "  Status:     ${YELLOW}Missing${RESET}"
        echo "  Run:        mc update database"
    fi

    section "Java"

    if command -v java >/dev/null 2>&1; then
        local java_version
        java_version="$(java -version 2>&1 | head -n 1)"

        echo -e "  Status:     ${GREEN}Available${RESET}"
        echo "  Version:    $java_version"
        echo "  Binary:     $(command -v java)"
    else
        echo -e "  Status:     ${RED}Not found${RESET}"
        echo "  Install a compatible Java runtime to launch Minecraft."
    fi

    section "Environment"

    echo "  OS:         $(uname -s)"
    echo "  Kernel:     $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo "  Shell:      ${SHELL:-Unknown}"

    echo
}


show_java_info() {
    echo
    echo -e "${BOLD}${CYAN}Java Information${RESET}"
    line

    if ! command -v java >/dev/null 2>&1; then
        echo -e "  Status: ${RED}Java not found${RESET}"
        echo
        return 1
    fi

    echo -e "  Binary:     $(command -v java)"

    echo
    echo -e "${BOLD}Version:${RESET}"
    java -version 2>&1

    echo
    echo -e "${BOLD}JAVA_HOME:${RESET}"
    if [[ -n "${JAVA_HOME:-}" ]]; then
        echo "  $JAVA_HOME"
    else
        echo "  Not set"
    fi

    echo
}


show_version_info() {
    require_command jq

    local version="${1:-}"

    [[ -f "$VERSIONS_DB" ]] ||
        die "Version database not found. Run 'mc update database' first."

    if [[ -z "$version" ]]; then
        echo
        echo -e "${BOLD}${CYAN}Minecraft Versions${RESET}"
        line

        local latest_release
        latest_release="$(jq -r '.latest.release // "Unknown"' "$VERSIONS_DB")"

        local latest_snapshot
        latest_snapshot="$(jq -r '.latest.snapshot // "Unknown"' "$VERSIONS_DB")"

        local release_count
        release_count="$(
            jq '[.versions[] | select(.type == "release")] | length' \
                "$VERSIONS_DB"
        )"

        local snapshot_count
        snapshot_count="$(
            jq '[.versions[] | select(.type == "snapshot")] | length' \
                "$VERSIONS_DB"
        )"

        echo "  Latest release:  $latest_release"
        echo "  Latest snapshot: $latest_snapshot"
        echo "  Releases:        $release_count"
        echo "  Snapshots:       $snapshot_count"
        echo

        echo "Use:"
        echo "  mc info version <version>"
        echo

        return
    fi

    local data

    data="$(
        jq -c \
            --arg version "$version" \
            '.versions[] | select(.id == $version)' \
            "$VERSIONS_DB"
    )"

    if [[ -z "$data" ]]; then
        die "Minecraft version '$version' was not found in the database."
    fi

    echo
    echo -e "${BOLD}${CYAN}Minecraft $version${RESET}"
    line

    local type
    type="$(jq -r '.type // "unknown"' <<<"$data")"

    local release_time
    release_time="$(jq -r '.releaseTime // "Unknown"' <<<"$data")"

    local url
    url="$(jq -r '.url // "Unknown"' <<<"$data")"

    echo "  ID:           $version"
    echo "  Type:         $type"
    echo "  Release time: $release_time"
    echo "  Metadata:     $url"

    local installed_dir="$VERSIONS_DIR/$version"

    section "Local Installation"

    if [[ -d "$installed_dir" ]]; then
        echo -e "  Status:       ${GREEN}Installed${RESET}"

        local jar="$installed_dir/$version.jar"
        local json="$installed_dir/$version.json"

        [[ -f "$jar" ]] &&
            echo "  JAR:          $(human_size "$(stat -c%s "$jar" 2>/dev/null || echo 0)")"

        [[ -f "$json" ]] &&
            echo "  Metadata:     Present"
    else
        echo -e "  Status:       ${YELLOW}Not installed${RESET}"
        echo
        echo "Install with:"
        echo "  mc install version $version"
    fi

    echo
}


show_mod_info() {
    local query="${1:-}"

    [[ -d "$MODS_DIR" ]] ||
        die "Mods directory does not exist."

    shopt -s nullglob

    local files=("$MODS_DIR"/*)

    if (( ${#files[@]} == 0 )); then
        echo "No mods installed."
        return
    fi

    local matches=()

    for file in "${files[@]}"; do
        [[ -f "$file" ]] || continue

        local name
        name="$(basename "$file")"

        if [[ -z "$query" || "${name,,}" == *"${query,,}"* ]]; then
            matches+=("$file")
        fi
    done

    if (( ${#matches[@]} == 0 )); then
        die "No installed mod matching '$query' found."
    fi

    echo
    echo -e "${BOLD}${CYAN}Installed Mods${RESET}"
    line

    for file in "${matches[@]}"; do
        local name
        name="$(basename "$file")"

        local size
        size="$(human_size "$(stat -c%s "$file" 2>/dev/null || echo 0)")"

        local loader
        loader="$(get_mod_loader "$file")"

        echo
        echo -e "${BOLD}${GREEN}$name${RESET}"
        echo "  Loader: $loader"
        echo "  Size:   $size"
        echo "  Path:   $file"
    done

    echo
}


show_world_info() {
    local query="${1:-}"

    [[ -d "$WORLDS_DIR" ]] ||
        die "Worlds directory does not exist."

    shopt -s nullglob

    local worlds=("$WORLDS_DIR"/*)

    if (( ${#worlds[@]} == 0 )); then
        echo "No worlds installed."
        return
    fi

    echo
    echo -e "${BOLD}${CYAN}Minecraft Worlds${RESET}"
    line

    local found=0

    for world in "${worlds[@]}"; do
        [[ -d "$world" ]] || continue

        local name
        name="$(basename "$world")"

        if [[ -n "$query" &&
              "${name,,}" != *"${query,,}"* ]]; then
            continue
        fi

        found=1

        local level="$world/level.dat"

        echo
        echo -e "${BOLD}${GREEN}$name${RESET}"

        if [[ -f "$level" ]]; then
            echo "  level.dat: Present"
        else
            echo "  level.dat: Missing"
        fi

        echo "  Size: $(human_size "$(directory_size "$world")")"
        echo "  Path: $world"
    done

    (( found == 1 )) ||
        die "No installed world matching '$query' found."

    echo
}


show_installed_versions() {
    echo
    echo -e "${BOLD}${CYAN}Installed Minecraft Versions${RESET}"
    line

    if [[ ! -d "$VERSIONS_DIR" ]]; then
        echo "No versions installed."
        return
    fi

    shopt -s nullglob

    local dirs=("$VERSIONS_DIR"/*)
    local count=0

    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue

        local name
        name="$(basename "$dir")"

        local jar="$dir/$name.jar"

        if [[ -f "$jar" ]]; then
            echo -e "  ${GREEN}✓${RESET} $name"
        else
            echo -e "  ${YELLOW}!${RESET} $name ${DIM}(incomplete)${RESET}"
        fi

        ((count++))
    done

    if (( count == 0 )); then
        echo "No Minecraft versions installed."
    fi

    echo
}


show_content_summary() {
    echo
    echo -e "${BOLD}${CYAN}Installed Content${RESET}"
    line

    printf "  %-18s %s\n" "Mods:" "$(count_files "$MODS_DIR")"
    printf "  %-18s %s\n" "Shaders:" "$(count_files "$SHADERS_DIR")"
    printf "  %-18s %s\n" "Resourcepacks:" "$(count_files "$RESOURCEPACKS_DIR")"
    printf "  %-18s %s\n" "Modpacks:" "$(count_files "$MODPACKS_DIR")"
    printf "  %-18s %s\n" "Worlds:" "$(count_directories "$WORLDS_DIR")"
    printf "  %-18s %s\n" "Instances:" "$(count_directories "$INSTANCES_DIR")"
    printf "  %-18s %s\n" "Versions:" "$(count_directories "$VERSIONS_DIR")"

    echo
}


show_help() {
    cat <<EOF
Usage:

  mc info
  mc info java
  mc info version
  mc info version <version>
  mc info mods
  mc info mod [name]
  mc info worlds
  mc info world [name]
  mc info versions

Commands:

  info
      Show complete launcher and Minecraft information.

  java
      Show Java runtime information.

  version
      Show Minecraft version database information.

  version <version>
      Show detailed information about one Minecraft version.

  versions
      Show installed Minecraft versions.

  mod
  mods
      Show installed mods.

  mod <name>
      Show information about matching installed mods.

  world
  worlds
      Show installed worlds.

  world <name>
      Show information about a matching world.

Examples:

  mc info
  mc info java
  mc info version
  mc info version 1.21.8
  mc info mods
  mc info mod sodium
  mc info worlds
  mc info world survival
EOF
}


main() {
    local type="${1:-}"

    case "$type" in
        "")
            show_general_info
            ;;

        java)
            show_java_info
            ;;

        version)
            show_version_info "${2:-}"
            ;;

        versions)
            show_installed_versions
            ;;

        mod|mods)
            show_mod_info "${2:-}"
            ;;

        world|worlds)
            show_world_info "${2:-}"
            ;;

        summary)
            show_content_summary
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            die "Unknown info type '$type'. Try 'mc info --help'."
            ;;
    esac
}


main "$@"