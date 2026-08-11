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

Text appears as you speak, one phrase at a time. The cut is a pause, not a
clock: a phrase is typed once you stop saying it, so nothing ever has to be
taken back out of a window it was already typed into.

If something is playing when you start recording, Cadmus pauses it and starts it
again when you stop. This is not politeness, it is Bluetooth: a headset cannot
carry good audio out and a microphone in at the same time, so while music plays
it has no microphone at all. Only what Cadmus paused is ever resumed.

The sound you hear is the microphone becoming live, which on a Bluetooth headset
is a moment after the hotkey. Wait for it before talking.

## Environment
- `CADMUS_INSERT`: `keystrokes` (default) or `paste`.
- `CADMUS_MODEL`: path to a different ggml model.
- `CADMUS_VOICE_FLOOR`: loudness under which audio is not speech, `0.012` by
  default. Raise it if a quiet room ends phrases late, lower it if Cadmus cuts
  you off mid sentence.
