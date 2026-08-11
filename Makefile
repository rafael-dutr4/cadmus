MODEL := models/ggml-small.en.bin
MODEL_URL := https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
APP := Cadmus.app

AGENT := br.dutra.cadmus
PLIST := $(HOME)/Library/LaunchAgents/$(AGENT).plist

.PHONY: build app run start stop install uninstall model fmt clean

build:
	swift build -c release

# Two spaces, and the rest of the house style. Configured in .swift-format.
fmt:
	swift format -i -r -p Sources Package.swift

# macOS grants the microphone and the right to post keystrokes per binary path,
# so the bundle is built in place and stays there. Moving it asks for both
# permissions again.
app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp .build/release/Cadmus $(APP)/Contents/MacOS/Cadmus
	# Ad hoc signature. Unsigned, the permissions are re-asked on every build.
	codesign --force --sign - --identifier br.dutra.cadmus $(APP)

# Tied to this terminal, so the log is visible and Ctrl+C stops it. This is the
# one to use while working on Cadmus.
run: app
	./$(APP)/Contents/MacOS/Cadmus

# Detached, for actually using it. Closing the terminal does not stop it.
start: app
	open $(APP)

stop:
	pkill -f "$(APP)/Contents/MacOS/Cadmus" || true

# Starts Cadmus at login. There is no KeepAlive on purpose: Quit in the menu
# means quit, not restart in a second.
install: app
	@printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0">' \
	  '<dict>' \
	  '	<key>Label</key><string>$(AGENT)</string>' \
	  '	<key>ProgramArguments</key>' \
	  '	<array><string>$(CURDIR)/$(APP)/Contents/MacOS/Cadmus</string></array>' \
	  '	<key>RunAtLoad</key><true/>' \
	  '	<key>ProcessType</key><string>Interactive</string>' \
	  '</dict>' \
	  '</plist>' > $(PLIST)
	launchctl bootout gui/$(shell id -u)/$(AGENT) 2>/dev/null || true
	launchctl bootstrap gui/$(shell id -u) $(PLIST)
	@echo "Cadmus starts at login. Undo with: make uninstall"

uninstall:
	launchctl bootout gui/$(shell id -u)/$(AGENT) 2>/dev/null || true
	rm -f $(PLIST)

model: $(MODEL)

$(MODEL):
	mkdir -p models
	curl -L -o $(MODEL) $(MODEL_URL)

clean:
	rm -rf .build $(APP)
