#!/bin/bash

set -o pipefail

MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$MC_DIR/data"
VERSION_DB="$DATA_DIR/versions.json"

MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

die() {
    printf '%bError:%b %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

info() {
    printf '%s\n' "$*" >&2
}

success() {
    printf '%b✓%b %s\n' "$GREEN" "$RESET" "$*" >&2
}

warn() {
    printf '%b!%b %s\n' "$YELLOW" "$RESET" "$*" >&2
}

usage() {
    cat <<EOF
${BOLD}${CYAN}Usage:${RESET}

  mc update database

${BOLD}Commands:${RESET}

  database    Update the Minecraft version database

${BOLD}Examples:${RESET}

  mc update database
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

cleanup() {
    [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

trap cleanup EXIT

download_file() {
    local url="$1"
    local output="$2"

    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 3 \
        --retry-delay 1 \
        --connect-timeout 15 \
        --max-time 120 \
        "$url" \
        -o "$output"
}

update_database() {
    require_command curl
    require_command jq
    require_command mktemp
    require_command mv

    mkdir -p "$DATA_DIR" || die "Could not create data directory: $DATA_DIR"

    TMP_DIR="$(mktemp -d)" || die "Could not create temporary directory"

    local manifest="$TMP_DIR/version_manifest.json"
    local metadata_dir="$TMP_DIR/metadata"

    mkdir -p "$metadata_dir" || die "Could not create temporary metadata directory"

    printf '\n'
    printf '%bUpdating Minecraft database...%b\n' "$BOLD" "$RESET"
    printf '\n'

    printf 'Downloading Minecraft version manifest...\n'

    download_file "$MANIFEST_URL" "$manifest" \
        || die "Failed to download Minecraft version manifest"

    jq empty "$manifest" 2>/dev/null \
        || die "Downloaded Minecraft manifest is not valid JSON"

    local version_count
    version_count="$(jq '.versions | length' "$manifest" 2>/dev/null)" \
        || die "Could not read version list"

    [[ "$version_count" =~ ^[0-9]+$ ]] \
        || die "Invalid version count returned by Mojang"

    (( version_count > 0 )) \
        || die "Minecraft manifest contains no versions"

    local latest_release
    local latest_snapshot

    latest_release="$(jq -r '.latest.release // empty' "$manifest")"
    latest_snapshot="$(jq -r '.latest.snapshot // empty' "$manifest")"

    printf 'Processing %s Minecraft versions...\n' "$version_count"
    printf '\n'

    #
    # Build the database in Python.
    #
    # We use Python here because:
    #   - the metadata is large
    #   - nested JSON needs to be preserved exactly
    #   - jq is still used for validation/extraction
    #
    local database_tmp="$TMP_DIR/versions.json"

    python3 - "$manifest" "$metadata_dir" "$database_tmp" <<'PY'
import json
import os
import sys
import urllib.request
import urllib.error
import time

manifest_path = sys.argv[1]
metadata_dir = sys.argv[2]
output_path = sys.argv[3]

with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

versions = manifest.get("versions", [])

total = len(versions)
processed = 0
failed = 0

def download(url, path):
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "mc-launcher/0.1"
        }
    )

    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()

    with open(path, "wb") as f:
        f.write(data)

for index, version in enumerate(versions, start=1):
    version_id = version.get("id")
    metadata_url = version.get("url")

    if not version_id or not metadata_url:
        failed += 1
        continue

    safe_id = version_id.replace("/", "_").replace("\\", "_")
    metadata_path = os.path.join(metadata_dir, safe_id + ".json")

    try:
        if not os.path.exists(metadata_path):
            download(metadata_url, metadata_path)

        with open(metadata_path, "r", encoding="utf-8") as f:
            metadata = json.load(f)

        #
        # Keep the original manifest information and attach
        # the complete version metadata.
        #
        entry = {
            "id": version.get("id"),
            "type": version.get("type"),
            "url": version.get("url"),
            "time": version.get("time"),
            "releaseTime": version.get("releaseTime"),
            "sha1": version.get("sha1"),
            "complianceLevel": version.get("complianceLevel", 0),

            "metadata": metadata
        }

        #
        # Replace the temporary version entry with the
        # expanded entry.
        #
        version["_expanded"] = entry

        processed += 1

        #
        # Keep terminal output compact.
        #
        print(
            f"\r  Processing versions: {index}/{total} "
            f"({version_id})",
            end="",
            flush=True
        )

    except (
        urllib.error.URLError,
        urllib.error.HTTPError,
        TimeoutError,
        json.JSONDecodeError,
        OSError
    ):
        failed += 1

        print(
            f"\r  Processing versions: {index}/{total} "
            f"({version_id}) [failed]",
            end="",
            flush=True
        )

print()

#
# Build the final database.
#
expanded_versions = []

for version in versions:
    expanded = version.get("_expanded")

    if expanded is not None:
        expanded_versions.append(expanded)

database = {
    "latest": manifest.get("latest", {}),
    "versions": expanded_versions
}

with open(output_path, "w", encoding="utf-8") as f:
    json.dump(database, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(
    f"Processed: {processed}/{total}",
    file=sys.stderr
)

if failed:
    print(
        f"Failed: {failed}",
        file=sys.stderr
    )
PY

    [[ -f "$database_tmp" ]] \
        || die "Database generation failed"

    jq empty "$database_tmp" 2>/dev/null \
        || die "Generated database is not valid JSON"

    local stored_count
    stored_count="$(jq '.versions | length' "$database_tmp" 2>/dev/null)"

    [[ "$stored_count" =~ ^[0-9]+$ ]] \
        || die "Generated database has an invalid version count"

    (( stored_count > 0 )) \
        || die "Generated database contains no versions"

    #
    # Atomically replace the old database.
    #
    mv "$database_tmp" "$VERSION_DB" \
        || die "Could not install new database"

    printf '\n'

    success "Database updated successfully"

    printf '%b  Database:%b        %s\n' \
        "$DIM" "$RESET" "$VERSION_DB"

    printf '%b  Versions:%b        %s\n' \
        "$DIM" "$RESET" "$stored_count"

    printf '%b  Latest release:%b  %s\n' \
        "$DIM" "$RESET" "${latest_release:-unknown}"

    printf '%b  Latest snapshot:%b %s\n' \
        "$DIM" "$RESET" "${latest_snapshot:-unknown}"

    printf '\n'

    #
    # Verify that the important information needed by
    # install.sh actually exists.
    #
    local client_count
    local library_count
    local asset_count

    client_count="$(
        jq '
            [
                .versions[]
                | select(.metadata.downloads.client.url?)
            ] | length
        ' "$VERSION_DB"
    )"

    library_count="$(
        jq '
            [
                .versions[].metadata.libraries[]?
                | select(.downloads.artifact.url? or .downloads.classifiers?)
            ] | length
        ' "$VERSION_DB"
    )"

    asset_count="$(
        jq '
            [
                .versions[]
                | select(.metadata.assetIndex.url?)
            ] | length
        ' "$VERSION_DB"
    )"

    printf '%b  Metadata check:%b\n' "$BOLD" "$RESET"
    printf '    Client downloads: %s\n' "$client_count"
    printf '    Library entries:  %s\n' "$library_count"
    printf '    Asset indexes:    %s\n' "$asset_count"

    printf '\n'

    if (( client_count == 0 )); then
        warn "No client download URLs were found in the database"
    else
        success "Client download metadata available"
    fi

    if (( library_count == 0 )); then
        warn "No library download metadata was found"
    else
        success "Library download metadata available"
    fi

    if (( asset_count == 0 )); then
        warn "No asset index metadata was found"
    else
        success "Asset index metadata available"
    fi
}

COMMAND="${1:-}"

case "$COMMAND" in
    database)
        shift
        [[ $# -eq 0 ]] || die "Unknown option: $*"
        update_database
        ;;

    -h|--help|help)
        usage
        ;;

    "")
        usage
        exit 1
        ;;

    *)
        printf '%bError:%b Unknown update command: %s\n' \
            "$RED" "$RESET" "$COMMAND" >&2
        printf "Try 'mc update --help' for more information.\n" >&2
        exit 1
        ;;
esac