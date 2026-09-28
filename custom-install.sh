#!/bin/bash
# Installa-Browser_v6_20260927-1532.sh by Daniele Lolli (UncleDan) feat. Claude AI - Release 6 - 2026-09-27 15:32:25

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run this script with root privileges (sudo)."
    echo "Usage: sudo $0 [OPTIONS]"
    exit 1
fi

# Declare associative arrays to store application properties
declare -A APP_NAMES
declare -A APP_SHORT_NAMES
declare -A APP_ARGS_SHORT
declare -A APP_ARGS_LONG
declare -A APP_URLS
declare -A APP_ICONS
declare -A APP_DESKTOPS
declare -A APP_INSTALL_CMDS   # per-app install logic, executed via eval
declare -A APP_ICON_CMDS      # per-app icon-download logic, executed via eval (empty = skip)

# Ogni blocco app è autonomo: per aggiungerne una nuova basta copiare un blocco
# e scrivere in APP_INSTALL_CMDS i comandi necessari (possono essere completamente
# diversi da un'app all'altra: tar.xz, .deb, script di terze parti, ecc.).
# Variabili disponibili dentro APP_INSTALL_CMDS: $URL $SHORT_NAME $NAME $TMP_DIR

# ==========================================
# 1. Mozilla Firefox (tarball .tar.xz)
# ==========================================
APP_KEY_FIREFOX="firefox"
APP_NAMES[$APP_KEY_FIREFOX]="Mozilla Firefox"
APP_SHORT_NAMES[$APP_KEY_FIREFOX]="firefox"
APP_ARGS_SHORT[$APP_KEY_FIREFOX]="-f"
APP_ARGS_LONG[$APP_KEY_FIREFOX]="--firefox"
APP_URLS[$APP_KEY_FIREFOX]="https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US"
APP_ICONS[$APP_KEY_FIREFOX]="https://upload.wikimedia.org/wikipedia/commons/a/a0/Firefox_logo%2C_2019.svg"
APP_DESKTOPS[$APP_KEY_FIREFOX]="[Desktop Entry]
Version=1.0
Name=Firefox (Official Binaries)
Comment=Browse the Web
Exec=/opt/firefox/firefox %u
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;"
APP_INSTALL_CMDS[$APP_KEY_FIREFOX]='
    wget -q --show-progress -O archive.tmp "$URL"
    rm -rf "/opt/$SHORT_NAME"
    mkdir -p "/opt/$SHORT_NAME"
    tar xf archive.tmp -C "/opt/$SHORT_NAME" --strip-components=1
'
APP_ICON_CMDS[$APP_KEY_FIREFOX]='
    wget -q -O "/opt/$SHORT_NAME/${SHORT_NAME}.svg" "$ICON_URL"
'

# ==========================================
# 2. Mozilla Thunderbird (tarball .tar.xz)
# ==========================================
APP_KEY_THUNDERBIRD="thunderbird"
APP_NAMES[$APP_KEY_THUNDERBIRD]="Mozilla Thunderbird"
APP_SHORT_NAMES[$APP_KEY_THUNDERBIRD]="thunderbird"
APP_ARGS_SHORT[$APP_KEY_THUNDERBIRD]="-t"
APP_ARGS_LONG[$APP_KEY_THUNDERBIRD]="--thunderbird"
APP_URLS[$APP_KEY_THUNDERBIRD]="https://download.mozilla.org/?product=thunderbird-latest-ssl&os=linux64&lang=en-US"
APP_ICONS[$APP_KEY_THUNDERBIRD]="https://upload.wikimedia.org/wikipedia/commons/e/e3/Thunderbird_Logo_2023.svg"
APP_DESKTOPS[$APP_KEY_THUNDERBIRD]="[Desktop Entry]
Version=1.0
Name=Thunderbird (Official Binaries)
Comment=Read your emails
Exec=/opt/thunderbird/thunderbird %u
Terminal=false
Type=Application
Categories=Network;Email;
MimeType=x-scheme-handler/mailto;"
APP_INSTALL_CMDS[$APP_KEY_THUNDERBIRD]='
    wget -q --show-progress -O archive.tmp "$URL"
    rm -rf "/opt/$SHORT_NAME"
    mkdir -p "/opt/$SHORT_NAME"
    tar xf archive.tmp -C "/opt/$SHORT_NAME" --strip-components=1
