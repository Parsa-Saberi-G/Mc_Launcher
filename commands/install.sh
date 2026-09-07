#!/bin/bash

set -o pipefail

# ============================================================
# MC LAUNCHER — INSTALL
# ============================================================

MC_VERSION="0.1.0"

MODRINTH_API="https://api.modrinth.com/v2"
FABRIC_META="https://meta.fabricmc.net/v2"

MC_DATABASE="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)/data/versions.json"

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
    CYAN='\033[36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    CYAN=''
    BOLD=''
    DIM=''
    RESET=''
fi

# ============================================================
# Symbols
# ============================================================

SYM_INFO="◆"
SYM_LOAD="◌"
SYM_DOWNLOAD="↓"
SYM_INSTALL="+"
SYM_VERIFY="◇"
SYM_REMOVE="-"
SYM_WAIT="○"
SYM_SUCCESS="✓"
SYM_WARNING="!"
SYM_ERROR="×"

# ============================================================
# Helpers
# ============================================================

die() {
    printf '%b%s%b %s\n' \
        "$RED" \
        "$SYM_ERROR" \
        "$RESET" \
        "$*" >&2
    exit 1
}

info() {
    printf '%b%s%b %s\n' \
        "$CYAN" \
        "$SYM_INFO" \
        "$RESET" \
        "$*" >&2
}

success() {
    printf '%b%s%b %s\n' \
        "$GREEN" \
        "$SYM_SUCCESS" \
        "$RESET" \
        "$*" >&2
}

warn() {
    printf '%b%s%b %s\n' \
        "$RESET" \
        "$SYM_WARNING" \
        "$RESET" \
        "$*" >&2
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command '$1' is not installed."
}

check_dependencies() {
    require_command curl
    require_command jq
    require_command python3
    require_command sha1sum
    require_command du
    require_command awk
    require_command sed
    require_command tr
    require_command mktemp
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
# Terminal UI
# ============================================================

# ============================================================
# Global Progress
# ============================================================

TOTAL_STAGES=5
CURRENT_STAGE=0

draw_progress() {
    local current=$1
    local total=$2
    local width=22

    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    printf "   %bOverall%b  " "$CYAN" "$RESET" >&2

    printf "%b" "$GREEN"

    printf '◆%.0s' $(seq 1 $filled)

    printf "%b" "$DIM"

    printf '◇%.0s' $(seq 1 $empty)

    printf "%b %d%%%b\n" \
        "$RESET" \
        $((current * 100 / total)) \
        "$RESET" >&2
}


progress_stage() {
    CURRENT_STAGE=$((CURRENT_STAGE + 1))

    draw_progress \
        "$CURRENT_STAGE" \
        "$TOTAL_STAGES"
}


print_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-22}"

    if (( total <= 0 )); then
        total=1
    fi

    if (( current < 0 )); then
        current=0
    fi

    if (( current > total )); then
        current="$total"
    fi

    local filled=$((current * width / total))
    local empty=$((width - filled))

    local filled_bar=""
    local empty_bar=""

    if (( filled > 0 )); then
        filled_bar="$(printf '%*s' "$filled" '' | tr ' ' '●')"
    fi

    if (( empty > 0 )); then
        empty_bar="$(printf '%*s' "$empty" '' | tr ' ' '○')"
    fi

    local percent=$((current * 100 / total))

    printf '   %b%s%b%s  %3d%%' \
        "$CYAN" \
        "$filled_bar" \
        "$DIM" \
        "$empty_bar" \
        "$percent" >&2
}

operation() {
    local symbol="$1"
    local text="$2"

    printf '%b%s%b %s\n' \
        "$CYAN" \
        "$symbol" \
        "$RESET" \
        "$text" >&2
}

loading() {
    local text="$1"

    printf '%b%s%b %s' \
        "$CYAN" \
        "$SYM_LOAD" \
        "$RESET" \
        "$text" >&2
}

