#!/bin/bash

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
    echo -e "${RED}Error:${RESET} $*" >&2
    exit 1
}


success() {
    echo -e "${GREEN}✓${RESET} $*"
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
gpu=amd
EOF
    else
        # Add missing defaults to existing configs.
        grep -qE '^java=' "$CONFIG_FILE" ||
            printf '%s\n' 'java=' >> "$CONFIG_FILE"

        grep -qE '^min_memory=' "$CONFIG_FILE" ||
            printf '%s\n' 'min_memory=1G' >> "$CONFIG_FILE"

        grep -qE '^max_memory=' "$CONFIG_FILE" ||
            printf '%s\n' 'max_memory=4G' >> "$CONFIG_FILE"

        grep -qE '^java_args=' "$CONFIG_FILE" ||
            printf '%s\n' 'java_args=' >> "$CONFIG_FILE"

        grep -qE '^game_args=' "$CONFIG_FILE" ||
            printf '%s\n' 'game_args=' >> "$CONFIG_FILE"

        grep -qE '^game_dir=' "$CONFIG_FILE" ||
            printf '%s\n' "game_dir=$GAME_DIR_DEFAULT" >> "$CONFIG_FILE"

        grep -qE '^gpu=' "$CONFIG_FILE" ||
            printf '%s\n' 'gpu=amd' >> "$CONFIG_FILE"
    fi
}


get_value() {
    local key="$1"

    [[ -f "$CONFIG_FILE" ]] || return 0

    grep -E "^${key}=" "$CONFIG_FILE" |
        head -n1 |
        cut -d= -f2-
}


set_value() {
    local key="$1"
    local value="$2"

    init_config

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
    printf "  %-15s %s\n" "GPU:" "$(get_value gpu)"

    echo
}


set_java() {
    init_config

    local value="$1"

    if [[ -z "$value" ]]; then
        set_value "java" ""
        success "Java reset to automatic."
        return
    fi

    if [[ ! -x "$value" ]]; then
        die "Java executable not found or not executable: $value"
    fi

    set_value "java" "$value"
    success "Java set to: $value"
}


set_min_memory() {
    init_config

    local value="$1"

    if [[ -z "$value" ]]; then
        die "Missing memory value."
    fi

    set_value "min_memory" "$value"
    success "Minimum memory set to: $value"
}


set_max_memory() {
    init_config

    local value="$1"

    if [[ -z "$value" ]]; then
        die "Missing memory value."
    fi

    set_value "max_memory" "$value"
    success "Maximum memory set to: $value"
}


set_java_args() {
    init_config

    local value="$*"

    set_value "java_args" "$value"
    success "Java arguments updated."
}


set_game_args() {
    init_config

    local value="$*"

    set_value "game_args" "$value"
    success "Game arguments updated."
}


set_game_dir() {
    init_config

    local value="$1"

    if [[ -z "$value" ]]; then
        die "Missing game directory."
    fi

    value="${value/#\~/$HOME}"

    mkdir -p "$value" || die "Could not create game directory: $value"

    set_value "game_dir" "$value"
    success "Game directory set to: $value"
}


set_gpu() {
    init_config

    local value="${1,,}"

    case "$value" in
        amd)
            set_value "gpu" "amd"
            success "GPU set to AMD Radeon HD 7670M."
            ;;

        intel)
            set_value "gpu" "intel"
            success "GPU set to Intel HD Graphics 4000."
            ;;

        auto)
            set_value "gpu" "auto"
            success "GPU set to automatic."
            ;;

        *)
            die "Invalid GPU: $value (use amd, intel, or auto)"
            ;;
    esac
}


reset_config() {
    mkdir -p "$CONFIG_DIR"

    cat > "$CONFIG_FILE" <<EOF
java=
min_memory=1G
max_memory=4G
java_args=
game_args=
game_dir=$GAME_DIR_DEFAULT
gpu=amd
EOF

    success "Configuration reset."
}


usage() {
    cat <<EOF
Usage:
  mc config
  mc config show

  mc config set java <path>
  mc config set min-memory <value>
  mc config set max-memory <value>
  mc config set java-args <args...>
  mc config set game-args <args...>
  mc config set game-dir <path>
  mc config set gpu <amd|intel|auto>

  mc config reset

Examples:
  mc config
  mc config set gpu amd
  mc config set gpu intel
  mc config set gpu auto
  mc config set java /usr/bin/java
  mc config set max-memory 4G
EOF
}


main() {
    init_config

    local action="${1:-show}"

    case "$action" in
        show)
            show_config
            ;;

        set)
            local key="${2:-}"
            shift 2 || true

            case "$key" in
                java)
                    set_java "$1"
                    ;;

                min-memory)
                    set_min_memory "$1"
                    ;;

                max-memory)
                    set_max_memory "$1"
                    ;;

                java-args)
                    set_java_args "$@"
                    ;;

                game-args)
                    set_game_args "$@"
                    ;;

                game-dir)
                    set_game_dir "$1"
                    ;;

                gpu)
                    set_gpu "$1"
                    ;;

                *)
                    die "Unknown config key: $key"
                    ;;
            esac
            ;;

        reset)
            reset_config
            ;;

        help|-h|--help)
            usage
            ;;

        *)
            die "Unknown config command: $action"
            ;;
    esac
}


main "$@"