#!/bin/bash
# registra-mxrepo.sh
# Da eseguire su Debian, dopo aver copiato accanto a questo script la
# cartella "mxrepo" prodotta da esporta-mxrepo.sh su MX Linux.
# Si autoeleva con sudo se non gia' lanciato come root.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Servono i permessi di root, rilancio con sudo..."
    exec sudo "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/mxrepo"

if [ ! -d "$SRC_DIR" ]; then
    echo "Cartella 'mxrepo' non trovata accanto a questo script."
    exit 1
fi

REPO_FILE="$SRC_DIR/mx.sources.list"
if [ ! -s "$REPO_FILE" ]; then
    echo "Nessun repository MX Linux da registrare (file mancante o vuoto in $SRC_DIR)."
    exit 0
fi

DEST_LIST="/etc/apt/sources.list.d/mx.list"

grep -v '^# --- da:' "$REPO_FILE" | grep -v '^\s*$' > "$DEST_LIST"
chown root:root "$DEST_LIST"
chmod 644 "$DEST_LIST"
echo "Repository scritti in: $DEST_LIST (root:root, 644)"

for k in "$SRC_DIR"/*; do
    [ -f "$k" ] || continue
    [ "$k" = "$REPO_FILE" ] && continue

    case "$k" in
        *.gpg)
            DEST="/etc/apt/trusted.gpg.d/$(basename "$k")"
            cp "$k" "$DEST"
            chown root:root "$DEST"
            chmod 644 "$DEST"
            echo "Chiave copiata: $(basename "$k") -> $DEST (root:root, 644)"
            ;;
        *.asc|*.key)
            mkdir -p /etc/apt/keyrings
            chown root:root /etc/apt/keyrings
            chmod 755 /etc/apt/keyrings
            DEST="/etc/apt/keyrings/$(basename "$k")"
            cp "$k" "$DEST"
            chown root:root "$DEST"
            chmod 644 "$DEST"
            echo "Chiave copiata: $(basename "$k") -> $DEST (root:root, 644)"
            ;;
        *)
            echo "File non riconosciuto, ignorato: $(basename "$k")"
            ;;
    esac
done

echo ""
echo "Aggiorno gli indici pacchetti (apt update)..."
apt update

echo ""
echo "Fatto. Verifica con: apt-cache policy | grep -i mx"