operation_success() {
    local text="$1"

    printf '%b%s%b %s\n' \
        "$GREEN" \
        "$SYM_SUCCESS" \
        "$RESET" \
        "$text" >&2
}

operation_error() {
    local text="$1"

    printf '%b%s%b %s\n' \
        "$RED" \
        "$SYM_ERROR" \
        "$RESET" \
        "$text" >&2
}

operation_warning() {
    local text="$1"

    printf '%b%s%b %s\n' \
        "$SYM_WARNING" \
        "$RESET" \
        "$text" >&2
}

operation_line() {
    local prefix="$1"
    local text="$2"

    printf '├─ %b%s%b %s\n' \
        "$CYAN" \
        "$prefix" \
        "$RESET" \
        "$text" >&2
}

operation_last() {
    local prefix="$1"
    local text="$2"

    printf '└─ %b%s%b %s\n' \
        "$CYAN" \
        "$prefix" \
        "$RESET" \
        "$text" >&2
}

sub_success() {
    printf '│  %b%s%b %s\n' \
        "$GREEN" \
        "$SYM_SUCCESS" \
        "$RESET" \
        "$1" >&2
}

sub_error() {
    printf '│  %b%s%b %s\n' \
        "$RED" \
        "$SYM_ERROR" \
        "$RESET" \
        "$1" >&2
}

sub_info() {
    printf '│  %b%s%b %s\n' \
        "$CYAN" \
        "$SYM_INFO" \
        "$RESET" \
        "$1" >&2
}

file_info() {
    local label="$1"
    local value="$2"

    printf '│  %b%-14s%b %s\n' \
        "$DIM" \
        "${label}:" \
        "$RESET" \
        "$value" >&2
}

format_size() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        printf '0 B'
        return
    fi

    du -h "$file" 2>/dev/null |
        awk '{print $1}'
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

# ============================================================
# Download with progress
# ============================================================

download_file() {
    local url="$1"
    local output="$2"
    local display_name="${3:-$(basename "$output")}"

    mkdir -p "$(dirname "$output")"

    local tmp="${output}.tmp"

    rm -f "$tmp"

    printf '\n' >&2

    printf '   %b%s%b %b%s%b\n' \
        "$CYAN" \
        "$SYM_DOWNLOAD" \
        "$RESET" \
        "$BOLD" \
        "$display_name" \
        "$RESET" >&2

    curl \
        --fail \
        --show-error \
        --location \
        --connect-timeout 10 \
        --max-time 3600 \
        --progress-bar \
        --retry 3 \
        --retry-delay 2 \
        -H "User-Agent: mc-launcher/${MC_VERSION}" \
        -o "$tmp" \
        "$url"

    local status=$?

    if (( status != 0 )); then
        rm -f "$tmp"

        printf '   %b%s%b Download failed\n' \
            "$RED" \
            "$SYM_ERROR" \
            "$RESET" >&2

        return "$status"
    fi

    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"

        printf '   %b%s%b Download produced an empty file\n' \
            "$RED" \
            "$SYM_ERROR" \
            "$RESET" >&2

        return 1
    fi

    mv -f "$tmp" "$output"

    local size
    size="$(format_size "$output")"

    printf '   %b%s%b Download complete  %b(%s)%b\n' \
        "$GREEN" \
        "$SYM_SUCCESS" \
        "$RESET" \
        "$DIM" \
        "$size" \
        "$RESET" >&2

    return 0
}

