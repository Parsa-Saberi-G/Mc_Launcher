#!/bin/bash

# ============================================================
# MC LAUNCHER — DOCTOR
# Comprehensive non-interactive diagnostics
# ============================================================

MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_DIR="$MC_DIR/commands"
DATA_DIR="$MC_DIR/data"
VERSION_DB="$DATA_DIR/versions.json"
MC_GAME_DIR="${MC_GAME_DIR:-$HOME/.minecraft}"

# ============================================================
# Colors
# ============================================================

if [[ -t 1 ]]; then
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    BLUE='\033[34m'
    CYAN='\033[36m'
    MAGENTA='\033[35m'
    WHITE='\033[37m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    WHITE=''
    BOLD=''
    DIM=''
    RESET=''
fi

# ============================================================
# Counters
# ============================================================

CHECKS=0
PASSED=0
WARNINGS=0
ERRORS=0

# ============================================================
# Helpers
# ============================================================

pass() {
    ((CHECKS++))
    ((PASSED++))
    printf "  %b✓%b %s\n" "$GREEN" "$RESET" "$*"
}

warn() {
    ((CHECKS++))
    ((WARNINGS++))
    printf "  %b!%b %s\n" "$YELLOW" "$RESET" "$*"
}

fail() {
    ((CHECKS++))
    ((ERRORS++))
    printf "  %b✗%b %s\n" "$RED" "$RESET" "$*"
}

section() {
    echo
    printf "%b%s%b\n" "$BOLD$CYAN" "$*" "$RESET"
    printf "%b%s%b\n" "$DIM" "────────────────────────────────────────────────────────────" "$RESET"
}

detail() {
    printf "    %b→%b %s\n" "$DIM" "$RESET" "$*"
}

# ============================================================
# Header
# ============================================================

echo
printf "%bMC Launcher Doctor%b\n" "$BOLD$CYAN" "$RESET"
printf "%bComprehensive non-interactive diagnostics%b\n" "$DIM" "$RESET"
echo
printf "Project: %b%s%b\n" "$CYAN" "$MC_DIR" "$RESET"
printf "Game:    %b%s%b\n" "$CYAN" "$MC_GAME_DIR" "$RESET"

# ============================================================
# 1. Project structure
# ============================================================

section "1. Project structure"

[[ -d "$MC_DIR" ]] \
    && pass "Project directory exists" \
    || fail "Project directory missing"

[[ -d "$COMMAND_DIR" ]] \
    && pass "commands/ directory exists" \
    || fail "commands/ directory missing"

[[ -d "$DATA_DIR" ]] \
    && pass "data/ directory exists" \
    || fail "data/ directory missing"

[[ -f "$MC_DIR/mc" ]] \
    && pass "Main launcher exists" \
    || fail "Main launcher missing"

# ============================================================
# 2. Command files
# ============================================================

section "2. Command files"

COMMANDS=(
    help
    install
    remove
    run
    list
    find
    search
    info
    import
    export
    config
    account
    update
    doctor
)

for cmd in "${COMMANDS[@]}"; do
    if [[ -f "$COMMAND_DIR/$cmd.sh" ]]; then
        pass "$cmd.sh exists"
    else
        fail "$cmd.sh is missing"
    fi
done

# ============================================================
# 3. Permissions
# ============================================================

section "3. Executable permissions"

if [[ -x "$MC_DIR/mc" ]]; then
    pass "mc is executable"
else
    fail "mc is not executable"
    detail "chmod +x \"$MC_DIR/mc\""
fi

for cmd in "${COMMANDS[@]}"; do
    file="$COMMAND_DIR/$cmd.sh"

    [[ -f "$file" ]] || continue

    if [[ -x "$file" ]]; then
        pass "$cmd.sh is executable"
    else
        fail "$cmd.sh is not executable"
        detail "chmod +x \"$file\""
    fi
done

# ============================================================
# 4. Syntax
# ============================================================

section "4. Bash syntax"

if bash -n "$MC_DIR/mc" 2>/dev/null; then
    pass "mc syntax OK"
else
    fail "mc contains a Bash syntax error"
    bash -n "$MC_DIR/mc"
fi

for cmd in "${COMMANDS[@]}"; do
    file="$COMMAND_DIR/$cmd.sh"

    [[ -f "$file" ]] || continue

    if bash -n "$file" 2>/dev/null; then
        pass "$cmd.sh syntax OK"
    else
        fail "$cmd.sh contains a Bash syntax error"
        bash -n "$file"
    fi