'
APP_ICON_CMDS[$APP_KEY_THUNDERBIRD]='
    wget -q -O "/opt/$SHORT_NAME/${SHORT_NAME}.svg" "$ICON_URL"
'

# ==========================================
# 3. Zen Browser (tarball .tar.xz)
# ==========================================
APP_KEY_ZEN="zen"
APP_NAMES[$APP_KEY_ZEN]="Zen Browser"
APP_SHORT_NAMES[$APP_KEY_ZEN]="zen"
APP_ARGS_SHORT[$APP_KEY_ZEN]="-z"
APP_ARGS_LONG[$APP_KEY_ZEN]="--zen"
APP_URLS[$APP_KEY_ZEN]="https://github.com/zen-browser/desktop/releases/latest/download/zen.linux-x86_64.tar.xz"
APP_ICONS[$APP_KEY_ZEN]="https://raw.githubusercontent.com/zen-browser/desktop/main/assets/zen-alpha.svg"
APP_DESKTOPS[$APP_KEY_ZEN]="[Desktop Entry]
Version=1.0
Name=Zen Browser
Comment=Experience tranquillity while browsing the web
Exec=/opt/zen/zen %u
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;"
APP_INSTALL_CMDS[$APP_KEY_ZEN]='
    wget -q --show-progress -O archive.tmp "$URL"
    rm -rf "/opt/$SHORT_NAME"
    mkdir -p "/opt/$SHORT_NAME"
    tar xf archive.tmp -C "/opt/$SHORT_NAME" --strip-components=1
'
APP_ICON_CMDS[$APP_KEY_ZEN]='
    wget -q -O "/opt/$SHORT_NAME/${SHORT_NAME}.svg" "$ICON_URL"
'

# ==========================================
# 4. Google Chrome (stable, pacchetto .deb)
# Il pacchetto .deb installa da solo binario, symlink in /usr/bin e voce di menu:
# per questo APP_ICONS/APP_DESKTOPS restano vuoti e i rispettivi passaggi
# vengono saltati automaticamente dalla logica modulare.
# ==========================================
APP_KEY_CHROME="chrome"
APP_NAMES[$APP_KEY_CHROME]="Google Chrome"
APP_SHORT_NAMES[$APP_KEY_CHROME]="google-chrome"
APP_ARGS_SHORT[$APP_KEY_CHROME]="-c"
APP_ARGS_LONG[$APP_KEY_CHROME]="--chrome"
APP_URLS[$APP_KEY_CHROME]="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
APP_ICONS[$APP_KEY_CHROME]=""
APP_DESKTOPS[$APP_KEY_CHROME]=""
APP_INSTALL_CMDS[$APP_KEY_CHROME]='
    wget -q --show-progress -O chrome.deb "$URL"
    apt-get update
    apt-get install -y ./chrome.deb
'
APP_ICON_CMDS[$APP_KEY_CHROME]=''

