# AffirmationWallpaper

An animated aurora field as a macOS desktop background. Affirmations and
optional vision-board images fade in over free space — never behind your
open windows.

## Features

- One desktop-level window per screen (above the wallpaper, below apps)
- Aurora field rendered once and shared across monitors
- Still frame synced to the real desktop picture (Mission Control / lock screen)
- Affirmations: fade in, dwell, fade out; at most two at a time
- Images from a folder you choose (recursive, with optional exclusions)
- Placement avoids open windows, the menu bar, and the Dock
- About 2–6% of one CPU core, ~30–46 MB RAM
- Clicks pass through to the desktop; Esc or ⌘Q quits

## Settings

**AffirmationWallpaper → Einstellungen …** (or ⌘,)

- **Darstellung** — live aurora preview, brightness, hue, speed, frame rate
- **Affirmationen** — your sentences (edit in place) and spawn interval (`0` = off)
- **Bilder** — folder picker, image interval (`0` = off), excluded subfolders

Your list and folder stay on this Mac (`UserDefaults`). They are not in the
source. First launch uses a few generic sample sentences and no image folder.

## Build

```sh
xcodebuild -scheme AffirmationWallpaper -configuration Release -derivedDataPath build
```

App: `build/Build/Products/Release/AffirmationWallpaper.app`

## Install

Drag the `.app` into `/Applications`, or:

```sh
cp -R build/Build/Products/Release/AffirmationWallpaper.app /Applications/
```

On another Mac, Gatekeeper may block an unsigned build until the app is
Developer ID signed and notarized.

## Run / quit

```sh
open /Applications/AffirmationWallpaper.app
killall AffirmationWallpaper
```

Login items: **System Settings → General → Login Items**.

## Edit

Open `AffirmationWallpaper.xcodeproj` in Xcode.

- Engine: `AffirmationWallpaper/main.swift`
- Settings UI: `AffirmationWallpaper/Settings.swift`
- Sample sentences: `defaultAffirmations` in `main.swift`
- Palette: `baseColors` in `main.swift` (the hue slider rotates this at runtime)
