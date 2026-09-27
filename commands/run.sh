#!/bin/bash

set -o pipefail

# ============================================================
# MC LAUNCHER — RUN
# ============================================================

MC_VERSION="0.1.0"

GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"

AUTO_YES=0

# Colors
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
    printf '%bError:%b %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

info() { echo -e "$*" >&2; }
warn() { printf '%b!%b %s\n' "$YELLOW" "$RESET" "$*" >&2; }
success() { printf '%b✓%b %s\n' "$GREEN" "$RESET" "$*" >&2; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command '$1' is not installed."
}

check_dependencies() {
    # for running we need java and unzip (for modpack detection)
    require_command java
    require_command jq
    require_command sha1sum
    require_command unzip || true
}

# helpers to get installed versions and modpacks
list_installed_versions() {
    local versions_dir="$GAME_DIR/versions"
    [[ -d "$versions_dir" ]] || return 0
    shopt -s nullglob
    for d in "$versions_dir"/*; do
        [[ -d "$d" ]] || continue
        basename "$d"
    done
}

list_installed_modpacks() {
    local mdir="$GAME_DIR/modpacks"
    [[ -d "$mdir" ]] || return 0
    shopt -s nullglob
    for f in "$mdir"/*; do
        if [[ -d "$f" ]]; then
            basename "$f"
        else
            basename "$f"
        fi
    done
}

# Build classpath from version metadata
build_classpath() {
    local json_file="$1"
    local cp_entries=()

    # include all library paths from metadata if available
    # metadata may contain .libraries[] with .downloads.artifact.path
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        cp_entries+=("$GAME_DIR/libraries/$path")
    done < <(jq -r '.libraries // [] | .[] | .downloads.artifact.path // empty' "$json_file")

    # include version jar
    local version_name
    version_name="$(basename "$json_file" .json)"
    local version_jar="$GAME_DIR/versions/$version_name/$version_name.jar"
    cp_entries+=("$version_jar")

    # also include all jars in libraries dir (fallback)
    for jar in "$GAME_DIR"/libraries/**/*.jar 2>/dev/null; do
        [[ -f "$jar" ]] || continue
        cp_entries+=("$jar")
    done

    # produce colon-separated classpath
    local IFS=:
    echo "${cp_entries[*]}" | sed 's::\(::g'
}

# Extract main class from metadata
get_main_class() {
    local json_file="$1"
    # try common fields
    jq -r '(.mainClass // .main_class // .minecraftArguments | select(type=="string") | "")' "$json_file" 2>/dev/null || true
    # better attempt: try .mainClass
    local m
    m="$(jq -r '.mainClass // empty' "$json_file" 2>/dev/null)"
    if [[ -n "$m" ]]; then
        printf '%s\n' "$m"
        return
    fi
    # fallback to legacy launcher main for older versions
    echo "net.minecraft.client.main.Main"
}

# Build game arguments string
build_game_args() {
    local json_file="$1"
    local version_name
    version_name="$(basename "$json_file" .json)"

    # try modern arguments.game (array) -> join strings, ignore objects
    local args
    args="$(jq -r 'if .arguments and .arguments.game then (.arguments.game | map(if type=="string" then . else "" end) | join(" ")) elif .minecraftArguments then .minecraftArguments else "" end' "$json_file" 2>/dev/null)"

    # basic placeholders
    args="${args//\$\{version_name\}/$version_name}"
    args="${args//\$\{game_directory\}/$GAME_DIR}"
    args="${args//\$\{assets_root\}/$GAME_DIR/assets}"
    args="${args//\$\{assets_index_name\}/$(jq -r '.assetIndex.id // empty' "$json_file" || echo '')}"

    # common minimal required args if none present
    if [[ -z "$args" ]]; then
        args="--username Player --version $version_name --gameDir $GAME_DIR --assetsDir $GAME_DIR/assets --assetIndexName $(jq -r '.assetIndex.id // empty' "$json_file" || echo '')"
    fi

    echo "$args"
}

