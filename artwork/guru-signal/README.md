# Guru Signal bitmap banner

Standalone concept artwork.

- `guru-signal.png`: native **640×400** canvas.
- `guru-signal-2x.png`: **1280×800** nearest-neighbor preview.
- `measurements.json`: input checksums, provenance, text positions, and verification results.

The native image preserves the reference's **640×78 frame**, with **6-pixel
borders on all four sides**, background `#101010`, and foreground `#ff2000`.
These dimensions refer to this particular screenshot, not every Amiga alert.

## Font and layout

The reference uses the early serif **Topaz 9** variant: **10×9 source cells**
with each row doubled vertically, yielding **10×18 displayed cells**. The
original glyphs have up to fourteen visible pixels of height plus descender and
blank rows. The initially considered Topaz Double font recreates Topaz 8 and
was not used, because it would not match this screenshot's character geometry.

All three original text segments were reconstructed and compared pixel for
pixel, with **zero differences**. They cover 28 distinct characters. Characters
not present in the reference use the same sourced Topaz 9 bitmap, but cannot be
individually compared against that screenshot.

The customized image has three centered rows at the same font size. Their
vertical placement changes to fit three rows inside the unchanged frame:

```text
Service failure. Stay calm. We are watching.
Less meditation. More remediation.
Guru Signal #00000003.00000002
```

The number is a fictional reference to three failures opening an incident and
two successful checks resolving it; it is not a real incident identifier.

## Reproduce

Requires Python 3 and Pillow. To install Pillow without changing global tooling:

```bash
python3 -m venv .local-tools/artwork-venv
.local-tools/artwork-venv/bin/python -m pip install -r artwork/requirements.txt
```

Download the reference inputs into the ignored local directory:

```bash
curl -fL https://toastytech.com/guis/amiga1guru.png \
  -o .local-tools/amiga-guru-reference.png
curl -fL https://raw.githubusercontent.com/robhagemans/hoard-of-bitfonts/80f28e9d2262517688b0cffa40d8a8d770ddde01/amiga/amiga-ks13-topaz-09.yaff \
  -o .local-tools/topaz-ks13-09.yaff
.local-tools/artwork-venv/bin/python bin/render-guru-banner
```

The renderer rejects unexpected input checksums. It verifies the reference font
segments, every border pixel, text bounds, the two-color palette, and lossless
integer scaling before saving. Running it again replaces the same deliverables
with deterministic output. Existing Pillow 12.3.0 was used for verification;
no global packages were installed by the agent.

## Provenance

- [Reference screenshot](https://toastytech.com/guis/amiga1guru.png), from
  [ToastyTech's Amiga Workbench gallery](https://toastytech.com/guis/amiga12.html).
- [Topaz 9 bitmap source, pinned revision](https://github.com/robhagemans/hoard-of-bitfonts/blob/80f28e9d2262517688b0cffa40d8a8d770ddde01/amiga/amiga-ks13-topaz-09.yaff).
  Its metadata identifies extraction from Amiga Kickstart 1.3, with the original
  ROM checksum and bitmap offsets.

The original screenshot, ROM, and font source are not vendored. The font data
used here is **not** the MIT-licensed Topaz Double reconstruction; no MIT license
is claimed for it. Original font rights remain with their respective holders.
This artwork does not select a license for the GuruSignal project.
