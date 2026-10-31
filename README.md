# Beam

<img src="icon.svg" alt="Beam icon" width="128">

A native macOS app, written entirely in arm64 assembly, that plays YouTube audio on any speaker. Paste a link or type a search, pick a speaker, press Return.

## Where it plays

Choose in the "Playing on" menu at the bottom of the window:

- **This Mac**: the current macOS output: built-in, wired, Bluetooth or AirPlay speakers and headphones.
- **Wi-Fi speakers and TVs**: any UPnP/DLNA renderer on the network, Sonos included, found automatically; opening the menu also finds the ones turned on since. Set `BEAM_HOST` to a device's description URL (or a Sonos IP) to use only that one.

Videos and live streams both play; a live stream reaches Wi-Fi speakers as continuous AAC audio.

## Build and run

Needs an Apple silicon Mac with macOS 26 or later.

```sh
./install.sh
```

Nothing gets installed: no cache, no preferences.

## Keyboard shortcuts

| Action                    | Keys                    |
| ------------------------- | ----------------------- |
| Play / Pause              | Space (when not typing) |
| Stop                      | ⌘.                      |
| Back / forward 10 seconds | ⌘← / ⌘→                 |
| Volume up / down          | ⌘↑ / ⌘↓                 |
| Mute                      | ⌥⌘↓                     |
| Paste a link or search    | ⌘L                      |
| Find devices again        | ⌘R                      |
