#!/bin/bash
# ===========================================================================
#  repo-sync.sh  -  APT repository & signing key migration tool
# ---------------------------------------------------------------------------
#  Copies APT repository definitions and their GPG signing keys from one
#  machine to another (typically MX Linux -> Debian).
#
#    ./repo-sync.sh export     run on the SOURCE machine, saves into ./data
#    ./repo-sync.sh import     run on the TARGET machine (root), installs them
#    ./repo-sync.sh            asks which mode to run
#
#  Both modes open a checkbox list:
#    Up/Down  move      Space  toggle      A  all/none      Enter  confirm
# ===========================================================================

set -uo pipefail

VERSION="26.08"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
FPR_CACHE=""

# ---------------------------------------------------------------------------
#  Repository catalogue
#
#    id ; display name ; apt match regex ; key filename glob ;
#    official key URL ; official fingerprint
#
#  The last two fields are only used by the optional key verification in
#  import mode. Leave them empty when no stable public source is known:
#  that repository will simply be reported as "not verifiable".
#  Fields are separated by ';' so regexes may freely use '|'.
# ---------------------------------------------------------------------------
CATALOGUE=(
"mx;MX Linux;mxlinux\.org|mx-packages|mxrepo;*mx*;;"
"chrome;Google Chrome;dl\.google\.com/linux/chrome|google-chrome;*google*;https://dl.google.com/linux/linux_signing_key.pub;"
"teamviewer;TeamViewer;linux\.teamviewer\.com|teamviewer;*teamviewer*;https://linux.teamviewer.com/pubkey/currentkey.asc;"
"vscode;Visual Studio Code;packages\.microsoft\.com/repos/code;*microsoft*;https://packages.microsoft.com/keys/microsoft.asc;"
"vscodium;VSCodium;vscodium|paulcarroty;*vscodium*;https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg;"
"claude;Claude Desktop;downloads\.claude\.ai/claude-desktop;*claude*;https://downloads.claude.ai/claude-desktop/key.asc;31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
)

APT_KEY_DIRS=(/etc/apt/trusted.gpg.d /etc/apt/keyrings /usr/share/keyrings)

# ===========================================================================
#  Presentation helpers
# ===========================================================================
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
    C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
    C_BLU=$'\033[34m'; C_MAG=$'\033[35m'; C_CYN=$'\033[36m'
    C_INV=$'\033[7m'; C_CLR=$'\033[2K'
else
    C_RST=""; C_B=""; C_DIM=""; C_RED=""; C_GRN=""; C_YEL=""
    C_BLU=""; C_MAG=""; C_CYN=""; C_INV=""; C_CLR=""
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
bye()     { printf '\n  %s%s%s\n\n'      "$C_DIM" "$1" "$C_RST"; exit 0; }

# True when the controlling terminal can actually be opened.
tty_available() { { : < /dev/tty; } 2>/dev/null; }

# yes/no question, reads from the terminal even inside pipes
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
#  Checkbox list
#
#    cl_add "<label>" <0|1> "<hint>"      build the list
#    cl_run "<title>"                     draw it, returns 1 if cancelled
#    CL_STATE[i]                          0/1 after cl_run
# ===========================================================================
CL_LABEL=(); CL_STATE=(); CL_HINT=(); CL_EXCLUSIVE=0

# cl_reset [exclusive]  -  pass 1 for a radio list: ticking one option
#                          automatically unticks all the others.
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
        line=$(printf '%-28s %s%s%s' "${CL_LABEL[$i]}" "$C_DIM" "${CL_HINT[$i]}" "$C_RST")
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

    # No terminal available: keep the proposed defaults and carry on.
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

    printf '\033[?25l'                       # hide cursor
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
            'q'|'Q')
                printf '\033[?25h'; trap - EXIT INT TERM; return 1 ;;
            '')
                printf '\033[?25h'; trap - EXIT INT TERM; return 0 ;;
        esac
        printf '\033[%dA' "$n"
        cl_draw "$cur"
    done
}

