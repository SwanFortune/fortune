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

### Card art — **768 × 576 px**, 4:3 landscape, PNG (RGBA, transparency OK)

- **The whole image is shown. Nothing is cropped and nothing is drawn over
  it.** The card holds a window of exactly this shape open — you can see it as
  an empty recess on every card in the game today — and the numbers, the name
  and the badges are all outside it, above and below. There is no safe zone to
  work around because there is nothing to work around.
- It's displayed at about **106 × 79** in the player's hand, so **it has to
  read at thumbnail size**. One clear silhouette beats fine detail. The 768
  source gives us headroom for a zoomed card-inspect view later.
- A piece delivered in some other shape still works — it fills the window and
  loses whatever hangs over the edges — but 4:3 is the shape that loses
  nothing.
- The window's shape lives in `UIKit.ART_WELL`; `tests/test_art.gd` fails if
  this line and that constant stop agreeing, so the number above cannot go
  stale without somebody being told.

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

---

## What is drawn in code, and what replaces it

Three things on screen are not in the manifest, because they are not files:
they are drawn procedurally by the game. They exist so the game looks like a
game rather than a spreadsheet while the real art is being made, and each one
is a placeholder with a clear replacement.

| Where | What it draws | Replaced by |
|---|---|---|
| `scenes/UIKit.gd` — `sitter_portrait()` | A face: an oval, two eyes, a mouth whose curve follows the sitter's mood | A sitter portrait PNG, via the manifest. Already wired: deliver the file and the drawing stops being used. |
| `scenes/Table.gd` | The parlour, behind EVERY screen in the game, in three views: the table (a papered wall, a door, a coat on a hook, a floor, the table in perspective with its cloth, a Minitel and a cup of tea on it, and the reader's two hands holding the fan with every mark drawn on them), the closed door, and the bare wall | Nothing yet. See below. |
| `autoload/Icons.gd` | The element, sign, planet and archetype glyphs, rasterised at runtime from the vector paths in `data/base/icons.json` | These are FINISHED, not placeholders — they came from the design document and are meant to stay. Redraw a path in `icons.json` to change one. |

### The room, the table and the hands

`scenes/Table.gd` draws the reading screen's background and the pair of hands
holding the player's cards. It is geometry — ellipses, tapered capsules, a few
lines — and it is the piece most obviously waiting for a person.

**Every prop in it is something the game already says.** None were invented to
fill space:

| Prop | Where it comes from |
|---|---|
| The door | Someone knocks on it. A run ends when the knocking stops. |
| The coat on a hook | TAKE THEIR COAT, a basic card in every deck. |
| The cup of tea | POUR THE TEA and WARM THE CUP. |
| The Minitel | The 3615 screen (`docs/MINITEL.md`) dials it. It had never been drawn. |
| The cloth | SET DOWN THE CLOTH. |
| The lamplight | LIGHT THE LAMP — drawn as the light it throws, since the framing never shows a ceiling. |

If you add a prop, take it from the card list or the writing the same way. A
teapot is fine; a crystal ball is a different game.

**Two placement rules the drawing already follows.** The room is BEHIND the
screen's words, and the reading screen's left third — from the composure bar
down to the hand label — is solid text in every layout it produces. Props go in
the gaps (`MINITEL_AT` and `TEACUP_AT` in the file), and everything above the
horizon is deliberately darker than the table so it is recognised rather than
read. A prettier wall that makes a sentence hard to read is a bad trade.

**It is not decoration, and whatever replaces it has to keep one thing.** The
overlay that lists your relics is called YOUR HANDS; the four kinds of mark are
rings, tattoos, scars and boons. The game has always described them as things
on the reader's own hands, and for the whole port they were a list on a panel.
Now a ring you win goes on a finger and stays there for the rest of the run,
where you can see it while you play. A replacement that is a beautiful painting
of hands with nothing on them would be a step backwards.

**There are three views, and a replacement needs all three** — `VIEW_TABLE`,
`VIEW_DOOR` and `VIEW_WALL` in the file. They are the same room from three
places in it, and they have to look like the same room: same wallpaper, same
door, same light. The wall view is deliberately empty, because the screens that
use it are dense with words.

If you want to take it over, the two useful shapes are:

- **A painted background.** One image, roughly 16:9, of a table with a cloth on
  it, lit from above, dark at the edges. Drop-in: it replaces `background()`
  and nothing else changes.
- **Hands.** Harder, because four kinds of mark have to be able to land on
  them at run time, in any number and any combination. The current version
  solves that with `Table.mark_places()`, which returns a point per mark; art
  would need the same — a hand image plus a small table of where a ring on
  each finger, ink on the back, a scar across the knuckles, and a boon above
  the hand each go. Talk to whoever is doing the code before starting.

Sizes are all fractions of the space the game gives it, so there is no fixed
pixel size to match: it is drawn at whatever height the window works out to.
