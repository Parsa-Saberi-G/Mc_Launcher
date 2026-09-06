#!/bin/bash


set -o pipefail

# ============================================================
# MC LAUNCHER — INSTALL
# ============================================================

MC_VERSION="0.1.0"

MODRINTH_API="https://api.modrinth.com/v2"
FABRIC_META="https://meta.fabricmc.net/v2"

GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"

AUTO_YES=0

QUERY=""
TARGET_VERSION=""
LOADER=""
LOADER_VERSION=""

# ============================================================
# Colors
# ============================================================

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

# ============================================================
# Helpers
# ============================================================

die() {
    printf '%bError:%b %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

info() {
    echo -e "$*" >&2
}

success() {
    printf '%b✓%b %s\n' "$GREEN" "$RESET" "$*" >&2
}

warn() {
    printf '%b!%b %s\n' "$YELLOW" "$RESET" "$*" >&2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command '$1' is not installed."
}

check_dependencies() {
    require_command curl
    require_command jq
    require_command python3
}

urlencode() {
    python3 - "$1" <<'PY'
import sys
from urllib.parse import quote

print(quote(sys.argv[1], safe=""))
PY
}

normalize_text() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        sed 's/[^a-z0-9]/ /g' |
        tr -s ' ' |
        sed 's/^ *//;s/ *$//'
}

# ============================================================
# HTTP
# ============================================================

modrinth_get() {
    local url="$1"

    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 10 \
        --max-time 30 \
        -H "User-Agent: mc-launcher/${MC_VERSION}" \
        -H "Accept: application/json" \
        "$url"
}

download_file() {
    local url="$1"
    local output="$2"

    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 10 \
        --max-time 300 \
        -H "User-Agent: mc-launcher/${MC_VERSION}" \
        -o "$output" \
        "$url"
}

# ============================================================
# Modrinth Search
#
# Normal search:
#   /search?query=sodium
#
# Browse mode:
#   /search?query=&index=downloads
#
# ============================================================

search_modrinth() {
    local query="$1"
    local project_type="$2"
    local limit="${3:-100}"

    local facets
    facets="$(
        jq -cn --arg type "$project_type" \
            '[[("project_type:" + $type)]]'
    )"

    local encoded_facets
    encoded_facets="$(urlencode "$facets")"

    local url
    url="${MODRINTH_API}/search"

    if [[ -n "$query" ]]; then
        local encoded_query
        encoded_query="$(urlencode "$query")"

        url+="?query=${encoded_query}"
        url+="&index=relevance"
    else
        # Empty query = browsing mode.
        # Show popular projects first.
        url+="?index=downloads"
    fi

    url+="&limit=${limit}"
    url+="&facets=${encoded_facets}"

    modrinth_get "$url"
}

# ============================================================
# Search Variants
# ============================================================

build_search_variants() {
    local query="$1"

    # Empty query is a browse request.
    if [[ -z "$(normalize_text "$query")" ]]; then
        return 0
    fi

    python3 - "$query" <<'PY'
import sys

query = sys.argv[1].strip().lower()

seen = set()
variants = []


def add(value):
    value = " ".join(value.split()).strip()

    if not value:
        return

    if value in seen:
        return

    seen.add(value)
    variants.append(value)


add(query)

words = query.split()

# Individual words.
for word in words:
    add(word)

# Prefixes.
for word in words:
    if len(word) >= 6:
        add(word[:7])
        add(word[:6])
        add(word[:5])

# Remove one character from likely typo positions.
for word in words:
    if len(word) >= 6:
        positions = [
            len(word) - 1,
            len(word) - 2,
            len(word) // 2,
            len(word) // 2 - 1,
        ]

        for pos in positions:
            if 0 <= pos < len(word):
                add(word[:pos] + word[pos + 1:])

# Swap adjacent characters.
for word in words:
    if len(word) >= 6:
        positions = [
            len(word) - 2,
            len(word) // 2,
        ]

        for pos in positions:
            if 0 <= pos < len(word) - 1:
                chars = list(word)
                chars[pos], chars[pos + 1] = chars[pos + 1], chars[pos]
                add("".join(chars))

# Multi-word variants with one shortened word.
if len(words) > 1:
    for i, word in enumerate(words):
        if len(word) >= 6:
            shortened = words.copy()
            shortened[i] = word[:-1]
            add(" ".join(shortened))

for value in variants[:20]:
    print(value)
PY
}

