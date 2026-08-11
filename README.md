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

Cadmus records from the built in microphone, whatever the default input is. A
Bluetooth headset has two profiles and only one of them has a microphone, so
opening it wrecks whatever is playing, and closing it hands the next recording a
device with no microphone at all. Never opening it avoids the whole thing, and
your headphones keep playing at full quality throughout.

The machine also goes quiet while Cadmus listens, and gets its sound back when
you stop. That is no longer needed to protect the audio, it is so that nothing
playing gets recorded along with you. `CADMUS_QUIET=0` turns it off.

Watch the menu bar: `◌` the microphone is opening, `●` it is listening, `…`
Cadmus is catching up on what you already said, `○` idle.

## Environment
- `CADMUS_INSERT`: `keystrokes` (default) or `paste`.
- `CADMUS_MODEL`: path to a different ggml model.
- `CADMUS_VOICE_FLOOR`: loudness under which audio is not speech, `0.012` by
  default. Raise it if a quiet room ends phrases late, lower it if Cadmus cuts
  you off mid sentence.
- `CADMUS_QUIET`: `0` to leave the machine's sound alone while recording.
