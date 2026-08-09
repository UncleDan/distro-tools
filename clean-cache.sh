#!/bin/bash
# ===========================================================================
#  clean-cache.sh  -  cache and regenerable data cleaner
# ---------------------------------------------------------------------------
#  Removes caches, thumbnails, crash dumps and other regenerable files for
#  Thunderbird, Firefox, LibreWolf, Chrome, Chromium, pCloud and Konqueror/KDE.
#
#    ./clean-cache.sh                 current user only
#    ./clean-cache.sh -a              pick users, then applications
#    ./clean-cache.sh --dry-run       show what would go, delete nothing
#    ./clean-cache.sh firefox chrome  only these applications
#
#  The lists are checkbox lists:
#    Up/Down  move      Space  toggle      A  all/none      Enter  confirm
# ===========================================================================

set -uo pipefail

VERSION="26.08"

DRY_RUN=false
TB_MBOX=true          # Thunderbird: also wipe the local mail stores
BYTES_TOTAL=0
BYTES_USER=0

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
subsec()  { printf '\n  %s%s%s\n' "$C_B" "$1" "$C_RST"; }
info()    { printf '    %s·%s %s%s%s\n' "$C_DIM" "$C_RST" "$C_DIM" "$1" "$C_RST"; }
ok()      { printf '    %s✔%s %s\n'     "$C_GRN" "$C_RST" "$1"; }
warn()    { printf '    %s!%s %s\n'     "$C_YEL" "$C_RST" "$1"; }
fail()    { printf '    %s✘%s %s\n'     "$C_RED" "$C_RST" "$1"; }
gone()    { printf '    %s−%s %s\n'     "$C_RED" "$C_RST" "$1"; }
dry()     { printf '    %s~%s %s\n'     "$C_YEL" "$C_RST" "$1"; }
detail()  { printf '        %s%s%s\n'   "$C_DIM" "$1" "$C_RST"; }
die()     { printf '\n  %s✘ %s%s\n\n'   "$C_RED$C_B" "$1" "$C_RST"; exit "${2:-1}"; }
bye()     { printf '\n  %s%s%s\n\n'     "$C_DIM" "$1" "$C_RST"; exit 0; }

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
#  Application catalogue
#
#    id ; display name ; detection paths (colon separated, relative to $HOME)
#       ; process names (space separated)
# ===========================================================================
APPS=(
"thunderbird;Thunderbird;.thunderbird:.cache/thunderbird;thunderbird"
"firefox;Firefox;.mozilla/firefox:.cache/mozilla/firefox;firefox"
"librewolf;LibreWolf;.librewolf:.cache/librewolf;librewolf"
"chrome;Google Chrome;.config/google-chrome:.cache/google-chrome;chrome google-chrome"
"chromium;Chromium;.config/chromium:.cache/chromium;chromium chromium-browser"
"pcloud;pCloud;.pcloud:.local/share/pcloud;pcloud"
"kde;Konqueror / KDE;.cache/konqueror:.cache/kio_http:.cache/thumbnails:.thumbnails:.local/share/konqueror;konqueror"
)

app_field() { printf '%s' "${APPS[$1]}" | cut -d';' -f"$2"; }

app_index() {   # app_index <id> -> catalogue position, or 1 if unknown
    local i
    for i in "${!APPS[@]}"; do
        [ "$(app_field "$i" 1)" = "$1" ] && { printf '%s' "$i"; return 0; }
    done
    return 1
}

# True when the application leaves any trace in the given home.
app_present() {   # app_present <catalogue index> <home>
    local paths p
    paths="$(app_field "$1" 3)"
    # `|| [ -n "$p" ]` so the last path, which has no trailing newline,
    # is still tested.
    while IFS= read -r p || [ -n "$p" ]; do
        [ -n "$p" ] && [ -e "$2/$p" ] && return 0
    done < <(printf '%s' "$paths" | tr ':' '\n')
    return 1
}

# ===========================================================================
#  Size / deletion primitives
#
#  Every one of them works on an explicit path, never on $HOME, so the same
#  code cleans any user's home.
# ===========================================================================
path_size() {
    [ -e "$1" ] && du -sb "$1" 2>/dev/null | awk '{print $1}' || echo 0
}