# ============================================================
# Collect Search Results
# ============================================================

collect_candidates() {
    local query="$1"
    local project_type="$2"

    local temp_dir
    temp_dir="$(mktemp -d)" || return 1

    local merged="$temp_dir/merged.json"

    echo '{"hits":[]}' > "$merged"

    # ========================================================
    # Browse mode
    # ========================================================

    if [[ -z "$(normalize_text "$query")" ]]; then
        local result

        result="$(
            search_modrinth \
                "" \
                "$project_type" \
                20 \
                2>/dev/null
        )"

        if [[ -n "$result" ]] &&
           jq -e '.hits' >/dev/null 2>&1 <<<"$result"; then

            printf '%s\n' "$result" > "$merged"
        fi

        cat "$merged"
        rm -rf "$temp_dir"
        return 0
    fi

    # ========================================================
    # Normal/fuzzy search
    # ========================================================

    local first=1
    local variant
    local index=0

    while IFS= read -r variant; do
        [[ -z "$variant" ]] && continue

        index=$((index + 1))

        local result

        result="$(
            search_modrinth \
                "$variant" \
                "$project_type" \
                100 \
                2>/dev/null
        )"

        [[ -z "$result" ]] && continue

        if ! jq -e . >/dev/null 2>&1 <<<"$result"; then
            continue
        fi

        if ! jq -e '.hits' >/dev/null 2>&1 <<<"$result"; then
            continue
        fi

        jq -s '
            {
                hits:
                (
                    map(.hits // [])
                    | add
                    | unique_by(.project_id)
                )
            }
        ' \
            "$merged" \
            <(printf '%s\n' "$result") \
            > "$temp_dir/merged_new.json" || {
                rm -rf "$temp_dir"
                return 1
            }

        mv "$temp_dir/merged_new.json" "$merged"

        # Original query worked.
        # Don't waste time doing many more requests.
        if (( first == 1 )); then
            local hit_count

            hit_count="$(jq '.hits | length' "$merged")"

            if (( hit_count > 0 )); then
                break
            fi

            first=0
        fi

        # For fuzzy searches, stop once we have enough results.
        if (( index > 1 )); then
            local hit_count

            hit_count="$(jq '.hits | length' "$merged")"

            if (( hit_count >= 10 )); then
                break
            fi
        fi

    done < <(build_search_variants "$query")

    cat "$merged"

    rm -rf "$temp_dir"
}

# ============================================================
# Rank Candidates
#
# IMPORTANT:
# JSON is written to a temporary file.
#
# We do NOT pass the JSON as a command-line argument.
# We do NOT pipe JSON into Python while also using a heredoc.
#
# This fixes:
#   Argument list too long
#   JSONDecodeError / empty stdin
#
# ============================================================

rank_candidates() {
    local json="$1"
    local query="$2"

    local temp_json

    temp_json="$(mktemp)" || return 1

    printf '%s' "$json" > "$temp_json"

    python3 - "$query" "$temp_json" <<'PYRANK'
import json
import sys
import re
from difflib import SequenceMatcher

query = sys.argv[1].strip().lower()
json_file = sys.argv[2]

with open(json_file, "r", encoding="utf-8") as f:
    data = json.load(f)

hits = data.get("hits", [])


def normalize(s):
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def score(project):
    title = project.get("title", "")
    slug = project.get("slug", "")
    description = project.get("description", "")

    q = normalize(query)
    t = normalize(title)
    s = normalize(slug)
    d = normalize(description)

    score = 0.0

    # --------------------------------------------------------
    # Empty query = browse mode.
    # Modrinth already sorted by downloads.
    # Keep that order.
    # --------------------------------------------------------

    if not q:
        return 0.0

    # --------------------------------------------------------
    # Exact matches
    # --------------------------------------------------------

    if q == t:
        score += 1000

    if q == s:
        score += 950

    # --------------------------------------------------------
    # Partial matches
    # --------------------------------------------------------

    if q in t:
        score += 500

    if q in s:
        score += 450

    # --------------------------------------------------------
    # Individual words
    # --------------------------------------------------------

    qwords = q.split()

    for word in qwords:
        if word in t:
            score += 180

        if word in s:
            score += 160

        if word in d:
            score += 20

    # --------------------------------------------------------
    # Fuzzy similarity
    # --------------------------------------------------------

    if t:
        score += SequenceMatcher(None, q, t).ratio() * 300

    if s:
        score += SequenceMatcher(None, q, s).ratio() * 250

    # --------------------------------------------------------
    # Downloads = weak tie breaker
    # --------------------------------------------------------

    downloads = project.get("downloads", 0) or 0

    try:
        downloads = int(downloads)
    except (ValueError, TypeError):
        downloads = 0

    score += min(downloads / 1_000_000, 30)

    return score


# Only score when we actually have a query.
if query.strip():
    for project in hits:
        project["_mc_score"] = score(project)

    hits.sort(
        key=lambda project: project.get("_mc_score", 0),
        reverse=True
    )

    for project in hits:
        project.pop("_mc_score", None)


print(
    json.dumps(
        {"hits": hits},
        ensure_ascii=False
    )
)
PYRANK

    local status=$?

    rm -f "$temp_json"

    return "$status"
}

