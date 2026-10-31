# Beam

<img src="icon.svg" alt="Beam icon" width="128">

A native macOS media player, written entirely in arm64 assembly. It plays audio and video from your Mac or the web, on your Mac, on AirPlay, or on any speaker or TV on your network.

## What it plays

- **Files**: any audio or video macOS plays. Open one with ⌘O, drop it on the window, or use Open With in the Finder.
- **From a URL** (⌘L): a YouTube or Dailymotion link, or words to search YouTube for; any other web address of a media file or HLS stream plays as it is.
- **YouTube** plays up to 4K, in AV1 where the chip decodes it in hardware and H.264 otherwise; live streams play with their picture.
- **Audio Only** (⌥⌘A, or the headphones): the picture is neither downloaded nor decoded.
- **Subtitles and audio tracks** of files and streams that have them, in the View menu; **speed** from 0.5× to 2× in the Playback menu; **Picture in Picture** (⌥⌘P).

## Where it plays

- **This Mac**: the current macOS output: built-in, wired, Bluetooth or AirPlay speakers and headphones.
- **AirPlay** (the AirPlay button): picture and sound to an Apple TV or an AirPlay TV or speaker.
- **Network speakers and TVs** (the speaker button, yellow while one plays): any UPnP/DLNA renderer, Sonos included, found automatically; opening the menu also finds the ones turned on since. Speakers get the sound; TVs get the picture too. Files from your Mac play on them as well. Set `BEAM_HOST` to a device's description URL (or a Sonos IP) to use only that one.

## Build and run

Needs an Apple silicon Mac with macOS 26 or later.

```sh
./install.sh
open Beam.app
```

Nothing gets installed: no cache, no preferences.

It opens in about 0.15 s; a 4K YouTube link plays in about 0.8 s, and in about 0.6 s once Beam has played one (connections, TLS sessions and DNS answers are pooled); 4K at 60 fps plays at about 3% CPU, decoded by the chip. Against a standard AVKit player on the same files (HEVC 4K, H.264, HEVC with alpha), it starts as fast or faster and uses two to six times less CPU.

## Keyboard shortcuts

| Action                     | Keys                            |
| -------------------------- | ------------------------------- |
| Play / Pause               | Space                           |
| Back / forward 10 seconds  | ← / →, or ⌘← / ⌘→               |
| Volume up / down           | ↑ / ↓, or ⌘↑ / ⌘↓               |
| Mute                       | M, or ⌥⌘↓                       |
| Full screen                | F, ⌃⌘F or a double click; Esc   |
| Picture in Picture         | ⌥⌘P                             |
| Open a file                | ⌘O                              |
| Open from URL              | ⌘L                              |
| Audio Only                 | ⌥⌘A                             |
| Stop                       | ⌘.                              |
| Find devices again         | ⌘R                              |

While a video plays, the controls and the pointer step aside after three still seconds; moving the mouse brings them back.
