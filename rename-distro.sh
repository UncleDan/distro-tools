#!/bin/bash
# ===========================================================================
#  rename-distro.sh  -  distribution branding editor
# ---------------------------------------------------------------------------
#  Changes the name a Linux installation reports about itself:
#  /etc/os-release, /etc/lsb-release, /etc/issue, /etc/issue.net, /etc/motd.
#
#    ./rename-distro.sh show                       print the current values
#    ./rename-distro.sh apply "Name" [Ver] [ID]    back up, then rewrite
#    ./rename-distro.sh restore                    put a backup back
#    ./rename-distro.sh                            ask what to do
#
#  Backups go to ./prettyname/<timestamp>/, keeping the original paths.
#  The file list is a checkbox list:
#    Up/Down  move      Space  toggle      A  all/none      Enter  confirm
# ===========================================================================

set -uo pipefail

VERSION="26.08"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/prettyname"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

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

# ask_text <prompt> <default> ; result in REPLY_TEXT
ask_text() {
    local prompt="$1" default="${2:-}" reply
    REPLY_TEXT="$default"
    tty_available || return 0
    if [ -n "$default" ]; then
        printf '  %s?%s %s %s[%s]%s ' "$C_YEL" "$C_RST" "$prompt" "$C_DIM" "$default" "$C_RST" > /dev/tty
    else
        printf '  %s?%s %s ' "$C_YEL" "$C_RST" "$prompt" > /dev/tty
    fi
    read -r reply < /dev/tty || reply=""
    [ -n "$reply" ] && REPLY_TEXT="$reply"
}

# ===========================================================================
#  Checkbox list  (cl_reset [1] for a single-choice list)
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
        line=$(printf '%-30s %s%s%s' "${CL_LABEL[$i]}" "$C_DIM" "${CL_HINT[$i]}" "$C_RST")
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
#  Target files
# ===========================================================================
# /etc/os-release is often a symlink into /usr/lib: follow it, so the change
# survives and the backup records the file that is really being edited.
if [ -L /etc/os-release ]; then
    OS_RELEASE="$(readlink -f /etc/os-release)"
else
    OS_RELEASE="/etc/os-release"
fi

FILES=("$OS_RELEASE" /etc/lsb-release /etc/issue /etc/issue.net /etc/motd)

label_of() {
    case "$1" in
        */os-release) printf 'os-release' ;;
        *)            printf '%s' "$(basename "$1")" ;;
    esac
}

show_current() {
    local f
    for f in "${FILES[@]}"; do
        printf '\n  %s%s%s' "$C_B" "$f" "$C_RST"
        [ "$f" = "$OS_RELEASE" ] && [ "$f" != "/etc/os-release" ] && \
            printf ' %s(via /etc/os-release)%s' "$C_DIM" "$C_RST"
        printf '\n'
        if [ -f "$f" ]; then
            sed 's/^/      /' "$f" | sed "s/^/$(printf '%s' "$C_DIM")/;s/$/$(printf '%s' "$C_RST")/"
        else
            printf '      %snot present%s\n' "$C_DIM" "$C_RST"
        fi
    done
    printf '\n'
}

# ===========================================================================
#  Writing helpers
# ===========================================================================
# Replace KEY=... in place, appending the line when the key is absent.
# Keeps the original ownership and permissions of the file.
set_kv() {   # set_kv <file> <key> <value>
    local f="$1" k="$2" v="$3" tmp found=0 line
    tmp="$(mktemp)"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$k="*) printf '%s=%s\n' "$k" "$v"; found=1 ;;
            *)      printf '%s\n' "$line" ;;
        esac
    done < "$f" > "$tmp"
    [ "$found" = "0" ] && printf '%s=%s\n' "$k" "$v" >> "$tmp"
    cat "$tmp" > "$f"
    rm -f "$tmp"
}

make_id() {   # a name -> a usable ID
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' \
        | sed 's/^-//; s/-$//'
}

# ===========================================================================
#  Backup / restore
# ===========================================================================
do_backup() {   # do_backup <file>...
    local session="$BACKUP_DIR/$TIMESTAMP" f dest
    mkdir -p "$session"
    for f in "$@"; do
        [ -f "$f" ] || continue
        dest="$session$(dirname "$f")"
        mkdir -p "$dest"
        cp -p "$f" "$dest/"
    done
    printf '%s' "$session"
}

