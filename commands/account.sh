```bash
# MC Launcher shared UI
MC_COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MC_COMMAND_DIR/ui.sh"

#!/bin/bash

set -o pipefail

# ============================================================
# MC LAUNCHER — ACCOUNT
# ============================================================

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mc"
ACCOUNT_DIR="$CONFIG_DIR/accounts"

ACCOUNTS_FILE="$ACCOUNT_DIR/accounts.json"
ACTIVE_FILE="$ACCOUNT_DIR/active"

# ============================================================
# Colors
# ============================================================

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

# ============================================================
# Helpers
# ============================================================

die() {
    mc_error $*" >&2
    exit 1
}

success() {
    mc_ok $*" >&2
}

warn() {
    mc_warn $*" >&2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command '$1' is not installed."
}

init_accounts() {

    require_command jq

    mkdir -p "$ACCOUNT_DIR"

    if [[ ! -f "$ACCOUNTS_FILE" ]]; then

        printf '%s\n' '{"accounts":[]}' > "$ACCOUNTS_FILE"

    fi

    if ! jq -e . "$ACCOUNTS_FILE" >/dev/null 2>&1; then
        die "accounts.json contains invalid JSON."
    fi
}

# ============================================================
# List Accounts
# ============================================================

list_accounts() {

    init_accounts

    local count

    count="$(jq '.accounts | length' "$ACCOUNTS_FILE")"

    if (( count == 0 )); then
        echo "No Minecraft accounts configured."
        return 0
    fi

    local active=""

    if [[ -f "$ACTIVE_FILE" ]]; then
        active="$(cat "$ACTIVE_FILE")"
    fi

    echo
    echo -e "${BOLD}Minecraft accounts:${RESET}"
    echo

    jq -r '.accounts[] |
        [
            (.id // ""),
            (.username // "Unknown"),
            (.uuid // "Unknown")
        ] |
        @tsv
    ' "$ACCOUNTS_FILE" |
    while IFS=$'\t' read -r id username uuid; do

        if [[ "$id" == "$active" ]]; then

            echo -e \
                "  ${CYAN}●${RESET} ${BOLD}${username}${RESET}"

            echo -e \
                "    UUID: $uuid"

            echo -e \
                "    ID: $id"

            echo -e \
                "    ${GREEN}Active${RESET}"

        else

            echo -e \
                "  ${DIM}○${RESET} ${username}"

            echo -e \
                "    UUID: $uuid"

            echo -e \
                "    ID: $id"

        fi

        echo

    done
}

# ============================================================
# Select Account
# ============================================================

select_account() {

    init_accounts

    local count

    count="$(jq '.accounts | length' "$ACCOUNTS_FILE")"

    if (( count == 0 )); then
        die "No Minecraft accounts configured."
    fi

    echo
    echo -e "${BOLD}Accounts:${RESET}"
    echo

    jq -r '.accounts[] |
        [
            (.id // ""),
            (.username // "Unknown"),
            (.uuid // "Unknown")
        ] |
        @tsv
    ' "$ACCOUNTS_FILE" |
    nl -w2 -s') ' |
    while IFS= read -r line; do
        echo "  $line"
    done

    echo
    echo -e "  ${RED}0)${RESET} Cancel"
    echo

    local selection

    while true; do

        read -r \
            -p "Select an account [1-$count, 0 to cancel]: " \
            selection

        if [[ "$selection" == "0" ]]; then
            return 1
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= count )); then

            ACCOUNT_ID="$(
                jq -r \
                    --argjson n "$selection" \
                    '.accounts[$n - 1].id' \
                    "$ACCOUNTS_FILE"
            )"

            ACCOUNT_USERNAME="$(
                jq -r \
                    --argjson n "$selection" \
                    '.accounts[$n - 1].username' \
                    "$ACCOUNTS_FILE"
            )"

            return 0
        fi

        echo \
            -e "${RED}Invalid selection.${RESET}" \
            >&2

    done
}

# ============================================================
# Add Account
# ============================================================

add_account() {

    init_accounts

    echo
    echo -e "${BOLD}Add Minecraft account${RESET}"
    echo

    echo "Microsoft authentication will be used."
    echo "Your Microsoft password should never be entered into mc."
    echo

    warn "Microsoft OAuth authentication is not connected yet."
    echo
    echo "The account authentication backend will be added here."
    echo
    echo "For now, no account has been added."
}

# ============================================================
# Remove Account
# ============================================================

remove_account() {

    init_accounts

    select_account || return 0

    echo
    echo -e "${BOLD}Selected:${RESET} $ACCOUNT_USERNAME"
    echo

    read -r \
        -p "Remove this account? [y/N]: " \
        answer

    case "${answer,,}" in
        y|yes)
            ;;
        *)
            echo "Cancelled."
            return 0
            ;;
    esac

    local new_accounts

    new_accounts="$(
        jq \
            --arg id "$ACCOUNT_ID" \
            '.accounts |= map(select(.id != $id))' \
            "$ACCOUNTS_FILE"
    )" || die "Failed to update account database."

    printf '%s\n' "$new_accounts" > "$ACCOUNTS_FILE"

    # Clear active account if this was it.
    if [[ -f "$ACTIVE_FILE" ]] &&
       [[ "$(cat "$ACTIVE_FILE")" == "$ACCOUNT_ID" ]]; then

        rm -f "$ACTIVE_FILE"

    fi

    success "Removed account $ACCOUNT_USERNAME"
}

# ============================================================
# Use Account
# ============================================================

use_account() {

    init_accounts

    select_account || return 0

    printf '%s\n' "$ACCOUNT_ID" > "$ACTIVE_FILE"

    success "Active account: $ACCOUNT_USERNAME"
}

# ============================================================
# Show Active Account
# ============================================================

show_active() {

    init_accounts

    if [[ ! -f "$ACTIVE_FILE" ]]; then
        echo "No active Minecraft account."
        return 0
    fi

    local active_id
    active_id="$(cat "$ACTIVE_FILE")"

    local account

    account="$(
        jq -c \
            --arg id "$active_id" \
            '.accounts[] | select(.id == $id)' \
            "$ACCOUNTS_FILE"
    )"

    if [[ -z "$account" ]]; then
        warn "Active account no longer exists."
        rm -f "$ACTIVE_FILE"
        return 0
    fi

    local username
    username="$(jq -r '.username // "Unknown"' <<<"$account")"

    local uuid
    uuid="$(jq -r '.uuid // "Unknown"' <<<"$account")"

    echo
    echo -e "${BOLD}Active account:${RESET}"
    echo
    echo "  Username: $username"
    echo "  UUID:     $uuid"
    echo "  ID:       $active_id"
    echo
}

# ============================================================
# Help
# ============================================================

show_help() {

    cat <<EOF
Usage:

  mc account
  mc account list
  mc account add
  mc account remove
  mc account use
  mc account active

Commands:

  list      List Minecraft accounts
  add       Add a Microsoft/Minecraft account
  remove    Remove an account
  use       Select the active account
  active    Show the active account

Examples:

  mc account

  mc account list

  mc account add

  mc account use

  mc account remove
EOF
}

# ============================================================
# Main
# ============================================================

main() {

    local action="${1:-}"

    case "$action" in

        "")
            list_accounts
            ;;

        list)
            list_accounts
            ;;

        add)
            add_account
            ;;

        remove|rm)
            remove_account
            ;;

        use)
            use_account
            ;;

        active)
            show_active
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            die "Unknown account command '$action'. Try 'mc account --help'."
            ;;

    esac
}

main "$@"
```
