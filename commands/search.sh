#!/bin/bash

set -o pipefail

MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"
VERSION_DB="$MC_DIR/data/versions.json"

# ─────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────

BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

die() {
    echo "${RED}Error:${RESET} $*" >&2
    exit 1
}

usage() {
    cat <<EOF
${BOLD}${CYAN}Usage:${RESET}

  mc search <type> [query] [options]

${BOLD}Types:${RESET}

  mod
  modpack
  shader
  resourcepack
  versions

${BOLD}Examples:${RESET}

  mc search mod sodium
  mc search mod sodium --version 1.21.8
  mc search mod sodium --loader fabric
  mc search shader complementary
  mc search resourcepack faithful

  mc search versions
  mc search versions 1.21
  mc search versions 1.21.8
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command '$1' is not installed."
}

# ─────────────────────────────────────────────
# Minecraft version search
# ─────────────────────────────────────────────

search_versions() {
    local query=""
    local snapshot=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --snapshot)
                snapshot=true
                shift
                ;;

            --help|-h)
                echo
                echo "${BOLD}${CYAN}mc search versions${RESET}"
                echo
                echo "Usage:"
                echo "  mc search versions"
                echo "  mc search versions --snapshot"
                echo "  mc search versions <query>"
                echo "  mc search versions <query> --snapshot"
                echo
                return 0
                ;;

            --*)
                die "Unknown option '$1'."
                ;;

            *)
                if [[ -z "$query" ]]; then
                    query="$1"
                else
                    die "Unexpected argument '$1'."
                fi
                shift
                ;;
        esac
    done

    [[ -f "$VERSION_DB" ]] || die "Minecraft version database not found.

Run:
  mc update database"

    require_command jq

    if ! jq empty "$VERSION_DB" >/dev/null 2>&1; then
        die "Minecraft version database contains invalid JSON."
    fi

    echo
    echo "${BOLD}${CYAN}Minecraft versions${RESET}"
    echo

    # ─────────────────────────────────────────
    # No query: show newest releases/snapshots
    # ─────────────────────────────────────────

    if [[ -z "$query" ]]; then

        if [[ "$snapshot" == true ]]; then
            echo "${DIM}10 newest snapshots:${RESET}"
            echo

            jq -r '
                .versions
                | map(select(.type == "snapshot"))
                | .[:10]
                | .[]
                | [.id, .releaseTime]
                | @tsv
            ' "$VERSION_DB" |
            while IFS=$'\t' read -r id release_time; do
                printf "  ${YELLOW}%-18s${RESET} snapshot     %s\n" \
                    "$id" \
                    "${release_time:0:10}"
            done

        else
            echo "${DIM}10 newest releases:${RESET}"
            echo

            jq -r '
                .versions
                | map(select(.type == "release"))
                | .[:10]
                | .[]
                | [.id, .releaseTime]
                | @tsv
            ' "$VERSION_DB" |
            while IFS=$'\t' read -r id release_time; do
                printf "  ${GREEN}%-18s${RESET} release      %s\n" \
                    "$id" \
                    "${release_time:0:10}"
            done
        fi

        echo
        echo "${DIM}Use '--snapshot' to show snapshots.${RESET}"
        echo

        return 0
    fi

    # ─────────────────────────────────────────
    # Query search
    # ─────────────────────────────────────────

    if [[ "$snapshot" == true ]]; then
        echo "${DIM}Snapshots matching:${RESET} ${BOLD}$query${RESET}"
    else
        echo "${DIM}Releases matching:${RESET} ${BOLD}$query${RESET}"
    fi

    echo

    local results

    if [[ "$snapshot" == true ]]; then
        results="$(
            jq -r --arg q "$query" '
                .versions[]
                | select(
                    (.id | ascii_downcase | contains($q | ascii_downcase))
                    and
                    .type == "snapshot"
                  )
                | [.id, .releaseTime]
                | @tsv
            ' "$VERSION_DB"
        )"
    else
        results="$(
            jq -r --arg q "$query" '
                .versions[]
                | select(
                    (.id | ascii_downcase | contains($q | ascii_downcase))
                    and
                    .type == "release"
                  )
                | [.id, .releaseTime]
                | @tsv
            ' "$VERSION_DB"
        )"
    fi

    if [[ -z "$results" ]]; then
        echo "${YELLOW}No matching versions found.${RESET}"
        echo
        return 0
    fi

    local index=1

    while IFS=$'\t' read -r id release_time; do

        if [[ "$snapshot" == true ]]; then
            type_label="${YELLOW}snapshot${RESET}"
        else
            type_label="${GREEN}release${RESET}"
        fi

        printf "  ${CYAN}%2d${RESET}  %-18s %-12b %s\n" \
            "$index" \
            "$id" \
            "$type_label" \
            "${release_time:0:10}"

        ((index++))
    done <<< "$results"

    echo
}

