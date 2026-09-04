# Affirmation Wallpaper

An aurora desktop for the Mac. Affirmations and images fade in and out in the empty space around your windows — never covering what you are working on.

## Download

1. Get **[AffirmationWallpaper.zip](https://github.com/mtsogias/affirmation-wallpaper/releases/latest/download/AffirmationWallpaper.zip)**
2. Unzip
3. Drag `Affirmation Wallpaper.app` into **Applications**
4. Double-click to open

On first launch: right-click the app → **Open** (macOS warns because the app is not notarized yet).

Requires macOS 14 or later.

## How it works

The aurora is a live desktop behind your apps, including on extra displays.

Affirmations and vision-board images do not sit still under a window. The app watches where your windows are, then places each sentence or photo **outside** the window you are looking at — in the free space beside it, so you still catch a glimpse of the picture or the words. The menu bar and Dock stay clear.

Each piece fades in, stays for a moment, then fades out. Affirmations and images each have their own on/off switch, so you can use only sentences, only photos, or both. In Settings you also set how often they appear and how quickly they fade.

Open **Affirmation Wallpaper → Settings** (⌘,) to change:

- Aurora look (brightness, color, speed)
- Your own affirmations
- A folder of images, and which subfolders to skip
- Whether affirmations and images are on, how often they appear, and how fast they fade

## Build from source

```sh
xcodebuild -scheme AffirmationWallpaper -configuration Release -derivedDataPath build
```

The app is at `build/Build/Products/Release/Affirmation Wallpaper.app`.
