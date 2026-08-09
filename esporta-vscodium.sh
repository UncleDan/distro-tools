#!/bin/bash
# esporta-vscodium.sh
# Da eseguire su MX Linux come utente normale (non con sudo davanti).
# Estrae le righe di repository relative a VSCodium e la/le chiave/i
# GPG corrispondenti nella cartella "vscodiumrepo" creata accanto a
# questo script, con proprietario e permessi dell'utente reale. Se il
# repository non e' presente, non estrae nulla e lo segnala.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/vscodiumrepo"
mkdir -p "$OUT_DIR"

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    REAL_UID="$SUDO_UID"
    REAL_GID="$SUDO_GID"
else
    REAL_UID="$(id -u)"
    REAL_GID="$(id -g)"
fi

sudo -v

REPO_FILE="$OUT_DIR/vscodium.sources.list"
> "$REPO_FILE"

echo "Cerco il repository VSCodium nei file apt..."

declare -a KEY_PATHS=()

for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    if sudo grep -qi "codium" "$f" 2>/dev/null; then
        {
            echo "# --- da: $f ---"
            sudo grep -i "codium" "$f"
            echo ""
        } >> "$REPO_FILE"

        while IFS= read -r p; do
            [ -n "$p" ] && KEY_PATHS+=("$p")
        done < <(sudo grep -oP '(?<=signed-by=)[^]\s]+' "$f" 2>/dev/null || true)

        while IFS= read -r p; do
            [ -n "$p" ] && KEY_PATHS+=("$p")
        done < <(sudo grep -oP '(?<=Signed-By:\s)\S+' "$f" 2>/dev/null || true)
    fi
done

if [ ${#KEY_PATHS[@]} -eq 0 ]; then
    while IFS= read -r p; do
        KEY_PATHS+=("$p")
    done < <(sudo find /etc/apt/trusted.gpg.d /etc/apt/keyrings /usr/share/keyrings -iname "*codium*" 2>/dev/null || true)
fi

if [ ! -s "$REPO_FILE" ]; then
    echo "Nessun repository VSCodium trovato su questa macchina."
fi

if [ ${#KEY_PATHS[@]} -eq 0 ]; then
    if [ -s "$REPO_FILE" ]; then
        echo "ATTENZIONE: repository trovato ma nessuna chiave individuata automaticamente."
        echo "Copiala manualmente nella cartella: $OUT_DIR"
    fi
else
    for k in "${KEY_PATHS[@]}"; do
        if sudo test -f "$k"; then
            sudo cat "$k" > "$OUT_DIR/$(basename "$k")"
            echo "Copiata chiave: $k"
        fi
    done
fi

chown -R "$REAL_UID:$REAL_GID" "$OUT_DIR"
chmod 755 "$OUT_DIR"
find "$OUT_DIR" -type f -exec chmod 644 {} +

echo ""
echo "Fatto. Contenuto di $OUT_DIR:"
ls -l "$OUT_DIR"
