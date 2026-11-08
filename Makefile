PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
RELEASE_BINARY := .build/release/monitorer

.PHONY: build test install uninstall clean

build:
	swift build -c release

test:
	swift test

install: build
	install -d "$(BINDIR)"
	install -m 755 "$(RELEASE_BINARY)" "$(BINDIR)/monitorer"

uninstall:
	rm -f "$(BINDIR)/monitorer"

clean:
	swift package clean
