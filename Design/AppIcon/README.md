# App icon

**Status: 2026-10-30 rebrand, pending your verdict** (replaces the scarab
icon approved 2026-09-24, kept as `legacy-scarab-mark.svg`).

The icon is the solar emblem — two crescent wings cradling a gold sphere over
a navy horizon — from the "Khepri: A Brighter Future" reference. The emblem is
a hand-built vector interpretation of that image, not a designer's source
file.

The SVGs here are **generated**; don't edit them by hand. Their source is
`north-web-app/scripts/brand/build.py`, which writes
`static/assets/brand/solar/app-icon-{light,dark,tinted}.svg`. Copy those here:

| File | Appearance |
|------|------------|
| `icon-light.svg` | Default. Navy plate lifting toward the sphere, soft sun halo. |
| `icon-dark.svg` | iOS dark icons. Darker plate. |
| `icon-tinted.svg` | iOS tinted icons. Greyscale mark on black; the system tints it. |

Render and install:

```sh
for v in light dark tinted; do
  rsvg-convert -w 1024 -h 1024 Design/AppIcon/icon-$v.svg -o /tmp/icon-$v.png
  # App Store icons must not carry an alpha channel.
  sips -s format jpeg -s formatOptions 100 /tmp/icon-$v.png --out /tmp/icon-$v.jpg
  sips -s format png /tmp/icon-$v.jpg --out khepri/Assets.xcassets/AppIcon.appiconset/AppIcon-$v.png
done
```

The same emblem is the in-app mark (`NorthKit` `Brand.xcassets`:
`KhepriMark`, detailed, and `KhepriMarkSmall`, the silhouette for 32 pt and
below) and the launch screen (`LaunchMark` on `LaunchBackground` in the app's
asset catalog, set in `Config/Info.plist` under `UILaunchScreen`). Each is a
PDF rendered from the web repo's SVGs with `rsvg-convert -f pdf`.
