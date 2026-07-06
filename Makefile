APP = ClaudeMeter
DIST = dist/$(APP).app

.PHONY: build test bundle run clean

build:
	swift build -c release

test:
	swift test

# Empaqueta el binario como .app firmada ad-hoc (sin App Store, sin notarización).
bundle: build
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS
	cp .build/release/$(APP) $(DIST)/Contents/MacOS/
	cp Resources/Info.plist $(DIST)/Contents/
	codesign --force --sign - $(DIST)
	@echo "Listo: $(DIST) — movela a /Applications si querés."

run: bundle
	open $(DIST)

clean:
	swift package clean
	rm -rf dist
