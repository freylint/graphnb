# GraphNB project Makefile
.PHONY: all clean
.ONESHELL:

all: README.md dist/index.html

README.md: notebook.ipynb
	python3 -m nbconvert --to markdown --output README \
		--MarkdownExporter.exclude_input=True \
		--MarkdownExporter.exclude_output=True \
		--TagRemovePreprocessor.enabled=True \
		--TagRemovePreprocessor.remove_cell_tags hide-on-readme \
		notebook.ipynb

build/notebook.html: notebook.ipynb | build
	python3 -m nbconvert --to html --output build/notebook \
		--HTMLExporter.exclude_input=True \
		--TagRemovePreprocessor.enabled=True \
		--template basic \
		notebook.ipynb

build/index.html: build/notebook.html | build
	# Copy the template html to the build directory
	cp public/layout.html build/index.html

	# Embed the stylesheet and notebook into the page
	python3 - <<'PY'
	from pathlib import Path

	index_path = Path('build/index.html')
	style_path = Path('public/style.css')
	notebook_path = Path('build/notebook.html')

	page = index_path.read_text()
	style = style_path.read_text().rstrip()
	notebook = notebook_path.read_text()

	page = page.replace('<!-- NBSTYLE ---->', f'<style>\n{style}\n</style>')
	page = page.replace('<!-- NBNOTEBOOK -->', notebook)
	index_path.write_text(page)
	PY

	# Minify only the build/index.html output
	npx html-minifier --collapse-whitespace --remove-comments --remove-optional-tags \
		--minify-css true --minify-js true \
		build/index.html -o build/index.html

dist/index.html: build/index.html | dist
	cp build/index.html dist/index.html

dist:
	mkdir -p dist

build:
	mkdir -p build

clean:
	rm -f build dist
