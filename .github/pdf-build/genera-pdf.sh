#!/usr/bin/env bash
#
# Genera i PDF dei documenti WildOut APS a partire dai file Markdown alla radice
# del repository. Output in pdf/.
#
# Uso:  bash .github/pdf-build/genera-pdf.sh
#
# Richiede: pandoc, xelatex, i pacchetti TeX elencati nel workflow
# .github/workflows/genera-pdf.yml
#
# L'elenco dei documenti è esplicito e non ricavato da un glob: README.md e
# CLAUDE.md non sono documenti associativi e non devono finire in PDF.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$ROOT/.github/pdf-build"
OUT="$ROOT/pdf"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# sorgente | destinazione | nome nel piè di pagina | indice | avviso di cortesia
DOCUMENTI=(
  "Statuto.md|Statuto.pdf|Statuto|si|si"
  "Atto_costitutivo.md|Atto_costitutivo.pdf|Atto costitutivo|no|si"
  "Codice_di_condotta.md|Codice_di_condotta.pdf|Codice di condotta|si|no"
  "Informativa_sul_trattamento_dei_dati.md|Informativa_sul_trattamento_dei_dati.pdf|Informativa sul trattamento dei dati|no|no"
  "Liberatoria_per_l_utilizzo_di_immagini_audio_e_video.md|Liberatoria_per_l_utilizzo_di_immagini_audio_e_video.pdf|Liberatoria immagini, audio e video|no|no"
)

mkdir -p "$OUT"

# I font TeX Gyre migliorano la resa ma non sono indispensabili: se fontconfig
# non li trova si usa il Latin Modern di XeLaTeX, sempre presente. Meglio un PDF
# con il font di ripiego che nessun PDF.
FONT_OPZIONI=()
if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -qi "TeX Gyre Termes"; then
  FONT_OPZIONI=(
    --variable "mainfont:TeX Gyre Termes"
    --variable "sansfont:TeX Gyre Heros"
    --variable "monofont:TeX Gyre Cursor"
  )
  echo "Font: TeX Gyre"
else
  echo "Font: TeX Gyre non disponibile, uso il default Latin Modern."
fi

falliti=0
generati=0

for riga in "${DOCUMENTI[@]}"; do
  IFS='|' read -r sorgente destinazione nome indice cortesia <<< "$riga"

  if [[ ! -f "$ROOT/$sorgente" ]]; then
    echo "::error::Documento non trovato: $sorgente"
    falliti=$((falliti + 1))
    continue
  fi

  # Il nome del documento finisce nel piè di pagina del preambolo.
  preambolo="$TMP/preambolo-${destinazione%.pdf}.tex"
  sed "s|@@DOCNAME@@|$nome|g" "$BUILD/preambolo.tex" > "$preambolo"

  opzioni=(
    --from "markdown+autolink_bare_uris"
    --pdf-engine xelatex
    --include-in-header "$preambolo"
    --variable "geometry:margin=2.4cm"
    --variable "fontsize:11pt"
    "${FONT_OPZIONI[@]}"
    --variable "linkcolor:black"
    --variable "urlcolor:black"
    --variable "lang:it"
    --variable "papersize:a4"
  )

  [[ "$indice" == "si" ]] && opzioni+=(--toc --toc-depth 2)
  [[ "$cortesia" == "si" ]] && opzioni+=(--include-before-body "$BUILD/avviso-cortesia.tex")

  echo "→ $sorgente"
  registro="$TMP/pandoc-${destinazione%.pdf}.log"

  if pandoc --verbose "${opzioni[@]}" "$ROOT/$sorgente" -o "$OUT/$destinazione" \
       > "$registro" 2>&1; then
    generati=$((generati + 1))
  else
    falliti=$((falliti + 1))
    echo "::error::Generazione fallita per $sorgente"

    echo "===== output completo di pandoc/xelatex per $sorgente ====="
    cat "$registro"
    echo "==========================================================="

    # Le righe che contano finiscono anche fra le annotazioni del run, così
    # sono leggibili senza dover aprire il log completo.
    grep -iE '^!|^l\.[0-9]|not found|undefined control sequence|emergency stop|fatal|error' \
      "$registro" | head -n 12 | while IFS= read -r r; do
        [ -n "$r" ] && echo "::error::[$(basename "$sorgente")] $r"
      done
  fi
done

echo
echo "PDF generati: $generati — falliti: $falliti"

if (( falliti > 0 )); then
  exit 1
fi

# Un PDF di poche centinaia di byte è quasi certamente un output vuoto o troncato.
for riga in "${DOCUMENTI[@]}"; do
  IFS='|' read -r _ destinazione _ _ _ <<< "$riga"
  dimensione=$(wc -c < "$OUT/$destinazione")
  if (( dimensione < 5000 )); then
    echo "::error::$destinazione pesa solo $dimensione byte: output sospetto."
    exit 1
  fi
  printf '%-56s %s byte\n' "$destinazione" "$dimensione"
done
