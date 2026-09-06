#!/bin/bash

MC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND_DIR="$MC_DIR/commands"


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
            "$COMMAND_DIR/install.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # REMOVE
        # ─────────────────────────────────────

        remove|-u)
            shift
            "$COMMAND_DIR/remove.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # RUN
        # ─────────────────────────────────────

        run|-r)
            shift
            "$COMMAND_DIR/run.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # LIST
        # ─────────────────────────────────────

        list|-l)
            shift
            "$COMMAND_DIR/list.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # FIND
        # ─────────────────────────────────────

        find|-f)
            shift
            "$COMMAND_DIR/find.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # SEARCH
        # ─────────────────────────────────────

        search|-s)
            shift
            "$COMMAND_DIR/search.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # INFO
        # ─────────────────────────────────────

        info|-I)
            shift
            "$COMMAND_DIR/info.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # IMPORT
        # ─────────────────────────────────────

        import|-o)
            shift
            "$COMMAND_DIR/import.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # EXPORT
        # ─────────────────────────────────────

        export|-e)
            shift
            "$COMMAND_DIR/export.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # CONFIG
        # ─────────────────────────────────────

        config|-c)
            shift
            "$COMMAND_DIR/config.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # ACCOUNT
        # ─────────────────────────────────────

        account)
            shift
            "$COMMAND_DIR/account.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # UPDATE
        # ─────────────────────────────────────

        update)
            shift
            "$COMMAND_DIR/update.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # DOCTOR
        # ─────────────────────────────────────

        doctor)
            shift
            "$COMMAND_DIR/doctor.sh" "$@"
            ;;


        # ─────────────────────────────────────
        # HELP
        # ─────────────────────────────────────

        help|-h|--help)

            # mc --help
            if [[ -z "$2" ]]; then
                "$COMMAND_DIR/help.sh"
                return $?
            fi

            # mc --help install
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