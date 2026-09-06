#!/bin/bash

BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

show_main_help() {
    cat <<EOF

${BOLD}${CYAN}mc${RESET} — Minecraft command-line launcher
${DIM}Version 0.1.0${RESET}

${BOLD}Usage:${RESET}  mc <command> [type] [name] [options]

${BOLD}${CYAN}Commands${RESET}
  ${GREEN}install${RESET}  -i   Install content
  ${GREEN}remove${RESET}   -u   Remove content
  ${GREEN}run${RESET}      -r   Launch Minecraft
  ${GREEN}list${RESET}     -l   List installed content
  ${GREEN}find${RESET}     -f   Find installed content
  ${GREEN}search${RESET}   -s   Search online / Minecraft versions
  ${GREEN}info${RESET}     -I   Show information
  ${GREEN}import${RESET}   -o   Import content
  ${GREEN}export${RESET}   -e   Export content
  ${GREEN}config${RESET}   -c   Configure launcher
  ${GREEN}account${RESET}       Manage accounts
  ${GREEN}update${RESET}        Update databases
  ${GREEN}doctor${RESET}        Diagnose installation
  ${GREEN}help${RESET}     -h   Show help
  ${GREEN}version${RESET}  -V   Show launcher version

${BOLD}${CYAN}Search${RESET}
  mc search versions [query]       Search Minecraft versions
  mc search mod <query>             Search mods
  mc search modpack <query>         Search modpacks
  mc search shader <query>          Search shaders
  mc search resourcepack <query>   Search resource packs

${BOLD}${CYAN}Install${RESET}
  mc install version <version>      Install Minecraft
  mc install mod <name>             Install a mod
  mc install shader <name>          Install a shader
  mc install modpack <name>         Install a modpack
  mc install loader fabric          Install a loader

${BOLD}${CYAN}Examples${RESET}
  mc search versions 1.21
  mc search mod sodium --version 1.21.8
  mc install version 1.21.8
  mc install mod sodium
  mc install loader fabric --version 1.21.8
  mc run 1.21.8

${BOLD}${CYAN}Local${RESET}
  mc list [type]                    List installed content
  mc find <query>                   Find installed content
  mc info [type] [name]             Show detailed information

${BOLD}${CYAN}Configuration${RESET}
  mc config                         Show configuration
  mc config java                    Configure Java
  mc config memory                  Configure memory
  mc config game-dir                Configure game directory
  mc config game-args               Configure game arguments

${BOLD}${CYAN}Accounts${RESET}
  mc account                       List accounts
  mc account add                   Add Microsoft account
  mc account remove                Remove account
  mc account use                   Select account
  mc account active                Show active account

${BOLD}${CYAN}Maintenance${RESET}
  mc update database               Update Minecraft database
  mc doctor                        Check launcher installation

${BOLD}${CYAN}Global options${RESET}
  --java PATH       Java executable
  --min-memory SIZE Minimum memory
  --max-memory SIZE Maximum memory
  --java-args ARGS  JVM arguments
  --game-args ARGS  Game arguments
  --game-dir PATH   Minecraft directory
  --yes, -y         Skip confirmations

${DIM}Run 'mc help <command>' for more information.${RESET}

EOF
}

show_search_help() {
    cat <<EOF

${BOLD}${CYAN}mc search${RESET} — Search Minecraft content

${BOLD}Usage:${RESET}  mc search <type> [query] [options]

  versions [query]                  Minecraft versions
  mod <query>                       Mods
  modpack <query>                   Modpacks
  shader <query>                    Shaders
  resourcepack <query>              Resource packs

${BOLD}Options:${RESET}
  --version VERSION
  --loader LOADER
  --limit NUMBER

${BOLD}Examples:${RESET}
  mc search versions 1.21
  mc search mod sodium
  mc search mod sodium --version 1.21.8
  mc search mod sodium --loader fabric
  mc search shader complementary

EOF
}

show_install_help() {
    cat <<EOF

${BOLD}${CYAN}mc install${RESET} — Install Minecraft content

${BOLD}Usage:${RESET}  mc install <type> <name> [options]

  version <version>                 Minecraft version
  mod <name>                        Mod
  shader <name>                     Shader
  resourcepack <name>               Resource pack
  modpack <name>                    Modpack
  loader <loader>                   Mod loader

${BOLD}Options:${RESET}
  --version VERSION
  --loader LOADER
  --loader-version VERSION
  --game-dir PATH
  --yes, -y

EOF
}

show_run_help() {
    cat <<EOF

${BOLD}${CYAN}mc run${RESET} — Launch Minecraft

${BOLD}Usage:${RESET}
  mc run
  mc run <version>
  mc run version <version>

${BOLD}Options:${RESET}
  --java PATH
  --min-memory SIZE
  --max-memory SIZE
  --java-args ARGS
  --game-args ARGS
  --game-dir PATH

EOF
}

show_list_help() {
    cat <<EOF

${BOLD}${CYAN}mc list${RESET} — List installed content

${BOLD}Usage:${RESET}  mc list [type]

  mods              Shaders
  shaders            Resource packs
  resourcepacks      Modpacks
  modpacks           Worlds
  worlds             Instances
  instances          Versions
  versions

EOF
}

show_find_help() {
    cat <<EOF

${BOLD}${CYAN}mc find${RESET} — Find installed content

${BOLD}Usage:${RESET}
  mc find <query>
  mc find <type> <query>

${BOLD}Examples:${RESET}
  mc find sodium
  mc find mod sodium
  mc find world survival

EOF
}

show_info_help() {
    cat <<EOF

${BOLD}${CYAN}mc info${RESET} — Show detailed information

${BOLD}Usage:${RESET}
  mc info
  mc info <type>
  mc info <type> <name>

${BOLD}Examples:${RESET}
  mc info
  mc info java
  mc info version
  mc info version 1.21.8
  mc info mod sodium

EOF
}

show_config_help() {
    cat <<EOF

${BOLD}${CYAN}mc config${RESET} — Configure launcher

${BOLD}Usage:${RESET}
  mc config
  mc config java
  mc config java args
  mc config memory
  mc config game-dir
  mc config game-args
  mc config reset

EOF
}

show_account_help() {
    cat <<EOF

${BOLD}${CYAN}mc account${RESET} — Manage Minecraft accounts

${BOLD}Usage:${RESET}
  mc account
  mc account add
  mc account remove
  mc account use
  mc account active

EOF
}

show_update_help() {
    cat <<EOF

${BOLD}${CYAN}mc update${RESET} — Update launcher databases

${BOLD}Usage:${RESET}
  mc update database

EOF
}

show_doctor_help() {
    cat <<EOF

${BOLD}${CYAN}mc doctor${RESET} — Diagnose installation

${BOLD}Usage:${RESET}
  mc doctor

EOF
}

case "${1:-}" in
    "")
        show_main_help
        ;;
    search|-s)
        show_search_help
        ;;
    install|-i)
        show_install_help
        ;;
    run|-r)
        show_run_help
        ;;
    list|-l)
        show_list_help
        ;;
    find|-f)
        show_find_help
        ;;
    info|-I)
        show_info_help
        ;;
    config|-c)
        show_config_help
        ;;
    account)
        show_account_help
        ;;
    update)
        show_update_help
        ;;
    doctor)
        show_doctor_help
        ;;
    *)
        echo "${YELLOW}No detailed help available for '$1'.${RESET}"
        echo "Run 'mc --help' to see available commands."
        exit 1
        ;;
esac