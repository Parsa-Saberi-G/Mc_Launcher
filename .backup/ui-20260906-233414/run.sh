#!/bin/bash

set -o pipefail

MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"
VERSIONS_DIR="$GAME_DIR/versions"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mc"
CONFIG_FILE="$CONFIG_DIR/config"

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


die() {
    echo -e "${RED}Error:${RESET} $*" >&2
    exit 1
}


warn() {
    echo -e "${YELLOW}Warning:${RESET} $*" >&2
}


get_config() {
    local key="$1"

    [[ -f "$CONFIG_FILE" ]] || return 0

    grep -E "^${key}=" "$CONFIG_FILE" |
        head -n1 |
        cut -d= -f2-
}


human_name() {
    echo "$1"
}


find_version() {
    local requested="$1"

    if [[ -d "$VERSIONS_DIR/$requested" ]]; then
        echo "$requested"
        return 0
    fi

    die "Minecraft version '$requested' is not installed."
}


show_versions() {
    if [[ ! -d "$VERSIONS_DIR" ]]; then
        die "No Minecraft versions are installed."
    fi

    shopt -s nullglob

    local dirs=("$VERSIONS_DIR"/*)
    local matches=()

    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue

        local name
        name="$(basename "$dir")"

        [[ -f "$dir/$name.json" ]] ||
            continue

        matches+=("$name")
    done

    if (( ${#matches[@]} == 0 )); then
        die "No usable Minecraft versions found."
    fi

    echo
    echo -e "${BOLD}${CYAN}Installed versions${RESET}"
    echo

    local i=0

    for version in "${matches[@]}"; do
        ((i++))
        echo -e "  ${GREEN}${i})${RESET} ${BOLD}$version${RESET}"
    done

    echo
    echo -e "  ${RED}0)${RESET} Cancel"
    echo

    local selection

    while true; do
        read -r -p "Select version [1-${#matches[@]}]: " selection

        if [[ "$selection" == "0" ]]; then
            exit 0
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= ${#matches[@]} )); then

            echo "${matches[$((selection - 1))]}"
            return
        fi

        echo -e "${RED}Invalid selection.${RESET}"
    done
}


parse_arguments() {
    JAVA_PATH=""
    MIN_MEMORY=""
    MAX_MEMORY=""
    JAVA_ARGS=""
    GAME_ARGS=""
    VERSION=""
    GAME_DIR_OVERRIDE=""
    TYPE=""
    NAME=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --java)
                [[ -n "${2:-}" ]] ||
                    die "--java requires a path."

                JAVA_PATH="$2"
                shift 2
                ;;

            --min-memory)
                [[ -n "${2:-}" ]] ||
                    die "--min-memory requires a value."

                MIN_MEMORY="$2"
                shift 2
                ;;

            --max-memory)
                [[ -n "${2:-}" ]] ||
                    die "--max-memory requires a value."

                MAX_MEMORY="$2"
                shift 2
                ;;

            --java-args)
                [[ -n "${2:-}" ]] ||
                    die "--java-args requires a value."

                JAVA_ARGS="$2"
                shift 2
                ;;

            --game-args)
                [[ -n "${2:-}" ]] ||
                    die "--game-args requires a value."

                GAME_ARGS="$2"
                shift 2
                ;;

            --game-dir)
                [[ -n "${2:-}" ]] ||
                    die "--game-dir requires a path."

                GAME_DIR_OVERRIDE="$2"
                shift 2
                ;;

            version)
                TYPE="version"
                VERSION="${2:-}"
                shift

                [[ -n "$VERSION" ]] && shift
                ;;

            modpack)
                TYPE="modpack"
                NAME="${2:-}"
                shift

                [[ -n "$NAME" ]] && shift
                ;;

            instance)
                TYPE="instance"
                NAME="${2:-}"
                shift

                [[ -n "$NAME" ]] && shift
                ;;

            --help|-h)
                show_help
                exit 0
                ;;

            *)
                if [[ -z "$TYPE" && -z "$VERSION" ]]; then
                    VERSION="$1"
                    shift
                else
                    die "Unknown option '$1'."
                fi
                ;;
        esac
    done
}


build_classpath() {
    local version="$1"

    local version_dir="$GAME_DIR/versions/$version"
    local version_json="$version_dir/$version.json"

    [[ -f "$version_json" ]] ||
        die "Version metadata not found: $version_json"

    if ! command -v jq >/dev/null 2>&1; then
        die "jq is required to build the Minecraft classpath."
    fi

    local libraries

    libraries="$(
        jq -r '
            .libraries[]?.downloads.artifact.path // empty
        ' "$version_json"
    )"

    local classpath=""

    while IFS= read -r library; do
        [[ -n "$library" ]] || continue

        local full_path="$GAME_DIR/libraries/$library"

        if [[ ! -f "$full_path" ]]; then
            warn "Missing library:"
            echo "  $full_path"
            continue
        fi

        if [[ -z "$classpath" ]]; then
            classpath="$full_path"
        else
            classpath="$classpath:$full_path"
        fi
    done <<< "$libraries"

    local client_jar="$version_dir/$version.jar"

    [[ -f "$client_jar" ]] ||
        die "Minecraft client JAR not found: $client_jar"

    if [[ -z "$classpath" ]]; then
        classpath="$client_jar"
    else
        classpath="$classpath:$client_jar"
    fi

    printf '%s' "$classpath"
}


launch_version() {
    local version="$1"

    version="$(find_version "$version")"

    local version_dir="$VERSIONS_DIR/$version"
    local version_json="$version_dir/$version.json"
    local client_jar="$version_dir/$version.jar"

    [[ -f "$version_json" ]] ||
        die "Version JSON is missing."

    [[ -f "$client_jar" ]] ||
        die "Client JAR is missing."

    local java
    java="${JAVA_PATH:-$(get_config java)}"

    if [[ -z "$java" ]]; then
        java="$(command -v java || true)"
    fi

    [[ -n "$java" ]] ||
        die "Java was not found."

    [[ -x "$java" ]] ||
        die "Java executable is not executable: $java"

    local min_memory
    min_memory="${MIN_MEMORY:-$(get_config min_memory)}"

    local max_memory
    max_memory="${MAX_MEMORY:-$(get_config max_memory)}"

    min_memory="${min_memory:-1G}"
    max_memory="${max_memory:-4G}"

    local configured_java_args
    configured_java_args="$(get_config java_args)"

    local configured_game_args
    configured_game_args="$(get_config game_args)"

    local game_dir
    game_dir="${GAME_DIR_OVERRIDE:-$(get_config game_dir)}"

    game_dir="${game_dir:-$GAME_DIR}"

    mkdir -p "$game_dir"

    echo
    echo -e "${BOLD}${CYAN}Launching Minecraft${RESET}"
    echo
    echo "  Version: $version"
    echo "  Java:    $java"
    echo "  Memory:  $min_memory → $max_memory"
    echo "  Game:    $game_dir"
    echo

    local classpath
    classpath="$(build_classpath "$version")"

    echo -e "${YELLOW}Notice:${RESET}"
    echo "The full authentication/argument system is still being built."
    echo

    local main_class

    main_class="$(
        jq -r '.mainClass // empty' "$version_json"
    )"

    [[ -n "$main_class" ]] ||
        die "mainClass is missing from version metadata."

    echo "Main class: $main_class"
    echo

    read -r -p "Launch with the currently available metadata? [y/N]: " answer

    case "${answer,,}" in
        y|yes)
            ;;
        *)
            echo "Cancelled."
            return 0
            ;;
    esac

    cd "$game_dir" ||
        die "Could not enter game directory."

    # shellcheck disable=SC2086
    "$java" \
        "-Xms$min_memory" \
        "-Xmx$max_memory" \
        $configured_java_args \
        $JAVA_ARGS \
        -cp "$classpath" \
        "$main_class" \
        $configured_game_args \
        $GAME_ARGS
}


show_help() {
    cat <<EOF

Usage:

  mc run
  mc run version <version>
  mc run modpack <name>
  mc run instance <name>

Options:

  --java PATH
  --min-memory SIZE
  --max-memory SIZE
  --java-args ARGS
  --game-args ARGS
  --game-dir PATH

Examples:

  mc run
  mc run version 1.21.8
  mc run version 1.21.8 --max-memory 6G

EOF
}


main() {
    parse_arguments "$@"

    if [[ -z "$VERSION" ]]; then
        VERSION="$(show_versions)"
    fi

    launch_version "$VERSION"
}


main "$@"