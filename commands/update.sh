#!/bin/bash
# MC Launcher shared UI
MC_COMMAND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MC_COMMAND_DIR/ui.sh"


set -o pipefail

MC_VERSION="0.1.0"

MODRINTH_API="https://api.modrinth.com/v2"
GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"
MODS_DIR="$GAME_DIR/mods"

AUTO_YES=0

info() {
    echo "Info: $*"
}

success() {
    echo "✓ $*"
}

warn() {
    echo "Warning: $*" >&2
}

die() {
    echo "Error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command not found: $1"
}

check_dependencies() {
    require_command curl
    require_command jq
}

modrinth_get() {
    local url="$1"

    curl -fsSL \
        -A "mc-launcher/$MC_VERSION" \
        "$url"
}

download_file() {
    local url="$1"
    local destination="$2"

    curl -fL \
        --progress-bar \
        -A "mc-launcher/$MC_VERSION" \
        "$url" \
        -o "$destination"
}

find_project() {
    local query="$1"

    local encoded
    encoded="$(python3 - "$query" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
)"

    modrinth_get \
        "$MODRINTH_API/search?query=$encoded&limit=10&index=relevance"
}

get_project_versions() {
    local project_id="$1"

    modrinth_get \
        "$MODRINTH_API/project/$project_id/version"
}

select_project() {
    local json="$1"

    local count
    count="$(jq '.hits | length' <<<"$json")"

    if (( count == 0 )); then
        return 1
    fi

    local display_count="$count"

    (( display_count > 10 )) && display_count=10

    echo
    echo "Possible matches:"
    echo

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
    ' <<<"$json" |
    while IFS=$'\t' read -r number title description downloads slug; do
        printf " %2s) %s\n" "$number" "$title"
        printf "      %s\n" "$description"
        printf "      Downloads: %s\n" "$downloads"
        printf "      Slug: %s\n" "$slug"
        echo
    done

    echo "  0) Cancel"
    echo

    while true; do
        read -r -p "Select a project [1-$display_count, 0 to cancel]: " selection

        if [[ "$selection" == "0" ]]; then
            return 2
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] &&
           (( selection >= 1 && selection <= display_count )); then

            jq -c \
                --argjson n "$selection" \
                '.hits[$n - 1]' \
                <<<"$json"

            return 0
        fi

        echo "Invalid selection."
    done
}

update_one_mod() {
    local installed_file="$1"

    local filename
    filename="$(basename "$installed_file")"

    echo
    echo "Checking: $filename"

    local query
    query="${filename%.jar}"

    local search_result
    search_result="$(find_project "$query")" || {
        warn "Could not search Modrinth for $filename"
        return 1
    }

    local project
    project="$(select_project "$search_result")"

    local status=$?

    if (( status == 2 )); then
        return 0
    fi

    if (( status != 0 )) || [[ -z "$project" ]]; then
        warn "No project selected for $filename"
        return 1
    fi

    local project_id
    project_id="$(jq -r '.project_id // .id // .slug // empty' <<<"$project")"

    local project_title
    project_title="$(jq -r '.title // .slug // empty' <<<"$project")"

    echo
    echo "Selected: $project_title"

    local versions
    versions="$(get_project_versions "$project_id")" || {
        warn "Could not get versions for $project_title"
        return 1
    }

    local latest
    latest="$(
        jq -c '
            sort_by(
                .date_published // ""
            )
            | reverse
            | .[]
            | select((.files // []) | length > 0)
        ' <<<"$versions" |
        head -n 1
    )"

    if [[ -z "$latest" ]]; then
        warn "No downloadable version found."
        return 1
    fi

    local latest_version
    latest_version="$(jq -r '.version_number // .name // "unknown"' <<<"$latest")"

    local file
    file="$(
        jq -r '
            (.files // [])
            | map(select(.primary == true))
            | .[0].url //
              (
                (.files // [])
                | .[0].url
              ) //
              empty
        ' <<<"$latest"
    )"

    local new_name
    new_name="$(
        jq -r '
            (.files // [])
            | map(select(.primary == true))
            | .[0].filename //
              (
                (.files // [])
                | .[0].filename
              ) //
              empty
        ' <<<"$latest"
    )"

    [[ -n "$file" ]] || {
        warn "No downloadable file found."
        return 1
    }

    [[ -n "$new_name" ]] || {
        warn "No filename found."
        return 1
    }

    echo
    echo "Latest version: $latest_version"
    echo "File: $new_name"
    echo

    if (( AUTO_YES == 0 )); then
        read -r -p "Update this mod? [y/N]: " confirm

        case "${confirm,,}" in
            y|yes)
                ;;
            *)
                echo "Skipped."
                return 0
                ;;
        esac
    fi

    local temp_file
    temp_file="$(mktemp "$MODS_DIR/.mc-update-XXXXXX.jar")"

    echo "Downloading $new_name..."

    if ! download_file "$file" "$temp_file"; then
        rm -f "$temp_file"
        warn "Download failed."
        return 1
    fi

    rm -f -- "$installed_file"

    mv "$temp_file" "$MODS_DIR/$new_name" || {
        rm -f "$temp_file"
        warn "Could not install updated file."
        return 1
    }

    success "Updated $new_name"
}

update_all_mods() {
    [[ -d "$MODS_DIR" ]] ||
        die "Mods directory does not exist."

    shopt -s nullglob

    local files=("$MODS_DIR"/*.jar)

    if (( ${#files[@]} == 0 )); then
        echo "No installed mods found."
        return 0
    fi

    echo "Checking ${#files[@]} installed mod(s)..."

    for file in "${files[@]}"; do
        update_one_mod "$file"
    done
}

main() {
    check_dependencies

    local action="${1:-}"

    case "$action" in
        mods)
            shift
            update_all_mods
            ;;

        mod)
            shift

            [[ $# -gt 0 ]] ||
                die "Usage: mc update mod <name>"

            local query="$*"

            shopt -s nullglob

            local files=("$MODS_DIR"/*.jar)
            local matches=()

            for file in "${files[@]}"; do
                name="$(basename "$file")"

                if [[ "${name,,}" == *"${query,,}"* ]]; then
                    matches+=("$file")
                fi
            done

            if (( ${#matches[@]} == 0 )); then
                die "No installed mod matching '$query' found."
            fi

            echo
            echo "Installed mod matches:"
            echo

            for i in "${!matches[@]}"; do
                printf " %2d) %s\n" \
                    "$((i + 1))" \
                    "$(basename "${matches[$i]}")"
            done

            echo
            echo "  0) Cancel"
            echo

            while true; do
                read -r -p "Select a mod [1-${#matches[@]}, 0 to cancel]: " selection

                if [[ "$selection" == "0" ]]; then
                    exit 0
                fi

                if [[ "$selection" =~ ^[0-9]+$ ]] &&
                   (( selection >= 1 && selection <= ${#matches[@]} )); then

                    update_one_mod "${matches[$((selection - 1))]}"
                    break
                fi

                echo "Invalid selection."
            done
            ;;

        database)
            # Keep your existing database-update implementation here.
            echo "Use your existing database update implementation."
            ;;

        *)
            cat <<EOF
Usage:
  mc update mods
  mc update mod <name>
  mc update database
EOF
            exit 1
            ;;
    esac
}

main "$@"