done

# ============================================================
# 5. Router
# ============================================================

section "5. Router command mappings"

ROUTER_COMMANDS=(
    install
    remove
    run
    list
    find
    search
    info
    import
    export
    config
    account
    update
    doctor
    help
)

for cmd in "${ROUTER_COMMANDS[@]}"; do
    if grep -Eq "$cmd\|-|$cmd\)" "$MC_DIR/mc" 2>/dev/null; then
        pass "Router mapping: $cmd"
    elif grep -Eq "$cmd" "$MC_DIR/mc" 2>/dev/null; then
        pass "Router contains: $cmd"
    else
        fail "Router mapping missing: $cmd"
    fi
done

# ============================================================
# 6. UI dependency scan
# ============================================================

section "6. UI dependency scan"

UI_FOUND=0

for file in "$COMMAND_DIR"/*.sh; do
    [[ -f "$file" ]] || continue

    # Do not scan doctor itself because doctor contains the
    # strings it uses to detect old UI references.
    [[ "$file" == "$COMMAND_DIR/doctor.sh" ]] && continue

    if grep -nE \
        'source[[:space:]]+.*ui\.sh|mc_error|mc_ok|mc_warn|mc_info|mc_done|mc_section' \
        "$file" >/dev/null 2>&1; then

        UI_FOUND=1

        warn "Old UI references found in $(basename "$file")"

        grep -nE \
            'source[[:space:]]+.*ui\.sh|mc_error|mc_ok|mc_warn|mc_info|mc_done|mc_section' \
            "$file" |
            head -10 |
            while IFS= read -r line; do
                detail "$line"
            done
    fi
done

if (( UI_FOUND == 0 )); then
    pass "No old UI dependencies detected"
fi

# ============================================================
# 7. Recursive helper detection
# ============================================================

section "7. Recursive function detection"

RECURSIVE_FOUND=0

for file in "$COMMAND_DIR"/*.sh; do
    [[ -f "$file" ]] || continue
    [[ "$file" == "$COMMAND_DIR/doctor.sh" ]] && continue

    while IFS= read -r fn; do

        body="$(
            awk -v fn="$fn" '
                $0 ~ "^" fn "[[:space:]]*\\(" {inside=1}
                inside {print}
                inside && /^}/ {exit}
            ' "$file"
        )"

        if echo "$body" |
            grep -Eq "^[[:space:]]*${fn}[[:space:]]+['\"]?\\$\\*" 2>/dev/null; then

            RECURSIVE_FOUND=1
            fail "Possible recursive $fn() in $(basename "$file")"
        fi

    done < <(
        grep -Eo '^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)' "$file" |
        sed 's/[[:space:]]*().*//'
    )
done

if (( RECURSIVE_FOUND == 0 )); then
    pass "No obvious recursive helper functions detected"
fi

# ============================================================
# 8. Suspicious files
# ============================================================

section "8. Suspicious project files"

SUSPICIOUS=0