run_version() {
    local version="$1"
    [[ -n "$version" ]] || die "Version is required."

    local json_file="$GAME_DIR/versions/$version/$version.json"
    local jar_file="$GAME_DIR/versions/$version/$version.jar"

    [[ -f "$json_file" ]] || die "Version metadata not found: $json_file"
    [[ -f "$jar_file" ]] || die "Version jar not found: $jar_file"

    info "Preparing to run Minecraft $version"

    local main_class
    main_class="$(jq -r '.mainClass // empty' "$json_file")"
    if [[ -z "$main_class" ]]; then
        # some metadata don't include mainClass; fallback
        main_class="$(jq -r '.main_class // empty' "$json_file")"
    fi
    # fallback to common main
    [[ -n "$main_class" ]] || main_class="net.minecraft.client.main.Main"

    local classpath
    classpath="$(build_classpath "$json_file")"

    # if classpath empty, include jar only
    if [[ -z "$classpath" ]]; then
        classpath="$jar_file"
    fi

    local game_args
    game_args="$(build_game_args "$json_file")"

    info "Main class: $main_class"
    info "Classpath length: ${#classpath}"

    echo
    info "Launching..."
    echo

    # run with reasonable defaults; user can pass additional JVM args after '--'
    # support: mc run <version> -- <jvm-args>

    # collect extra jvm args separated after --
    local extra_jvm=()
    local saw_dash=false
    for a in "$@"; do
        if [[ "$a" == "--" ]]; then
            saw_dash=true
            continue
        fi
        if [[ "$saw_dash" == true ]]; then
            extra_jvm+=("$a")
        fi
    done

    # default memory
    local mem="-Xmx2G"

    java $mem "${extra_jvm[@]}" -cp "$classpath" "$main_class" $game_args
}

# Attempt to detect modpack version. Supports:
# - modpacks/<name>/manifest.json (common)
# - modpacks/<name>/instance.json
# - modpacks/<name>/versions/<version>
get_modpack_minecraft_version() {
    local name="$1"
    local base="$GAME_DIR/modpacks/$name"
    [[ -d "$base" ]] || return 1

    if [[ -f "$base/manifest.json" ]]; then
        jq -r '.minecraft?.version // .manifest?.minecraftVersion // .minecraft_version // empty' "$base/manifest.json" 2>/dev/null || true
    elif [[ -f "$base/instance.json" ]]; then
        jq -r '.minecraftVersion // .minecraft?.version // empty' "$base/instance.json" 2>/dev/null || true
    elif [[ -d "$base/versions" ]]; then
        # pick newest directory inside versions
        local v
        v="$(ls -1 "$base/versions" | tail -n1 2>/dev/null)"
        printf '%s\n' "$v"
    else
        return 1
    fi
}

run_modpack() {
    local name="$1"
    [[ -n "$name" ]] || die "Modpack name is required."

    local base="$GAME_DIR/modpacks/$name"
    if [[ ! -d "$base" && ! -f "$base" ]]; then
        die "Modpack '$name' not found in $GAME_DIR/modpacks"
    fi

    # try directory-based modpack
    local mc_version
    mc_version="$(get_modpack_minecraft_version "$name")"
    if [[ -n "$mc_version" ]]; then
        info "Modpack $name targets Minecraft $mc_version"
        run_version "$mc_version" "$@"
        return $?
    fi

    # attempt to read manifest from zip
    if command -v unzip >/dev/null 2>&1 && [[ -f "$base" ]]; then
        local tmp
        tmp="$(mktemp -d)"
        unzip -q "$base" -d "$tmp" || { rm -rf "$tmp"; die "Failed to inspect modpack zip."; }
        if [[ -f "$tmp/manifest.json" ]]; then
            mc_version="$(jq -r '.minecraft?.version // .minecraftVersion // empty' "$tmp/manifest.json" 2>/dev/null || true)"
        fi
        rm -rf "$tmp"
        if [[ -n "$mc_version" ]]; then
            run_version "$mc_version" "$@"
            return $?
        fi
    fi

    die "Could not determine Minecraft version for modpack '$name'."
}

