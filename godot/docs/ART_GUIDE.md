# Art guide — Parlour

Everything the game needs drawn, what size to draw it at, where to put the
files, and how to tell the game a piece is finished. Written for the artist;
no Godot knowledge needed, and you never have to touch code.

The authoritative checklist is **`data/base/art_manifest.json`** — it's
generated from the game's real content, so it can't drift out of date. This
document explains how to read and use it.

---

## The short version

1. Draw a piece at the size given below.
2. Save it as a PNG to `assets/art/<kind>/<slug>.png` — the `<kind>/<slug>`
   part is exactly the asset's id in `art_manifest.json`.
3. In `art_manifest.json`, find that asset and set `"status": "final"` (or
   `"wip"` while you're still iterating).
4. The game picks it up on next launch. No code change needed.

Anything with no art yet keeps rendering the current placeholder, so the game
is always runnable — art can land one piece at a time, in any order.

---

## Sizes and formats

### Card art — **512 × 512 px**, square, PNG (RGBA, transparency OK)

- **Safe zone: keep the subject inside the centre 440 × 440.** The card frame
  overlays roughly 36px on every edge.
- **The top ~52px carries the cost and restore numbers** (top-left and
  top-right corners) — don't put anything you'd hate to lose behind them.
- It's displayed at about **106 × 106** in the player's hand, so **it has to
  read at thumbnail size**. One clear silhouette beats fine detail. The 512
  source gives us headroom for a zoomed card-inspect view later.

### Portrait art (sitters and readers) — **768 × 1024 px**, 3:4 portrait, PNG (RGBA)

- **Face and shoulders inside the top 768 × 768.** The bottom quarter may be
  cropped or covered by a name plate depending on the screen.
- **Sitters** are the villagers who sit across the table from you — this is
  the face the player watches for a whole encounter, and the one that visibly
  softens as their composure fills. If it's practical, a **second variant**
  showing them noticeably more at ease is very welcome (name it
  `<slug>-mended.png`); it isn't required, and the game works fine with one.
- **Readers** are the fortune-teller the player chooses to *be*, shown on the
  sign-select screen.

### File naming

Lowercase, hyphen-separated, accents stripped — always exactly the asset id
from the manifest:

```
assets/art/card/pour-the-tea.png
assets/art/card/the-high-priestess.png
assets/art/sitter/mme-perrot.png
assets/art/sitter/pere-renaud.png      (Père Renaud — accent dropped in the filename)
assets/art/reader/serpentarius.png
```

Accents are stripped from filenames on purpose so they stay portable across
Windows/Mac/Linux and safe inside Steam Workshop archives — the accented name
still displays correctly in-game, it's only the filename that's plain.

---

## Reading the manifest

`data/base/art_manifest.json` looks like this:

```json
{
  "spec": { ... the sizes above, in machine-readable form ... },
  "assets": {
    "card/pour-the-tea": {
      "kind": "card",
      "display": "Pour The Tea",
      "pool": "cards_minor",
      "element": "water",
      "rarity": "common",
      "archetype": "",
      "spoken": "pour the tea",
      "flavor": "It is for you as much as for them.",
      "status": "missing",
      "file": "",
      "notes": ""
    }
  }
}
```

Fields you'll **read** (generated — don't edit, they'll be overwritten):

| Field | What it tells you |
|---|---|
| `display` | The name as the player sees it. |
| `kind` | `card`, `sitter`, or `reader` — decides which size spec applies. |
| `element` | `fire` / `earth` / `air` / `water` / `none`. See the palette below. |
| `rarity` | `basic`, `common`, `uncommon`, `rare`. Rarer cards can be stranger and more elaborate. |
| `archetype` | `digging`, `switch`, `pinpoint`, `channel`, `timing`, or blank — the card's mechanical family. |
| `spoken` | The literal phrase the fortune-teller says, e.g. "pour the tea". **This is usually the single most useful field: it's the action to draw.** |
| `flavor` | The card's flavor line. Tone reference, and often the actual image idea. |
| `pronoun` | (sitters) `he` / `she` / `they`. |
| `planet` | (readers) their ruling planet. |

Fields you'll **write** (yours; preserved when the file is regenerated):

| Field | What to put |
|---|---|
| `status` | `missing` → `wip` → `final`. |
| `file` | Usually leave blank — the game finds `assets/art/<id>.png` automatically. Only fill this in if a file lives somewhere non-standard. |
| `notes` | Anything you want to record — questions, "needs a redraw", references. Nothing reads this but us. |

**Regenerating:** when cards get added or renamed, someone runs
`godot --headless --path godot -s tests/gen_art_manifest.gd`. Your `status`,
`file`, and `notes` survive that. New entries appear as `missing`; removed
ones are reported in the console so nothing silently vanishes.

(That generator reads the game's *live* content, which includes any mods
loaded in dev — that's why a demo card like `card/warm-the-cup` from
`mods_example/` shows up. It isn't base-game content and doesn't need art.)

---

## Elements — the colour language

Four elements run through everything. Each already has a colour and a glyph
in the game; art doesn't have to match the colour literally, but it should
feel like it belongs to that family.

| Element | Glyph | Colour | It means | The game's own words for it |
|---|---|---|---|---|
| Fire | △ | warm orange `#D97F4C` | Empowerment, reckless action | "Take it. Refuse. Backflip. Scream. Destroy it. Action." |
| Earth | □ | green `#8FBF6B` | Anchoring, the material world | "Coins, calluses, taxes, dates, the material world." |
| Air | ◇ | pale gold `#D9C87A` | Understanding, intellect | "Naming it. The family, the pattern, the plot." |
| Water | ▽ | blue `#5B9BD5` | Feeling, emotion | "Nodding, tea, silence, sitting closer, hugging." |
| (none) | — | bone `#EAE4D7` | The plain human basics | The seven "basic decency" cards every reader starts with. |

The UI background is near-black (`#141213`) with bone-coloured text, so art
sitting on it wants enough internal contrast not to disappear.

---

## Tone

Small French village, somewhere with more weather than money. You are the
village fortune-teller, and you are a fraud — but the people who sit down
across from you are in real trouble, and what you do to them is basically
counselling. The comedy and the ache are the same thing.

The cards are not spells. They're what a person actually does in a room with
someone who's upset: pour the tea, ask about the family, say their name, sit
in the silence, kick the chair over. **Draw the gesture, not the magic.**
Tarot iconography is the wrapper, not the content — a card called
"The Emperor" can be a heavy kitchen table.

Melancholic, warm, a bit spooky, funny in a dry way. Not whimsical, not
grimdark.

---

## The full checklist

Everything below needs art. Counts as of the last manifest regeneration.

**Cards — 56 base game** (plus 1 demo card from the example mod that doesn't
need art):

- 7 **basics** — the "basic decency" cards, no element, every reader starts
  with all seven. These are seen most; worth doing first.
- 2 **chromatic** — no fixed element (they shift). Only Serpentarius starts
  with them.
- 31 **minor** — the elemental pool: 9 fire, 8 earth, 7 water, 7 air.
- 16 **arcana** — the Major Arcana. Rarest, strangest, most elaborate.

**Sitters — 10 portraits** (9 villagers + Mayor Havel, the boss). These carry
the most emotional weight in the game; the player stares at one for a whole
encounter.

**Readers — 13 portraits** — the twelve zodiac signs plus Serpentarius, the
thirteenth. Serpentarius is the odd one out by design: no fixed element,
rainbow/glitchy in the prototype, "nobody knows what you are and they come
anyway."

**Suggested order** (most player-visible first): basics → sitters → minor →
readers → arcana → chromatic.

Run this any time for the current state:

```
godot --headless --path godot -s tests/gen_art_manifest.gd
```

It prints a by-status summary (how many missing / wip / final).
