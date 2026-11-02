# Beam

<img src="icon.svg" alt="Beam icon" width="128">

A native macOS media player, written entirely in arm64 assembly. It plays audio and video from your Mac or the web, on your Mac or on AirPlay.

## What it plays

- **Files**: any audio or video macOS plays. Open one from the File menu (⌘O), drop it on the window, or use Open With in the Finder.
- **From a URL** (File > Open from URL, ⌘L): a YouTube link, or words to search YouTube for; any other web address of a media file or HLS stream plays as it is.
- **YouTube** plays up to 4K, in AV1 where the chip decodes it in hardware and H.264 otherwise, with the original sound rather than a dub; live streams play with their picture.
- **Audio Only** (⌥⌘A, or the headphones): the picture is neither downloaded nor decoded.
- **Subtitles and audio tracks** of files and streams that have them, in the View menu; **speed** from 0.5× to 2× in the Playback menu; **Picture in Picture** (⌥⌘P).

## Where it plays

- **This Mac**: the current macOS output: built-in, wired, Bluetooth or AirPlay speakers and headphones.
- **AirPlay** (the AirPlay button, once something plays): picture and sound to an Apple TV or an AirPlay TV or speaker.

## Build and run

Needs an Apple silicon Mac with macOS 26 or later.

```sh
./install.sh
open Beam.app
```

Nothing gets installed: no cache, no preferences.

Beam reads the media itself (MP4, fragmented MP4, MPEG-TS, HLS, YouTube's DASH, and sound files through AudioFileStream) and hands the compressed samples to the chip's decoders. A sound file starts in about 30 ms and a 4K file shows its first picture in about 35 ms; seeks land on the exact frame in about 20 ms (1080p) to 50 ms (4K at 60 fps). A YouTube link shows its picture in about 0.45 s and seeks in about 0.7 s.

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
