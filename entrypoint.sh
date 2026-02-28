#!/bin/bash
set -e

# Ensure /data is owned by openclaw user and has restricted permissions
chown openclaw:openclaw /data 2>/dev/null || true
chmod 700 /data 2>/dev/null || true

# Persist Homebrew to Railway volume so it survives container rebuilds
BREW_VOLUME="/data/.linuxbrew"
BREW_SYSTEM="/home/openclaw/.linuxbrew"

if [ -d "$BREW_VOLUME" ]; then
  if [ ! -L "$BREW_SYSTEM" ]; then
    rm -rf "$BREW_SYSTEM"
    ln -sf "$BREW_VOLUME" "$BREW_SYSTEM"
    echo "[entrypoint] Restored Homebrew from volume symlink"
  fi
else
  if [ -d "$BREW_SYSTEM" ] && [ ! -L "$BREW_SYSTEM" ]; then
    mv "$BREW_SYSTEM" "$BREW_VOLUME"
    ln -sf "$BREW_VOLUME" "$BREW_SYSTEM"
    echo "[entrypoint] Persisted Homebrew to volume on first boot"
  fi
fi

# ── Bobby customizations ──────────────────────────────────────
# Start cron daemon (installed in Dockerfile, used for scheduled tasks)
service cron start 2>/dev/null || cron 2>/dev/null
echo "[entrypoint] cron started"

# Restore gog binary (Google API CLI) if persisted on volume
if [ -f /data/.gog/gog_binary ]; then
  cp /data/.gog/gog_binary /usr/local/bin/gog
  chmod +x /usr/local/bin/gog
  echo "[entrypoint] gog restored"
fi

# Restore goplaces binary
if [ -f /data/.gog/goplaces ]; then
  cp /data/.gog/goplaces /usr/local/bin/goplaces
  chmod +x /usr/local/bin/goplaces
  echo "[entrypoint] goplaces restored"
fi

# Set up config symlinks for openclaw user
OHOME="/home/openclaw"
mkdir -p "$OHOME/.config/gogcli" "$OHOME/.config/notion" "$OHOME/.config/vodoo"
[ -d /data/.gog/gogcli ] && ln -sf /data/.gog/gogcli "$OHOME/.config/gogcli" 2>/dev/null
[ -f /data/.notion/api_key ] && ln -sf /data/.notion/api_key "$OHOME/.config/notion/api_key" 2>/dev/null
chown -R openclaw:openclaw "$OHOME/.config"

# Run Bobby's startup script if it exists (sets up crontab, gmail watcher, etc.)
if [ -f /data/scripts/startup.sh ]; then
  echo "[entrypoint] Running Bobby startup script..."
  bash /data/scripts/startup.sh 2>&1 | sed 's/^/  [startup] /'
fi
# ── End Bobby customizations ─────────────────────────────────

exec gosu openclaw node src/server.js
