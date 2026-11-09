# Guru Signal banner

The project banner recreates the frame and bitmap typography of a specific Amiga
Guru Meditation screenshot. Its fictional number, `00000003.00000002`, references
three failed checks opening an incident and two successful checks resolving it.

## Files and dimensions

| File | Purpose |
| --- | --- |
| `guru-signal.png` | Native 640×400 canvas with a 640×78 frame |
| `guru-signal-2x.png` | 1280×800 nearest-neighbor preview |
| `guru-signal-banner.png` | 1280×156 README banner, cropped to the frame and scaled 2× |
| `measurements.json` | Source checksums, geometry, text positions, and verification results |

The native frame has six-pixel borders, background `#101010`, and foreground
`#ff2000`. The serif Topaz 9 bitmap uses 10×9 source cells with doubled scanlines,
producing 10×18 displayed cells. All three text rows use the same font size.
These measurements describe the selected reference, not every Amiga alert.

## Reproduce

Run from the repository root with Python 3:

```bash
python3 -m venv .local-tools/artwork-venv
.local-tools/artwork-venv/bin/python -m pip install -r artwork/requirements.txt
curl -fL https://toastytech.com/guis/amiga1guru.png \
  -o .local-tools/amiga-guru-reference.png
curl -fL https://raw.githubusercontent.com/robhagemans/hoard-of-bitfonts/80f28e9d2262517688b0cffa40d8a8d770ddde01/amiga/amiga-ks13-topaz-09.yaff \
  -o .local-tools/topaz-ks13-09.yaff
.local-tools/artwork-venv/bin/python bin/render-guru-banner
```

The renderer checks input hashes, reference glyphs, borders, text bounds, palette,
and integer scaling before replacing the outputs. The three reference text
segments cover 28 distinct characters and match pixel for pixel; other characters
come from the same bitmap source. Reference inputs remain in ignored local storage.

## Sources

- [Reference screenshot](https://toastytech.com/guis/amiga1guru.png), from
  [ToastyTech's Amiga gallery](https://toastytech.com/guis/amiga12.html).
- [Topaz 9 bitmap, pinned revision](https://github.com/robhagemans/hoard-of-bitfonts/blob/80f28e9d2262517688b0cffa40d8a8d770ddde01/amiga/amiga-ks13-topaz-09.yaff),
  with Kickstart 1.3 extraction metadata.

This uses the Kickstart bitmap, not the MIT-licensed Topaz Double reconstruction;
no MIT license is claimed for the font. Original font rights remain with their
respective holders. A project license has not yet been selected.