for file in \
    "$COMMAND_DIR"/*.bak \
    "$COMMAND_DIR"/*.broken \
    "$COMMAND_DIR"/*.old \
    "$COMMAND_DIR"/*.orig \
    "$COMMAND_DIR"/*~; do

    [[ -e "$file" ]] || continue

    SUSPICIOUS=1
    warn "Suspicious file: $(basename "$file")"
done

if (( SUSPICIOUS == 0 )); then
    pass "No suspicious backup/broken command files"
fi

# ============================================================
# 9. Database
# ============================================================

section "9. Minecraft database"

if [[ -f "$VERSION_DB" ]]; then
    pass "versions.json exists"
else
    fail "versions.json is missing"
fi

if [[ -f "$VERSION_DB" ]]; then

    if python3 - "$VERSION_DB" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)

    assert isinstance(data, dict)
    assert isinstance(data.get("latest"), dict)
    assert isinstance(data.get("versions"), list)

except Exception:
    sys.exit(1)
PY
    then
        pass "versions.json is valid"
    else
        fail "versions.json is invalid"
    fi

    VERSION_COUNT="$(
        python3 - "$VERSION_DB" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        print(len(json.load(f).get("versions", [])))
except Exception:
    print(0)
PY
    )"

    if (( VERSION_COUNT > 0 )); then
        pass "Database contains $VERSION_COUNT versions"
    else
        fail "Database contains no versions"
    fi

    LATEST_RELEASE="$(
        python3 - "$VERSION_DB" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        print(json.load(f)["latest"]["release"])
except Exception:
    print("unknown")
PY
    )"

    LATEST_SNAPSHOT="$(
        python3 - "$VERSION_DB" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as f:
        print(json.load(f)["latest"]["snapshot"])
except Exception:
    print("unknown")
PY
    )"

    detail "Latest release: $LATEST_RELEASE"
    detail "Latest snapshot: $LATEST_SNAPSHOT"
fi

# ============================================================
# 10. Required programs
# ============================================================

section "10. Required programs"

REQUIRED_PROGRAMS=(
    bash
    curl
    python3
    grep
    sed
    awk
    find
    sort
    head
    tail
    date
    timeout
)

for program in "${REQUIRED_PROGRAMS[@]}"; do
    if command -v "$program" >/dev/null 2>&1; then
        pass "$program available"
    else
        fail "$program is missing"
    fi
done

# ============================================================
# 11. Optional programs
# ============================================================

section "11. Optional programs"

OPTIONAL_PROGRAMS=(
    jq
    unzip
    tar
    git
    java
)

for program in "${OPTIONAL_PROGRAMS[@]}"; do
    if command -v "$program" >/dev/null 2>&1; then
        pass "$program available"
    else
        warn "$program is not installed"
    fi
done

# ============================================================
# 12. Java
# ============================================================

section "12. Java runtime"

if command -v java >/dev/null 2>&1; then

    pass "Java is installed"

    JAVA_VERSION="$(java -version 2>&1 | head -1)"
    detail "$JAVA_VERSION"

    JAVA_MAJOR="$(
        java -version 2>&1 |
        awk -F '"' '/version/ {
            split($2,v,".")
            if (v[1] == "1")
                print v[2]
            else
                print v[1]
        }'
    )"

    if [[ "$JAVA_MAJOR" =~ ^[0-9]+$ ]]; then
        if (( JAVA_MAJOR >= 17 )); then
            pass "Java major version $JAVA_MAJOR is supported"
        else
            warn "Java major version $JAVA_MAJOR may be too old"
        fi
    else
        warn "Could not determine Java major version"
    fi

else
    fail "Java is not installed"
fi

# ============================================================
# 13. Minecraft directory
# ============================================================

section "13. Minecraft game directory"

if [[ -d "$MC_GAME_DIR" ]]; then
    pass "Minecraft directory exists"
else
    warn "Minecraft directory does not exist"
fi

for dir in versions mods shaderpacks resourcepacks saves; do

    if [[ -d "$MC_GAME_DIR/$dir" ]]; then
        pass "~/.minecraft/$dir exists"
    else
        # These are optional directories and are NOT errors.
        case "$dir" in
            versions)
                fail "~/.minecraft/versions does not exist"
                ;;
            *)
                warn "~/.minecraft/$dir does not exist"
                ;;
        esac
    fi

done

# ============================================================
# 14. Installed versions
# ============================================================

section "14. Installed Minecraft versions"

INSTALLED_COUNT=0

if [[ -d "$MC_GAME_DIR/versions" ]]; then

    while IFS= read -r -d '' dir; do

        version="$(basename "$dir")"
        ((INSTALLED_COUNT++))

        jar="$dir/$version.jar"
        json="$dir/$version.json"

        if [[ -f "$jar" ]]; then
            pass "$version: JAR exists"
        else
            fail "$version: JAR missing"
        fi

        if [[ -f "$json" ]]; then
            pass "$version: JSON exists"
        else
            fail "$version: JSON missing"
        fi

    done < <(
        find "$MC_GAME_DIR/versions" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print0 2>/dev/null
    )

fi

if (( INSTALLED_COUNT == 0 )); then
    warn "No Minecraft versions installed"
else
    detail "Installed versions checked: $INSTALLED_COUNT"
fi

# ============================================================
# 15. Search
# ============================================================

section "15. Search command"

SEARCH="$COMMAND_DIR/search.sh"

if [[ -f "$SEARCH" ]]; then

    grep -q "search_versions" "$SEARCH" \
        && pass "Minecraft version search implementation found" \
        || fail "Minecraft version search implementation missing"

    grep -q "search_modrinth" "$SEARCH" \
        && pass "Modrinth search implementation found" \
        || warn "Modrinth search implementation not detected"

    grep -Eq 'versions\|version' "$SEARCH" \
        && pass "version/version(s) handling found" \
        || warn "version/version(s) handling not detected"

else
    fail "search.sh missing"
fi

# ============================================================
# 16. Update
# ============================================================

section "16. Update command"

UPDATE="$COMMAND_DIR/update.sh"

if [[ -f "$UPDATE" ]]; then

    if grep -Eq 'version_manifest_v2|piston-meta\.mojang\.com' "$UPDATE"; then
        pass "Mojang version manifest detected"
    else
        warn "Mojang manifest URL not detected"
    fi

    if grep -q "versions.json" "$UPDATE"; then
        pass "versions.json update logic detected"
    else
        warn "versions.json update logic not detected"
    fi

    if grep -Eq 'curl|wget' "$UPDATE"; then
        pass "Network downloader detected"
    else
        fail "No curl/wget downloader detected"
    fi

else
    fail "update.sh missing"
fi

# ============================================================
# 17. Non-interactive smoke tests
# ============================================================

section "17. Non-interactive smoke tests"

echo
detail "Interactive and destructive commands are deliberately NOT executed."
echo

run_test() {
    local name="$1"
    shift

    if timeout 5s "$@" </dev/null >/dev/null 2>&1; then
        pass "$name"
    else
        fail "$name failed"
    fi
}

run_test "mc help" "$MC_DIR/mc" help
run_test "mc version" "$MC_DIR/mc" version
run_test "mc list" "$MC_DIR/mc" list
run_test "mc info" "$MC_DIR/mc" info
run_test "mc search versions" "$MC_DIR/mc" search versions
run_test "mc search versions --snapshot" "$MC_DIR/mc" search versions --snapshot

# ============================================================
# 18. Command inspection
# ============================================================

section "18. Interactive/destructive command inspection"

INSPECT_ONLY=(
    find
    config
    account
    install
    remove
    run
    import
    export
    update
)

for cmd in "${INSPECT_ONLY[@]}"; do

    file="$COMMAND_DIR/$cmd.sh"

    if [[ ! -f "$file" ]]; then
        continue
    fi

    if bash -n "$file" 2>/dev/null; then
        pass "$cmd.sh structurally valid"
    else
        fail "$cmd.sh structural check failed"
    fi

done

echo
detail "These commands were NOT executed:"
detail "find, config, account, install, remove, run, import, export, update"

# ============================================================
# 19. Router error handling
# ============================================================

section "19. Router error handling"

if "$MC_DIR/mc" "__mc_doctor_invalid_command__" \
    >/dev/null 2>&1; then

    fail "Unknown command incorrectly returned success"

else
    pass "Unknown command returns non-zero status"
fi

# ============================================================
# 20. Help
# ============================================================

section "20. Help"

if timeout 5s "$MC_DIR/mc" help >/dev/null 2>&1; then
    pass "Help command works"
else
    fail "Help command failed"
fi

# ============================================================
# Final report
# ============================================================

echo
printf "%b============================================================%b\n" "$CYAN" "$RESET"
printf "%bDOCTOR REPORT%b\n" "$BOLD$CYAN" "$RESET"
printf "%b============================================================%b\n" "$CYAN" "$RESET"

echo
printf "Checks:   %b%s%b\n" "$WHITE" "$CHECKS" "$RESET"
printf "Passed:   %b%s%b\n" "$GREEN" "$PASSED" "$RESET"
printf "Warnings: %b%s%b\n" "$YELLOW" "$WARNINGS" "$RESET"
printf "Errors:   %b%s%b\n" "$RED" "$ERRORS" "$RESET"

echo

if (( ERRORS == 0 )); then

    if (( WARNINGS == 0 )); then
        printf "%b✓ MC Launcher is completely healthy.%b\n" \
            "$GREEN$BOLD" "$RESET"
    else
        printf "%b✓ No critical errors found.%b\n" \
            "$YELLOW$BOLD" "$RESET"
        printf "%b  %d warning(s) should be reviewed.%b\n" \
            "$YELLOW" "$WARNINGS" "$RESET"
    fi

else

    printf "%b✗ MC Launcher has %d critical problem(s).%b\n" \
        "$RED$BOLD" "$ERRORS" "$RESET"

fi

echo

if (( ERRORS == 0 )); then
    exit 0
else
    exit 1
fi