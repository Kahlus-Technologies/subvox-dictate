# Subvox Dictate

Hold a key, talk, and the text gets pasted into whatever app you're using, like Wispr Flow. Each
dictation also saves the AirPods head and jaw motion recorded while you spoke, with every word
timestamped. Everyday dictation turns into training data for
[Subvox](https://github.com/Kahlus-Technologies/subvox), our silent-speech decoder.

Uses the Subvox icon. Fork of [Hex](https://github.com/kitlangton/Hex) (MIT) by Kit Langton. Transcription runs on your
Mac (Parakeet or Whisper). Nothing leaves your machine.

## Install

1. Open `SubvoxDictate.dmg` and drag **Subvox Dictate** to Applications.
2. The app isn't notarized yet, so the first launch needs a right-click on the app, then **Open**.
3. Allow **Microphone**, **Accessibility**, **Input Monitoring**, and **Motion & Fitness** when
   asked. If no Motion prompt appears, put your AirPods in. The prompt shows up once they connect.
4. Open **Settings** from the menu bar icon and download a model (Parakeet is the default).
5. Put your AirPods Pro in. Hold **Option**, speak, release. The text pastes.

Quit Wispr Flow first, or move one of the two apps to a different hotkey.

## What gets saved

Each dictation creates `~/Documents/Subvox/Sessions/<time>-dictation/`:

| File | Contents |
| --- | --- |
| `audio.wav` | the clip (16 kHz mono) |
| `motion.csv` | AirPods motion at about 50 Hz, the same columns the Subvox app writes |
| `words.json` | transcript plus each word's start and end time |
| `meta.json` | duration, mic, model, which app you dictated into |

`motion.csv` `t`, the word times, and the audio share one clock: seconds since the first audio
sample. **Open Subvox Sessions Folder** in the menu bar opens the folder.

Check that sessions are usable (AirPods connected, motion covers the audio):

    python3 subvox/check_sessions.py

**Privacy:** every dictation's audio and text is kept on disk. Delete any session folder you don't
want to keep.

## Sharing (opt in)

Settings > **Help build silent speech** uploads each dictation's motion, transcript, and word timings to
our research backend (Convex, see `backend/`). Off by default. Audio is uploaded only with **Include
audio** on. No account: a random ID on your Mac groups your sessions. **Delete my shared data** erases
everything uploaded from your Mac. Failed uploads retry on the next dictation or launch.

## Tips for useful data

- Dictate with the **Mac's microphone**. This is the default if you never picked a mic in
  Settings. The AirPods mic switches them into a low-quality call mode.
- Whispering is closer to silent speech than talking at normal volume, so whisper when you can.
- No AirPods connected means no motion. Those sessions are flagged and useless for training.

## Build

    subvox/make_dmg.sh        # -> dist/SubvoxDictate.dmg (ad-hoc signed)

Changes from Hex: `Hex/Clients/SubvoxCapture.swift` (motion buffer and session writer), plus small
hooks in the capture engine (host time of the first audio sample), the Parakeet and Whisper clients
(word timings), and the transcription flow (save after each dictation). Other changes: the built-in
mic is the default input, the app is unsandboxed, and Sparkle auto-update is removed so it never
"updates" back to stock Hex.
