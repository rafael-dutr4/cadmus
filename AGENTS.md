# AGENTS.md

Kadmos is a dictation tool for macOS. I press a hotkey, I speak, and the words
appear where the cursor already is.

## The rule
Kadmos never presses Enter. It writes the text and stops.

A wrong transcription has to cost a keystroke, not an agent acting on a sentence
I did not say. This also keeps Kadmos from knowing what is in front of it: it is
a keyboard, not an agent, which is why it works the same in a terminal, in
Obsidian and in a browser field. Do not add anything that submits, sends or
interprets the text.

## Layout
```text
Sources/Kadmos/main.swift        menu bar, hotkey, the cycle
Sources/Kadmos/Recorder.swift    microphone to 16 kHz mono float, in memory
Sources/Kadmos/Transcriber.swift whisper.cpp
Sources/Kadmos/Typist.swift      putting text into the focused application
Sources/Kadmos/Hotkey.swift      the system wide hotkey
Sources/CWhisper/               the module map over whisper.h
```

## Build
```bash
make app     # builds and bundles into Kadmos.app
make run     # builds, bundles and runs
make model   # downloads the model into models/
make fmt     # swift-format, two space indentation
```

`whisper.cpp` comes from Homebrew (`brew install whisper-cpp`) and the module map
points at `/opt/homebrew/include/whisper.h`. The library is not vendored.

The bundle is built in place and stays at the same path. macOS grants the
microphone and the right to post keystrokes per binary path, so moving it means
granting both again.

## Conventions
- Swift, and the OS APIs directly. No dependencies beyond whisper.cpp.
- Two spaces of indentation. Run `make fmt` before committing.
- Audio never touches the disk.
- Comments explain why a decision was made, not what the line does.
- Conventional Commits, and no `Co-Authored-By` trailer.

## Environment
- `KADMOS_INSERT`: `keystrokes` (default) or `paste`.
- `KADMOS_MODEL`: path to a different ggml model.
