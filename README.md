# AffirmationWallpaper

Aurora-Hintergrund für den Mac. Affirmationen und Bilder erscheinen im freien Raum — nicht hinter deinen Fenstern.

## App herunterladen

1. **[AffirmationWallpaper.zip](https://github.com/mtsogias/affirmation-wallpaper/releases/latest/download/AffirmationWallpaper.zip)** laden
2. Zip entpacken
3. `AffirmationWallpaper.app` in den Ordner **Programme** ziehen
4. Doppelklick zum Starten

Beim ersten Öffnen: Rechtsklick auf die App → **Öffnen** (macOS warnt, weil die App noch nicht von Apple notarisiert ist).

macOS 14 oder neuer.

## Was sie macht

- Animierter Aurora-Desktop, auch mit mehreren Bildschirmen
- Eigene Affirmationen
- Bilder aus einem Vision-Board-Ordner
- Texte und Bilder weichen offenen Fenstern, Menüleiste und Dock aus
- Einstellungen unter AffirmationWallpaper → Einstellungen (⌘,)

## Aus dem Quellcode bauen

```sh
xcodebuild -scheme AffirmationWallpaper -configuration Release -derivedDataPath build
```

Die App liegt dann in `build/Build/Products/Release/AffirmationWallpaper.app`.