# ============================================================
# Select Project
#
# ALWAYS interactive unless --yes was supplied.
#
# Even one result:
#
#   1) Sodium
#   0) Cancel
#
# ============================================================

select_modrinth_project() {
    local query="$1"
    local project_type="$2"
    local auto_yes="${3:-0}"

    local candidates

    candidates="$(
        collect_candidates \
            "$query" \
            "$project_type"
    )"

    if [[ -z "$candidates" ]]; then
        die "No results found."
    fi

    if ! jq -e '.hits' >/dev/null 2>&1 <<<"$candidates"; then
        die "Modrinth returned invalid search data."
    fi

    local count

    count="$(jq '.hits | length' <<<"$candidates")"

    if (( count == 0 )); then
        if [[ -n "$query" ]]; then
            die "No results found for '$query'."
        fi

        die "No projects available for browsing."
    fi

    # ========================================================
    # Automatic mode
    #
    # ONLY --yes can get here.
    # ========================================================

    if (( auto_yes == 1 )); then
        jq -c '.hits[0]' <<<"$candidates"
        return 0
    fi

    # ========================================================
    # Rank
    # ========================================================

    local ranked

    ranked="$(
        rank_candidates \
            "$candidates" \
            "$query"
    )" || {
        die "Could not rank Modrinth results."
    }

    if [[ -z "$ranked" ]]; then
        die "Could not rank Modrinth results."
    fi

    if ! jq -e '.hits' >/dev/null 2>&1 <<<"$ranked"; then
        die "Could not rank Modrinth results."
    fi

    count="$(jq '.hits | length' <<<"$ranked")"

    if (( count == 0 )); then
        die "No suitable results found."
    fi

    # ========================================================
    # Display
    #
    # Best result is number 1 at the bottom.
    # Worst displayed result is number 10 at the top.
    #
    # Selection still uses normal ranked index:
    #
    #   1 -> hits[0]
    #   2 -> hits[1]
    #   ...
    #
    # ========================================================

    local display_count="$count"

    (( display_count > 10 )) &&
        display_count=10

    echo >&2

    if [[ -n "$query" ]]; then
        echo -e \
            "${YELLOW}Search results for:${RESET} $query" \
            >&2
    else
        echo -e \
            "${YELLOW}Browsing popular ${project_type}s:${RESET}" \
            >&2
    fi

    echo >&2
    echo -e "${BOLD}Possible matches:${RESET}" >&2
    echo >&2

    jq -r --argjson limit "$display_count" '
        .hits[:$limit]
        | reverse
        | to_entries[]
        | [
            ($limit - .key),
            (.value.title // ""),
            (.value.description // ""),
            ((.value.downloads // 0) | tostring),
            (.value.slug // "")
        ]
        | @tsv
    ' <<<"$ranked" |
    while IFS=$'\t' read -r number title description downloads slug; do

        printf "  %b%s)%b %b%s%b\n" "$CYAN" "$number" "$RESET" "$BOLD" "$title" "$RESET" >&2

        if [[ -n "$description" ]]; then
            description="${description//$'\\n'/ }"

            echo -e \
                "     ${DIM}${description:0:110}${RESET}" \
                >&2
        fi

        echo -e \
            "     Downloads: ${downloads}" \
            >&2

        echo -e \
            "     Slug: ${slug}" \
            >&2

        echo >&2

    done

    echo -e \
        "  ${RED}0)${RESET} Cancel" \
        >&2

    echo >&2

    # ========================================================
    # Selection
    # ========================================================

    local selection

    while true; do

        read -r \
            -p "Select a project [1-${display_count}, 0 to cancel]: " \
            selection

        if [[ "$selection" == "0" ]]; then
            echo "Cancelled." >&2
            return 1
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= display_count )); then

            # IMPORTANT:
            # Do NOT reverse this.
            #
            # 1 = best ranked result
            # 2 = second best
            # etc.
            #
            jq -c \
                --argjson n "$selection" \
                '.hits[$n - 1]' \
                <<<"$ranked"

            return 0
        fi

        echo \
            -e "${RED}Invalid selection.${RESET} Choose 1-${display_count} or 0." \
            >&2
    done
}

# ============================================================
# Select Project Version
#
# ALWAYS asks when interactive, even if there is only one.
# ============================================================

select_project_version() {
    local project="$1"

    local project_id

    project_id="$(
        jq -r '.project_id // .id // .slug // empty' <<<"$project"
    )"

    [[ -n "$project_id" ]] ||
        die "Project has no ID or slug."

    local url

    url="${MODRINTH_API}/project/${project_id}/version"

    local versions

    versions="$(
        modrinth_get "$url"
    )" || die "Failed to retrieve project versions."

    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$versions"; then
        die "Modrinth returned invalid version data."
    fi

    # ========================================================
    # Filter by Minecraft version / loader
    # ========================================================

    local filtered

    filtered="$(
        jq -c \
            --arg mc "$TARGET_VERSION" \
            --arg loader "$LOADER" '
            [
                .[]
                | select(
                    ($mc == "" or (.game_versions // [] | index($mc)))
                )
                | select(
                    ($loader == "" or (.loaders // [] | index($loader)))
                )
            ]
        ' <<<"$versions"
    )"

    local count

    count="$(jq 'length' <<<"$filtered")"

    if (( count == 0 )); then

        if [[ -n "$TARGET_VERSION" ]]; then
            die "No compatible version found for Minecraft $TARGET_VERSION."
        fi

        if [[ -n "$LOADER" ]]; then
            die "No compatible version found for loader $LOADER."
        fi

        die "No downloadable versions found."
    fi

    # ========================================================
    # Automatic mode only with --yes
    # ========================================================

    if (( AUTO_YES == 1 )); then
        jq -c '.[0]' <<<"$filtered"
        return 0
    fi

    # ========================================================
    # Interactive version menu
    # ========================================================

    local display_count="$count"

    (( display_count > 10 )) &&
        display_count=10

    echo >&2
    echo -e "${BOLD}Compatible versions:${RESET}" >&2
    echo >&2

    # Reverse the visual display so:
    #
    #   10) older
    #    9)
    #   ...
    #    1) newest
    #
    # Selection still maps 1 -> filtered[0].
    jq -r --argjson limit "$display_count" '
        .[:$limit]
        | reverse
        | to_entries[]
        | [
            ($limit - .key),
            (.value.name // .value.version_number // ""),
            ((.value.version_number // "") | tostring),
            ((.value.loaders // []) | join(", ")),
            ((.value.game_versions // []) | join(", "))
        ]
        | @tsv
    ' <<<"$filtered" |
    while IFS=$'\t' read -r number name version loaders games; do

        echo -e \
            "  ${CYAN}${number})${RESET} ${BOLD}${name}${RESET}" \
            >&2

        echo -e \
            "     Version: ${version}" \
            >&2

        echo -e \
            "     Loaders: ${loaders}" \
            >&2

        echo >&2

    done

    echo -e \
        "  ${RED}0)${RESET} Cancel" \
        >&2

    echo >&2

    local selection

    while true; do

        read -r \
            -p "Select a version [1-${display_count}, 0 to cancel]: " \
            selection

        if [[ "$selection" == "0" ]]; then
            echo "Cancelled." >&2
            return 1
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= display_count )); then

            jq -c \
                --argjson n "$selection" \
                '.[($n - 1)]' \
                <<<"$filtered"

            return 0
        fi

        echo \
            -e "${RED}Invalid selection.${RESET} Choose 1-${display_count} or 0." \
            >&2
    done
}

# ============================================================
# Download Modrinth File
# ============================================================

download_project_file() {
    local version="$1"
    local destination="$2"

    local file_url

    file_url="$(
        jq -r '
            (
                .files[]
                | select(.primary == true)
                | .url
            ) // (
                .files[0].url
            ) // empty
        ' <<<"$version"
    )"

    local file_name

    file_name="$(
        jq -r '
            (
                .files[]
                | select(.primary == true)
                | .filename
            ) // (
                .files[0].filename
            ) // empty
        ' <<<"$version"
    )"

    [[ -n "$file_url" ]] ||
        die "No downloadable file found."

    [[ -n "$file_name" ]] ||
        die "Modrinth returned no filename."

    mkdir -p "$destination"

    local output

    output="$destination/$file_name"

    if [[ -f "$output" ]]; then
        warn "$file_name is already installed."
        return 0
    fi

    info "Downloading ${BOLD}${file_name}${RESET}..."

    download_file "$file_url" "$output" ||
        die "Failed to download '$file_name'."

    success "Installed $file_name"
}

# ============================================================
# Install Modrinth Content
# ============================================================

install_modrinth_content() {
    local project_type="$1"
    local query="$2"
    local destination="$3"

    echo >&2
    echo -e "${CYAN}Searching Modrinth...${RESET}" >&2

    local project

    project="$(
        select_modrinth_project \
            "$query" \
            "$project_type" \
            "$AUTO_YES"
    )" || return 1

    local title

    title="$(jq -r '.title // "Unknown"' <<<"$project")"

    local slug

    slug="$(jq -r '.slug // .project_id // "unknown"' <<<"$project")"

    echo >&2
    echo -e "${BOLD}Selected:${RESET} $title" >&2
    echo -e "Slug: $slug" >&2

    local version

    version="$(
        select_project_version "$project"
    )" || return 1

    download_project_file \
        "$version" \
        "$destination"
}

# ============================================================
# Vanilla Minecraft
# ============================================================

install_vanilla_version() {
    local version="$1"

    [[ -n "$version" ]] ||
        die "Minecraft version is required."

    local manifest_url

    manifest_url="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

    info "Checking Minecraft version ${BOLD}${version}${RESET}..."

    local manifest

    manifest="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --connect-timeout 10 \
            --max-time 30 \
            "$manifest_url"
    )" || die "Failed to retrieve Minecraft version manifest."

    local version_url

    version_url="$(
        jq -r \
            --arg version "$version" '
            .versions[]
            | select(.id == $version)
            | .url
        ' <<<"$manifest" |
        head -n 1
    )"

    [[ -n "$version_url" ]] ||
        die "Minecraft version '$version' does not exist."

    local version_dir

    version_dir="$GAME_DIR/versions/$version"

    mkdir -p "$version_dir"

    local json_file

    json_file="$version_dir/$version.json"

    local jar_file

    jar_file="$version_dir/$version.jar"

    info "Downloading version metadata..."

    download_file \
        "$version_url" \
        "$json_file" ||
        die "Failed to download Minecraft metadata."

    local client_url

    client_url="$(
        jq -r '.downloads.client.url // empty' "$json_file"
    )"

    [[ -n "$client_url" ]] ||
        die "Minecraft version has no client download."

    if [[ ! -f "$jar_file" ]]; then

        info "Downloading Minecraft client..."

        download_file \
            "$client_url" \
            "$jar_file" ||
            die "Failed to download Minecraft client."

    fi

    success "Minecraft $version installed."
}

