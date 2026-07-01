#!/usr/bin/env bash
# AIR26 offline provisioning — shared shell helpers. Sourced by download.sh and verify.sh.

# --- paths -------------------------------------------------------------------
# Cache folder that gets distributed by pendrive. Override: AIR26_CACHE=/path ...
: "${AIR26_CACHE:=$HOME/air26-offline}"
# Repo root (this file lives in <repo>/scripts/)
SUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="$SUP_DIR/manifest"

# --- logging -----------------------------------------------------------------
_c() { tput setaf "$1" 2>/dev/null || true; }
_r() { tput sgr0 2>/dev/null || true; }
log()   { echo "$(_c 6)[air26]$(_r) $*"; }
ok()    { echo "$(_c 2)  ok$(_r)   $*"; }
warn()  { echo "$(_c 3)  warn$(_r) $*" >&2; }
err()   { echo "$(_c 1)  ERR$(_r)  $*" >&2; }
die()   { err "$*"; exit 1; }
hdr()   { echo; echo "$(_c 4)==== $* ====$(_r)"; }

# --- small utilities ---------------------------------------------------------
have()  { command -v "$1" >/dev/null 2>&1; }
need()  { have "$1" || die "required command not found: $1"; }

# read a manifest file, stripping comments/blanks
manifest() { sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$MANIFEST_DIR/$1"; }

# sha256 of a single file
sha_of() { sha256sum "$1" | awk '{print $1}'; }

# count files under a dir matching a glob (0 if dir missing)
count() { local d="$1" pat="$2"; [ -d "$d" ] || { echo 0; return; }; find "$d" -type f -name "$pat" | wc -l; }