human() {
    local b="$1"
    if   [ "$b" -ge 1073741824 ] 2>/dev/null; then awk "BEGIN{printf \"%.2f GB\", $b/1073741824}"
    elif [ "$b" -ge 1048576 ]    2>/dev/null; then awk "BEGIN{printf \"%.2f MB\", $b/1048576}"
    elif [ "$b" -ge 1024 ]       2>/dev/null; then awk "BEGIN{printf \"%.2f KB\", $b/1024}"
    else printf '%s B' "$b"
    fi
}

add_bytes() {
    BYTES_USER=$(( BYTES_USER + $1 ))
    BYTES_TOTAL=$(( BYTES_TOTAL + $1 ))
}

# Empty a directory, keeping the directory itself.
empty_dir() {   # empty_dir <path> <label>
    local d="$1" label="${2:-$1}" size
    [ -d "$d" ] || return 0
    [ -z "$(ls -A "$d" 2>/dev/null)" ] && return 0
    size="$(path_size "$d")"
    if $DRY_RUN; then
        dry "$label — $(human "$size")"
    else
        gone "$label — $(human "$size")"
        rm -rf -- "${d:?}"/* "${d:?}"/.[!.]* 2>/dev/null
    fi
    add_bytes "$size"
}

# Remove a directory entirely.
drop_dir() {   # drop_dir <path> <label>
    local d="$1" label="${2:-$1}" size
    [ -d "$d" ] || return 0
    size="$(path_size "$d")"
    if $DRY_RUN; then
        dry "$label — $(human "$size")"
    else
        gone "$label — $(human "$size")"
        rm -rf -- "$d"
    fi
    add_bytes "$size"
}

# Remove files matched by find expressions.
drop_files() {   # drop_files <base dir> <label> <find args...>
    local base="$1" label="$2"; shift 2
    [ -d "$base" ] || return 0
    local -a files=()
    mapfile -t files < <(find "$base" "$@" 2>/dev/null)
    [ "${#files[@]}" -eq 0 ] && return 0

    local size=0 f s
    for f in "${files[@]}"; do
        s="$(path_size "$f")"
        size=$(( size + s ))
    done

    if $DRY_RUN; then
        dry "${#files[@]} file(s): $label — $(human "$size")"
    else
        gone "${#files[@]} file(s): $label — $(human "$size")"
        find "$base" "$@" -delete 2>/dev/null
    fi
    add_bytes "$size"
}

# Is any of these processes running for this user?
proc_running() {   # proc_running <user> <process names...>
    local user="$1"; shift
    local p
    for p in "$@"; do
        if pgrep -x -u "$user" "$p" > /dev/null 2>&1; then
            printf '%s' "$p"; return 0
        fi
    done
    return 1
}

# ===========================================================================
#  Per-application cleaners  -  clean_x <home> <user>
# ===========================================================================
clean_gecko() {   # clean_gecko <home> <profiles subdir> <cache subdir> <is firefox>
    local home="$1" profiles="$1/$2" cachedir="$1/$3" is_ff="$4"
    local pc pd pname sub

    if [ -d "$cachedir" ]; then
        while IFS= read -r pc; do
            empty_dir "$pc" "cache/$(basename "$pc")"
        done < <(find "$cachedir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    fi

    if [ -d "$profiles" ]; then
        while IFS= read -r pd; do
            pname="$(basename "$pd")"
            for sub in cache cache2 thumbnails startupCache offlinecache; do
                drop_dir "$pd/$sub" "$pname/$sub"
            done
            # storage/: only the throwaway subtrees, never storage/default,
            # which holds persistent extension data.
            for sub in temporary cache; do
                drop_dir "$pd/storage/$sub" "$pname/storage/$sub"
            done
            drop_dir "$pd/weave/logs"   "$pname/weave/logs"
            drop_dir "$pd/weave/failed" "$pname/weave/failed"

            drop_files "$pd" "$pname session checkpoints" \
                -maxdepth 1 -type f -name "sessionCheckpoints.json"
            drop_files "$pd/sessionstore-backups" "$pname session backups" -type f
            drop_files "$pd" "$pname tmp/bak" \
                -maxdepth 2 -type f \( -name "*.bak" -o -name "*.tmp" -o -name "*.corrupt" \)
            drop_files "$pd" "$pname crash minidumps" \
                -maxdepth 2 -type f -name "*.dmp"
        done < <(find "$profiles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    fi

    if [ "$is_ff" = "1" ]; then
        drop_dir "$home/.cache/mesa_shader_cache" "mesa_shader_cache"
        drop_dir "$home/.cache/mozilla-ipc"       "mozilla-ipc"
    fi
}

clean_firefox()   { clean_gecko "$1" ".mozilla/firefox" ".cache/mozilla/firefox" 1; }
clean_librewolf() { clean_gecko "$1" ".librewolf"       ".cache/librewolf"       0; }

clean_thunderbird() {
    local home="$1" profiles="$1/.thunderbird" pd pname store f d

    empty_dir "$home/.cache/thunderbird" "thunderbird cache"
    [ -d "$profiles" ] || return 0

    while IFS= read -r pd; do
        pname="$(basename "$pd")"
        drop_dir "$pd/cache"        "$pname/cache"
        drop_dir "$pd/cache2"       "$pname/cache2"
        drop_dir "$pd/startupCache" "$pname/startupCache"

        drop_files "$pd" "$pname global index" \
            -maxdepth 1 -type f -name "global-messages-db.sqlite"
        drop_files "$pd" "$pname .msf indexes" -type f -name "*.msf"

        if $TB_MBOX; then
            for store in ImapMail Mail; do
                [ -d "$pd/$store" ] || continue
                while IFS= read -r f; do
                    local fs; fs="$(path_size "$f")"
                    if $DRY_RUN; then
                        dry "$pname/${f##"$pd/"} — $(human "$fs")"
                    else
                        gone "$pname/${f##"$pd/"} — $(human "$fs")"
                        rm -f -- "$f"
                    fi
                    add_bytes "$fs"
                done < <(find "$pd/$store" -mindepth 2 -maxdepth 2 -type f \
                            ! -name "msgFilterRules.dat" 2>/dev/null)
                while IFS= read -r d; do
                    drop_dir "$d" "$pname/${d##"$pd/"}"
                done < <(find "$pd/$store" -mindepth 2 -maxdepth 2 -type d 2>/dev/null)
            done
        fi

        drop_dir "$pd/crashes" "$pname/crashes"
        drop_files "$pd" "$pname crash minidumps" -maxdepth 3 -type f -name "*.dmp"
        drop_files "$pd" "$pname tmp/bak" \
            -maxdepth 2 -type f \( -name "*.bak" -o -name "*.tmp" \)
    done < <(find "$profiles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
}

clean_chromium_like() {   # clean_chromium_like <cache root> <config root>
    local cache="$1" config="$2" pc extra

    if [ -d "$cache" ]; then
        for pc in "$cache"/*/; do
            [ -d "$pc" ] || continue
            empty_dir "$pc" "cache/$(basename "$pc")"
        done
    fi

    [ -d "$config" ] || return 0

    while IFS= read -r extra; do
        drop_dir "$extra" "${extra##"$config/"}"
    done < <(find "$config" -type d \
                \( -name "GPUCache" -o -name "ShaderCache" -o -name "Code Cache" \
                   -o -name "DawnCache" -o -name "GrShaderCache" \
                   -o -name "Crash Reports" \) 2>/dev/null)

    drop_files "$config" "tmp/log/dmp" \
        -maxdepth 4 -type f \( -name "*.tmp" -o -name "*.log" -o -name "*.dmp" \)
}

