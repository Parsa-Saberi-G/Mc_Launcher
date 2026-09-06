#!/bin/bash
# MC Launcher shared UI
MC_COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MC_COMMAND_DIR/ui.sh"


set -o pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mc"
CONFIG_FILE="$CONFIG_DIR/config"

GAME_DIR_DEFAULT="${MC_GAME_DIR:-$HOME/.minecraft}"

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
    mc_error $*" >&2
    exit 1
}


success() {
    mc_ok $*"
}


init_config() {
    mkdir -p "$CONFIG_DIR"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" <<EOF
java=
min_memory=1G
max_memory=4G
java_args=
game_args=
game_dir=$GAME_DIR_DEFAULT
EOF
    fi
}


get_value() {
    local key="$1"

    grep -E "^${key}=" "$CONFIG_FILE" |
        head -n1 |
        cut -d= -f2-
}


set_value() {
    local key="$1"
    local value="$2"

    if grep -qE "^${key}=" "$CONFIG_FILE"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
    else
        printf '%s=%s\n' "$key" "$value" >> "$CONFIG_FILE"
    fi
}


show_config() {
    init_config

    echo
    echo -e "${BOLD}${CYAN}mc configuration${RESET}"
    echo
    echo "  Config file:"
    echo "    $CONFIG_FILE"
    echo

    printf "  %-15s %s\n" "Java:" "$(get_value java)"
    printf "  %-15s %s\n" "Min memory:" "$(get_value min_memory)"
    printf "  %-15s %s\n" "Max memory:" "$(get_value max_memory)"
    printf "  %-15s %s\n" "Java args:" "$(get_value java_args)"
    printf "  %-15s %s\n" "Game args:" "$(get_value game_args)"
    printf "  %-15s %s\n" "Game directory:" "$(get_value game_dir)"

    echo
}


set_java() {
    init_config

    local current
    current="$(get_value java)"

    echo
    echo -e "${BOLD}Java executable${RESET}"
    echo
    echo "Current: ${current:-auto}"
    echo

    read -r -p "Java path [Enter = auto]: " value

    if [[ -z "$value" ]]; then
        set_value java ""
        success "Java set to automatic detection."
        return
    fi

    if [[ ! -x "$value" ]]; then
        mc_warn '$value' is not executable."
        echo
        read -r -p "Use it anyway? [y/N]: " answer

        case "${answer,,}" in
            y|yes) ;;
            *) echo "Cancelled."; return ;;
        esac
    fi

    set_value java "$value"
    success "Java path updated."
}


set_memory() {
    init_config

    echo
    echo -e "${BOLD}Minecraft memory${RESET}"
    echo

    echo "Current minimum: $(get_value min_memory)"
    echo "Current maximum: $(get_value max_memory)"
    echo

    read -r -p "Minimum memory [$(get_value min_memory)]: " min

    if [[ -z "$min" ]]; then
        min="$(get_value min_memory)"
    fi

    read -r -p "Maximum memory [$(get_value max_memory)]: " max

    if [[ -z "$max" ]]; then
        max="$(get_value max_memory)"
    fi

    if ! [[ "$min" =~ ^[0-9]+[MG]$ ]]; then
        die "Invalid minimum memory. Use values such as 512M, 1G, 2G."
    fi

    if ! [[ "$max" =~ ^[0-9]+[MG]$ ]]; then
        die "Invalid maximum memory. Use values such as 2G, 4G, 8G."
    fi

    set_value min_memory "$min"
    set_value max_memory "$max"

    success "Memory settings updated."
}


set_game_dir() {
    init_config

    echo
    echo -e "${BOLD}Minecraft game directory${RESET}"
    echo
    echo "Current: $(get_value game_dir)"
    echo

    read -r -p "Game directory: " value

    [[ -n "$value" ]] || {
        echo "Cancelled."
        return
    }

    value="${value/#\~/$HOME}"

    mkdir -p "$value" ||
        die "Could not create '$value'."

    set_value game_dir "$value"

    success "Game directory updated."
}


set_java_args() {
    init_config

    echo
    echo -e "${BOLD}Java arguments${RESET}"
    echo
    echo "Current:"
    echo "  $(get_value java_args)"
    echo

    read -r -p "Java arguments: " value

    set_value java_args "$value"

    success "Java arguments updated."
}


set_game_args() {
    init_config

    echo
    echo -e "${BOLD}Minecraft arguments${RESET}"
    echo
    echo "Current:"
    echo "  $(get_value game_args)"
    echo

    read -r -p "Game arguments: " value

    set_value game_args "$value"

    success "Game arguments updated."
}


reset_config() {
    echo
    read -r -p "Reset all launcher settings? [y/N]: " answer

    case "${answer,,}" in
        y|yes)
            rm -f "$CONFIG_FILE"
            init_config
            success "Configuration reset."
            ;;
        *)
            echo "Cancelled."
            ;;
    esac
}


show_help() {
    cat <<EOF

Usage:

  mc config
  mc config show
  mc config java
  mc config java args
  mc config memory
  mc config game-dir
  mc config game-args
  mc config reset

EOF
}


main() {
    init_config

    case "${1:-}" in
        "")
            show_config
            ;;

        show)
            show_config
            ;;

        java)
            if [[ "${2:-}" == "args" ]]; then
                set_java_args
            else
                set_java
            fi
            ;;

        memory)
            set_memory
            ;;

        game-dir)
            set_game_dir
            ;;

        game-args)
            set_game_args
            ;;

        reset)
            reset_config
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            die "Unknown config option '$1'. Try 'mc config --help'."
            ;;
    esac
}


main "$@"