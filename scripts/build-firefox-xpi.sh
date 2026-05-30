#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-"$ROOT_DIR/dist"}"
SRC_DIR="${FIREFOX_SRC_DIR:-"$DIST_DIR/firefox-src"}"
XPI_NAME="${XPI_NAME:-duplicate-tabs-closer-firefox.xpi}"
XPI_PATH="$DIST_DIR/$XPI_NAME"

log() {
  printf '==> %s\n' "$*"
}

require_file() {
  if [[ ! -f "$1" ]]; then
    printf 'Missing required file: %s\n' "$1" >&2
    exit 1
  fi
}

require_dir() {
  if [[ ! -d "$1" ]]; then
    printf 'Missing required directory: %s\n' "$1" >&2
    exit 1
  fi
}

cd "$ROOT_DIR"

if ! command -v zip >/dev/null 2>&1; then
  printf 'The zip command is required but was not found.\n' >&2
  exit 1
fi

first_party_files=(
  manifest.json
  background.js
  badge.js
  helper.js
  LICENSE
  messageListener.js
  options.js
  README.md
  tabsInfo.js
  urlUtils.js
  worker.js
)

required_dirs=(
  _locales
  images
  optionPage
  popup
  ext_lib
)

log "Checking required files"
for file in "${first_party_files[@]}"; do
  require_file "$file"
done

for dir in "${required_dirs[@]}"; do
  require_dir "$dir"
done

log "Preparing Firefox package source"
rm -rf "$SRC_DIR" "$XPI_PATH"
mkdir -p "$SRC_DIR"

cp "${first_party_files[@]}" "$SRC_DIR/"
cp -R "${required_dirs[@]}" "$SRC_DIR/"

# Bootstrap JavaScript is not needed if popup/options pages only use Bootstrap CSS.
# Keeping unused vendor JS causes AMO warnings because Bootstrap internally writes HTML.
if [[ -d "$SRC_DIR/ext_lib/bootstrap-5.3.3-dist/js" ]]; then
  if grep -R -q 'bootstrap-5\.3\.3-dist/js\|bootstrap\.bundle\|bootstrap\.min\.js' \
    "$SRC_DIR/popup" "$SRC_DIR/optionPage" 2>/dev/null; then
    log "Bootstrap JS is referenced by HTML; keeping it"
  else
    log "Removing unused Bootstrap JS"
    rm -rf "$SRC_DIR/ext_lib/bootstrap-5.3.3-dist/js"
  fi
fi

log "Validating package contents"
require_file "$SRC_DIR/manifest.json"
require_file "$SRC_DIR/background.js"
require_dir "$SRC_DIR/_locales"
require_dir "$SRC_DIR/images"
require_dir "$SRC_DIR/popup"
require_dir "$SRC_DIR/optionPage"

if [[ -d "$SRC_DIR/.git" || -d "$SRC_DIR/.github" || -d "$SRC_DIR/build" ]]; then
  printf 'Unexpected repository/build metadata was copied into %s\n' "$SRC_DIR" >&2
  exit 1
fi

if find "$SRC_DIR" \( -name manifest-c.json -o -name manifest-f.json \) -print -quit | grep -q .; then
  printf 'Unexpected alternate manifest was copied into %s\n' "$SRC_DIR" >&2
  exit 1
fi

if find "$SRC_DIR" -name .DS_Store -print -quit | grep -q .; then
  printf 'Unexpected .DS_Store file found in %s\n' "$SRC_DIR" >&2
  exit 1
fi

log "Building XPI"
(
  cd "$SRC_DIR"
  zip -r -q "$XPI_PATH" .
)

if [[ ! -s "$XPI_PATH" ]]; then
  printf 'XPI was not created: %s\n' "$XPI_PATH" >&2
  exit 1
fi

log "Created $XPI_PATH"
