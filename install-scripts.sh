#!/bin/bash
# ===========================================================================
#  install-scripts.sh  -  put these tools on your PATH
# ---------------------------------------------------------------------------
#  Creates a symlink for every script in this folder, dropping the .sh
#  extension, so they can be run from anywhere:
#
#      /usr/local/bin/clean-cache  ->  <this folder>/clean-cache.sh
#
#    ./install-scripts.sh              pick what to link
#    ./install-scripts.sh install      link everything not linked yet
#    ./install-scripts.sh remove       remove the links
#    ./install-scripts.sh status       show what is linked
#    ./install-scripts.sh --dir DIR    use DIR instead of /usr/local/bin
#
#  The scripts are linked, not copied: this folder has to stay where it is.
# ===========================================================================

set -uo pipefail

VERSION="26.08"

# Resolve symlinks, so the script still finds its own folder when it is
# called through a link in /usr/local/bin.
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
BIN_DIR="/usr/local/bin"

# ===========================================================================
#  Presentation helpers
# ===========================================================================
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
    C_BLU=$'\033[34m'; C_CYN=$'\033[36m'; C_CLR=$'\033[2K'
else
    C_RST=""; C_B=""; C_DIM=""; C_RED=""; C_GRN=""; C_YEL=""
    C_BLU=""; C_CYN=""; C_CLR=""
fi

WIDTH=74

hr()      { printf '%s%s%s\n' "$C_DIM" "$(printf '─%.0s' $(seq 1 $WIDTH))" "$C_RST"; }
banner() {
    printf '\n%s╭%s╮%s\n' "$C_CYN" "$(printf '─%.0s' $(seq 1 $((WIDTH-2))))" "$C_RST"
    printf '%s│%s %-*s %s│%s\n' "$C_CYN" "$C_B$C_CYN" "$((WIDTH-4))" "$1" "$C_RST$C_CYN" "$C_RST"
    printf '%s╰%s╯%s\n\n' "$C_CYN" "$(printf '─%.0s' $(seq 1 $((WIDTH-2))))" "$C_RST"
}
section() { printf '\n%s%s▸ %s%s\n' "$C_B" "$C_BLU" "$1" "$C_RST"; }
info()    { printf '  %s•%s %s\n'      "$C_BLU" "$C_RST" "$1"; }
ok()      { printf '  %s✔%s %s\n'      "$C_GRN" "$C_RST" "$1"; }
warn()    { printf '  %s!%s %s\n'      "$C_YEL" "$C_RST" "$1"; }
fail()    { printf '  %s✘%s %s\n'      "$C_RED" "$C_RST" "$1"; }
detail()  { printf '      %s%s%s\n'    "$C_DIM" "$1" "$C_RST"; }
die()     { printf '\n  %s✘ %s%s\n\n'  "$C_RED$C_B" "$1" "$C_RST"; exit "${2:-1}"; }
bye()     { printf '\n  %s%s%s\n\n'    "$C_DIM" "$1" "$C_RST"; exit 0; }

tty_available() { { : < /dev/tty; } 2>/dev/null; }

ask_yes_no() {
    local prompt="$1" default="${2:-n}" hint reply
    [ "$default" = "y" ] && hint="[Y/n]" || hint="[y/N]"
    if ! tty_available; then
        [ "$default" = "y" ]; return $?
    fi
    while true; do
        printf '  %s?%s %s %s%s%s ' "$C_YEL" "$C_RST" "$prompt" "$C_DIM" "$hint" "$C_RST" > /dev/tty
        read -r reply < /dev/tty || reply=""
        [ -z "$reply" ] && reply="$default"
        case "$reply" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO])     return 1 ;;
        esac
    done
}

# ===========================================================================
#  Checkbox list  (cl_reset 1 for a single-choice list)
# ===========================================================================
CL_LABEL=(); CL_STATE=(); CL_HINT=(); CL_EXCLUSIVE=0

cl_reset() { CL_LABEL=(); CL_STATE=(); CL_HINT=(); CL_EXCLUSIVE="${1:-0}"; }
cl_add()   { CL_LABEL+=("$1"); CL_STATE+=("$2"); CL_HINT+=("${3:-}"); }

