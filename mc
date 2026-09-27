#!/bin/bash

MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND_DIR="$MC_DIR/commands"


# ─────────────────────────────────────────────
# GLOBAL OPTIONS
# ─────────────────────────────────────────────

YES=false
ARGS=()

for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            YES=true
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done

set -- "${ARGS[@]}"


# ─────────────────────────────────────────────
# COMMAND ROUTER
# ─────────────────────────────────────────────

run_command() {

    case "$1" in

        # ─────────────────────────────────────
        # INSTALL
        # ─────────────────────────────────────

        install|-i)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/install.sh" -y "$@"
            else
                "$COMMAND_DIR/install.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # REMOVE
        # ─────────────────────────────────────

        remove|-u)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/remove.sh" -y "$@"
            else
                "$COMMAND_DIR/remove.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # RUN
        # ─────────────────────────────────────

        run|-r)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/run.sh" -y "$@"
            else
                "$COMMAND_DIR/run.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # LIST
        # ─────────────────────────────────────

        list|-l)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/list.sh" -y "$@"
            else
                "$COMMAND_DIR/list.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # FIND
        # ─────────────────────────────────────

        find|-f)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/find.sh" -y "$@"
            else
                "$COMMAND_DIR/find.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # SEARCH
        # ─────────────────────────────────────

        search|-s)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/search.sh" -y "$@"
            else
                "$COMMAND_DIR/search.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # INFO
        # ─────────────────────────────────────

        info|-I)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/info.sh" -y "$@"
            else
                "$COMMAND_DIR/info.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # IMPORT
        # ─────────────────────────────────────

        import|-o)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/import.sh" -y "$@"
            else
                "$COMMAND_DIR/import.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # EXPORT
        # ─────────────────────────────────────

        export|-e)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/export.sh" -y "$@"
            else
                "$COMMAND_DIR/export.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # CONFIG
        # ─────────────────────────────────────

        config|-c)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/config.sh" -y "$@"
            else
                "$COMMAND_DIR/config.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # ACCOUNT
        # ─────────────────────────────────────

        account)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/account.sh" -y "$@"
            else
                "$COMMAND_DIR/account.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # UPDATE
        # ─────────────────────────────────────

        update)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/update.sh" -y "$@"
            else
                "$COMMAND_DIR/update.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # DOCTOR
        # ─────────────────────────────────────

        doctor)
            shift

            if [[ "$YES" == true ]]; then
                "$COMMAND_DIR/doctor.sh" -y "$@"
            else
                "$COMMAND_DIR/doctor.sh" "$@"
            fi
            ;;


        # ─────────────────────────────────────
        # HELP
        # ─────────────────────────────────────

        help|-h|--help)

            if [[ -z "$2" ]]; then
                "$COMMAND_DIR/help.sh"
                return $?
            fi

            "$COMMAND_DIR/help.sh" "$2"
            return $?
            ;;


        # ─────────────────────────────────────
        # VERSION
        # ─────────────────────────────────────

        version|-V|--version)

            echo "mc version 0.1.0"
            ;;


        # ─────────────────────────────────────
        # NO COMMAND
        # ─────────────────────────────────────

        "")
            "$COMMAND_DIR/help.sh"
            ;;


        # ─────────────────────────────────────
        # UNKNOWN COMMAND
        # ─────────────────────────────────────

        *)
            echo "mc: unknown command '$1'"
            echo "Try 'mc --help' for more information."
            return 1
            ;;

    esac
}


# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    "$COMMAND_DIR/help.sh"
    exit $?
fi

run_command "$@"