list_sessions() {
    [ -d "$BACKUP_DIR" ] || return 0
    find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -r
}

run_restore() {
    banner "rename-distro $VERSION  -  RESTORE"

    local -a sessions=()
    while IFS= read -r s; do [ -n "$s" ] && sessions+=("$s"); done < <(list_sessions)
    [ "${#sessions[@]}" -eq 0 ] && die "No backup found in $BACKUP_DIR."

    cl_reset 1
    local i first=1 n
    for i in "${sessions[@]}"; do
        n="$(find "$BACKUP_DIR/$i" -type f | wc -l)"
        cl_add "$i" "$first" "$n file(s)"
        first=0
    done
    cl_run "Which backup do you want to restore?" || bye "Cancelled."

    local pick="" idx=0
    for i in "${sessions[@]}"; do
        [ "${CL_STATE[$idx]}" = "1" ] && pick="$i"
        idx=$((idx+1))
    done
    [ -z "$pick" ] && bye "Nothing selected."

    local src="$BACKUP_DIR/$pick" f target
    section "Files in this backup"
    while IFS= read -r f; do
        target="${f#$src}"
        printf '    %s  %s→%s  %s\n' "$(basename "$f")" "$C_DIM" "$C_RST" "$target"
    done < <(find "$src" -type f | sort)

    printf '\n'
    ask_yes_no "Restore these files over the current ones?" n || bye "Cancelled."

    section "Restoring"
    while IFS= read -r f; do
        target="${f#$src}"
        if cp -p "$f" "$target" 2>/dev/null; then
            ok "$target"
        else
            fail "$target — could not be written"
        fi
    done < <(find "$src" -type f | sort)

    printf '\n'; hr
    ok "Done."
    printf '\n'
}

# ===========================================================================
#  Apply
# ===========================================================================
run_apply() {
    banner "rename-distro $VERSION  -  APPLY"

    local new_name="${1:-}" new_version="${2:-}" new_id="${3:-}"

    # ---- values ----------------------------------------------------------
    if [ -z "$new_name" ]; then
        section "New identity"
        ask_text "Distribution name:" ""
        new_name="$REPLY_TEXT"
        [ -z "$new_name" ] && die "A name is required."
        ask_text "Version (optional):" ""
        new_version="$REPLY_TEXT"
        ask_text "ID (optional):" "$(make_id "$new_name")"
        new_id="$REPLY_TEXT"
    fi
    [ -z "$new_id" ] && new_id="$(make_id "$new_name")"

    local pretty="$new_name"
    [ -n "$new_version" ] && pretty="$new_name $new_version"

    # ---- which files -----------------------------------------------------
    cl_reset
    local f
    for f in "${FILES[@]}"; do
        if [ -f "$f" ]; then
            cl_add "$(label_of "$f")" 1 "$f"
        else
            cl_add "$(label_of "$f")" 0 "not present"
        fi
    done
    cl_run "Select the files to rewrite" || bye "Cancelled."

    local -a todo=()
    local idx=0
    for f in "${FILES[@]}"; do
        if [ "${CL_STATE[$idx]}" = "1" ]; then
            if [ -f "$f" ]; then
                todo+=("$f")
            else
                warn "$(label_of "$f") does not exist, skipped."
            fi
        fi
        idx=$((idx+1))
    done
    [ "${#todo[@]}" -eq 0 ] && bye "Nothing selected."

    # ---- preview ---------------------------------------------------------
    section "What will be written"
    printf '    %-22s %s\n' "NAME"        "\"$new_name\""
    printf '    %-22s %s\n' "PRETTY_NAME" "\"$pretty\""
    printf '    %-22s %s\n' "ID"          "$new_id"
    if [ -n "$new_version" ]; then
        printf '    %-22s %s\n' "VERSION"    "\"$new_version\""
        printf '    %-22s %s\n' "VERSION_ID" "\"$new_version\""
    else
        printf '    %s%-22s left untouched%s\n' "$C_DIM" "VERSION / VERSION_ID" "$C_RST"
    fi
    printf '\n'
    for f in "${todo[@]}"; do detail "$f"; done

    printf '\n'
    warn "/etc/issue, /etc/issue.net and /etc/motd are replaced, not edited:"
    detail "any custom banner in them is lost (the backup keeps the original)."
    printf '\n'
    ask_yes_no "Apply these changes?" n || bye "Cancelled."

    # ---- backup ----------------------------------------------------------
    section "Backup"
    local session; session="$(do_backup "${todo[@]}")"
    ok "Saved to $session"
    if [ -n "${SUDO_UID:-}" ]; then
        chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$BACKUP_DIR" 2>/dev/null || true
    fi

    # ---- write -----------------------------------------------------------
    section "Writing"
    for f in "${todo[@]}"; do
        case "$f" in
            */os-release)
                set_kv "$f" NAME        "\"$new_name\""
                set_kv "$f" PRETTY_NAME "\"$pretty\""
                set_kv "$f" ID          "$new_id"
                if [ -n "$new_version" ]; then
                    set_kv "$f" VERSION    "\"$new_version\""
                    set_kv "$f" VERSION_ID "\"$new_version\""
                fi
                ok "$f"
                ;;
            /etc/lsb-release)
                set_kv "$f" DISTRIB_ID          "$new_id"
                set_kv "$f" DISTRIB_DESCRIPTION "\"$pretty\""
                [ -n "$new_version" ] && set_kv "$f" DISTRIB_RELEASE "$new_version"
                ok "$f"
                ;;
            /etc/issue|/etc/issue.net)
                printf '%s \\n \\l\n\n' "$pretty" > "$f"
                ok "$f"
                ;;
            /etc/motd)
                printf 'Welcome to %s\n' "$pretty" > "$f"
                ok "$f"
                ;;
        esac
    done

    section "Current values"
    show_current

    hr
    ok "Done. Restore anytime with: ${C_B}$(basename "$0") restore${C_RST}"
    printf '\n'
}

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf '%s  Root privileges are required, re-running with sudo...%s\n' "$C_DIM" "$C_RST"
        exec sudo -- "$0" "$@"
    fi
}

