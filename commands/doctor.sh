#!/bin/bash
# MC Launcher shared UI
MC_COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MC_COMMAND_DIR/ui.sh"


set -o pipefail

MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mc"
CONFIG_FILE="$CONFIG_DIR/config"
ACCOUNTS_FILE="$CONFIG_DIR/accounts/accounts.json"
VERSIONS_DB="$MC_DIR/data/versions.json"

PASS=0
WARN=0
FAIL=0

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


pass() {
    ((PASS++))
    echo -e "  ${GREEN}✓${RESET} $*"
}


warning() {
    ((WARN++))
    echo -e "  ${YELLOW}!${RESET} $*"
}


fail() {
    ((FAIL++))
    echo -e "  ${RED}✗${RESET} $*"
}


section() {
    echo
    echo -e "${BOLD}${CYAN}$1${RESET}"
    echo "────────────────────────────────────────────────────────"
}


check_command() {
    local command="$1"
    local description="$2"

    if command -v "$command" >/dev/null 2>&1; then
        pass "$description: $(command -v "$command")"
    else
        fail "$description: not installed"
    fi
}


check_java() {
    section "Java"

    if ! command -v java >/dev/null 2>&1; then
        fail "Java is not installed."
        return
    fi

    pass "Java executable found."

    local version
    version="$(java -version 2>&1 | head -n1)"

    echo "     $version"

    if java -version 2>&1 | grep -qE '"([0-9]+)'; then
        pass "Java can be executed."
    else
        warning "Could not determine Java version."
    fi
}


check_game_directory() {
    section "Minecraft directory"

    if [[ -d "$GAME_DIR" ]]; then
        pass "Game directory exists: $GAME_DIR"
    else
        warning "Game directory does not exist: $GAME_DIR"
        echo "     It will be created when needed."
    fi

    if [[ -w "$GAME_DIR" ]]; then
        pass "Game directory is writable."
    elif [[ -d "$GAME_DIR" ]]; then
        fail "Game directory is not writable."
    fi
}


check_directories() {
    section "Minecraft directories"

    local dirs=(
        "$GAME_DIR/versions"
        "$GAME_DIR/mods"
        "$GAME_DIR/shaderpacks"
        "$GAME_DIR/resourcepacks"
        "$GAME_DIR/modpacks"
        "$GAME_DIR/saves"
        "$GAME_DIR/instances"
    )

    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            pass "$(basename "$dir")/"
        else
            warning "$(basename "$dir")/ does not exist."
        fi
    done
}


check_database() {
    section "Version database"

    if [[ ! -f "$VERSIONS_DB" ]]; then
        fail "Version database missing."
        echo "     Run: mc update database"
        return
    fi

    pass "Version database exists."

    if ! command -v jq >/dev/null 2>&1; then
        fail "jq is required to read the version database."
        return
    fi

    if jq -e . "$VERSIONS_DB" >/dev/null 2>&1; then
        pass "Version database contains valid JSON."
    else
        fail "Version database contains invalid JSON."
        return
    fi

    local count
    count="$(jq '.versions | length' "$VERSIONS_DB")"

    if (( count > 0 )); then
        pass "Database contains $count versions."
    else
        fail "Database contains no versions."
    fi

    local latest
    latest="$(jq -r '.latest.release // empty' "$VERSIONS_DB")"

    if [[ -n "$latest" ]]; then
        pass "Latest release: $latest"
    else
        warning "Latest release is missing."
    fi
}


check_tools() {
    section "Required tools"

    check_command "curl" "curl"

    check_command "jq" "jq"

    check_command "python3" "Python"

    check_command "unzip" "unzip"

    check_command "tar" "tar"

    check_command "sha256sum" "sha256sum"
}


check_network() {
    section "Network"

    if ! command -v curl >/dev/null 2>&1; then
        fail "Cannot test network because curl is missing."
        return
    fi

    if curl \
        --silent \
        --show-error \
        --fail \
        --max-time 10 \
        https://piston-meta.mojang.com/mc/game/version_manifest_v2.json \
        >/dev/null 2>&1; then

        pass "Mojang version manifest is reachable."
    else
        fail "Could not reach Mojang services."
    fi

    if curl \
        --silent \
        --show-error \
        --fail \
        --max-time 10 \
        https://api.modrinth.com/v2 \
        >/dev/null 2>&1; then

        pass "Modrinth API is reachable."
    else
        warning "Could not reach Modrinth API."
    fi
}


check_config() {
    section "Launcher configuration"

    if [[ -f "$CONFIG_FILE" ]]; then
        pass "Configuration file exists."

        if grep -q '^game_dir=' "$CONFIG_FILE"; then
            pass "Game directory setting exists."
        else
            warning "game_dir setting is missing."
        fi

        if grep -q '^max_memory=' "$CONFIG_FILE"; then
            pass "Memory configuration exists."
        else
            warning "Memory configuration is missing."
        fi
    else
        warning "Configuration file does not exist."
        echo "     Run: mc config"
    fi
}


check_accounts() {
    section "Accounts"

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then
        warning "No account database exists."
        echo "     Run: mc account add"
        return
    fi

    if ! command -v jq >/dev/null 2>&1; then
        warning "Cannot inspect accounts without jq."
        return
    fi

    if ! jq -e . "$ACCOUNTS_FILE" >/dev/null 2>&1; then
        fail "Account database contains invalid JSON."
        return
    fi

    local count
    count="$(jq '.accounts | length' "$ACCOUNTS_FILE")"

    if (( count > 0 )); then
        pass "$count account(s) configured."
    else
        warning "No Minecraft accounts configured."
    fi
}


check_versions() {
    section "Installed versions"

    if [[ ! -d "$GAME_DIR/versions" ]]; then
        warning "No versions directory."
        return
    fi

    shopt -s nullglob

    local dirs=("$GAME_DIR/versions"/*)
    local count=0
    local incomplete=0

    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue

        ((count++))

        local name
        name="$(basename "$dir")"

        if [[ ! -f "$dir/$name.jar" ||
              ! -f "$dir/$name.json" ]]; then
            ((incomplete++))
        fi
    done

    if (( count == 0 )); then
        warning "No Minecraft versions installed."
    else
        pass "$count installed version(s)."
    fi

    if (( incomplete > 0 )); then
        warning "$incomplete version(s) appear incomplete."
    fi
}


print_summary() {
    echo
    echo -e "${BOLD}${CYAN}Doctor summary${RESET}"
    echo "────────────────────────────────────────────────────────"

    echo -e "  ${GREEN}Passed:${RESET}   $PASS"
    echo -e "  ${YELLOW}Warnings:${RESET} $WARN"
    echo -e "  ${RED}Failed:${RESET}   $FAIL"

    echo

    if (( FAIL > 0 )); then
        echo -e "${RED}${BOLD}Your launcher has problems that should be fixed.${RESET}"
        return 1
    elif (( WARN > 0 )); then
        echo -e "${YELLOW}${BOLD}Launcher is usable, but some things need attention.${RESET}"
        return 0
    else
        echo -e "${GREEN}${BOLD}Everything looks healthy. ✓${RESET}"
        return 0
    fi
}


main() {
    echo
    echo -e "${BOLD}${CYAN}mc doctor${RESET}"
    echo -e "${DIM}Minecraft launcher diagnostic${RESET}"

    check_tools
    check_java
    check_game_directory
    check_directories
    check_database
    check_config
    check_accounts
    check_versions
    check_network

    print_summary
}


main "$@"