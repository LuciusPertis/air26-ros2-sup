#!/usr/bin/env bash
# AIR26 offline provisioning — VERIFIER.
#
# Checks the DOWNLOADED files in $AIR26_CACHE for integrity + completeness.
# It does NOT install anything and does NOT touch the system — safe to run anywhere
# (including on a target box straight off the pendrive, before installing).
#
# Usage:
#   scripts/verify.sh                                  # verify ~/air26-offline
#   AIR26_CACHE=/mnt/usb/air26-offline scripts/verify.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAIL=0
bad() { err "$*"; FAIL=$((FAIL+1)); }

[ -d "$AIR26_CACHE" ] || die "cache folder not found: $AIR26_CACHE"
log "verifying $AIR26_CACHE"

# --- 1. checksums (the authoritative integrity check) -----------------------
hdr "checksums"
if [ -f "$AIR26_CACHE/MANIFEST.sha256" ]; then
  if ( cd "$AIR26_CACHE" && sha256sum -c --quiet MANIFEST.sha256 ); then
    ok "all $(wc -l < "$AIR26_CACHE/MANIFEST.sha256") files match MANIFEST.sha256"
  else
    bad "one or more files failed sha256 check (corrupt/incomplete copy?)"
  fi
else
  bad "MANIFEST.sha256 missing — run download.sh 'manifest' step on staging first"
fi

# --- 2. apt: .debs present, integrity, Packages.gz --------------------------
hdr "apt repo"
adir="$AIR26_CACHE/apt"
if [ -d "$adir" ]; then
  n=$(count "$adir" '*.deb')
  [ "$n" -gt 0 ] && ok "$n .deb files" || bad "no .deb files in $adir"
  [ -f "$adir/Packages.gz" ] && ok "Packages.gz present" || bad "Packages.gz missing (targets can't resolve deps offline)"
  broken=0
  while IFS= read -r deb; do dpkg-deb -I "$deb" >/dev/null 2>&1 || { bad "corrupt .deb: $deb"; broken=$((broken+1)); }; done \
       < <(find "$adir" -name '*.deb')
  [ "$broken" -eq 0 ] && ok "all .debs pass dpkg-deb integrity"
else bad "apt/ missing"; fi

# --- 3. webots deb ----------------------------------------------------------
hdr "webots"
wdeb=$(find "$AIR26_CACHE/webots" -name 'webots_*_amd64.deb' 2>/dev/null | head -1)
if [ -n "$wdeb" ]; then
  dpkg-deb -I "$wdeb" >/dev/null 2>&1 && ok "webots deb ok ($(du -h "$wdeb"|cut -f1))" || bad "webots deb corrupt"
else bad "webots deb missing"; fi

# --- 4. ollama: tarball intact, models manifests reference existing blobs ----
hdr "ollama"
odir="$AIR26_CACHE/ollama"
otgz=$(find "$odir" -name 'ollama-linux-amd64*.tgz' 2>/dev/null | head -1)
if [ -n "$otgz" ]; then tar -tzf "$otgz" >/dev/null 2>&1 && ok "ollama tarball ok" || bad "ollama tarball corrupt"
else bad "ollama tarball missing"; fi
[ -f "$odir/ollama.service" ] && ok "ollama.service unit present" || bad "ollama.service missing"
mdir="$odir/models/manifests"
if [ -d "$mdir" ]; then
  missing=0; nman=0
  while IFS= read -r man; do
    nman=$((nman+1))
    # each manifest lists blob digests as "sha256:xxxx"; blob file is blobs/sha256-xxxx
    while IFS= read -r dig; do
      bf="$odir/models/blobs/${dig/:/-}"
      [ -f "$bf" ] || { bad "ollama blob missing for $dig"; missing=$((missing+1)); }
    done < <(grep -o 'sha256:[0-9a-f]\{64\}' "$man" | sort -u)
  done < <(find "$mdir" -type f)
  [ "$missing" -eq 0 ] && ok "$nman model manifest(s), all blobs present" || bad "$missing blob(s) missing"
else bad "ollama models/manifests missing"; fi

# --- 5. pip wheelhouses -----------------------------------------------------
hdr "pip wheelhouses"
for w in system vla-venv; do
  d="$AIR26_CACHE/pip/$w"
  n=$(count "$d" '*')
  [ "$n" -gt 0 ] && ok "pip/$w: $n files" || bad "pip/$w: empty or missing"
done
# torch CPU wheel sanity (project 07)
if ls "$AIR26_CACHE"/pip/vla-venv/torch-* >/dev/null 2>&1; then
  ls "$AIR26_CACHE"/pip/vla-venv/torch-*cp310* >/dev/null 2>&1 \
    && ok "torch cp310 wheel present" || warn "torch wheel present but not cp310 — check python version"
else bad "no torch wheel in pip/vla-venv"; fi

# --- 6. hf snapshot completeness --------------------------------------------
hdr "hugging face"
hdir="$AIR26_CACHE/hf"
if [ -d "$hdir" ]; then
  if find "$hdir" -path '*smolvla_base*' -name 'config.json' | grep -q .; then ok "smolvla_base config present"; else bad "smolvla_base config.json not found"; fi
  nsafe=$(find "$hdir" -name '*.safetensors' | wc -l)
  [ "$nsafe" -gt 0 ] && ok "$nsafe .safetensors weight file(s)" || bad "no .safetensors weights (policy/backbone incomplete)"
else bad "hf/ missing"; fi

# --- summary ----------------------------------------------------------------
echo
if [ "$FAIL" -eq 0 ]; then
  log "$(_c 2)VERIFY PASSED$(_r) — cache is complete and intact. Safe to distribute."
else
  die "VERIFY FAILED with $FAIL problem(s) — see above. Re-run the relevant download.sh step."
fi