# ============================================================
# Modrinth Search
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
    # ========================================================

    local display_count="$count"

    (( display_count > 10 )) &&
        display_count=10

    echo >&2

    operation_line \
        "$SYM_INFO" \
        "Search results"

    if [[ -n "$query" ]]; then
        file_info "Query" "$query"
    else
        file_info "Browse" "Popular ${project_type}s"
    fi

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

        printf '├─ %b%s)%b %b%s%b\n' \
            "$CYAN" \
            "$number" \
            "$RESET" \
            "$BOLD" \
            "$title" \
            "$RESET" >&2

        if [[ -n "$description" ]]; then
            description="${description//$'\n'/ }"

            printf '│  %b%s%b\n' \
                "$DIM" \
                "${description:0:110}" \
                "$RESET" >&2
        fi

        printf '│  Downloads: %s\n' "$downloads" >&2
        printf '│  Slug: %s\n' "$slug" >&2
        echo >&2

    done

    printf '%b└─ 0)%b Cancel\n' \
        "$RED" \
        "$RESET" >&2

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

            jq -c \
                --argjson n "$selection" \
                '.hits[$n - 1]' \
                <<<"$ranked"

            return 0
        fi

        printf '%b%s%b Invalid selection. Choose 1-%d or 0.\n' \
            "$RED" \
            "$SYM_ERROR" \
            "$RESET" \
            "$display_count" >&2
    done
}

# ============================================================
# Select Project Version
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
    # Automatic mode
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

    operation_line \
        "$SYM_LOAD" \
        "Compatible versions"

    echo >&2

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

        printf '├─ %b%s)%b %b%s%b\n' \
            "$CYAN" \
            "$number" \
            "$RESET" \
            "$BOLD" \
            "$name" \
            "$RESET" >&2

        printf '│  Version: %s\n' "$version" >&2
        printf '│  Loaders: %s\n' "$loaders" >&2
        echo >&2

    done

    printf '%b└─ 0)%b Cancel\n' \
        "$RED" \
        "$RESET" >&2

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

        printf '%b%s%b Invalid selection. Choose 1-%d or 0.\n' \
            "$RED" \
            "$SYM_ERROR" \
            "$RESET" \
            "$display_count" >&2
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

    operation_line \
        "$SYM_DOWNLOAD" \
        "Downloading $file_name"

    download_file \
        "$file_url" \
        "$output" \
        "$file_name" ||
        die "Failed to download '$file_name'."

    operation_success "Installed $file_name"
}

# ============================================================
# Install Modrinth Content
# ============================================================

install_modrinth_content() {
    local project_type="$1"
    local query="$2"
    local destination="$3"

    echo >&2

    printf '%b%s%b %bModrinth %s%b\n' \
        "$CYAN" \
        "$SYM_INFO" \
        "$RESET" \
        "$BOLD" \
        "$project_type" \
        "$RESET" >&2

    file_info "Search" "${query:-popular}"
    file_info "Destination" "$destination"

    echo >&2

    operation_line \
        "$SYM_LOAD" \
        "Searching Modrinth..."

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

    operation_line \
        "$SYM_SUCCESS" \
        "Selected $title"

    file_info "Slug" "$slug"

    local version

    version="$(
        select_project_version "$project"
    )" || return 1

    local version_number

    version_number="$(
        jq -r '.version_number // "unknown"' <<<"$version"
    )"

    echo >&2

    file_info "Version" "$version_number"

    download_project_file \
        "$version" \
        "$destination"
}

# ============================================================
# Minecraft Database
# ============================================================

check_minecraft_database() {
    [[ -f "$MC_DATABASE" ]] ||
        die "Minecraft database not found.

Run:

  mc update database"

    jq -e . "$MC_DATABASE" >/dev/null 2>&1 ||
        die "Minecraft database contains invalid JSON:

  $MC_DATABASE

Run:

  mc update database"
}

# ============================================================
# Get Minecraft Version URL
# ============================================================

get_minecraft_version_url() {
    local version="$1"

    jq -r \
        --arg version "$version" '
        .versions[]
        | select(.id == $version)
        | .url // empty
        ' \
        "$MC_DATABASE" |
        head -n 1
}

# ============================================================
# Get Minecraft Metadata
# ============================================================