# ===========================================================================
#  Catalogue accessors
# ===========================================================================
cat_field() {  # cat_field <index> <field-number 1..6>
    printf '%s' "${CATALOGUE[$1]}" | cut -d';' -f"$2"
}

# ===========================================================================
#  GPG helpers
# ===========================================================================
fingerprints_of() {   # print every primary-key fingerprint found in a file
    gpg --with-colons --show-keys --fingerprint "$1" 2>/dev/null \
        | awk -F: '$1=="fpr"{print $10}' | sort -u
}

pretty_fpr() {        # 40 hex chars -> groups of four
    printf '%s' "$1" | sed 's/.\{4\}/& /g' | sed 's/ $//'
}

# ===========================================================================
#  EXPORT
# ===========================================================================
apt_files() {
    local f
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
}

# Prints "<apt file>" for the first file that defines the repository.
find_repo_file() {
    local regex="$1" f
    while IFS= read -r f; do
        if sudo grep -Eqi -- "$regex" "$f" 2>/dev/null; then
            printf '%s' "$f"; return 0
        fi
    done < <(apt_files)
    return 1
}

export_one() {   # export_one <catalogue index>
    local idx="$1"
    local id name regex glob src out
    id="$(cat_field "$idx" 1)"; name="$(cat_field "$idx" 2)"
    regex="$(cat_field "$idx" 3)"; glob="$(cat_field "$idx" 4)"
    src="${REPO_FILE[$idx]}"
    out="$DATA_DIR/$id"

    rm -rf "$out"
    mkdir -p "$out/keys"
    : > "$out/manifest"

    # --- repository definition -------------------------------------------
    local base; base="$(basename "$src")"
    if [ "${src##*.}" = "sources" ]; then
        sudo cat "$src" > "$out/repo.sources"
        printf 'list\trepo.sources\t%s\n' "$base" >> "$out/manifest"
    else
        if [ "$src" = "/etc/apt/sources.list" ]; then base="$id.list"; fi
        sudo grep -Ei -- "$regex" "$src" | grep -v '^[[:space:]]*#' > "$out/repo.list"
        printf 'list\trepo.list\t%s\n' "$base" >> "$out/manifest"
    fi
    ok "$name — definition taken from $src"

    # --- signing keys -----------------------------------------------------
    local -a keys=()
    local p
    while IFS= read -r p; do [ -n "$p" ] && keys+=("$p"); done < <(
        sudo grep -oP '(?<=signed-by=)[^]\s]+' "$src" 2>/dev/null
        sudo grep -oP '(?<=^Signed-By:)\s*\S+' "$src" 2>/dev/null | tr -d ' '
    )

    if [ "${#keys[@]}" -eq 0 ]; then
        local d
        for d in "${APT_KEY_DIRS[@]}"; do
            [ -d "$d" ] || continue
            while IFS= read -r p; do [ -n "$p" ] && keys+=("$p"); done < <(
                sudo find "$d" -maxdepth 1 -type f -iname "$glob" 2>/dev/null)
        done
    fi

    if [ "${#keys[@]}" -eq 0 ]; then
        warn "no signing key found — copy it into $out/keys/ by hand"
        return 0
    fi

    local k kb seen=""
    for k in "${keys[@]}"; do
        sudo test -f "$k" || continue
        case "$seen" in *"|$k|"*) continue ;; esac
        seen="$seen|$k|"
        kb="$(basename "$k")"
        sudo cat "$k" > "$out/keys/$kb"
        printf 'key\t%s\t%s\n' "$kb" "$k" >> "$out/manifest"
        local fpr; fpr="$(fingerprints_of "$out/keys/$kb" | head -n1)"
        ok "key $kb"
        detail "from $k"
        [ -n "$fpr" ] && detail "fingerprint $(pretty_fpr "$fpr")"
    done
}

