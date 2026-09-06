#!/bin/bash

# ============================================================
# MC LAUNCHER — SHARED UI
# ============================================================

# Avoid loading twice
[[ "${MC_UI_LOADED:-0}" == "1" ]] && return 0
MC_UI_LOADED=1

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

if [[ -t 2 ]]; then
    MC_RED='\033[31m'
    MC_GREEN='\033[32m'
    MC_YELLOW='\033[33m'
    MC_BLUE='\033[34m'
    MC_MAGENTA='\033[35m'
    MC_CYAN='\033[36m'
    MC_WHITE='\033[37m'
    MC_BOLD='\033[1m'
    MC_DIM='\033[2m'
    MC_RESET='\033[0m'
else
    MC_RED=''
    MC_GREEN=''
    MC_YELLOW=''
    MC_BLUE=''
    MC_MAGENTA=''
    MC_CYAN=''
    MC_WHITE=''
    MC_BOLD=''
    MC_DIM=''
    MC_RESET=''
fi

# ------------------------------------------------------------
# Optional Wallust integration
# ------------------------------------------------------------

MC_WALLUST_COLORS="${MC_WALLUST_COLORS:-$HOME/.cache/wallust/colors}"

if [[ -f "$MC_WALLUST_COLORS" ]]; then
    # Read simple key=value Wallust palettes if available.
    # Never fail the launcher because a theme file is malformed.
    while IFS='=' read -r key value; do
        case "$key" in
            color1|color2|color3|color4|color5|color6|color7)
                [[ "$value" =~ ^#?[0-9a-fA-F]{6}$ ]] || continue
                ;;
        esac
    done < "$MC_WALLUST_COLORS" 2>/dev/null || true
fi

# ------------------------------------------------------------
# Logo
# ------------------------------------------------------------

mc_logo() {
    printf '\n'
    printf '%b╭──────────────────────────────────────────────╮%b\n' \
        "$MC_CYAN" "$MC_RESET"
    printf '%b│%b  %bmc%b  %b— Minecraft command-line launcher%b  %b│%b\n' \
        "$MC_CYAN" "$MC_RESET" \
        "$MC_BOLD" "$MC_RESET" \
        "$MC_DIM" "$MC_RESET" \
        "$MC_CYAN" "$MC_RESET"
    printf '%b╰──────────────────────────────────────────────╯%b\n' \
        "$MC_CYAN" "$MC_RESET"
    printf '\n'
}

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

mc_info() {
    printf '  %b●%b %s\n' \
        "$MC_CYAN" "$MC_RESET" "$*" >&2
}

mc_step() {
    printf '  %b●%b %s\n' \
        "$MC_BLUE" "$MC_RESET" "$*" >&2
}

mc_ok() {
    printf '  %b✓%b %s\n' \
        "$MC_GREEN" "$MC_RESET" "$*" >&2
}

mc_warn() {
    printf '  %b⚠%b %s\n' \
        "$MC_YELLOW" "$MC_RESET" "$*" >&2
}

mc_error() {
    printf '  %b✗%b %s\n' \
        "$MC_RED" "$MC_RESET" "$*" >&2
}

mc_debug() {
    [[ "${MC_DEBUG:-0}" == "1" ]] || return 0

    printf '  %b·%b %s\n' \
        "$MC_DIM" "$MC_RESET" "$*" >&2
}

# ------------------------------------------------------------
# Section
# ------------------------------------------------------------

mc_section() {
    printf '\n%b%s%b\n' \
        "$MC_BOLD" "$*" "$MC_RESET" >&2
}

# ------------------------------------------------------------
# Progress bar
# ------------------------------------------------------------

mc_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-Processing}"

    [[ "$total" =~ ^[0-9]+$ ]] || return 0
    (( total > 0 )) || return 0
    [[ "$current" =~ ^[0-9]+$ ]] || return 0

    local width=30
    local percent=$((current * 100 / total))

    (( percent > 100 )) && percent=100
    (( percent < 0 )) && percent=0

    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    local bar=""
    local i

    for ((i=0; i<filled; i++)); do
        bar+="█"
    done

    for ((i=0; i<empty; i++)); do
        bar+="░"
    done

    printf '\r  %b%s%b [%s] %3d%%' \
        "$MC_CYAN" \
        "$label" \
        "$MC_RESET" \
        "$bar" \
        "$percent" >&2

    if (( percent >= 100 )); then
        printf '\n' >&2
    fi
}

# ------------------------------------------------------------
# Spinner
# ------------------------------------------------------------

MC_SPINNER_PID=""

mc_spinner_start() {
    local message="${1:-Working}"

    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0

        while true; do
            printf '\r  %b%s%b %s' \
                "$MC_CYAN" \
                "${frames[i]}" \
                "$MC_RESET" \
                "$message" >&2

            i=$(( (i + 1) % ${#frames[@]} ))
            sleep 0.08
        done
    ) &

    MC_SPINNER_PID=$!
}

mc_spinner_stop() {
    if [[ -n "${MC_SPINNER_PID:-}" ]]; then
        kill "$MC_SPINNER_PID" 2>/dev/null || true
        wait "$MC_SPINNER_PID" 2>/dev/null || true
        MC_SPINNER_PID=""
        printf '\r\033[2K' >&2
    fi
}

# ------------------------------------------------------------
# Command wrapper
# ------------------------------------------------------------

mc_run_step() {
    local label="$1"
    shift

    mc_info "$label"

    "$@"
    local status=$?

    if (( status == 0 )); then
        mc_ok "$label"
    else
        mc_error "$label failed"
    fi

    return "$status"
}

# ------------------------------------------------------------
# Download progress using curl
# ------------------------------------------------------------

mc_download() {
    local url="$1"
    local output="$2"
    local label="${3:-Downloading}"

    curl \
        --fail \
        --location \
        --connect-timeout 10 \
        --max-time 300 \
        --progress-bar \
        -H "User-Agent: mc-launcher/0.1.0" \
        -o "$output" \
        "$url"

    local status=$?

    if (( status == 0 )); then
        mc_ok "$label"
    else
        mc_error "$label failed"
    fi

    return "$status"
}

# ------------------------------------------------------------
# Completion
# ------------------------------------------------------------

mc_done() {
    printf '\n%b✓ %s%b\n\n' \
        "$MC_GREEN" \
        "$*" \
        "$MC_RESET" >&2
}

# ------------------------------------------------------------
# Failure
# ------------------------------------------------------------

mc_fail() {
    printf '\n%b✗ %s%b\n\n' \
        "$MC_RED" \
        "$*" \
        "$MC_RESET" >&2
}