get_minecraft_metadata() {
    local version="$1"

    check_minecraft_database

    local stored_metadata

    stored_metadata="$(
        jq -c \
            --arg version "$version" '
            .versions[]
            | select(.id == $version)
            | .metadata
            | select(. != null)
            ' \
            "$MC_DATABASE" |
        head -n 1
    )"

    if [[ -n "$stored_metadata" ]]; then
        if jq -e . >/dev/null 2>&1 <<<"$stored_metadata"; then
            printf '%s\n' "$stored_metadata"
            return 0
        fi
    fi

    local version_url

    version_url="$(get_minecraft_version_url "$version")"

    [[ -n "$version_url" ]] ||
        return 1

    operation_line \
        "$SYM_DOWNLOAD" \
        "Downloading Minecraft ${version} metadata..."

    local metadata

    metadata="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --location \
            --connect-timeout 10 \
            --max-time 30 \
            -H "User-Agent: mc-launcher/${MC_VERSION}" \
            -H "Accept: application/json" \
            "$version_url"
    )" || return 1

    if ! jq -e . >/dev/null 2>&1 <<<"$metadata"; then
        return 1
    fi

    printf '%s\n' "$metadata"
}

# ============================================================
# SHA-1 Verification
# ============================================================

verify_sha1() {
    local file="$1"
    local expected="$2"

    [[ -z "$expected" ]] &&
        return 0

    [[ -f "$file" ]] ||
        return 1

    local actual

    actual="$(
        sha1sum "$file" |
        awk '{print $1}'
    )"

    [[ "$actual" == "$expected" ]]
}

# ============================================================
# Minecraft Library Rules
# ============================================================

minecraft_library_allowed() {
    local library="$1"

    local rules

    rules="$(jq -c '.rules // null' <<<"$library")"

    if [[ "$rules" == "null" ]]; then
        return 0
    fi

    local os_name="linux"
    local os_arch

    case "$(uname -m)" in
        x86_64|amd64)
            os_arch="x86_64"
            ;;
        i686|i386)
            os_arch="x86"
            ;;
        aarch64|arm64)
            os_arch="aarch64"
            ;;
        armv7l|armv7)
            os_arch="arm"
            ;;
        *)
            os_arch="$(uname -m)"
            ;;
    esac

    local matching_rules

    matching_rules="$(
        jq -c \
            --arg os "$os_name" \
            --arg arch "$os_arch" '
            [
                .[]
                | select(
                    (.os == null)
                    or (
                        (.os.name == null or .os.name == $os)
                        and
                        (.os.arch == null or .os.arch == $arch)
                    )
                )
            ]
            ' <<<"$rules"
    )"

    local matching_count

    matching_count="$(jq 'length' <<<"$matching_rules")"

    if (( matching_count == 0 )); then
        return 0
    fi

    local action

    action="$(
        jq -r '.[-1].action // "allow"' <<<"$matching_rules"
    )"

    [[ "$action" == "allow" ]]
}

# ============================================================
# Install Minecraft Libraries
# ============================================================