clean_chrome()   { clean_chromium_like "$1/.cache/google-chrome" "$1/.config/google-chrome"; }
clean_chromium() { clean_chromium_like "$1/.cache/chromium"      "$1/.config/chromium"; }

clean_pcloud() {
    local home="$1"
    empty_dir "$home/.pcloud/Cache"                    "pcloud cache"
    empty_dir "$home/.pcloud/ntfthumbs"                "pcloud thumbnails"
    empty_dir "$home/.local/share/pcloud/Cache"        "pcloud cache (alt path)"
    empty_dir "$home/.local/share/pcloud/Thumbnails"   "pcloud thumbnails (alt path)"
}

clean_kde() {
    local home="$1"
    # Cookies and history are user data and are deliberately left alone.
    drop_dir "$home/.cache/konqueror"             "konqueror cache"
    drop_dir "$home/.cache/kio_http"              "KIO HTTP cache"
    drop_dir "$home/.local/share/konqueror/cache" "konqueror local cache"
    drop_dir "$home/.cache/thumbnails"            "KDE thumbnails"
    drop_dir "$home/.thumbnails"                  "KDE thumbnails (legacy)"
    drop_dir "$home/.cache/plasma_theme"          "plasma theme cache"
    drop_dir "$home/.cache/plasma-svgelements"    "plasma SVG cache"
    drop_dir "$home/.cache/ksvg-elements"         "ksvg cache"
    drop_dir "$home/.cache/icon-cache.kcache"     "KDE icon cache"
    drop_files "$home/.cache" ".kcache files" -maxdepth 1 -type f -name "*.kcache"
    drop_dir "$home/.local/share/drkonqi"         "drkonqi crash reports"
}