run_export() {
    banner "repo-sync $VERSION  -  EXPORT  (source machine)"

    command -v gpg >/dev/null 2>&1 || warn "gpg not installed: fingerprints will not be shown."

    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        REAL_UID="$SUDO_UID"; REAL_GID="$SUDO_GID"
    else
        REAL_UID="$(id -u)"; REAL_GID="$(id -g)"
    fi

    info "Root privileges are needed to read /etc/apt, requesting them now."
    sudo -v || die "sudo authentication failed."

    section "Scanning APT configuration"
    declare -ga REPO_FILE=()
    local -a found=()
    local i id name regex f
    for i in "${!CATALOGUE[@]}"; do
        id="$(cat_field "$i" 1)"; name="$(cat_field "$i" 2)"; regex="$(cat_field "$i" 3)"
        REPO_FILE[$i]=""
        if f="$(find_repo_file "$regex")"; then
            REPO_FILE[$i]="$f"
            found+=("$i")
            ok "$name"
            detail "$f"
        else
            printf '  %s·%s %s%s — not installed%s\n' "$C_DIM" "$C_RST" "$C_DIM" "$name" "$C_RST"
        fi
    done

    [ "${#found[@]}" -eq 0 ] && die "None of the known repositories is configured on this machine."

    # ---- selection list, pre-checking what has not been exported yet -----
    cl_reset
    local hint state exported
    for i in "${found[@]}"; do
        id="$(cat_field "$i" 1)"; name="$(cat_field "$i" 2)"
        exported=0
        if [ -d "$DATA_DIR/$id" ] && compgen -G "$DATA_DIR/$id/keys/*" >/dev/null 2>&1; then
            exported=1
        fi
        if [ "$exported" = "1" ]; then
            state=0; hint="already exported"
        else
            state=1; hint=""
        fi
        cl_add "$name" "$state" "$hint"
    done

    cl_run "Select the repositories to export" || bye "Cancelled."

    # ---- one-by-one overwrite confirmation -------------------------------
    local -a todo=()
    local n=0
    for i in "${found[@]}"; do
        if [ "${CL_STATE[$n]}" = "1" ]; then
            id="$(cat_field "$i" 1)"; name="$(cat_field "$i" 2)"
            if [ -d "$DATA_DIR/$id" ] && compgen -G "$DATA_DIR/$id/keys/*" >/dev/null 2>&1; then
                printf '\n'
                warn "$name is already present in data/$id"
                if ! ask_yes_no "Overwrite it?" n; then
                    info "$name skipped."
                    n=$((n+1)); continue
                fi
            fi
            todo+=("$i")
        fi
        n=$((n+1))
    done

    [ "${#todo[@]}" -eq 0 ] && bye "Nothing selected."

    section "Exporting"
    mkdir -p "$DATA_DIR"
    for i in "${todo[@]}"; do export_one "$i"; done

    chown -R "$REAL_UID:$REAL_GID" "$DATA_DIR" 2>/dev/null || \
        sudo chown -R "$REAL_UID:$REAL_GID" "$DATA_DIR"
    find "$DATA_DIR" -type d -exec chmod 755 {} +
    find "$DATA_DIR" -type f -exec chmod 644 {} +

    printf '\n'; hr
    ok "Done. Everything is under: ${C_B}$DATA_DIR${C_RST}"
    info "Copy the whole ${C_B}$(basename "$SCRIPT_DIR")${C_RST} folder to the target machine"
    info "and run there: ${C_B}sudo ./$(basename "${BASH_SOURCE[0]}") import${C_RST}"
    printf '\n'
}

# ===========================================================================
#  IMPORT
# ===========================================================================
repo_installed() {   # repo_installed <regex> <dest basename>
    local regex="$1" f
    while IFS= read -r f; do
        grep -Eqi -- "$regex" "$f" 2>/dev/null && return 0
    done < <(apt_files)
    return 1
}