# ==========================================
# 5. TeamViewer (pacchetto .deb ufficiale)
# Anche qui il .deb crea da solo binario, symlink e voce di menu.
# ==========================================
APP_KEY_TEAMVIEWER="teamviewer"
APP_NAMES[$APP_KEY_TEAMVIEWER]="TeamViewer"
APP_SHORT_NAMES[$APP_KEY_TEAMVIEWER]="teamviewer"
APP_ARGS_SHORT[$APP_KEY_TEAMVIEWER]="-v"
APP_ARGS_LONG[$APP_KEY_TEAMVIEWER]="--teamviewer"
APP_URLS[$APP_KEY_TEAMVIEWER]="https://download.teamviewer.com/download/linux/teamviewer_amd64.deb"
APP_ICONS[$APP_KEY_TEAMVIEWER]=""
APP_DESKTOPS[$APP_KEY_TEAMVIEWER]=""
APP_INSTALL_CMDS[$APP_KEY_TEAMVIEWER]='
    wget -q --show-progress -O teamviewer.deb "$URL"
    apt-get update
    apt-get install -y ./teamviewer.deb
'
APP_ICON_CMDS[$APP_KEY_TEAMVIEWER]=''

# ==========================================
# 6. pCloud Drive (AppImage)
# ATTENZIONE: pCloud non pubblica un link "latest" fisso — ogni release ha
# un URL con codice hash diverso (vedi https://www.pcloud.com/release-notes/linux).
# Aggiorna APP_URLS[$APP_KEY_PCLOUD] con il link corrente prima di lanciare
# lo script; se lo lasci vuoto, l'installazione si ferma con un messaggio chiaro.
# ==========================================
APP_KEY_PCLOUD="pcloud"
APP_NAMES[$APP_KEY_PCLOUD]="pCloud Drive"
APP_SHORT_NAMES[$APP_KEY_PCLOUD]="pcloud"
APP_ARGS_SHORT[$APP_KEY_PCLOUD]="-p"
APP_ARGS_LONG[$APP_KEY_PCLOUD]="--pcloud"
APP_URLS[$APP_KEY_PCLOUD]=""   # <-- incolla qui il link diretto all'AppImage dell'ultima versione
APP_ICONS[$APP_KEY_PCLOUD]=""
APP_DESKTOPS[$APP_KEY_PCLOUD]="[Desktop Entry]
Version=1.0
Name=pCloud Drive
Comment=Cloud storage virtual drive
Exec=/opt/pcloud/pcloud
Terminal=false
Type=Application
Categories=Network;FileTransfer;"
APP_INSTALL_CMDS[$APP_KEY_PCLOUD]='
    if [ -z "$URL" ]; then
        echo "Errore: nessun URL impostato per pCloud."
        echo "pCloud non ha un link \"latest\" fisso: prendi il link diretto"
        echo "dalla riga Download piu recente su https://www.pcloud.com/release-notes/linux"
        echo "e incollalo in APP_URLS[pcloud] nello script."
        exit 1
    fi
    wget -q --show-progress -O "$SHORT_NAME" "$URL"
    chmod +x "$SHORT_NAME"
    mkdir -p "/opt/$SHORT_NAME"
    mv "$SHORT_NAME" "/opt/$SHORT_NAME/$SHORT_NAME"
'
APP_ICON_CMDS[$APP_KEY_PCLOUD]=''

# ==========================================
# ESEMPIO (disattivato): altra app via .deb, per mostrare che il blocco
# Chrome sopra non è un caso speciale ma il pattern normale da riusare.
# ==========================================
# APP_KEY_ESEMPIO="esempio"
# APP_NAMES[$APP_KEY_ESEMPIO]="Nome Applicazione"
# APP_SHORT_NAMES[$APP_KEY_ESEMPIO]="esempio"
# APP_ARGS_SHORT[$APP_KEY_ESEMPIO]="-e"
# APP_ARGS_LONG[$APP_KEY_ESEMPIO]="--esempio"
# APP_URLS[$APP_KEY_ESEMPIO]="https://example.com/pacchetto.deb"
# APP_ICONS[$APP_KEY_ESEMPIO]=""
# APP_DESKTOPS[$APP_KEY_ESEMPIO]=""
# APP_INSTALL_CMDS[$APP_KEY_ESEMPIO]='
#     wget -q -O pacchetto.deb "$URL"
#     apt-get install -y ./pacchetto.deb
# '
# APP_ICON_CMDS[$APP_KEY_ESEMPIO]=''   # vuoto = nessuna icona da scaricare, viene saltato

