---
name: calarm-app-icon-alpha
description: >-
  Process CALarm App Store icons: remove alpha channel, generate dark/light/tinted
  1024x1024 assets. Use when ASC rejects icon transparency (error 90717) or updating logo.
---

# CALarm App Icon (No Alpha)

## ASC requirement

1024×1024 app icon **must not** have transparency. Rejection: `Invalid large app icon (90717)`.

## Process from source image

```bash
python3 scripts/process-app-icon.py /path/to/source.jpg \
  Calarm/Assets.xcassets/AppIcon.appiconset/
```

Or wrapper:

```bash
./scripts/fix-app-icon-alpha.sh /path/to/source.jpg
```

## Outputs

| File | Purpose |
|------|---------|
| `calarm.png` | Default / dark appearance |
| `calarm-light.png` | Light appearance |
| `calarm-tinted.png` | Tinted appearance slot |
| `Contents.json` | Asset catalog manifest |

## Implementation notes

- `ensure_opaque()` composites RGBA onto black
- `remove_corner_watermark()` for AI sparkle artifacts
- Requires Pillow: `pip install Pillow`

## Verify

```bash
sips -g hasAlpha Calarm/Assets.xcassets/AppIcon.appiconset/calarm.png
# hasAlpha: no
```

## When to run

- New logo before TestFlight / App Store upload
- After any manual edit to `AppIcon.appiconset`

## Do not

- Commit icons with alpha channel
- Use transparent PNG directly in 1024 slot
