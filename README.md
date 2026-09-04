# Affirmation Wallpaper

An aurora desktop for the Mac. Affirmations and images appear in empty space — never behind your windows.

## Download

1. Get **[AffirmationWallpaper.zip](https://github.com/mtsogias/affirmation-wallpaper/releases/latest/download/AffirmationWallpaper.zip)**
2. Unzip
3. Drag `AffirmationWallpaper.app` into **Applications**
4. Double-click to open

On first launch: right-click the app → **Open** (macOS warns because the app is not notarized yet).

Requires macOS 14 or later.

## What it does

- Animated aurora desktop, including multiple displays
- Your own affirmations
- Images from a vision-board folder
- Text and images stay out of the way of open windows, the menu bar, and the Dock
- Settings: Affirmation Wallpaper → Settings (⌘,)

## Build from source

```sh
xcodebuild -scheme AffirmationWallpaper -configuration Release -derivedDataPath build
```

The app is at `build/Build/Products/Release/AffirmationWallpaper.app`.
