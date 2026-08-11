# Cadmus

Dictation for macOS. Press a hotkey, speak, and the words appear where the
cursor already is. The transcription runs on the machine, with
[whisper.cpp](https://github.com/ggml-org/whisper.cpp). Nothing is sent anywhere
and no audio is written to disk.

The name is Cadmus, who brought the alphabet to Greece.

## The rule
Cadmus never presses Enter. It writes the text and stops there. I read it, I fix
what came out wrong, and I send it.

That is what makes it a keyboard instead of an agent, and it is why it works the
same in a terminal, in an editor and in a browser field: it never has to know
what is in front of it.

## Requirements
- macOS on Apple Silicon.
- `brew install whisper-cpp`

## Running
```bash
make model   # downloads ggml-small.en (about 470MB) into models/
make start   # runs it, detached from the terminal
```

Cadmus has to be running for the hotkey to do anything, but it does not need a
terminal. `make run` keeps it in the foreground with its log visible, which is
the one to use while working on it. `make install` puts a launch agent in place
so it starts at login, and `make uninstall` removes it.

The first run asks for the microphone and for accessibility (the right to type
into other applications). Both are granted per binary path, so keep the bundle
where it is.

Ctrl+Option+D starts recording, the same keys stop it. The menu bar shows the
state: `○` idle, `●` recording, `…` transcribing.

## Environment
- `CADMUS_INSERT`: `keystrokes` (default) or `paste`.
- `CADMUS_MODEL`: path to a different ggml model.
