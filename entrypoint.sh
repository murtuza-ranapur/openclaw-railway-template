#!/bin/bash
set -e

# ── Ensure critical env vars are set (safety net) ─────────────
# If Railway env vars are missing, force correct paths so OpenClaw
# never falls back to /home/openclaw/.openclaw (which triggers setup wizard)
export OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
export OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"

# Ensure /data and ALL subdirectories are owned by openclaw user
# (fixes legacy root-owned dirs: .secrets, .gog, scripts, cron, etc.)
chown -R openclaw:openclaw /data 2>/dev/null || true
chmod 700 /data 2>/dev/null || true
echo "[entrypoint] /data ownership fixed"

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
# (agent runs as openclaw, so configs go in /home/openclaw, NOT /root)
OHOME="/home/openclaw"
mkdir -p "$OHOME/.config"
[ -d /data/.gog/gogcli ] && rm -rf "$OHOME/.config/gogcli" && ln -sf /data/.gog/gogcli "$OHOME/.config/gogcli"
[ -f /data/.notion/api_key ] && mkdir -p "$OHOME/.config/notion" && ln -sf /data/.notion/api_key "$OHOME/.config/notion/api_key"
chown -R openclaw:openclaw "$OHOME/.config"

# Symlink /root/.config → /home/openclaw/.config so scripts referencing /root still work
# (startup.sh and other scripts may reference /root paths)
mkdir -p /root
ln -sf "$OHOME/.config" /root/.config 2>/dev/null || true

# Run Bobby's startup script if it exists (sets up crontab, gmail watcher, etc.)
if [ -f /data/scripts/startup.sh ]; then
  echo "[entrypoint] Running Bobby startup script..."
  bash /data/scripts/startup.sh 2>&1 | sed 's/^/  [startup] /'
fi
# ── End Bobby customizations ─────────────────────────────────

exec gosu openclaw node src/server.js
