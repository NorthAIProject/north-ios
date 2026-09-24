# App icon

**Status: approved 2026-09-24** for TestFlight and the App Store.

Traced from `north-web-app/web/assets/brand/source/khepri-emblem-original.jpg`,
the scarab emblem the brand README names as the mark. No square source at or
above 1024 px existed, and upscaling the 480 px `khepri-app-icon.png` would
blur, so the emblem was vectorised instead:

1. `sips` upscales the 600 px JPEG to 2400 px and writes BMP.
2. Two colour masks are split out: the brown silhouette (wings, scarab,
   crescent) and the gold sun.
3. `potrace` traces the silhouette. The sun is replaced by an exact circle
   fitted to its mask, because the JPEG edge traced jagged.
4. The paths are recoloured, gold on the brand board's navy, and placed on a
   1024 plate at 70% of the canvas.

| File | Appearance |
|------|------------|
| `icon-light.svg` | Default. Navy plate, gold mark, soft sun halo. |
| `icon-dark.svg` | iOS dark icons. Darker plate. |
| `icon-tinted.svg` | iOS tinted icons. White-to-grey mark on black; the system tints it. |

Render and install:

```sh
for v in light dark tinted; do
  rsvg-convert -w 1024 -h 1024 Design/AppIcon/icon-$v.svg -o /tmp/icon-$v.png
  # App Store icons must not carry an alpha channel.
  sips -s format jpeg -s formatOptions 100 /tmp/icon-$v.png --out /tmp/icon-$v.jpg
  sips -s format png /tmp/icon-$v.jpg --out khepri/Assets.xcassets/AppIcon.appiconset/AppIcon-$v.png
done
```
