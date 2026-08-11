MODEL := models/ggml-small.en.bin
MODEL_URL := https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
APP := Cadmus.app

.PHONY: build app run model fmt clean

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

run: app
	./$(APP)/Contents/MacOS/Cadmus

model: $(MODEL)

$(MODEL):
	mkdir -p models
	curl -L -o $(MODEL) $(MODEL_URL)

clean:
	rm -rf .build $(APP)
