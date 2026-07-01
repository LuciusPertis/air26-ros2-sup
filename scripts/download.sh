#!/usr/bin/env bash
# AIR26 offline provisioning — DOWNLOADER (run on a connected "staging" machine).
#
# Fills $AIR26_CACHE (default ~/air26-offline) with every heavy workshop artifact, then
# writes MANIFEST.sha256 + VERSIONS.txt. Copy that folder to a pendrive afterwards.
#
# Usage:
#   scripts/download.sh                 # all steps
#   scripts/download.sh apt pip-system  # only the named steps
#   AIR26_CACHE=/mnt/usb/air26-offline scripts/download.sh
#
# Steps: apt webots ollama pip-system pip-vla hf manifest
#
# Platform: run on Ubuntu 22.04 / amd64 / Python 3.10 with the ROS 2 Humble apt repo already
# configured (the apt step needs the ros2.list source to see ros-humble-* packages).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WEBOTS_VER="R2025a"
WEBOTS_DEB="webots_2025a_amd64.deb"
OLLAMA_VER="v0.30.11"
TORCH_CPU_INDEX="https://download.pytorch.org/whl/cpu"

STEPS=("$@"); [ ${#STEPS[@]} -eq 0 ] && STEPS=(apt webots ollama pip-system pip-vla hf manifest)
want() { for s in "${STEPS[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

mkdir -p "$AIR26_CACHE"
log "cache folder: $AIR26_CACHE"

# ---------------------------------------------------------------------------
step_apt() {
  hdr "apt: download .debs + transitive deps -> local repo"
  need apt-get
  have dpkg-scanpackages || die "dpkg-scanpackages not found — run: sudo apt-get install dpkg-dev"
  local out="$AIR26_CACHE/apt"; mkdir -p "$out"
  # Resolve the full recursive dependency closure of every top-level package, even ones already
  # installed on this box, then apt-get download the lot.
  local tops; mapfile -t tops < <(manifest apt-packages.txt)
  log "resolving deps for ${#tops[@]} top-level packages (this is the fragile bit)..."
  local deps
  deps=$(apt-cache depends --recurse --no-recommends --no-suggests \
              --no-conflicts --no-breaks --no-replaces --no-enhances --no-pre-depends \
              "${tops[@]}" 2>/dev/null \
         | grep '^\w' | sort -u)
  log "downloading $(echo "$deps" | wc -l) packages into $out ..."
  ( cd "$out" && apt-get download $deps 2>&1 | grep -vi 'Skipping' || true )
  log "building Packages.gz ..."
  ( cd "$out" && dpkg-scanpackages -m . /dev/null 2>/dev/null | gzip -9c > Packages.gz )
  ok "apt: $(count "$out" '*.deb') .debs + Packages.gz"
  warn "if a target later reports an unmet dep, this box was missing a source repo — re-run the"
  warn "apt step on a clean Ubuntu 22.04 box that has ONLY the ROS apt repo configured."
}

step_webots() {
  hdr "webots: $WEBOTS_DEB"
  need wget; local out="$AIR26_CACHE/webots"; mkdir -p "$out"
  local url="https://github.com/cyberbotics/webots/releases/download/$WEBOTS_VER/$WEBOTS_DEB"
  wget -c -O "$out/$WEBOTS_DEB" "$url"
  ok "webots: $(du -h "$out/$WEBOTS_DEB" | cut -f1)"
}

step_ollama() {
  hdr "ollama: binary tarball + models + systemd unit"
  need wget; need curl; local out="$AIR26_CACHE/ollama"; mkdir -p "$out/models"
  local tgz="ollama-linux-amd64.tgz"
  wget -c -O "$out/ollama-linux-amd64-$OLLAMA_VER.tgz" \
       "https://github.com/ollama/ollama/releases/download/$OLLAMA_VER/$tgz"
  # systemd unit (mirrors what the official install.sh writes; OLLAMA_MODELS set on target)
  cat > "$out/ollama.service" <<'UNIT'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="OLLAMA_MODELS=/usr/share/ollama/.ollama/models"

[Install]
WantedBy=multi-user.target
UNIT
  # Pull models into the cache. Needs a runnable ollama; use the just-downloaded binary.
  local tmp; tmp=$(mktemp -d); tar -xzf "$out/ollama-linux-amd64-$OLLAMA_VER.tgz" -C "$tmp"
  local bin; bin=$(find "$tmp" -name ollama -type f | head -1)
  if [ -n "$bin" ]; then
    OLLAMA_MODELS="$out/models" "$bin" serve >/dev/null 2>&1 &
    local pid=$!; sleep 4
    while read -r m; do
      log "ollama pull $m"
      OLLAMA_MODELS="$out/models" OLLAMA_HOST=127.0.0.1:11434 "$bin" pull "$m"
    done < <(manifest ollama-models.txt)
    kill "$pid" 2>/dev/null || true
  else
    warn "could not extract ollama binary; pull models manually into $out/models"
  fi
  rm -rf "$tmp"
  ok "ollama: tgz + $(du -sh "$out/models" 2>/dev/null | cut -f1) models"
}

step_pip_system() {
  hdr "pip: system wheelhouse (py3.10)"
  need pip3; local out="$AIR26_CACHE/pip/system"; mkdir -p "$out"
  pip3 download -d "$out" -r "$MANIFEST_DIR/pip-system.txt"
  ok "pip-system: $(count "$out" '*') files"
}

step_pip_vla() {
  hdr "pip: SmolVLA venv wheelhouse (py3.10, torch CPU)"
  need pip3; local out="$AIR26_CACHE/pip/vla-venv"; mkdir -p "$out"
  pip3 download -d "$out" --extra-index-url "$TORCH_CPU_INDEX" -r "$MANIFEST_DIR/pip-vla-venv.txt"
  ok "pip-vla: $(count "$out" '*') files"
}

step_hf() {
  hdr "hf: SmolVLA policy + VLM backbone -> HF cache"
  local out="$AIR26_CACHE/hf"; mkdir -p "$out"
  local venv="/home/lsp/vla_venv"
  if [ -x "$venv/bin/python" ]; then
    log "using $venv to load the policy once (auto-pulls backbone)"
    HF_HOME="$out" "$venv/bin/python" - <<'PY'
from lerobot.policies.smolvla.modeling_smolvla import SmolVLAPolicy
SmolVLAPolicy.from_pretrained("lerobot/smolvla_base")
print("policy + backbone cached")
PY
  elif have huggingface-cli; then
    warn "no venv; falling back to direct snapshot (backbone fetched on first online load)"
    while read -r repo; do
      HF_HOME="$out" huggingface-cli download "$repo"
    done < <(manifest hf-models.txt)
  else
    die "need either $venv or huggingface-cli to capture HF models"
  fi
  ok "hf: $(du -sh "$out" 2>/dev/null | cut -f1)"
}

step_manifest() {
  hdr "manifest: checksums + versions"
  ( cd "$AIR26_CACHE" && find . -type f ! -name MANIFEST.sha256 -print0 \
      | sort -z | xargs -0 sha256sum > MANIFEST.sha256 )
  {
    echo "AIR26 offline cache — generated $(date -u +%FT%TZ)"
    echo "host: $(uname -srm)  python: $(python3 --version 2>&1)"
    echo "webots: $WEBOTS_VER   ollama: $OLLAMA_VER"
    echo "apt top-level: $(manifest apt-packages.txt | tr '\n' ' ')"
  } > "$AIR26_CACHE/VERSIONS.txt"
  ok "wrote MANIFEST.sha256 ($(wc -l < "$AIR26_CACHE/MANIFEST.sha256") files) + VERSIONS.txt"
}

for s in "${STEPS[@]}"; do
  case "$s" in
    apt) step_apt ;; webots) step_webots ;; ollama) step_ollama ;;
    pip-system) step_pip_system ;; pip-vla) step_pip_vla ;; hf) step_hf ;;
    manifest) step_manifest ;;
    *) die "unknown step: $s (valid: apt webots ollama pip-system pip-vla hf manifest)" ;;
  esac
done

log "done. total: $(du -sh "$AIR26_CACHE" 2>/dev/null | cut -f1) in $AIR26_CACHE"
log "next: scripts/verify.sh   then copy $AIR26_CACHE to an exFAT pendrive"