cl_draw() {
    local cur="$1" i mark line
    for i in "${!CL_LABEL[@]}"; do
        if [ "${CL_STATE[$i]}" = "1" ]; then
            [ "$CL_EXCLUSIVE" = "1" ] && mark="${C_GRN}(•)${C_RST}" || mark="${C_GRN}[✓]${C_RST}"
        else
            [ "$CL_EXCLUSIVE" = "1" ] && mark="${C_DIM}( )${C_RST}" || mark="${C_DIM}[ ]${C_RST}"
        fi
        line=$(printf '%-24s %s%s%s' "${CL_LABEL[$i]}" "$C_DIM" "${CL_HINT[$i]}" "$C_RST")
        printf '%s' "$C_CLR"
        if [ "$i" = "$cur" ]; then
            printf '  %s❯%s %s %s\n' "$C_CYN$C_B" "$C_RST" "$mark" "$line"
        else
            printf '    %s %s\n' "$mark" "$line"
        fi
    done
}

cl_run() {
    local title="$1" n=${#CL_LABEL[@]} cur=0 i key rest
    [ "$n" -eq 0 ] && return 1

    section "$title"

    if [ ! -t 1 ] || ! tty_available; then
        warn "No interactive terminal, using the default selection."
        cl_draw -1
        return 0
    fi

    if [ "$CL_EXCLUSIVE" = "1" ]; then
        printf '  %sUp/Down%s move   %sSpace%s pick   %sEnter%s confirm   %sQ%s cancel\n\n' \
            "$C_B" "$C_RST" "$C_B" "$C_RST" "$C_B" "$C_RST" "$C_B" "$C_RST"
    else
        printf '  %sUp/Down%s move   %sSpace%s toggle   %sA%s all/none   %sEnter%s confirm   %sQ%s cancel\n\n' \
            "$C_B" "$C_RST" "$C_B" "$C_RST" "$C_B" "$C_RST" "$C_B" "$C_RST" "$C_B" "$C_RST"
    fi

    printf '\033[?25l'
    trap 'printf "\033[?25h"' EXIT INT TERM

    cl_draw "$cur"
    while true; do
        IFS= read -rsn1 key < /dev/tty || key=""
        case "$key" in
            $'\033')
                read -rsn2 -t 0.05 rest < /dev/tty || rest=""
                case "$rest" in
                    '[A') cur=$(( (cur - 1 + n) % n )) ;;
                    '[B') cur=$(( (cur + 1) % n )) ;;
                    '')   printf '\033[?25h'; trap - EXIT INT TERM; return 1 ;;
                esac
                ;;
            'k') cur=$(( (cur - 1 + n) % n )) ;;
            'j') cur=$(( (cur + 1) % n )) ;;
            ' ')
                if [ "$CL_EXCLUSIVE" = "1" ]; then
                    for i in "${!CL_STATE[@]}"; do CL_STATE[$i]=0; done
                    CL_STATE[$cur]=1
                else
                    [ "${CL_STATE[$cur]}" = "1" ] && CL_STATE[$cur]=0 || CL_STATE[$cur]=1
                fi ;;
            'a'|'A')
                [ "$CL_EXCLUSIVE" = "1" ] && continue
                local all=1
                for i in "${!CL_STATE[@]}"; do [ "${CL_STATE[$i]}" = "0" ] && all=0; done
                for i in "${!CL_STATE[@]}"; do CL_STATE[$i]=$(( all ? 0 : 1 )); done ;;
            'q'|'Q') printf '\033[?25h'; trap - EXIT INT TERM; return 1 ;;
            '')      printf '\033[?25h'; trap - EXIT INT TERM; return 0 ;;
        esac
        printf '\033[%dA' "$n"
        cl_draw "$cur"
    done
}

