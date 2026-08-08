#!/bin/bash
# esporta-tutti.sh
# Da eseguire su MX Linux come utente normale (non con sudo davanti).
# Lancia in sequenza tutti gli script esporta-*.sh presenti in questa
# stessa cartella (tranne se stesso); ognuno crea la propria
# sottocartella con repo + chiave, di proprieta' dell'utente reale.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$(basename "${BASH_SOURCE[0]}")"

echo "=== Avvio esportazione di tutti i repository ==="
echo ""

# Valida/cache le credenziali sudo una volta sola per tutti gli script
sudo -v

for script in "$SCRIPT_DIR"/esporta-*.sh; do
    [ -f "$script" ] || continue
    name="$(basename "$script")"
    [ "$name" = "$SELF" ] && continue

    echo "--- Eseguo: $name ---"
    bash "$script"
    echo ""
done

echo "=== Esportazione completata ==="
echo "Copia l'intera cartella dello script sulla Debian ed esegui li'"
echo "lo script registra-tutti.sh."