# Expected fingerprints for a repository: the pinned one, or those of the key
# published by the vendor. Prints nothing when no reference is available.
expected_fprs() {   # expected_fprs <catalogue index>
    local idx="$1" url fpr_exp tmp
    url="$(cat_field "$idx" 5)"; fpr_exp="$(cat_field "$idx" 6)"

    if [ -n "$fpr_exp" ]; then
        printf '%s\n' "$fpr_exp"
        return 0
    fi
    [ -n "$url" ] || return 1

    # Downloaded once per run and reused for both checks below.
    local cache="$FPR_CACHE/$(cat_field "$idx" 1)"
    if [ -f "$cache" ]; then
        cat "$cache"
        [ -s "$cache" ] && return 0 || return 1
    fi

    tmp="$(mktemp)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 30 -o "$tmp" "$url" 2>/dev/null || true
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp" --timeout=30 "$url" 2>/dev/null || true
    fi
    : > "$cache"
    [ -s "$tmp" ] && fingerprints_of "$tmp" > "$cache"
    rm -f "$tmp"

    cat "$cache"
    [ -s "$cache" ] && return 0 || return 1
}

# verify_files <catalogue index> <tag> <key file>...
#   0 = matches, 1 = mismatch, 2 = cannot be checked
verify_files() {
    local idx="$1" tag="$2"; shift 2
    local name; name="$(cat_field "$idx" 2)"
    local label="$name ${C_DIM}($tag)${C_RST}"

    command -v gpg >/dev/null 2>&1 || { warn "$label — gpg not installed, cannot check."; return 2; }
    [ "$#" -gt 0 ] || { warn "$label — no key found, cannot check."; return 2; }

    local expected
    if ! expected="$(expected_fprs "$idx")" || [ -z "$expected" ]; then
        if [ -z "$(cat_field "$idx" 5)$(cat_field "$idx" 6)" ]; then
            warn "$label — no official reference available, cannot check."
        else
            warn "$label — official key could not be downloaded, cannot check."
        fi
        return 2
    fi

    local k got matched=0 first="" seen=0
    for k in "$@"; do
        [ -f "$k" ] || continue
        while IFS= read -r got; do
            seen=1
            [ -z "$first" ] && first="$got"
            case "$expected" in *"$got"*) matched=1 ;; esac
        done < <(fingerprints_of "$k")
    done

    if [ "$seen" = "0" ]; then
        warn "$label — key file missing or unreadable, cannot check."
        for k in "$@"; do [ -f "$k" ] || detail "missing: $k"; done
        return 2
    fi

    if [ "$matched" = "1" ]; then
        ok "$label — matches the official fingerprint"
        return 0
    fi

    fail "$label — KEY MISMATCH"
    detail "found:     $(pretty_fpr "${first:-none}")"
    detail "official:  $(pretty_fpr "$(printf '%s' "$expected" | head -n1)")"
    return 1
}