# ============================================================
# Fabric
# ============================================================

install_fabric() {
    local minecraft_version="$TARGET_VERSION"

    [[ -n "$minecraft_version" ]] ||
        die "Fabric requires --version <minecraft-version>."

    info "Getting Fabric versions..."

    local loaders

    loaders="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --connect-timeout 10 \
            --max-time 30 \
            "${FABRIC_META}/versions/loader/${minecraft_version}"
    )" || die "Failed to retrieve Fabric versions."

    local loader_version

    if [[ -n "$LOADER_VERSION" ]]; then

        loader_version="$LOADER_VERSION"

    else

        loader_version="$(
            jq -r '.[0].loader.version // empty' <<<"$loaders"
        )"

    fi

    [[ -n "$loader_version" ]] ||
        die "No Fabric loader found for Minecraft $minecraft_version."

    local profile_url

    profile_url="${FABRIC_META}/versions/loader/"
    profile_url+="${minecraft_version}/"
    profile_url+="${loader_version}/profile/json"

    info "Downloading Fabric ${loader_version} profile..."

    local profile

    profile="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --connect-timeout 10 \
            --max-time 30 \
            "$profile_url"
    )" || die "Failed to retrieve Fabric profile."

    if ! jq -e . >/dev/null 2>&1 <<<"$profile"; then
        die "Fabric returned invalid JSON."
    fi

    local version_id

    version_id="fabric-loader-${loader_version}-${minecraft_version}"

    local version_dir

    version_dir="$GAME_DIR/versions/$version_id"

    mkdir -p "$version_dir"

    echo "$profile" |
        jq '.' > "$version_dir/$version_id.json"

    success \
        "Fabric ${loader_version} installed for Minecraft ${minecraft_version}."

    warn \
        "The launcher still needs to download/resolve Fabric libraries before this profile can be launched."
}