install_minecraft_libraries() {
    local metadata="$1"
    local version="$2"

    echo >&2

    operation_line \
        "$SYM_INSTALL" \
        "Installing libraries"

    local libraries

    libraries="$(
        jq -c '.libraries // []' <<<"$metadata"
    )"

    local total

    total="$(jq 'length' <<<"$libraries")"

    if (( total == 0 )); then
        operation_warning "No libraries listed for Minecraft $version."
        return 0
    fi

    file_info "Version" "$version"
    file_info "Libraries" "$total"
    file_info "Directory" "$GAME_DIR/libraries"

    echo >&2

    local downloaded=0
    local existing=0
    local failed=0
    local skipped=0
    local processed=0

    while IFS= read -r library; do
        processed=$((processed + 1))

        local name

        name="$(jq -r '.name // "unknown"' <<<"$library")"

        printf '│  %b[%d/%d]%b %s\n' \
            "$DIM" \
            "$processed" \
            "$total" \
            "$RESET" \
            "$name" >&2

        if ! minecraft_library_allowed "$library"; then
            skipped=$((skipped + 1))
            continue
        fi

        # ====================================================
        # Normal artifact
        # ====================================================

        local artifact_url
        local artifact_path
        local artifact_sha1

        artifact_url="$(
            jq -r \
                '.downloads.artifact.url // empty' \
                <<<"$library"
        )"

        artifact_path="$(
            jq -r \
                '.downloads.artifact.path // empty' \
                <<<"$library"
        )"

        artifact_sha1="$(
            jq -r \
                '.downloads.artifact.sha1 // empty' \
                <<<"$library"
        )"

        if [[ -n "$artifact_url" && -n "$artifact_path" ]]; then
            local output

            output="$GAME_DIR/libraries/$artifact_path"

            mkdir -p "$(dirname "$output")"

            if [[ -f "$output" && -s "$output" ]]; then
                if [[ -n "$artifact_sha1" ]] &&
                   ! verify_sha1 "$output" "$artifact_sha1"; then

                    operation_warning \
                        "Invalid library checksum, redownloading: $name"

                    rm -f "$output"
                else
                    existing=$((existing + 1))
                fi
            fi

            if [[ ! -f "$output" ]]; then
                if download_file \
                    "$artifact_url" \
                    "$output" \
                    "$(basename "$artifact_path")"; then

                    if [[ -n "$artifact_sha1" ]]; then
                        if verify_sha1 "$output" "$artifact_sha1"; then
                            sub_success "SHA-1 verified"
                        else
                            rm -f "$output"

                            sub_error \
                                "SHA-1 verification failed"

                            failed=$((failed + 1))
                            continue
                        fi
                    fi

                    downloaded=$((downloaded + 1))
                else
                    failed=$((failed + 1))
                fi
            fi
        fi

        # ====================================================
        # Linux native
        # ====================================================

        local native_key=""

        while IFS= read -r classifier; do
            [[ -z "$classifier" ]] &&
                continue

            case "$classifier" in
                natives-linux)
                    native_key="$classifier"
                    break
                    ;;
            esac
        done < <(
            jq -r '
                .downloads.classifiers // {}
                | keys[]
            ' <<<"$library"
        )

        if [[ -n "$native_key" ]]; then
            local native_url
            local native_path
            local native_sha1

            native_url="$(
                jq -r \
                    --arg key "$native_key" \
                    '.downloads.classifiers[$key].url // empty' \
                    <<<"$library"
            )"

            native_path="$(
                jq -r \
                    --arg key "$native_key" \
                    '.downloads.classifiers[$key].path // empty' \
                    <<<"$library"
            )"

            native_sha1="$(
                jq -r \
                    --arg key "$native_key" \
                    '.downloads.classifiers[$key].sha1 // empty' \
                    <<<"$library"
            )"

            if [[ -n "$native_url" && -n "$native_path" ]]; then
                local native_output

                native_output="$GAME_DIR/libraries/$native_path"

                mkdir -p "$(dirname "$native_output")"

                if [[ -f "$native_output" &&
                      -s "$native_output" ]]; then

                    if [[ -n "$native_sha1" ]] &&
                       ! verify_sha1 \
                            "$native_output" \
                            "$native_sha1"; then

                        operation_warning \
                            "Invalid native checksum, redownloading: $name"

                        rm -f "$native_output"
                    else
                        existing=$((existing + 1))
                    fi
                fi

                if [[ ! -f "$native_output" ]]; then
                    if download_file \
                        "$native_url" \
                        "$native_output" \
                        "$(basename "$native_path")"; then

                        if [[ -n "$native_sha1" ]]; then
                            if verify_sha1 \
                                "$native_output" \
                                "$native_sha1"; then

                                sub_success "SHA-1 verified"
                            else
                                rm -f "$native_output"

                                sub_error \
                                    "SHA-1 verification failed"

                                failed=$((failed + 1))
                                continue
                            fi
                        fi

                        downloaded=$((downloaded + 1))
                    else
                        failed=$((failed + 1))
                    fi
                fi
            fi
        fi

    done < <(
        jq -c '.[]' <<<"$libraries"
    )

    echo >&2

    operation_line \
        "$SYM_SUCCESS" \
        "Libraries processed"

    file_info "Downloaded" "$downloaded"
    file_info "Existing" "$existing"
    file_info "Skipped" "$skipped"
    file_info "Failed" "$failed"

    if (( failed > 0 )); then
        return 1
    fi

    return 0
}

