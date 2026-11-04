# MIA

<img src="icon.svg" alt="MIA icon" width="128">

A full-featured media player in just 66 KB. Plays MP4, MKV, WebM, FLV, HLS, and YouTube.

A native macOS media player, written entirely in arm64 assembly. It plays audio and video from your Mac or the web, on your Mac or on AirPlay.

The whole thing lives in one file, mia.s. I know I’m supposed to split the code up, but screw it. It was fun.

## What it plays

- **Files**: any audio or video macOS plays, and MKV, WebM and FLV with the codecs the Mac decodes (H.264, HEVC, AV1, VP9, ProRes; AAC, MP3, Opus, Vorbis, FLAC, ALAC, AC-3, E-AC-3, PCM) and their text subtitles. Open one from the File menu (⌘O), drop it on the window, or use Open With in the Finder.
- **From a URL** (File > Open from URL, ⌘L): a YouTube link, or words to search YouTube for; any other web address of a media file or HLS stream plays as it is.
- **YouTube** plays up to 4K, in AV1 where the chip decodes it in hardware and H.264 otherwise, with the original sound rather than a dub; live streams play with their picture.
- **Audio Only** (⌥⌘A, or the headphones): the picture is neither downloaded nor decoded.
- **Subtitles and audio tracks** of files and streams that have them, in the View menu; **speed** from 0.5× to 2× in the Playback menu; **Picture in Picture** (⌥⌘P).

## Where it plays

- **This Mac**: the current macOS output: built-in, wired, Bluetooth or AirPlay speakers and headphones.
- **AirPlay** (the AirPlay button): picture and sound to an Apple TV or an AirPlay TV or speaker.

## Build and run

Needs an Apple silicon Mac with macOS 26 or later and the Xcode command line tools (`xcode-select --install`).

```sh
curl -fsSL https://raw.githubusercontent.com/falcosan/mia/main/install.sh | bash
open MIA.app
```

In a clone, `./install.sh` does the same.

Nothing gets installed: no cache, no preferences.

MIA reads the media itself (MP4, fragmented MP4, MPEG-TS, HLS, YouTube's DASH, Matroska, WebM, FLV, and sound files through AudioFileStream) and hands the compressed samples to the chip's decoders. A sound file starts in about 30 ms and a 4K file shows its first picture in about 45 ms; seeks land on the exact frame in about 50 ms (1080p) to 0.2 s (4K at 60 fps). A YouTube link shows its picture in about 0.45 s and seeks in about 0.7 s.

## Keyboard shortcuts

| Action                    | Keys                          |
| ------------------------- | ----------------------------- |
| Play / Pause              | Space                         |
| Back / forward 10 seconds | ← / →, or ⌘← / ⌘→             |
| Volume up / down          | ↑ / ↓, or ⌘↑ / ⌘↓             |
| Mute                      | M, or ⌥⌘↓                     |
| Full screen               | F, ⌃⌘F or a double click; Esc |
| Picture in Picture        | ⌥⌘P                           |
| Open a file               | ⌘O                            |
| Open from URL             | ⌘L                            |
| Audio Only                | ⌥⌘A                           |
| Stop                      | ⌘.                            |

While a video plays, the controls and the pointer step aside after three still seconds; moving the mouse brings them back.
