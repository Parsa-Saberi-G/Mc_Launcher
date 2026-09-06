#!/bin/bash

set -o pipefail

# ============================================================
# MC LAUNCHER — SEARCH
# ============================================================

MC_VERSION="0.1.0"
MODRINTH_API="https://api.modrinth.com/v2"

MC_COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Shared UI if available
if [[ -f "$MC_COMMAND_DIR/ui.sh" ]]; then
    source "$MC_COMMAND_DIR/ui.sh"
fi

MC_DIR="$(cd "$MC_COMMAND_DIR/.." && pwd)"
GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"
VERSION_DB="$MC_DIR/data/versions.json"

# ============================================================
# Colors
# ============================================================

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    MAGENTA=$'\033[35m'
    CYAN=$'\033[36m'
    WHITE=$'\033[37m'
    RESET=$'\033[0m'
else
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    WHITE=""
    RESET=""
fi

# ============================================================
# Helpers
# ============================================================

die() {
    printf '%bError:%b %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

info() {
    printf '%b→%b %s\n' "$CYAN" "$RESET" "$*" >&2
}

success() {
    printf '%b✓%b %s\n' "$GREEN" "$RESET" "$*" >&2
}

warn() {
    printf '%b⚠%b %s\n' "$YELLOW" "$RESET" "$*" >&2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command '$1' is not installed."
}

trim_description() {
    local text="$1"

    text="${text//$'\n'/ }"
    text="${text//$'\r'/ }"

    if (( ${#text} > 100 )); then
        printf '%s...' "${text:0:97}"
    else
        printf '%s' "$text"
    fi
}

# ============================================================
# Help
# ============================================================

usage() {
    cat >&2 <<EOF

${BOLD}${CYAN}mc search${RESET} — Search Minecraft content

${BOLD}Usage${RESET}
  mc search <type> [query] [options]

${BOLD}Types${RESET}
  mod          Mods
  modpack      Modpacks
  shader       Shaders
  resourcepack Resource packs
  versions     Minecraft versions

${BOLD}Examples${RESET}
  mc search mod
  mc search mod sodium
  mc search mod sodium --version 1.21.8
  mc search mod sodium --loader fabric
  mc search shader
  mc search shader complementary
  mc search resourcepack faithful
  mc search modpack
  mc search versions
  mc search versions --snapshot
  mc search versions 1.21
  mc search versions 1.21 --snapshot

${BOLD}Options${RESET}
  --version VERSION    Filter projects by Minecraft version
  --loader LOADER      Filter by loader/category
  --limit NUMBER       Number of online results
  --snapshot           Show Minecraft snapshots

EOF
}

# ============================================================
# Minecraft Version Search
# ============================================================

search_versions() {

    local query=""
    local snapshot=0

    while [[ $# -gt 0 ]]; do

        case "$1" in

            --snapshot)
                snapshot=1
                shift
                ;;

            --help|-h)
                usage
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

    # --------------------------------------------------------
    # Database
    # --------------------------------------------------------

    [[ -f "$VERSION_DB" ]] ||
        die "Minecraft version database not found.

Run:
  mc update database"

    require_command jq

    if ! jq -e . "$VERSION_DB" >/dev/null 2>&1; then
        die "Minecraft version database contains invalid JSON."
    fi

    printf '\n'
    printf '%bMinecraft versions%b\n' "$BOLD$CYAN" "$RESET"
    printf '\n'

    # --------------------------------------------------------
    # No query = browse newest versions
    # --------------------------------------------------------

    if [[ -z "$query" ]]; then

        if (( snapshot == 1 )); then

            printf '%b10 newest snapshots:%b\n\n' \
                "$DIM" "$RESET"

            jq -r '
                .versions
                | map(select(.type == "snapshot"))
                | .[:10]
                | .[]
                | [
                    .id,
                    .type,
                    .releaseTime
                  ]
                | @tsv
            ' "$VERSION_DB" |
            while IFS=$'\t' read -r id type release_time; do

                printf '  %b%-22s%b %b%-10s%b %s\n' \
                    "$YELLOW" \
                    "$id" \
                    "$RESET" \
                    "$YELLOW" \
                    "snapshot" \
                    "$RESET" \
                    "${release_time:0:10}"

            done

        else

            printf '%b10 newest releases:%b\n\n' \
                "$DIM" "$RESET"

            jq -r '
                .versions
                | map(select(.type == "release"))
                | .[:10]
                | .[]
                | [
                    .id,
                    .type,
                    .releaseTime
                  ]
                | @tsv
            ' "$VERSION_DB" |
            while IFS=$'\t' read -r id type release_time; do

                printf '  %b%-22s%b %b%-10s%b %s\n' \
                    "$GREEN" \
                    "$id" \
                    "$RESET" \
                    "$GREEN" \
                    "release" \
                    "$RESET" \
                    "${release_time:0:10}"

            done

        fi

        printf '\n'
        printf '%bUse --snapshot to browse snapshots.%b\n' \
            "$DIM" "$RESET"
        printf '\n'

        return 0
    fi

    # --------------------------------------------------------
    # Query versions
    # --------------------------------------------------------

    printf '%bSearching versions:%b %s\n\n' \
        "$DIM" "$RESET" "$query"

    local results

    if (( snapshot == 1 )); then

        results="$(
            jq -r \
                --arg q "$query" '
                .versions[]
                | select(
                    .type == "snapshot"
                    and
                    (
                        (.id // "")
                        | ascii_downcase
                        | contains($q | ascii_downcase)
                    )
                )
                | [
                    .id,
                    .type,
                    .releaseTime
                  ]
                | @tsv
            ' "$VERSION_DB"
        )"

    else

        results="$(
            jq -r \
                --arg q "$query" '
                .versions[]
                | select(
                    .type == "release"
                    and
                    (
                        (.id // "")
                        | ascii_downcase
                        | contains($q | ascii_downcase)
                    )
                )
                | [
                    .id,
                    .type,
                    .releaseTime
                  ]
                | @tsv
            ' "$VERSION_DB"
        )"

    fi

    if [[ -z "$results" ]]; then

        printf '%bNo matching versions found.%b\n\n' \
            "$YELLOW" "$RESET"

        return 0
    fi

    local index=1

    while IFS=$'\t' read -r id type release_time; do

        if [[ "$type" == "snapshot" ]]; then
            type_color="$YELLOW"
        else
            type_color="$GREEN"
        fi

        printf '  %b%2d%b  %-22s %b%-10s%b %s\n' \
            "$CYAN" \
            "$index" \
            "$RESET" \
            "$id" \
            "$type_color" \
            "$type" \
            "$RESET" \
            "${release_time:0:10}"

        ((index++))

    done <<< "$results"

    printf '\n'
}

# ============================================================
# Modrinth API Request
# ============================================================

modrinth_search_request() {

    local query="$1"
    local project_type="$2"
    local version="$3"
    local loader="$4"
    local limit="$5"

    local args=(
        --fail
        --silent
        --show-error
        --location
        --retry 3
        --connect-timeout 10
        --max-time 30

        --get
        "$MODRINTH_API/search"

        --data-urlencode "limit=$limit"
        --data-urlencode "index=relevance"

        -H "User-Agent: mc-launcher/${MC_VERSION}"
        -H "Accept: application/json"
    )

    # --------------------------------------------------------
    # Query
    # --------------------------------------------------------

    if [[ -n "$query" ]]; then
        args+=(--data-urlencode "query=$query")
    fi

    # --------------------------------------------------------
    # Build facets with jq
    #
    # Modrinth expects:
    #
    # [
    #   ["project_type:mod"],
    #   ["versions:1.21.8"],
    #   ["categories:fabric"]
    # ]
    #
    # Separate arrays = AND.
    # Same array = OR.
    # --------------------------------------------------------

    local facets

    facets="$(
        jq -cn \
            --arg type "$project_type" \
            --arg version "$version" \
            --arg loader "$loader" '
            [
                ["project_type:" + $type]
            ]
            +
            (
                if $version != ""
                then [["versions:" + $version]]
                else []
                end
            )
            +
            (
                if $loader != ""
                then [["categories:" + $loader]]
                else []
                end
            )
        '
    )"

    args+=(--data-urlencode "facets=$facets")

    curl "${args[@]}"
}

# ============================================================
# Display Modrinth Results
# ============================================================

display_modrinth_results() {

    local response="$1"
    local project_type="$2"

    local count

    count="$(jq '.hits | length' <<<"$response")"

    printf '\n'
    printf '%b%s results%b\n' \
        "$BOLD$CYAN" \
        "$count" \
        "$RESET"
    printf '\n'

    if (( count == 0 )); then

        printf '%bNo results found.%b\n\n' \
            "$YELLOW" "$RESET"

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

        printf '%b%2s%b  %b%s%b\n' \
            "$CYAN" \
            "$index" \
            "$RESET" \
            "$BOLD" \
            "$title" \
            "$RESET"

        if [[ -n "$description" ]]; then

            description="$(trim_description "$description")"

            printf '     %b%s%b\n' \
                "$DIM" \
                "$description" \
                "$RESET"

        fi

        printf '     %bDownloads:%b %s  %bSlug:%b %s\n' \
            "$DIM" \
            "$RESET" \
            "$downloads" \
            "$DIM" \
            "$RESET" \
            "$slug"

        printf '\n'

    done
}

# ============================================================
# Modrinth Search / Browse
# ============================================================

search_modrinth() {

    local project_type="$1"
    local query="${2:-}"

    shift 2

    local version=""
    local loader=""
    local limit=10

    # --------------------------------------------------------
    # Arguments
    # --------------------------------------------------------

    while [[ $# -gt 0 ]]; do

        case "$1" in

            --version)

                [[ -n "${2:-}" ]] ||
                    die "--version requires a value."

                version="$2"
                shift 2
                ;;

            --loader)

                [[ -n "${2:-}" ]] ||
                    die "--loader requires a value."

                loader="$2"
                shift 2
                ;;

            --limit)

                [[ -n "${2:-}" ]] ||
                    die "--limit requires a value."

                [[ "$2" =~ ^[0-9]+$ ]] ||
                    die "--limit must be a number."

                if (( $2 < 1 || $2 > 100 )); then
                    die "--limit must be between 1 and 100."
                fi

                limit="$2"
                shift 2
                ;;

            --help|-h)

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

    # --------------------------------------------------------
    # Status
    # --------------------------------------------------------

    printf '\n'

    if [[ -n "$query" ]]; then

        printf '%bSearching Modrinth%b\n' \
            "$BOLD$CYAN" \
            "$RESET"

        printf '%bType:%b %s\n' \
            "$DIM" \
            "$RESET" \
            "$project_type"

        printf '%bQuery:%b %s\n' \
            "$DIM" \
            "$RESET" \
            "$query"

    else

        printf '%bBrowsing Modrinth%b\n' \
            "$BOLD$CYAN" \
            "$RESET"

        printf '%bShowing top %s %s projects%b\n' \
            "$DIM" \
            "$limit" \
            "$project_type" \
            "$RESET"

    fi

    [[ -n "$version" ]] &&
        printf '%bMinecraft:%b %s\n' \
            "$DIM" "$RESET" "$version"

    [[ -n "$loader" ]] &&
        printf '%bLoader:%b %s\n' \
            "$DIM" "$RESET" "$loader"

    printf '\n'

    # --------------------------------------------------------
    # API
    # --------------------------------------------------------

    local response

    if ! response="$(
        modrinth_search_request \
            "$query" \
            "$project_type" \
            "$version" \
            "$loader" \
            "$limit"
    )"; then

        die "Could not reach Modrinth API."

    fi

    # --------------------------------------------------------
    # Validate response
    # --------------------------------------------------------

    if ! jq -e 'type == "object" and (.hits | type == "array")' \
        >/dev/null 2>&1 <<<"$response"; then

        printf '%bModrinth response:%b\n' \
            "$RED" "$RESET" >&2

        printf '%s\n' "$response" >&2

        die "Modrinth returned invalid search data."

    fi

    # --------------------------------------------------------
    # Display
    # --------------------------------------------------------

    display_modrinth_results \
        "$response" \
        "$project_type"
}

# ============================================================
# Main
# ============================================================

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

TYPE="$1"
shift

case "$TYPE" in

    # --------------------------------------------------------
    # Minecraft versions
    # --------------------------------------------------------

    versions|version)

        search_versions "$@"
        ;;

    # --------------------------------------------------------
    # Modrinth project types
    # --------------------------------------------------------

    mod|modpack|shader|resourcepack)

        QUERY=""

        if [[ $# -gt 0 && "$1" != --* ]]; then
            QUERY="$1"
            shift
        fi

        search_modrinth \
            "$TYPE" \
            "$QUERY" \
            "$@"

        ;;

    # --------------------------------------------------------
    # Help
    # --------------------------------------------------------

    -h|--help)

        usage
        ;;

    # --------------------------------------------------------
    # Unknown
    # --------------------------------------------------------

    *)

        printf '\n'
        printf '%bError:%b unknown search type "%s"\n' \
            "$RED" "$RESET" "$TYPE"

        printf '\n'
        printf '%bValid types:%b\n\n' \
            "$BOLD" "$RESET"

        printf '  mod\n'
        printf '  modpack\n'
        printf '  shader\n'
        printf '  resourcepack\n'
        printf '  versions\n'
        printf '\n'

        exit 1
        ;;

esac