# ============================================================
# Install Minecraft Assets
# ============================================================

install_minecraft_assets() {
    local metadata="$1"
    local version="$2"

    echo >&2

    operation_line \
        "$SYM_INSTALL" \
        "Installing assets"

    local asset_index_id
    local asset_index_url
    local asset_index_sha1

    asset_index_id="$(
        jq -r \
            '.assetIndex.id // empty' \
            <<<"$metadata"
    )"

    asset_index_url="$(
        jq -r \
            '.assetIndex.url // empty' \
            <<<"$metadata"
    )"

    asset_index_sha1="$(
        jq -r \
            '.assetIndex.sha1 // empty' \
            <<<"$metadata"
    )"

    if [[ -z "$asset_index_id" ||
          -z "$asset_index_url" ]]; then

        operation_warning \
            "No asset index found for Minecraft $version."

        return 0
    fi

    local indexes_dir="$GAME_DIR/assets/indexes"
    local objects_dir="$GAME_DIR/assets/objects"

    mkdir -p \
        "$indexes_dir" \
        "$objects_dir"

    local index_file="$indexes_dir/${asset_index_id}.json"

    file_info "Version" "$version"
    file_info "Index" "$asset_index_id"
    file_info "Directory" "$objects_dir"

    echo >&2

    operation_line \
        "$SYM_LOAD" \
        "Preparing asset index..."

    if [[ -f "$index_file" && -s "$index_file" ]]; then
        if [[ -n "$asset_index_sha1" ]] &&
           ! verify_sha1 "$index_file" "$asset_index_sha1"; then

            operation_warning \
                "Asset index checksum invalid."

            operation_line \
                "$SYM_DOWNLOAD" \
                "Redownloading asset index..."

            rm -f "$index_file"
        else
            operation_success \
                "Asset index already present"
        fi
    fi

    if [[ ! -f "$index_file" ]]; then
        download_file \
            "$asset_index_url" \
            "$index_file" \
            "${asset_index_id}.json" ||
            die "Failed to download asset index."

        if [[ -n "$asset_index_sha1" ]] &&
           ! verify_sha1 "$index_file" "$asset_index_sha1"; then

            rm -f "$index_file"

            die "Asset index SHA1 verification failed."
        fi

        operation_success \
            "Asset index SHA1 verified"
    fi

    local asset_count

    asset_count="$(
        jq '.objects // {} | length' "$index_file"
    )"

    file_info "Assets" "$asset_count"

    echo >&2

    operation_line \
        "$SYM_DOWNLOAD" \
        "Downloading Minecraft assets..."

    local downloaded=0
    local existing=0
    local failed=0
    local processed=0

    while IFS=$'\t' read -r asset_name asset_hash; do
        [[ -z "$asset_hash" ]] &&
            continue

        processed=$((processed + 1))

        local prefix="${asset_hash:0:2}"
        local output="$objects_dir/$prefix/$asset_hash"

        mkdir -p "$(dirname "$output")"

        printf '│  %b[%d/%d]%b %s\n' \
            "$DIM" \
            "$processed" \
            "$asset_count" \
            "$RESET" \
            "$asset_name" >&2

        if [[ -f "$output" && -s "$output" ]]; then
            if verify_sha1 "$output" "$asset_hash"; then
                existing=$((existing + 1))
                continue
            fi

            rm -f "$output"
        fi

        local asset_url

        asset_url="https://resources.download.minecraft.net/${prefix}/${asset_hash}"

        if download_file \
            "$asset_url" \
            "$output" \
            "$asset_name"; then

            if verify_sha1 "$output" "$asset_hash"; then
                sub_success "SHA-1 verified"
                downloaded=$((downloaded + 1))
            else
                rm -f "$output"

                sub_error \
                    "Asset checksum mismatch: $asset_name"

                failed=$((failed + 1))
            fi
        else
            operation_warning \
                "Failed to download asset: $asset_name"

            failed=$((failed + 1))
        fi

    done < <(
        jq -r '
            .objects // {}
            | to_entries[]
            | [
                .key,
                .value.hash
            ]
            | @tsv
        ' "$index_file"
    )

    echo >&2

    operation_line \
        "$SYM_SUCCESS" \
        "Assets processed"

    file_info "Downloaded" "$downloaded"
    file_info "Existing" "$existing"
    file_info "Failed" "$failed"

    if (( failed > 0 )); then
        return 1
    fi

    return 0
}