# ===========================================================================
#  Entry point
# ===========================================================================
usage() {
    banner "rename-distro $VERSION"
    printf '  %sUsage:%s %s [show|apply|restore] ...\n\n' "$C_B" "$C_RST" "$(basename "$0")"
    printf '    %sshow%s                          print the current values\n' "$C_B" "$C_RST"
    printf '    %sapply%s "Name" [Ver] [ID]       back up, then rewrite\n' "$C_B" "$C_RST"
    printf '    %srestore%s                       put a previous backup back\n\n' "$C_B" "$C_RST"
    printf '  With no argument the action is asked interactively.\n'
    printf '  %sapply%s without a name asks for the values one by one.\n\n' "$C_B" "$C_RST"
    printf '  Backups: %s\n\n' "$BACKUP_DIR/<timestamp>/"
}

MODE="${1:-}"

case "$MODE" in
    show)
        banner "rename-distro $VERSION  -  CURRENT VALUES"
        show_current
        ;;
    apply)
        shift
        need_root apply "$@"
        run_apply "${1:-}" "${2:-}" "${3:-}"
        ;;
    restore)
        shift
        need_root restore "$@"
        run_restore
        ;;
    -h|--help|help)
        usage
        ;;
    "")
        banner "rename-distro $VERSION"
        cl_reset 1
        cl_add "Show    (current values)"          1 ""
        cl_add "Apply   (rename this system)"      0 ""
        cl_add "Restore (undo from a backup)"      0 ""
        cl_run "What do you want to do?" || bye "Cancelled."
        if   [ "${CL_STATE[0]}" = "1" ]; then section "Current values"; show_current
        elif [ "${CL_STATE[1]}" = "1" ]; then need_root apply;   run_apply
        elif [ "${CL_STATE[2]}" = "1" ]; then need_root restore; run_restore
        else bye "Nothing selected."
        fi
        ;;
    *)
        # Backwards compatible: rename-distro.sh "Name" [Ver] [ID]
        need_root apply "$@"
        run_apply "${1:-}" "${2:-}" "${3:-}"
        ;;
esac
