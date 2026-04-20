# Makefile for docs/paper/
#
# STATUS: dormant. The PDF/arxiv pipeline is intentionally inactive — the
# paper is maintained as markdown and read directly from the sections/
# directory. See README.md "Status" section.
#
# To activate this pipeline (e.g., if a downstream signal warrants a PDF
# preprint), install the tools listed below and run `make paper.pdf`.
#
# Prerequisites:
#   - pandoc 3.x          (https://pandoc.org/installing.html)
#   - typst   OR  pdflatex (https://typst.app/  or  https://miktex.org/)
#   - GNU make            (Git Bash on Windows ships an outdated make;
#                          use `winget install GnuWin32.Make` or similar)
#
# Verify with: `pandoc --version && typst --version && make --version`

SECTIONS  := $(sort $(wildcard sections/*.md))
METADATA  := metadata.yaml
BIBLIO    := refs.bib
OUT_DIR   := build
PAPER_MD  := $(OUT_DIR)/paper.md
PAPER_PDF := $(OUT_DIR)/paper.pdf
PAPER_TEX := $(OUT_DIR)/paper.tex

# Default engine. Swap to `pdflatex` when prepping for arxiv submission.
PDF_ENGINE := typst

.PHONY: all clean check-tools paper

all: paper

paper: $(PAPER_PDF)

# Concatenate sections into a single markdown file. This target works
# without pandoc/latex installed — useful if all you want is the
# combined-paper view as a single .md.
$(PAPER_MD): $(SECTIONS) | $(OUT_DIR)
	cat $(SECTIONS) > $(PAPER_MD)

# Render to PDF via pandoc + the configured PDF engine. Citations are
# resolved via pandoc-citeproc against refs.bib (entries that remain
# [CITATION-NEEDED] will render as raw text — fix in refs.bib before
# submission).
$(PAPER_PDF): $(PAPER_MD) $(METADATA) $(BIBLIO)
	pandoc $(METADATA) $(PAPER_MD) \
		--bibliography=$(BIBLIO) \
		--citeproc \
		--pdf-engine=$(PDF_ENGINE) \
		-o $(PAPER_PDF)

# Render to LaTeX without going to PDF — useful for arxiv submission
# (arxiv accepts .tex + .bib; they compile on their end).
$(PAPER_TEX): $(PAPER_MD) $(METADATA) $(BIBLIO)
	pandoc $(METADATA) $(PAPER_MD) \
		--bibliography=$(BIBLIO) \
		--citeproc \
		-o $(PAPER_TEX)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

check-tools:
	@command -v pandoc >/dev/null 2>&1 || { echo "FAIL: pandoc not installed"; exit 1; }
	@command -v $(PDF_ENGINE) >/dev/null 2>&1 || { echo "FAIL: $(PDF_ENGINE) not installed"; exit 1; }
	@echo "OK: pandoc + $(PDF_ENGINE) found"

clean:
	rm -rf $(OUT_DIR)
