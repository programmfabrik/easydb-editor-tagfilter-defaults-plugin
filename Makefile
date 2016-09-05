PLUGIN_NAME = editor-tagfilter-defaults
INSTALL_FILES = \
	$(WEB)/l10n/cultures.json \
	$(WEB)/l10n/de-DE.json \
	$(WEB)/l10n/en-US.json \
	$(WEB)/l10n/es-ES.json \
	$(WEB)/l10n/it-IT.json \
	$(WEB)/editor-tagfilter-defaults.js \
	easydb-editor-tagfilter-defaults.config.yml

L10N_FILES = l10n/editor-tagfilter-defaults.csv

COFFEE_FILES = \
	src/webfrontend/EditorTagfilterDefaults.coffee

all: build

include ./base-plugins.make

build: code

code: $(JS) $(L10N)

clean: clean-base

wipe: wipe-base