# ─────────────────────────────────────────────
# Modrinth search
# ─────────────────────────────────────────────

search_modrinth() {
    local type="$1"
    local query="$2"
    shift 2

    local version=""
    local loader=""
    local limit=10

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                [[ -n "${2:-}" ]] || die "--version requires a value."
                version="$2"
                shift 2
                ;;

            --loader)
                [[ -n "${2:-}" ]] || die "--loader requires a value."
                loader="$2"
                shift 2
                ;;

            --limit)
                [[ -n "${2:-}" ]] || die "--limit requires a value."
                limit="$2"
                shift 2
                ;;

            -h|--help)
                usage
                return 0
                ;;

            *)
                die "Unknown option '$1'."
                ;;
        esac
    done

    require_command curl
    require_command jq

    local project_type="$type"

    local facets
    facets="[\"project_type:${project_type}\"]"

    if [[ -n "$version" ]]; then
        facets="$facets,[\"versions:${version}\"]"
    fi

    if [[ -n "$loader" ]]; then
        facets="$facets,[\"categories:${loader}\"]"
    fi

    local url
    url="https://api.modrinth.com/v2/search"

    local response

    if [[ -n "$query" ]]; then
        response="$(
            curl -fsSL \
                --retry 3 \
                --connect-timeout 10 \
                --max-time 30 \
                -A "mc-launcher/0.1.0" \
                --get "$url" \
                --data-urlencode "query=$query" \
                --data-urlencode "limit=$limit" \
                --data-urlencode "facets=$facets"
        )" || die "Could not reach Modrinth API."
    else
        response="$(
            curl -fsSL \
                --retry 3 \
                --connect-timeout 10 \
                --max-time 30 \
                -A "mc-launcher/0.1.0" \
                --get "$url" \
                --data-urlencode "limit=$limit" \
                --data-urlencode "facets=$facets"
        )" || die "Could not reach Modrinth API."
    fi

    if ! jq empty <<<"$response" >/dev/null 2>&1; then
        die "Modrinth returned invalid JSON."
    fi

    local hits
    hits="$(jq '.hits | length' <<<"$response")"

    echo
    echo "${BOLD}${CYAN}Search results${RESET}"
    echo

    if [[ "$hits" -eq 0 ]]; then
        echo "${YELLOW}No results found.${RESET}"
        return 0
    fi

    jq -r '
        .hits
        | to_entries[]
        | [
            (.key + 1),
            (.value.title // ""),
            (.value.description // ""),
            (.value.downloads // 0),
            (.value.slug // "")
          ]
        | @tsv
    ' <<<"$response" |
    while IFS=$'\t' read -r index title description downloads slug; do

        printf "${CYAN}%2s${RESET}  ${BOLD}%s${RESET}\n" \
            "$index" "$title"

        printf "    ${DIM}%s${RESET}\n" \
            "$description"

        printf "    ${DIM}Downloads:${RESET} %s  ${DIM}Slug:${RESET} %s\n\n" \
            "$downloads" "$slug"
    done
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

TYPE="$1"
shift

case "$TYPE" in

    versions|version)
        search_versions "${1:-}"
        ;;

    mod|modpack|shader|resourcepack)
        QUERY=""

        if [[ $# -gt 0 && "$1" != --* ]]; then
            QUERY="$1"
            shift
        fi

        search_modrinth "$TYPE" "$QUERY" "$@"
        ;;

    -h|--help)
        usage
        ;;

    *)
        echo
        echo "${RED}Error:${RESET} unknown search type '$TYPE'"
        echo
        echo "Valid types:"
        echo
        echo "  mod"
        echo "  modpack"
        echo "  shader"
        echo "  resourcepack"
        echo "  versions"
        echo
        exit 1
        ;;
esac