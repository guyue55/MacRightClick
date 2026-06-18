# App icon candidates

These PNG files are ready-to-use macOS app icon sources generated from `img/img-*.png`.

Standard:

- 1024 x 1024
- RGBA with transparent corners
- 96-color visible RGB quantization
- Optimized for `Scripts/build.sh`, which generates `AppIcon.icns`

To switch the app icon:

```bash
cp img/app-icons-q96/img-3-appicon-q96.png Resources/AppIcon.png
./Scripts/build.sh
```

Replace `img-3-appicon-q96.png` with another candidate as needed.
