# GraphNB project Makefile
.PHONY: all clean baseimg srvimg clientimg
.ONESHELL:

define extract-cell
python3 scripts/extract-cell.py "$(1)"
endef

define notebook-call
npx ts-node --transpile-only scripts/notebook-call.ts --eval-only 
endef

define notebook-call-fn
npx ts-node --transpile-only scripts/notebook-call.ts --call "$(1)"
endef

all: README.md dist/index.html hlimg

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

build/base:
	# TODO build base image

build/index.html: build/notebook.html
	# Copy the template html to the build directory
	cp public/layout.html build/index.html

	# Embed the stylesheet and notebook into the page
	python3 scripts/style-embed.py

	# Minify only the build/index.html output
	npx html-minifier --collapse-whitespace --remove-comments --remove-optional-tags \
		--minify-css true --minify-js true \
		build/index.html -o build/index.html

dist/index.html: build/index.html
	cp build/index.html dist/index.html


baseimg: notebook.ipynb
	$(call extract-cell,// Homelab BaseImage Generation script) \
	  | $(call notebook-call)

srvimg: baseimg
	$(call extract-cell,// Homelab Server Image Generation script) \
	  | $(call notebook-call)


clientimg: baseimg
	$(call extract-cell,// Homelab Client Image Generation script) \
	  | $(call notebook-call)

clean:
	rm -rf build dist
