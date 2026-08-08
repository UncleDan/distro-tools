#!/bin/bash
# esporta-mxrepo.sh
# Da eseguire su MX Linux come utente normale (NON con sudo davanti:
# lo script chiede la password sudo internamente solo per le letture
# che lo richiedono). Estrae le righe di repository che riguardano
# "mx" e la/le chiave/i GPG corrispondenti nella cartella "mxrepo"
# creata accanto a questo script, con proprietario e permessi
# dell'utente reale (cosi' la cartella si puo' copiare liberamente).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/mxrepo"
mkdir -p "$OUT_DIR"

# Determina l'utente "reale" anche se lo script venisse lanciato con sudo
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    REAL_UID="$SUDO_UID"
    REAL_GID="$SUDO_GID"
else
    REAL_UID="$(id -u)"
    REAL_GID="$(id -g)"
fi

# Valida/cache le credenziali sudo una sola volta: le letture protette
# qui sotto non chiederanno piu' la password durante l'esecuzione
sudo -v

REPO_FILE="$OUT_DIR/mx.sources.list"
> "$REPO_FILE"

echo "Cerco i repository MX Linux nei file apt..."

declare -a KEY_PATHS=()

for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    if sudo grep -qi "mx" "$f" 2>/dev/null; then
        {
            echo "# --- da: $f ---"
            sudo grep -i "mx" "$f"
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
    done < <(sudo find /etc/apt/trusted.gpg.d /etc/apt/keyrings -iname "*mx*" 2>/dev/null || true)
fi

if [ ${#KEY_PATHS[@]} -eq 0 ]; then
    echo "ATTENZIONE: nessuna chiave trovata automaticamente."
    echo "Copiala manualmente nella cartella: $OUT_DIR"
else
    for k in "${KEY_PATHS[@]}"; do
        if sudo test -f "$k"; then
            # "sudo cat" legge il file protetto, ma il file di destinazione
            # viene creato dalla shell corrente: resta di proprieta'
            # dell'utente reale, non di root.
            sudo cat "$k" > "$OUT_DIR/$(basename "$k")"
            echo "Copiata chiave: $k"
        fi
    done
fi

# Proprietario e permessi corretti per copiare la cartella liberamente
chown -R "$REAL_UID:$REAL_GID" "$OUT_DIR"
chmod 755 "$OUT_DIR"
find "$OUT_DIR" -type f -exec chmod 644 {} +

echo ""
echo "Fatto. Contenuto di $OUT_DIR:"
ls -l "$OUT_DIR"
echo ""
echo "Ora copia l'intera cartella dello script (compresa 'mxrepo') sulla Debian"
echo "ed esegui li' lo script registra-mxrepo.sh."
