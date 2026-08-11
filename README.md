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

## The journal
Cadmus keeps a record of what it heard, one JSON line per phrase, in
`~/.local/share/cadmus/`. It is there to be read later, by me or by an agent,
to answer questions like which words keep coming out unclear and whether I am
getting faster.

```json
{"said": "I'm trying to connect a GitHub repo", "unsure": ["repo"],
 "words": 7, "speech": 3.1, "wpm": 135, "hesitations": 1, "fillers": 0}
```

Every number is one the recorder already computed to find the end of the
phrase, and `unsure` is the model's own confidence: Whisper reports a
probability per token, and a word it hedged on is usually a word that was said
unclearly. Nothing is measured for the journal, it is only kept instead of
thrown away.

Cadmus does not coach and is not going to. It keeps the record and stops there,
the same way it types the text and stops there.

The audio is still never written. This is text, it never leaves the machine, and
`CADMUS_JOURNAL=0` turns it off.

## Environment
- `CADMUS_INSERT`: `keystrokes` (default) or `paste`.
- `CADMUS_MODEL`: path to a different ggml model.
- `CADMUS_VOICE_FLOOR`: forces the loudness under which audio is not speech.
  Cadmus measures the room and works this out on its own, so this is for
  arguing with the measurement rather than for making it work.
- `CADMUS_QUIET`: `0` to leave the machine's sound alone while recording.
- `CADMUS_PAUSE`: seconds of quiet that end a phrase, `1.4` by default.
- `CADMUS_JOURNAL`: `0` to keep no record of what was said.
