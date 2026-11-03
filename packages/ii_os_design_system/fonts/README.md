# Bundled typeface

ii-os bundles Manrope so brand typography is identical on web, Android, iOS,
and desktop. A declared family with no bundled font renders in Roboto on
Android, Helvetica on iOS, and whatever the browser resolves on web.

| | |
| --- | --- |
| Family | Manrope |
| Upstream | https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/Manrope%5Bwght%5D.ttf |
| Variable SHA-256 | `d0639be45d0af36e798172419d7bd173c4bd4f29e2b76cbb69db1d11bf8b0a40` |
| License | SIL Open Font License 1.1 -- `Manrope-LICENSE.txt` |
| Weights | 400 Regular, 600 SemiBold, 700 Bold, 800 ExtraBold |

The OFL permits bundling and redistribution, including inside a proprietary
application, provided the licence travels with the font files.
`Manrope-LICENSE.txt` is that copy; do not remove it. The package `LICENSE`
repeats it as a section named `Manrope` after the package's own Apache-2.0
text, because the Flutter tool copies each dependency's `LICENSE` into an
app's `NOTICES`: that is what puts the OFL on the licence page of every app
built on the design system. `test/manrope_license_test.dart` keeps the two
copies identical; update both together.

## Why Manrope

It replaced Inter, which is drawn well but is also the default choice in this
category, so it carried no identity of its own. Manrope is geometric enough to
stay precise at interface sizes with open counters and softly cut terminals
that keep it from reading cold, and it ships tabular figures -- the KPI tiles,
job tables, and duration readouts stay column-aligned instead of jittering as
digits change.

One family covers the whole product. A separate display face would be a second
set of files to ship, subset, and keep in sync for headings that Manrope
already sets well at weight 800 with tight tracking.

## Instancing and subsetting

Upstream publishes a variable font. These are static instances cut from it at
the four weights the type scale uses, then subset to Latin, which brings all
four to ~132 KB total. Regenerate with:

```bash
python3 -m venv /tmp/fontenv && /tmp/fontenv/bin/pip install fonttools brotli
curl -sSLo /tmp/manrope-var.ttf \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/Manrope%5Bwght%5D.ttf'
curl -sSLo /tmp/manrope-OFL.txt \
  'https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/OFL.txt'
shasum -a 256 /tmp/manrope-var.ttf   # must match the SHA above

UNI="U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+2074,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD"
for pair in Regular:400 SemiBold:600 Bold:700 ExtraBold:800; do
  name="${pair%%:*}"; wght="${pair##*:}"
  /tmp/fontenv/bin/fonttools varLib.instancer /tmp/manrope-var.ttf "wght=$wght" \
    --update-name-table -o "/tmp/Manrope-$name.ttf"
  /tmp/fontenv/bin/pyftsubset "/tmp/Manrope-$name.ttf" \
    --output-file="fonts/Manrope-$name.ttf" \
    --unicodes="$UNI" \
    --layout-features="kern,liga,calt,tnum,ccmp,mark,mkmk" \
    --name-IDs='*' --no-hinting --desubroutinize
done
cp /tmp/manrope-OFL.txt fonts/Manrope-LICENSE.txt
```

`--update-name-table` names each static instance after its own weight, and
`--name-IDs='*'` keeps the licence description and licence URL records (name
IDs 13 and 14) that `pyftsubset` otherwise drops. The committed files predate
both flags: they keep the copyright record (name ID 0) but not the licence
records, and their full-name records still name the variable font's default
instance. The next regeneration corrects both.

`tnum` must stay in `--layout-features`; dropping it silently returns the
tables to proportional figures. Confirm it survived:

```bash
/tmp/fontenv/bin/python -c "
from fontTools.ttLib import TTFont
f = TTFont('fonts/Manrope-Regular.ttf')
tags = {r.FeatureTag for r in f['GSUB'].table.FeatureList.FeatureRecord}
assert 'tnum' in tags, tags
print('tabular figures present')"
```

If the app ever needs a script outside Latin, widen `--unicodes` rather than
shipping the unsubset files.
