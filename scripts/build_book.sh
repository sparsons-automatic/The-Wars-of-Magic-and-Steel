#!/usr/bin/env bash
# scripts/build_book.sh
# Build EPUB, PDF, and MOBI for any given book directory.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <book-directory> [epub|pdf|mobi|clean]" >&2
  echo "example: $0 book1-The-Wars-of-Magic-and-Steel" >&2
  exit 1
fi

BOOK_SUBDIR="$1"
ONLY="${2:-}"   # optional: epub | pdf | mobi | clean

# --- resolve paths ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOK_ROOT="$ROOT_DIR/$BOOK_SUBDIR"
BOOK_DIR="$BOOK_ROOT/book"
CHAPTERS_TXT="$BOOK_DIR/chapters.txt"
DIST_DIR="$BOOK_ROOT/dist"

mkdir -p "$DIST_DIR"

EPUB_OUT="$DIST_DIR/${BOOK_SUBDIR}.epub"
PDF_OUT="$DIST_DIR/${BOOK_SUBDIR}.pdf"
MOBI_OUT="$DIST_DIR/${BOOK_SUBDIR}.mobi"

META_YAML="$BOOK_DIR/metadata.yaml"
CSS_FILE="$BOOK_DIR/style.css"
COVER_IMG="$BOOK_DIR/cover.png"

# --- deps check ---
need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing dependency '$1'." >&2
    echo "install it via: sudo apt install -y $2" >&2
    exit 1
  fi
}
need pandoc pandoc
need xelatex texlive-xetex
need ebook-convert calibre

# --- mode handling ---
case "$ONLY" in
  ""|"epub"|"pdf"|"mobi"|"clean") : ;;
  *) echo "invalid mode: $ONLY" >&2; exit 2 ;;
esac

if [[ "$ONLY" == "clean" ]]; then
  rm -rf "$DIST_DIR"
  echo "cleaned $DIST_DIR"
  exit 0
fi

# --- chapter list ---
CHAPTERS=()

if [[ -f "$CHAPTERS_TXT" ]]; then
  # Read non-empty, non-comment lines
  mapfile -t RAW_CHAPS < <(grep -vE '^\s*(#|$)' "$CHAPTERS_TXT")

  for f in "${RAW_CHAPS[@]}"; do
    # Already absolute or relative to cwd?
    if [[ -f "$f" ]]; then
      CHAPTERS+=("$f")
    # Relative to the book root (where your chapter files live)
    elif [[ -f "$BOOK_ROOT/$f" ]]; then
      CHAPTERS+=("$BOOK_ROOT/$f")
    # Occasionally people place chapters in book/; support that too
    elif [[ -f "$BOOK_DIR/$f" ]]; then
      CHAPTERS+=("$BOOK_DIR/$f")
    else
      echo "warning: chapter entry not found: $f" >&2
    fi
  done
else
  # Fallback: pick up chapters by pattern under the book directory
  mapfile -t CHAPTERS < <(
    find "$BOOK_ROOT" -maxdepth 1 -type f \
      \( -iname 'chapter*.md' -o -iname 'chap*.md' \) \
      -printf '%p\n' | sort -V
  )
fi

if [[ "${#CHAPTERS[@]}" -eq 0 ]]; then
  echo "error: no chapters found/resolved" >&2
  exit 1
fi

echo "Building ${BOOK_SUBDIR} with chapters:"
printf ' - %s\n' "${CHAPTERS[@]}"


# --- meta/css opts ---
META_OPTS=()
[[ -f "$META_YAML" ]] && META_OPTS+=("--metadata-file=$META_YAML")
[[ -f "$CSS_FILE"   ]] && META_OPTS+=("--css=$CSS_FILE")
[[ -f "$COVER_IMG"  ]] && META_OPTS+=("--epub-cover-image=$COVER_IMG")

build_epub() {
  echo "==> EPUB"
  pandoc --from=gfm --to=epub3 \
    --toc --toc-depth=2 \
    --output="$EPUB_OUT" \
    "${META_OPTS[@]}" \
    "${CHAPTERS[@]}"
}

build_pdf() {
  echo "==> PDF"
  pandoc --from=gfm --pdf-engine=xelatex \
    -V geometry:margin=1in \
    -V mainfont="DejaVu Serif" \
    -V monofont="DejaVu Sans Mono" \
    --toc --toc-depth=2 \
    --output="$PDF_OUT" \
    "${CHAPTERS[@]}"
}

build_mobi() {
  echo "==> MOBI"
  [[ -f "$EPUB_OUT" ]] || build_epub
  ebook-convert "$EPUB_OUT" "$MOBI_OUT" --pretty-print
  echo "MOBI done."
}

case "$ONLY" in
  epub) build_epub ;;
  pdf)  build_pdf ;;
  mobi) build_mobi ;;
  "")   build_epub; build_pdf; build_mobi ;;
esac

echo "Artifacts in $DIST_DIR:"
ls -lh "$DIST_DIR"