show_selection_and_run() {
    # present installed versions and modpacks and let user pick
    local versions=()
    while IFS= read -r v; do [[ -n "$v" ]] && versions+=("$v"); done < <(list_installed_versions)
    local modpacks=()
    while IFS= read -r m; do [[ -n "$m" ]] && modpacks+=("$m"); done < <(list_installed_modpacks)

    echo
    echo -e "${BOLD}${CYAN}Choose a runtime to launch${RESET}"
    echo
    local i=1
    declare -A map_type map_name

    if (( ${#versions[@]} > 0 )); then
        echo "Installed Versions:" >&2
        for v in "${versions[@]}"; do
            printf "  %2d) %s\n" "$i" "$v" >&2
            map_type[$i]=version
            map_name[$i]="$v"
            i=$((i+1))
        done
        echo >&2
    fi

    if (( ${#modpacks[@]} > 0 )); then
        echo "Installed Modpacks:" >&2
        for m in "${modpacks[@]}"; do
            printf "  %2d) %s\n" "$i" "$m" >&2
            map_type[$i]=modpack
            map_name[$i]="$m"
            i=$((i+1))
        done
        echo >&2
    fi

    if (( i == 1 )); then
        echo "No installed versions or modpacks found. Try 'mc list' or 'mc install'." >&2
        return 1
    fi

    echo "  0) Cancel" >&2
    echo

    while true; do
        read -r -p "Select an entry [0-$((i-1))]: " sel
        if [[ "$sel" == "0" ]]; then
            echo "Cancelled." >&2
            return 1
        fi
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel < i )); then
            local typ="${map_type[$sel]}"
            local name="${map_name[$sel]}"
            if [[ "$typ" == "version" ]]; then
                run_version "$name"
                return $?
            else
                run_modpack "$name"
                return $?
            fi
        fi
        echo "Invalid selection." >&2
    done
}

parse_args() {
    ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y)
                AUTO_YES=1; shift ;;
            --game-dir)
                GAME_DIR="$2"; shift 2 ;;
            --help|-h)
                cat <<EOF >&2
Usage: mc run [version|modpack] [name] [-- <jvm-args>]

Examples:
  mc run 1.21.1
  mc run version 1.21.1
  mc run modpack mypack
  mc run    # interactive selection
EOF
                exit 0 ;;
            *) ARGS+=("$1"); shift ;;
        esac
    done
}

main() {
    check_dependencies

    parse_args "$@"

    if [[ ${#ARGS[@]} -eq 0 ]]; then
        show_selection_and_run
        return $?
    fi

    # accept: mc run <version>
    # or: mc run version <name>
    local first="${ARGS[0]}"
    if [[ "$first" == "version" ]]; then
        local v="${ARGS[1]}"
        [[ -n "$v" ]] || die "Version required."
        run_version "$v" "${ARGS[@]}"
        return $?
    elif [[ "$first" == "modpack" ]]; then
        local m="${ARGS[1]}"
        [[ -n "$m" ]] || die "Modpack name required."
        run_modpack "$m" "${ARGS[@]}"
        return $?
    else
        # if first looks like an installed version, run it
        if [[ -d "$GAME_DIR/versions/$first" ]]; then
            run_version "$first" "${ARGS[@]}"
            return $?
        fi
        # if first looks like a modpack
        if [[ -d "$GAME_DIR/modpacks/$first" || -f "$GAME_DIR/modpacks/$first" ]]; then
            run_modpack "$first" "${ARGS[@]}"
            return $?
        fi
        # otherwise show selection
        warn "Unknown runtime '$first'. Showing available options..."
        show_selection_and_run
        return $?
    fi
}

main "$@"