# Key files this repository ships in the export folder.
exported_keys() {   # exported_keys <catalogue index>
    local dir="$DATA_DIR/$(cat_field "$1" 1)/keys" k
    for k in "$dir"/*; do [ -f "$k" ] && printf '%s\n' "$k"; done
}

# Key files this repository already uses on the running system.
installed_keys() {   # installed_keys <catalogue index>
    local regex glob f p d
    regex="$(cat_field "$1" 3)"; glob="$(cat_field "$1" 4)"
    local -a keys=()

    while IFS= read -r f; do
        grep -Eqi -- "$regex" "$f" 2>/dev/null || continue
        while IFS= read -r p; do [ -n "$p" ] && keys+=("$p"); done < <(
            grep -oP '(?<=signed-by=)[^]\s]+' "$f" 2>/dev/null
            grep -oP '(?<=^Signed-By:)\s*\S+' "$f" 2>/dev/null | tr -d ' '
        )
    done < <(apt_files)

    if [ "${#keys[@]}" -eq 0 ]; then
        for d in "${APT_KEY_DIRS[@]}"; do
            [ -d "$d" ] || continue
            while IFS= read -r p; do [ -n "$p" ] && keys+=("$p"); done < <(
                find "$d" -maxdepth 1 -type f -iname "$glob" 2>/dev/null)
        done
    fi

    [ "${#keys[@]}" -eq 0 ] && return 0
    printf '%s\n' "${keys[@]}" | awk 'NF' | sort -u
}

import_one() {   # import_one <catalogue index>
    local idx="$1"
    local id name dir
    id="$(cat_field "$idx" 1)"; name="$(cat_field "$idx" 2)"
    dir="$DATA_DIR/$id"

    local kind file dest
    while IFS=$'\t' read -r kind file dest; do
        case "$kind" in
            list)
                cp "$dir/$file" "/etc/apt/sources.list.d/$dest"
                chown root:root "/etc/apt/sources.list.d/$dest"
                chmod 644 "/etc/apt/sources.list.d/$dest"
                ok "$name — /etc/apt/sources.list.d/$dest"
                ;;
            key)
                mkdir -p "$(dirname "$dest")"
                chmod 755 "$(dirname "$dest")"
                cp "$dir/keys/$file" "$dest"
                chown root:root "$dest"
                chmod 644 "$dest"
                ok "$name — key restored to $dest"
                ;;
        esac
    done < "$dir/manifest"
}

# Every path this repository would write to (used for the overwrite check).
targets_of() {
    local dir="$1" kind file dest
    while IFS=$'\t' read -r kind file dest; do
        case "$kind" in
            list) printf '/etc/apt/sources.list.d/%s\n' "$dest" ;;
            key)  printf '%s\n' "$dest" ;;
        esac
    done < "$dir/manifest"
}

run_import() {
    if [ "$(id -u)" -ne 0 ]; then
        printf '%s  Root privileges are required, re-running with sudo...%s\n' "$C_DIM" "$C_RST"
        exec sudo -- "$0" "$@"
    fi

    banner "repo-sync $VERSION  -  IMPORT  (target machine)"

    [ -d "$DATA_DIR" ] || die "Folder 'data' not found next to the script. Run the export first."

    section "Reading exported data"
    local -a avail=()
    local i id name regex dir
    for i in "${!CATALOGUE[@]}"; do
        id="$(cat_field "$i" 1)"; name="$(cat_field "$i" 2)"
        dir="$DATA_DIR/$id"
        if [ -f "$dir/manifest" ] && [ -s "$dir/manifest" ]; then
            avail+=("$i")
            ok "$name"
            local nk; nk="$(grep -c '^key' "$dir/manifest" || true)"
            detail "$nk key(s)"
        fi
    done

    [ "${#avail[@]}" -eq 0 ] && die "No exported repository found under $DATA_DIR."

    # ---- selection list, pre-checking what is not installed yet ----------
    cl_reset
    local state hint present
    for i in "${avail[@]}"; do
        name="$(cat_field "$i" 2)"; regex="$(cat_field "$i" 3)"
        if repo_installed "$regex"; then
            state=0; hint="already installed"
        else
            state=1; hint=""
        fi
        cl_add "$name" "$state" "$hint"
    done
    cl_add "Verify signing keys" 1 "exported + already installed — needs network"

    cl_run "Select what to install" || bye "Cancelled."

    local vidx=$(( ${#CL_STATE[@]} - 1 ))
    local do_verify="${CL_STATE[$vidx]}"

    # ---- one-by-one overwrite confirmation -------------------------------
    local -a todo=()
    local n=0 t existing
    for i in "${avail[@]}"; do
        if [ "${CL_STATE[$n]}" = "1" ]; then
            name="$(cat_field "$i" 2)"; id="$(cat_field "$i" 1)"
            existing=""
            while IFS= read -r t; do
                [ -e "$t" ] && existing="$existing$t"$'\n'
            done < <(targets_of "$DATA_DIR/$id")

            if [ -n "$existing" ]; then
                printf '\n'
                warn "$name is already present on this system:"
                while IFS= read -r t; do [ -n "$t" ] && detail "$t"; done <<< "$existing"
                if ! ask_yes_no "Overwrite it?" n; then
                    info "$name skipped."
                    n=$((n+1)); continue
                fi
            fi
            todo+=("$i")
        fi
        n=$((n+1))
    done

    [ "${#todo[@]}" -eq 0 ] && bye "Nothing selected."

    # ---- key verification -------------------------------------------------
    if [ "$do_verify" = "1" ]; then
        section "Verifying signing keys"
        FPR_CACHE="$(mktemp -d)"
        local bad=0 bad_installed=0 unknown=0 rc sel
        local -a kf=()

        # a) the keys about to be installed
        for i in "${todo[@]}"; do
            mapfile -t kf < <(exported_keys "$i")
            verify_files "$i" "to install" "${kf[@]}"; rc=$?
            [ "$rc" -eq 1 ] && bad=1
            [ "$rc" -eq 2 ] && unknown=1
        done

        # b) the keys already on this system, for repositories that are not
        #    being replaced by this run
        for i in "${!CATALOGUE[@]}"; do
            sel=0
            for j in "${todo[@]}"; do [ "$j" = "$i" ] && sel=1; done
            [ "$sel" = "1" ] && continue
            repo_installed "$(cat_field "$i" 3)" || continue
            mapfile -t kf < <(installed_keys "$i")
            verify_files "$i" "already installed" "${kf[@]}"; rc=$?
            [ "$rc" -eq 1 ] && bad_installed=1
            [ "$rc" -eq 2 ] && unknown=1
        done

        rm -rf "$FPR_CACHE"

        if [ "$bad" = "1" ]; then
            printf '\n'
            die "Aborted: a key to be installed does not match its official fingerprint. Nothing was installed."
        fi
        if [ "$bad_installed" = "1" ]; then
            printf '\n'
            warn "A key already present on this system does not match its official"
            detail "fingerprint. It is not one of the repositories being installed now,"
            detail "but you should look into it before trusting that repository."
            ask_yes_no "Continue with the installation anyway?" n || bye "Cancelled."
        fi
        if [ "$unknown" = "1" ]; then
            printf '\n'
            ask_yes_no "Some keys could not be checked. Install them anyway?" y \
                || bye "Cancelled."
        fi
    else
        warn "Key verification disabled."
    fi

    # ---- install ----------------------------------------------------------
    section "Installing"
    for i in "${todo[@]}"; do import_one "$i"; done

    section "Refreshing package lists"
    if apt update; then
        ok "apt update completed."
    else
        warn "apt update reported errors, check the output above."
    fi

    printf '\n'; hr
    ok "Done."
    printf '\n'
}

# ===========================================================================
#  Entry point
# ===========================================================================
usage() {
    banner "repo-sync $VERSION"
    printf '  %sUsage:%s %s [export|import]\n\n' "$C_B" "$C_RST" "$(basename "$0")"
    printf '    %sexport%s   run on the source machine — saves repositories into ./data\n' "$C_B" "$C_RST"
    printf '    %simport%s   run on the target machine as root — installs them\n\n' "$C_B" "$C_RST"
    printf '  With no argument the mode is asked interactively.\n\n'
}

MODE="${1:-}"

case "$MODE" in
    export)          run_export ;;
    import)          shift || true; run_import "$@" ;;
    -h|--help|help)  usage ;;
    "")
        banner "repo-sync $VERSION"
        cl_reset 1
        cl_add "Export  (this is the source machine)" 1 ""
        cl_add "Import  (this is the target machine)" 0 ""
        cl_run "What do you want to do?" || bye "Cancelled."
        if [ "${CL_STATE[0]}" = "1" ]; then
            run_export
        elif [ "${CL_STATE[1]}" = "1" ]; then
            run_import
        else
            bye "Nothing selected."
        fi
        ;;
    *) usage; die "Unknown mode: $MODE" ;;
esac
