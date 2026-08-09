#!/bin/bash
# registra-tutti.sh
# Da eseguire su Debian. Si autoeleva con sudo se non gia' lanciato
# come root, poi lancia in sequenza tutti gli script registra-*.sh
# presenti in questa stessa cartella (tranne se stesso). Ognuno legge
# la propria sottocartella (mxrepo, chromerepo, teamviewerrepo, ...)
# copiata insieme agli script e installa i file con proprietario
# root:root e permessi 644.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Servono i permessi di root, rilancio con sudo..."
    exec sudo "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(basename "${BASH_SOURCE[0]}")"

echo "=== Avvio registrazione di tutti i repository ==="
echo ""

for script in "$SCRIPT_DIR"/registra-*.sh; do
    [ -f "$script" ] || continue
    name="$(basename "$script")"
    [ "$name" = "$SELF" ] && continue

    echo "--- Eseguo: $name ---"
    bash "$script" || echo "ATTENZIONE: $name ha restituito un errore, proseguo con gli altri."
    echo ""
done

echo "=== Registrazione completata ==="