# ===========================================================================
#  Discovery
# ===========================================================================
# Every *.sh next to this script, this one included.
list_scripts() {
    local f
    for f in "$SCRIPT_DIR"/*.sh; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done | sort
}

link_name() { basename "$1" .sh; }          # clean-cache.sh -> clean-cache

# State of the link for a script:
#   linked      already points at this very file
#   elsewhere   exists but points somewhere else
#   occupied    exists and is not a symlink at all
#   free        nothing there
link_state() {
    local target="$BIN_DIR/$(link_name "$1")"
    if [ -L "$target" ]; then
        if [ "$(readlink -f "$target")" = "$(readlink -f "$1")" ]; then
            printf 'linked'
        else
            printf 'elsewhere'
        fi
    elif [ -e "$target" ]; then
        printf 'occupied'
    else
        printf 'free'
    fi
}

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf '%s  Root privileges are required to write in %s, re-running with sudo...%s\n' \
            "$C_DIM" "$BIN_DIR" "$C_RST"
        exec sudo -- "$0" "$@"
    fi
}

# ===========================================================================
#  Status
# ===========================================================================
run_status() {
    banner "install-scripts $VERSION  -  STATUS"
    info "Link directory: ${C_B}$BIN_DIR${C_RST}"

    section "Scripts in $(basename "$SCRIPT_DIR")"
    local f name state
    while IFS= read -r f; do
        name="$(link_name "$f")"
        state="$(link_state "$f")"
        case "$state" in
            linked)    ok   "$name" ; detail "$BIN_DIR/$name -> $f" ;;
            elsewhere) warn "$name — a link with this name points elsewhere"
                       detail "-> $(readlink -f "$BIN_DIR/$name")" ;;
            occupied)  warn "$name — a real file with this name already exists"
                       detail "$BIN_DIR/$name" ;;
            free)      printf '  %s·%s %s%s — not linked%s\n' "$C_DIM" "$C_RST" "$C_DIM" "$name" "$C_RST" ;;
        esac
    done < <(list_scripts)

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) printf '\n'; warn "$BIN_DIR is not in your PATH."
           detail "The links will exist but will not be found by name." ;;
    esac
    printf '\n'
}

# ===========================================================================
#  Install
# ===========================================================================
run_install() {
    need_root install --dir "$BIN_DIR"
    banner "install-scripts $VERSION  -  INSTALL"
    info "Link directory: ${C_B}$BIN_DIR${C_RST}"

    local -a scripts=()
    local f
    while IFS= read -r f; do scripts+=("$f"); done < <(list_scripts)
    [ "${#scripts[@]}" -eq 0 ] && die "No .sh script found next to this one."

    [ -d "$BIN_DIR" ] || die "$BIN_DIR does not exist."

    # ---- selection: pre-tick what is not linked yet ----------------------
    cl_reset
    local state
    for f in "${scripts[@]}"; do
        state="$(link_state "$f")"
        case "$state" in
            linked)    cl_add "$(link_name "$f")" 0 "already linked" ;;
            elsewhere) cl_add "$(link_name "$f")" 0 "name taken by another link" ;;
            occupied)  cl_add "$(link_name "$f")" 0 "name taken by a real file" ;;
            free)      cl_add "$(link_name "$f")" 1 "" ;;
        esac
    done
    cl_run "Select the scripts to link" || bye "Cancelled."

    # ---- one-by-one confirmation for anything already there --------------
    local -a todo=()
    local idx=0 name target
    for f in "${scripts[@]}"; do
        if [ "${CL_STATE[$idx]}" = "1" ]; then
            name="$(link_name "$f")"
            target="$BIN_DIR/$name"
            case "$(link_state "$f")" in
                linked)
                    info "$name is already linked, nothing to do."
                    ;;
                elsewhere|occupied)
                    printf '\n'
                    warn "$target already exists"
                    if [ -L "$target" ]; then
                        detail "currently -> $(readlink -f "$target")"
                    else
                        detail "and it is a regular file, not a link"
                    fi
                    if ask_yes_no "Replace it?" n; then
                        todo+=("$f")
                    else
                        info "$name skipped."
                    fi
                    ;;
                free)
                    todo+=("$f")
                    ;;
            esac
        fi
        idx=$((idx+1))
    done

    [ "${#todo[@]}" -eq 0 ] && bye "Nothing to do."

    section "Linking"
    for f in "${todo[@]}"; do
        name="$(link_name "$f")"
        target="$BIN_DIR/$name"
        chmod +x "$f" 2>/dev/null || true
        rm -f "$target"
        if ln -s "$f" "$target"; then
            ok "$name"
            detail "$target -> $f"
        else
            fail "$name — could not create the link"
        fi
    done

    printf '\n'; hr
    ok "Done."
    detail "These are links: keep this folder where it is, or run 'remove' first."
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) warn "$BIN_DIR is not in your PATH — add it to use the short names." ;;
    esac
    printf '\n'
}

# ===========================================================================
#  Remove
# ===========================================================================
run_remove() {
    need_root remove --dir "$BIN_DIR"
    banner "install-scripts $VERSION  -  REMOVE"
    info "Link directory: ${C_B}$BIN_DIR${C_RST}"

    local -a linked=()
    local f
    while IFS= read -r f; do
        [ "$(link_state "$f")" = "linked" ] && linked+=("$f")
    done < <(list_scripts)

    [ "${#linked[@]}" -eq 0 ] && bye "Nothing of this folder is linked in $BIN_DIR."

    cl_reset
    for f in "${linked[@]}"; do
        cl_add "$(link_name "$f")" 1 "$BIN_DIR/$(link_name "$f")"
    done
    cl_run "Select the links to remove" || bye "Cancelled."

    local -a todo=() 
    local idx=0
    for f in "${linked[@]}"; do
        [ "${CL_STATE[$idx]}" = "1" ] && todo+=("$f")
        idx=$((idx+1))
    done
    [ "${#todo[@]}" -eq 0 ] && bye "Nothing selected."

    section "Removing"
    local name target
    for f in "${todo[@]}"; do
        name="$(link_name "$f")"
        target="$BIN_DIR/$name"
        # Only ever remove a symlink that points back into this folder.
        if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$f")" ]; then
            rm -f "$target" && ok "$name" || fail "$name — could not remove $target"
        else
            warn "$name — $target is not our link, left alone"
        fi
    done

    printf '\n'; hr
    ok "Done. The scripts themselves were not touched."
    printf '\n'
}

# ===========================================================================
#  Entry point
# ===========================================================================
usage() {
    banner "install-scripts $VERSION"
    printf '  %sUsage:%s %s [install|remove|status] [--dir DIR]\n\n' \
        "$C_B" "$C_RST" "$(basename "$0")"
    printf '    %sinstall%s      link the scripts into %s\n' "$C_B" "$C_RST" "$BIN_DIR"
    printf '    %sremove%s       remove those links\n' "$C_B" "$C_RST"
    printf '    %sstatus%s       show what is linked right now\n' "$C_B" "$C_RST"
    printf '    %s--dir DIR%s    use DIR instead of %s\n\n' "$C_B" "$C_RST" "$BIN_DIR"
    printf '  Each script is linked without its .sh extension, so\n'
    printf '  %sclean-cache.sh%s becomes %sclean-cache%s and runs from anywhere.\n' \
        "$C_DIM" "$C_RST" "$C_B" "$C_RST"
    printf '  With no argument the action is asked interactively.\n\n'
}

MODE=""
declare -a REST=()

while [ $# -gt 0 ]; do
    case "$1" in
        install|remove|uninstall|status) MODE="$1" ;;
        --dir)
            shift
            [ -n "${1:-}" ] || die "--dir needs a directory."
            BIN_DIR="${1%/}" ;;
        --dir=*) BIN_DIR="${1#*=}"; BIN_DIR="${BIN_DIR%/}" ;;
        -h|--help) usage; exit 0 ;;
        *) usage; die "Unknown argument: $1" ;;
    esac
    shift
done

case "$MODE" in
    install)            run_install ;;
    remove|uninstall)   run_remove ;;
    status)             run_status ;;
    "")
        banner "install-scripts $VERSION"
        cl_reset 1
        cl_add "Install  (link into $BIN_DIR)" 1 ""
        cl_add "Remove   (delete the links)"   0 ""
        cl_add "Status   (what is linked)"     0 ""
        cl_run "What do you want to do?" || bye "Cancelled."
        if   [ "${CL_STATE[0]}" = "1" ]; then run_install
        elif [ "${CL_STATE[1]}" = "1" ]; then run_remove
        elif [ "${CL_STATE[2]}" = "1" ]; then run_status
        else bye "Nothing selected."
        fi
        ;;
esac
