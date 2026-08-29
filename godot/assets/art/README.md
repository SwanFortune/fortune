# Art drop zone

Finished art goes here, named exactly as its id in
`data/base/art_manifest.json`:

```
assets/art/card/pour-the-tea.png
assets/art/sitter/mme-perrot.png
assets/art/reader/serpentarius.png
```

Then set that asset's `"status"` to `"wip"` or `"final"` in the manifest —
the game only looks on disk for assets whose status isn't `"missing"`.

Anything absent falls back to the procedural placeholder automatically, so
the game always runs. See `docs/ART_GUIDE.md` for sizes and the full brief.