# ============================================================
# Vanilla Minecraft
# ============================================================

install_vanilla_version() {
    local version="$1"

    [[ -n "$version" ]] ||
        die "Minecraft version is required."

    echo >&2

    printf '%b%s%b %bMinecraft %s%b\n' \
        "$CYAN" \
        "$SYM_INFO" \
        "$RESET" \
        "$BOLD" \
        "$version" \
        "$RESET" >&2

    printf '│\n' >&2

    file_info "Game directory" "$GAME_DIR"
    file_info "Version" "$version"

    # ========================================================
    # Stage 1
    # ========================================================

    echo >&2

    operation_line \
        "$SYM_LOAD" \
        "Loading metadata..."

    check_minecraft_database

    local metadata

    metadata="$(
        get_minecraft_metadata "$version"
    )" || {
        die "Minecraft version '$version' was not found in the database."
    }

    [[ -n "$metadata" ]] ||
        die "Minecraft metadata for '$version' is empty."

    if ! jq -e . >/dev/null 2>&1 <<<"$metadata"; then
        die "Minecraft metadata for '$version' is invalid."
    fi

    local actual_version

    actual_version="$(jq -r '.id // empty' <<<"$metadata")"

    if [[ "$actual_version" != "$version" ]]; then
        die "Minecraft metadata ID mismatch:

Expected: $version