# ==========================================
# Functions
# ==========================================
show_help() {
    echo "Usage: sudo $0 [OPTIONS]"
    echo ""
    echo "Available options:"
    echo "  -h, --help       Show this help message and exit"
    for key in "${!APP_NAMES[@]}"; do
        printf "  %-4s %-15s %s\n" "${APP_ARGS_SHORT[$key]}," "${APP_ARGS_LONG[$key]}" "Install ${APP_NAMES[$key]}"
    done
    echo ""
    echo "Example:"
    echo "  sudo $0 -f -z -c -v -p   # Installs Firefox, Zen, Chrome, TeamViewer and pCloud"
}

install_app() {
    local APP_ID="$1"
    local NAME="${APP_NAMES[$APP_ID]}"
    local SHORT_NAME="${APP_SHORT_NAMES[$APP_ID]}"
    local URL="${APP_URLS[$APP_ID]}"
    local ICON_URL="${APP_ICONS[$APP_ID]}"
    local DESKTOP_CONTENT="${APP_DESKTOPS[$APP_ID]}"
    local INSTALL_CMDS="${APP_INSTALL_CMDS[$APP_ID]}"
    local ICON_CMDS="${APP_ICON_CMDS[$APP_ID]}"

    echo "--- Starting installation of $NAME ---"

    local TMP_DIR
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR" || exit 1

    echo "[1/4] Running install commands..."
    if [ -n "$INSTALL_CMDS" ]; then
        eval "$INSTALL_CMDS"
    else
        echo "Warning: no install commands defined for '$APP_ID'. Skipping."
    fi

    if [ -n "$ICON_CMDS" ]; then
        echo "[2/4] Running icon-download commands..."
        eval "$ICON_CMDS"
    else
        echo "[2/4] No icon commands defined. Skipping."
    fi

    if [ -n "$DESKTOP_CONTENT" ]; then
        echo "[3/4] Creating desktop entry..."
        echo "$DESKTOP_CONTENT" > "/usr/share/applications/${SHORT_NAME}.desktop"
        if [ -n "$ICON_URL" ]; then
            echo "Icon=/opt/$SHORT_NAME/${SHORT_NAME}.svg" >> "/usr/share/applications/${SHORT_NAME}.desktop"
        fi
    else
        echo "[3/4] No desktop entry template defined. Skipping."
    fi

    # Crea il symlink solo se il binario risultante esiste davvero in quel percorso
    # (non tutte le modalità di installazione, es. .deb via apt, lo prevedono)
    if [ -x "/opt/$SHORT_NAME/$SHORT_NAME" ]; then
        echo "[4/4] Creating symbolic link in /usr/local/bin/..."
        ln -sf "/opt/$SHORT_NAME/$SHORT_NAME" "/usr/local/bin/$SHORT_NAME"
    else
        echo "[4/4] No binary found at /opt/$SHORT_NAME/$SHORT_NAME. Skipping symlink."
    fi

    echo "Cleaning up temporary files..."
    cd /
    rm -rf "$TMP_DIR"

    echo "--- Installation of $NAME completed successfully! ---"
    echo ""
}

# ==========================================
# Main Execution Logic
# ==========================================
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

for arg in "$@"; do
    case $arg in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            MATCHED=""
            for key in "${!APP_NAMES[@]}"; do
                if [ "$arg" = "${APP_ARGS_SHORT[$key]}" ] || [ "$arg" = "${APP_ARGS_LONG[$key]}" ]; then
                    install_app "$key"
                    MATCHED="1"
                    break
                fi
            done
            if [ -z "$MATCHED" ]; then
                echo "Error: Unknown parameter '$arg'"
                echo "Run 'sudo $0 --help' for usage instructions."
                exit 1
            fi
            ;;
    esac
done
