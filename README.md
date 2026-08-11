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

Ctrl+Option+D starts recording, the same keys stop it.

Text appears as you speak, one phrase at a time. The cut is a pause, not a
clock: a phrase is typed once you stop saying it, so nothing ever has to be
taken back out of a window it was already typed into.

The machine goes quiet while Cadmus listens, and gets its sound back when you
stop. This is Bluetooth, not politeness: opening the microphone drags a headset
into the hands free profile, and anything still playing through it comes out
broken. Cadmus pauses what is playing and mutes the output device, then puts
both back exactly as they were.

Watch the menu bar: `◌` the microphone is opening, `●` it is listening, `…`
Cadmus is catching up on what you already said, `○` idle. Wait for `●` before
talking, because on a headset the profile has to change first and anything said
before it is gone.

## Environment
- `CADMUS_INSERT`: `keystrokes` (default) or `paste`.
- `CADMUS_MODEL`: path to a different ggml model.
- `CADMUS_VOICE_FLOOR`: loudness under which audio is not speech, `0.012` by
  default. Raise it if a quiet room ends phrases late, lower it if Cadmus cuts
  you off mid sentence.