run_app() {   # run_app <catalogue index> <home> <user>
    local idx="$1" home="$2" user="$3"
    local id name procs busy
    id="$(app_field "$idx" 1)"; name="$(app_field "$idx" 2)"; procs="$(app_field "$idx" 4)"

    if busy="$(proc_running "$user" $procs)"; then
        fail "$name — '$busy' is running for $user, skipped"
        return 1
    fi

    subsec "$name"
    case "$id" in
        thunderbird) clean_thunderbird "$home" ;;
        firefox)     clean_firefox     "$home" ;;
        librewolf)   clean_librewolf   "$home" ;;
        chrome)      clean_chrome      "$home" ;;
        chromium)    clean_chromium    "$home" ;;
        pcloud)      clean_pcloud      "$home" ;;
        kde)         clean_kde         "$home" ;;
    esac
    return 0
}

# ===========================================================================
#  Users
# ===========================================================================
# Prints "<user>:<home>" for every human account with an existing home.
list_users() {
    awk -F: '($3 >= 1000 && $3 < 60000) || $3 == 0 { print $1 ":" $6 ":" $7 }' /etc/passwd \
    | while IFS=: read -r u h sh; do
        case "$sh" in */nologin|*/false|"") continue ;; esac
        [ -d "$h" ] || continue
        printf '%s:%s\n' "$u" "$h"
    done | sort -u
}

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf '%s  Root privileges are required to reach other users, re-running with sudo...%s\n' \
            "$C_DIM" "$C_RST"
        exec sudo -- "$0" "$@"
    fi
}

# ===========================================================================
#  Entry point
# ===========================================================================
usage() {
    banner "clean-cache $VERSION"
    printf '  %sUsage:%s %s [-a] [--dry-run] [--no-tb-mail] [app ...]\n\n' \
        "$C_B" "$C_RST" "$(basename "$0")"
    printf '    %s-a, --all%s      pick which users to clean, then which applications\n' "$C_B" "$C_RST"
    printf '    %s--dry-run%s      report what would be removed, delete nothing\n' "$C_B" "$C_RST"
    printf '    %s--no-tb-mail%s   keep Thunderbird local mail stores\n' "$C_B" "$C_RST"
    printf '    %s--list%s         print the application ids and exit\n' "$C_B" "$C_RST"
    printf '\n  With no argument only the current user is cleaned, choosing the\n'
    printf '  applications from a checkbox list.\n\n'
    printf '  Applications: '
    local i
    for i in "${!APPS[@]}"; do printf '%s ' "$(app_field "$i" 1)"; done
    printf '\n\n'
}

ALL_USERS=false
declare -a CLI_APPS=()

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--all)      ALL_USERS=true ;;
        --dry-run|-n)  DRY_RUN=true ;;
        --no-tb-mail)  TB_MBOX=false ;;
        --list)
            for i in "${!APPS[@]}"; do
                printf '%-14s %s\n' "$(app_field "$i" 1)" "$(app_field "$i" 2)"
            done
            exit 0 ;;
        -h|--help)     usage; exit 0 ;;
        -*)            usage; die "Unknown option: $1" ;;
        *)
            if app_index "$1" >/dev/null; then
                CLI_APPS+=("$1")
            else
                usage; die "Unknown application: $1"
            fi ;;
    esac
    shift
done

banner "clean-cache $VERSION"
$DRY_RUN && warn "Dry run — nothing will be deleted."

# ---- which users ----------------------------------------------------------
declare -a SEL_USER=() SEL_HOME=()