# ============================================================
# Arguments
# ============================================================

parse_arguments() {

    while [[ $# -gt 0 ]]; do

        local arg="$1"

        case "$arg" in

            --version)

                [[ $# -ge 2 ]] ||
                    die "--version requires a value."

                TARGET_VERSION="$2"

                shift 2
                ;;

            --loader)

                [[ $# -ge 2 ]] ||
                    die "--loader requires a value."

                LOADER="$2"

                shift 2
                ;;

            --loader-version)

                [[ $# -ge 2 ]] ||
                    die "--loader-version requires a value."

                LOADER_VERSION="$2"

                shift 2
                ;;

            --game-dir)

                [[ $# -ge 2 ]] ||
                    die "--game-dir requires a value."

                GAME_DIR="$2"

                shift 2
                ;;

            --yes|-y)

                AUTO_YES=1

                shift
                ;;

            --help|-h)

                cat >&2 <<EOF
Usage:

  mc install <type> [name] [options]

Types:

  version
  mod
  shader
  resourcepack
  modpack
  loader

Examples:

  mc install version 1.21.8

  mc install mod sodium

  mc install shader complementary

  mc install resourcepack faithful

  mc install modpack fabric

  mc install modpack

  mc install loader fabric --version 1.21.8

Options:

  --version VERSION
  --loader LOADER
  --loader-version VERSION
  --game-dir PATH
  --yes, -y

Notes:

  Without a name, Modrinth browse mode is used.

  Interactive selection is always shown unless --yes is used.

EOF

                exit 0
                ;;

            --*)

                die "Unknown option '$arg'."
                ;;

            *)

                if [[ -z "$QUERY" ]]; then
                    QUERY="$arg"
                else
                    QUERY="$QUERY $arg"
                fi

                shift
                ;;

        esac

    done
}

# ============================================================
# Main
# ============================================================

main() {

    check_dependencies

    [[ $# -ge 1 ]] ||
        die "Install type is required."

    local type="$1"

    shift

    parse_arguments "$@"

    case "$type" in

        # ====================================================
        # Vanilla Minecraft
        # ====================================================

        version)

            local version="$QUERY"

            [[ -n "$version" ]] ||
                version="$TARGET_VERSION"

            [[ -n "$version" ]] ||
                die "Minecraft version is required."

            install_vanilla_version "$version"
            ;;

        # ====================================================
        # Loader
        # ====================================================

        loader)

            [[ -n "$QUERY" ]] ||
                die "Loader name is required."

            case "$QUERY" in

                fabric)

                    install_fabric
                    ;;

                quilt)

                    die "Quilt installation is not implemented yet."
                    ;;

                forge)

                    die "Forge installation is not implemented yet."
                    ;;

                neoforge)

                    die "NeoForge installation is not implemented yet."
                    ;;

                *)

                    die "Unknown loader '$QUERY'."
                    ;;

            esac

            ;;

        # ====================================================
        # Mod
        # ====================================================

        mod)

            install_modrinth_content \
                "mod" \
                "$QUERY" \
                "$GAME_DIR/mods"
            ;;

        # ====================================================
        # Shader
        # ====================================================

        shader)

            install_modrinth_content \
                "shader" \
                "$QUERY" \
                "$GAME_DIR/shaderpacks"
            ;;

        # ====================================================
        # Resource Pack
        # ====================================================

        resourcepack)

            install_modrinth_content \
                "resourcepack" \
                "$QUERY" \
                "$GAME_DIR/resourcepacks"
            ;;

        # ====================================================
        # Modpack
        # ====================================================

        modpack)

            install_modrinth_content \
                "modpack" \
                "$QUERY" \
                "$GAME_DIR/modpacks"
            ;;

        *)

            die "Unknown install type '$type'."

            ;;

    esac
}

main "$@"
# ============================================================