Received: $actual_version"
    fi

    local release_type

    release_type="$(jq -r '.type // "unknown"' <<<"$metadata")"

    sub_success "Version found"

    file_info "Type" "$release_type"

    # ========================================================
    # Version directory
    # ========================================================

    local version_dir

    version_dir="$GAME_DIR/versions/$version"

    mkdir -p "$version_dir"

    local json_file
    local jar_file

    json_file="$version_dir/$version.json"
    jar_file="$version_dir/$version.jar"

    # ========================================================
    # Save metadata
    # ========================================================

    printf '%s\n' "$metadata" |
        jq '.' > "$json_file" ||
        die "Failed to save Minecraft metadata."

    # ========================================================
    # Stage 2 — Client
    # ========================================================

    echo >&2

    operation_line \
        "$SYM_DOWNLOAD" \
        "Downloading client.jar"

    local client_url
    local client_sha1

    client_url="$(
        jq -r \
            '.downloads.client.url // empty' \
            <<<"$metadata"
    )"

    client_sha1="$(
        jq -r \
            '.downloads.client.sha1 // empty' \
            <<<"$metadata"
    )"

    [[ -n "$client_url" ]] ||
        die "Minecraft $version has no client download URL."

    if [[ -f "$jar_file" && -s "$jar_file" ]]; then
        if [[ -n "$client_sha1" ]] &&
           ! verify_sha1 "$jar_file" "$client_sha1"; then

            operation_warning \
                "Existing Minecraft client has an invalid checksum."

            operation_line \
                "$SYM_DOWNLOAD" \
                "Redownloading client..."

            rm -f "$jar_file"
        else
            operation_success \
                "Minecraft client already present"
        fi
    fi

    if [[ ! -f "$jar_file" ]]; then
        download_file \
            "$client_url" \
            "$jar_file" \
            "$version.jar" ||
            die "Failed to download Minecraft client."

        if [[ -n "$client_sha1" ]]; then
            if verify_sha1 "$jar_file" "$client_sha1"; then
                sub_success "Client SHA-1 verified"
            else
                rm -f "$jar_file"

                die "Minecraft client SHA1 verification failed."
            fi
        fi
    fi

    operation_success \
        "Minecraft client ready"

    # ========================================================
    # Stage 3 — Libraries
    # ========================================================

    echo >&2

    operation_line \
        "$SYM_INSTALL" \
        "Installing libraries"

    install_minecraft_libraries \
        "$metadata" \
        "$version" ||
        die "One or more Minecraft libraries failed to download."

    operation_success \
        "Libraries ready"

    # ========================================================
    # Stage 4 — Assets
    # ========================================================

    echo >&2

    operation_line \
        "$SYM_INSTALL" \
        "Installing assets"

    install_minecraft_assets \
        "$metadata" \
        "$version" ||
        die "One or more Minecraft assets failed to download."

    operation_success \
        "Assets ready"

    # ========================================================
    # Stage 5 — Finalization
    # ========================================================

    echo >&2

    operation_line \
        "$SYM_VERIFY" \
        "Finalizing installation"

    mkdir -p \
        "$GAME_DIR/versions" \
        "$GAME_DIR/libraries" \
        "$GAME_DIR/assets" \
        "$GAME_DIR/assets/indexes" \
        "$GAME_DIR/assets/objects" \
        "$GAME_DIR/natives/$version" \
        "$GAME_DIR/mods" \
        "$GAME_DIR/config" \
        "$GAME_DIR/logs"

    local client_size

    client_size="$(
        format_size "$jar_file"
    )"

    sub_success "Client SHA1"
    sub_success "Libraries"
    sub_success "Assets"

    echo >&2

    printf '└─ %b%s%b %bInstallation complete%b\n' \
        "$GREEN" \
        "$SYM_SUCCESS" \
        "$RESET" \
        "$BOLD" \
        "$RESET" >&2

    printf '   Minecraft: %s\n' "$version" >&2
    printf '   Type:      %s\n' "$release_type" >&2
    printf '   Client:    %s\n' "$client_size" >&2
    printf '   Directory: %s\n' "$GAME_DIR" >&2

    echo >&2
}

# ============================================================
# Fabric
# ============================================================

install_fabric() {
    local minecraft_version="$TARGET_VERSION"

    [[ -n "$minecraft_version" ]] ||
        die "Fabric requires --version <minecraft-version>."

    echo >&2

    printf '%b%s%b %bFabric Loader%b\n' \
        "$CYAN" \
        "$SYM_INFO" \
        "$RESET" \
        "$BOLD" \
        "$RESET" >&2

    file_info "Minecraft" "$minecraft_version"

    echo >&2

    operation_line \
        "$SYM_LOAD" \
        "Getting Fabric versions..."

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
            jq -r \
                '.[0].loader.version // empty' \
                <<<"$loaders"
        )"
    fi

    [[ -n "$loader_version" ]] ||
        die "No Fabric loader found for Minecraft $minecraft_version."

    local profile_url

    profile_url="${FABRIC_META}/versions/loader/"
    profile_url+="${minecraft_version}/"
    profile_url+="${loader_version}/profile/json"

    echo >&2

    file_info "Loader" "$loader_version"

    operation_line \
        "$SYM_DOWNLOAD" \
        "Downloading Fabric profile..."

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
        jq '.' > "$version_dir/$version_id.json" ||
        die "Failed to save Fabric profile."

    operation_success \
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
                cat >&2 <<'EOF'
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

  Minecraft version metadata is downloaded lazily from the
  local Minecraft database when installing a version.

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