if $ALL_USERS; then
    need_root --all $($DRY_RUN && echo --dry-run) $($TB_MBOX || echo --no-tb-mail) "${CLI_APPS[@]}"

    declare -a all_u=() all_h=()
    while IFS=: read -r u h; do all_u+=("$u"); all_h+=("$h"); done < <(list_users)
    [ "${#all_u[@]}" -eq 0 ] && die "No user account with a home directory found."

    cl_reset
    local_i=0
    for local_i in "${!all_u[@]}"; do
        n=0
        for i in "${!APPS[@]}"; do
            app_present "$i" "${all_h[$local_i]}" && n=$((n+1))
        done
        if [ "$n" -gt 0 ]; then
            cl_add "${all_u[$local_i]}" 1 "$n app(s) — ${all_h[$local_i]}"
        else
            cl_add "${all_u[$local_i]}" 0 "nothing to clean"
        fi
    done
    cl_run "Select the users to clean" || bye "Cancelled."

    for local_i in "${!all_u[@]}"; do
        if [ "${CL_STATE[$local_i]}" = "1" ]; then
            SEL_USER+=("${all_u[$local_i]}")
            SEL_HOME+=("${all_h[$local_i]}")
        fi
    done
    [ "${#SEL_USER[@]}" -eq 0 ] && bye "No user selected."
else
    SEL_USER+=("$(id -un)")
    SEL_HOME+=("${HOME:-$(getent passwd "$(id -un)" | cut -d: -f6)}")
    info "Current user only — use -a to pick other users."
fi

# ---- which applications ---------------------------------------------------
# An application is offered when it is present in at least one selected user.
declare -a SEL_APP=()

if [ "${#CLI_APPS[@]}" -gt 0 ]; then
    for a in "${CLI_APPS[@]}"; do SEL_APP+=("$(app_index "$a")"); done
else
    declare -a offer=() count=()
    for i in "${!APPS[@]}"; do
        n=0
        for j in "${!SEL_HOME[@]}"; do
            app_present "$i" "${SEL_HOME[$j]}" && n=$((n+1))
        done
        if [ "$n" -gt 0 ]; then offer+=("$i"); count+=("$n"); fi
    done
    [ "${#offer[@]}" -eq 0 ] && bye "Nothing found to clean for the selected user(s)."

    cl_reset
    for k in "${!offer[@]}"; do
        if [ "${#SEL_USER[@]}" -gt 1 ]; then
            cl_add "$(app_field "${offer[$k]}" 2)" 1 "found in ${count[$k]} of ${#SEL_USER[@]} users"
        else
            cl_add "$(app_field "${offer[$k]}" 2)" 1 ""
        fi
    done
    cl_run "Select the applications to clean" || bye "Cancelled."

    for k in "${!offer[@]}"; do
        [ "${CL_STATE[$k]}" = "1" ] && SEL_APP+=("${offer[$k]}")
    done
fi
[ "${#SEL_APP[@]}" -eq 0 ] && bye "No application selected."

# ---- confirm --------------------------------------------------------------
section "About to clean"
printf '    %-12s %s\n' "users:" "${SEL_USER[*]}"
apps_line=""
for i in "${SEL_APP[@]}"; do apps_line="$apps_line$(app_field "$i" 2), "; done
printf '    %-12s %s\n' "apps:" "${apps_line%, }"
$TB_MBOX && for i in "${SEL_APP[@]}"; do
    if [ "$(app_field "$i" 1)" = "thunderbird" ]; then
        printf '\n'
        warn "Thunderbird local mail stores will be wiped as well."
        detail "IMAP accounts resync from the server, but POP3 mail and"
        detail "Local Folders are lost. Pass --no-tb-mail to keep them."
    fi
done

if ! $DRY_RUN; then
    printf '\n'
    ask_yes_no "Proceed?" n || bye "Cancelled."
fi

# ---- run ------------------------------------------------------------------
for j in "${!SEL_USER[@]}"; do
    BYTES_USER=0
    section "${SEL_USER[$j]}  ${C_DIM}(${SEL_HOME[$j]})${C_RST}"
    for i in "${SEL_APP[@]}"; do
        if app_present "$i" "${SEL_HOME[$j]}"; then
            run_app "$i" "${SEL_HOME[$j]}" "${SEL_USER[$j]}"
        else
            info "$(app_field "$i" 2) — not present"
        fi
    done
    printf '\n'
    if $DRY_RUN; then
        info "${SEL_USER[$j]}: $(human "$BYTES_USER") would be freed"
    else
        ok "${SEL_USER[$j]}: $(human "$BYTES_USER") freed"
    fi
done

printf '\n'; hr
if $DRY_RUN; then
    warn "Dry run finished — $(human "$BYTES_TOTAL") would be freed. Nothing was deleted."
else
    ok "Finished — $(human "$BYTES_TOTAL") freed."
fi
printf '\n'
