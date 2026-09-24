# How the game feels: particles, card motion, haptics

**Start in the studio**: CREDITS → STUDIO, or `godot --path godot -- --studio`.
Every moment is a button there, played on a real card, with the preset it uses
printed beside it; files are reloaded the moment they are saved, and SLOW
MOTION and REPEAT are for tuning. `docs/ATELIER.md` is this guide in French.

This is the handover for whoever gives the game its feel: the sparks when a
card lands, a card that jolts as it goes through a wall, the rumble in a
gamepad when the reading lands. The plumbing is done and tested. **Every
preset in it is a placeholder**, tuned by eye with a procedural soft dot so
there is something to replace. What it should look like is not decided here.

Everything below is data, in `data/base/feel.json`. None of it needs code.
The code is `autoload/Feel.gd`; the tests are `tests/test_feel.gd`.

## The moments

A moment is something the game announces. The list is fixed: it is
`Feel.EVENTS` in `autoload/Feel.gd`, and `feel.json` must have an entry for
each one (the test fails otherwise, both ways).

| Moment | When | Placed on |
|---|---|---|
| `card_draw` | each card dealt into the hand | — (fires five times in a row, keep it light) |
| `card_lay` | a card leaves the hand for the table | where the card was |
| `card_link_same` | read out: continues the element before it | its line in the ledger |
| `card_link_turn` | read out: turns forward round the ring | its line |
| `card_pierce` | read out: goes straight through their denial | its line |
| `card_bank` | read out: paid as faith, not composure | its line |
| `card_exhaust` | read out: a ONCE card spoken for good | its line |
| `wall_absorb` | read out: the wall holds off the front | the wall's line |
| `reading_resolve` | read out: what reaches them | the total |
| `sitter_win` / `sitter_lose` | the verdict | the verdict's heading |
| `knock` | someone at the door | — (felt only) |
| `coin` | centimes change hands | the thing bought |

A line in the ledger gets one of pierce, bank or link, in that order of
precedence, plus `card_exhaust` if the card is a ONCE card.

Each entry can name any of three things, and any can be left out:

```json
"card_pierce": { "particles": "shards", "color": "element", "motion": "jolt", "haptic": "thud" }
```

`color` is `element` (the card's element, from `elements.json`), a hex
colour `#rrggbb`, or empty for white. The particle texture is tinted by it.

## Particles

```json
"shards": { "status": "placeholder", "texture": "", "amount": 16, "lifetime": 0.5,
            "explosiveness": 1.0, "from": "point", "direction": [1, 0], "spread": 30,
            "speed": [160, 320], "gravity": [0, 120], "scale": [0.1, 0.3], "spin": 360 }
```

- `texture`: **empty until there is a drawing.** A bare filename resolves
  under `assets/particles/` (create the folder). Until then every preset uses a
  32 px soft white dot, so `scale` is a fraction of 32 px. A white, or white on
  transparent, drawing takes the tint best.
- `status`: `placeholder`, `wip` or `final`, the same words the audio uses.
  The credits count them.
- `from`: `point` (the centre of what it came from), `area` (anywhere on it)
  or `edge` (round its outline, which suits a card).
- `amount`, `lifetime` (seconds), `explosiveness` (0 = a stream, 1 = all at
  once), `randomness`, `direction` + `spread` (degrees either side), `speed`
  [min, max] in px/s, `gravity` [x, y] in px/s², `damping`, `scale` [min, max],
  `spin` (degrees/s either way), `fade` (true by default: alpha to 0 over its
  life), `z`.

For an animator's drawing:

- `frames`: [columns, rows] — the texture is a flipbook. `cycles` plays it that
  many times over a particle's life (1 by default); `random_frame: true` gives
  each particle one frame at random instead.
- `blend`: `"add"` for light — a glow that brightens what is under it.
- `colors`: stops from birth to death, `#rrggbb` or `#rrggbbaa`, multiplied by
  the tint. Replaces `fade`.
- `size_over_life`: [at birth, …, at death], multiplying `scale`.

A drawing that does not divide into its grid, or a flipbook with no drawing,
is reported at load.

Bursts go on Feel's own layer above every screen, so they outlive the screen
being rebuilt, which happens on every action. At most 24 are alive at once.
They speed up with the game-speed setting.

## Card motion

```json
"jolt": { "kind": "shake", "amount": 4.0, "count": 4, "duration": 0.3 }
```

| `kind` | `amount` is |
|---|---|
| `pulse` | how much bigger it grows (0.06 = 6%) |
| `hop` | the same, with an overshoot |
| `shake` | degrees of rock, dying away over `count` swings |
| `tilt` | degrees it leans before coming back |
| `flash` | how much brighter it gets (0.35 = 35%) |
| `breathe` | the same as flash, **looping** for as long as the card is there |
| `keys` | not used — keyframes instead, below |

**Keyframes**, as an animator writes them:

```json
"pop": { "kind": "keys", "loop": false, "keys": [
  { "at": 0.0 },
  { "at": 0.08, "scale": 1.12, "bright": 1.4, "ease": "out" },
  { "at": 0.32, "scale": 1.0,  "bright": 1.0, "ease": "back" } ] }
```

`at` is seconds at 1x. `scale`, `turn` (degrees), `bright` and `alpha` are
RELATIVE to the card as it was when the motion started, so 1 / 0 / 1 / 1 is
"as it was". A value a key leaves out holds the previous key's. `ease` is how
the card arrives at that key: `linear`, `in`, `out`, `in_out`, `back`,
`elastic`, `bounce`, `snap`. The first key is a pose the card jumps to.

Every motion is a tween on scale, rotation or brightness, never on position:
the hand is laid out by containers, which would snap a card back. Each ends
exactly where it started, and `tests/test_feel.gd` measures that. `duration`
is in seconds at 1x game speed.

## Cards that animate on their own

`card_states` decide whether a card **in the hand** carries a looping motion
or a standing emitter while it sits there. The first rule that matches wins:

```json
"card_states": [
  { "id": "rare", "when": { "r": "rare" }, "particles": "shimmer", "color": "element" },
  { "id": "would_continue_the_line", "off": true,
    "when": { "affordable": true, "link": ["same", "turn"] }, "motion": "breathe" }
]
```

`when` holds field: value pairs that must all be true. A field is looked up in
what the screen knows about the card first, then on the card itself:

- `affordable`: it can be paid for right now;
- `link`: the link it would make if laid next (`same`, `turn`, `back`,
  `break`, `open`, `flat`, the words the ledger uses);
- `el`: its effective element;
- any field of the card: `r` (rarity), `pierce`, `exhaust`, `a` (archetype), `n`…

`true` means the field is set and not zero or empty. A list means any of these
values. Anything else must be equal.

**The second rule is switched off on purpose.** Making the cards that would
continue the line breathe is a real hint about how to play, and that is a
design decision, not a feel one. Remove `"off": true` to try it.

## The deal

A card drawn comes off the **deck on the table** — a pile of backs at the `deck`
spot in `room.json`, as thick as what is left to draw — face down, arcs over to
its place in the hand and turns over there. `deal` in `feel.json`:

```json
"deal": { "flight": 0.32, "flip": 0.16, "stagger": 0.08, "arc": 0.07 }
```

`flight` and `flip` are seconds, `stagger` the gap between one card and the
next in a hand dealt together, `arc` how high the card rises on the way, in
screen heights. The card's click and its rumble (`card_draw`) land as it turns
over. The back is `assets/art/ui/card-back.png` (`docs/ART_GUIDE.md`); until
it is drawn, `scenes/Deck.gd` draws a stand-in. The studio's MOMENTS tab has a
DEAL button that deals the card on show from a deck on its own table.

A card on its way is hidden by its WIDTH (`scale.x = 0`), never by its
visibility or its alpha: a hidden card would be left out of the fan's layout,
and the fan would jump; alpha is what `breathe` and `flash` drive. And a
container resets its children's scale every time it lays them out, so the
reading puts the cards still face down back to zero width after each layout.
`tests/test_scenes.gd` checks both.

## The player's hands

The two hands at the bottom of the reading move. `gestures` in `feel.json` are
keyframed like a `keys` motion, with their own values:

```json
"lay": { "hand": "right", "keys": [
  { "at": 0.0 },
  { "at": 0.12, "lift": 0.10, "turn": 6, "reach": 1.04, "ease": "out" },
  { "at": 0.34, "lift": -0.02, "turn": -2, "ease": "in_out" },
  { "at": 0.55, "lift": 0.0, "turn": 0, "reach": 1.0, "ease": "out" } ] }
```

- `lift`: up, in heights of the hands (0.1 is a tenth); negative is down;
- `turn`: degrees toward the cards, about the wrist, mirrored for the right hand;
- `reach`: finger length, 1 as drawn, 0.5 an open hand (1.1 at most);
- `spread`: how far the fingers fan, 1 as drawn;
- `hand`: `both` (the default), `left` or `right`; the other one keeps resting.

`rest` is what the hands do when nothing else is asked of them, and loops.
A moment starts a gesture with `"hands"`: `wall_absorb` flinches,
`card_lay` lays, `reading_resolve` offers. **A gesture starts and ends at rest**
— every value back to 0 or 1 — or the hands jump when it starts or stay lifted
after it; `tests/test_feel.gd` checks every one.

The hands keep the game's time: the speed setting and the studio's slow motion
both apply, and with motion off they hold still. The pose is kept by Feel, not
by the hands, because the reading rebuilds its hands every time a card is laid
— the new ones pick the gesture up where it had got to.

What the hands WEAR is in `marks.json` and `relics.json` (`on`, see
`docs/ART_GUIDE.md`); the studio's HANDS tab plays each gesture on hands
wearing one mark or all of them.

## The room remembers

Some cards, when laid, **become a thing in the parlour** and it stays there
for the rest of that visit: the tea turns into a cup on their side of the
table, steaming; their coat is carried to the hook by the door; the letter
burns and leaves its ash; the lamp is turned up and stays up. Kicking the
chair over rattles whatever is on the table. The next person to sit down finds
a clear table. Gentler than Inscryption's teeth and eyes, but the same idea:
the reading is the room as well as the cards.

It is all in `data/base/room.json`:

```json
"traces": [
  { "id": "tea", "when": { "n": "Pour The Tea" }, "becomes": "their_cup",
    "at": "their_side", "how": "melt", "once": true, "haptic": "tap" },
  { "id": "chair", "when": { "n": ["Kick The Chair Over", "Stand Up Mid-Sentence"] },
    "shakes": true, "haptic": "thud" }
]
```

- `when` matches the card, like `card_states`; the first rule that matches wins.
- `becomes` is a key of `props`, and `at` a key of `spots`, which are fractions
  of the screen chosen in the parts of the table the reading screen leaves
  clear. The studio's ROOM → EVERYTHING puts every thing down at once, which is
  how to see whether a new spot collides with one already there.
- `how`: `melt` (the card drifts to the spot and comes apart into steam),
  `burn` (the same, from its edges, in embers) or `carry` (it is carried there
  and becomes the thing as it lands). The card that comes apart is a copy of
  the card as it is drawn, so an illustrated card melts as illustrated.
- `once`: one of that thing per visit (their coat only comes off the once).
  Without it, a second of the same thing sits beside the first.
- `shakes`: nothing to become — the table rattles instead.
- `haptic`: a pattern from `feel.json`, felt when it lands.

`props` are drawn in code as placeholders (`draw`: `teacup`, `coat`, `cloth`,
`glow`, `ash`, `coins`, `stones`, `paper`) until a drawing lands at
`assets/art/prop/<id>.png` — a 512×512 transparent PNG, listed in the art
manifest like every other drawing. `size` is its height as a fraction of the
screen's, `anchor: top` hangs it from its spot rather than centring it (the
coat, from the hook), `tint: element` colours it by the sitter's element, and
`particles` is a `feel.json` preset left running on it (the steam off the tea).

What the room remembers is kept on the fight, so it is saved with it, TAKE IT
BACK takes it away with the card, and it is gone for the next person. Nothing
in the rules reads it.

## Haptics

```json
"knock": { "pulses": [[0.2, 0.8, 0.06, 0.12], [0.2, 0.8, 0.06, 0]] }
```

Each pulse is `[weak, strong, seconds, pause_after]`. `weak` is the
high-frequency motor (a tap, a tick) and `strong` the low one (a thud, a
swell); both run from 0 to 1 and are scaled by the player's strength setting.
Only the gamepad the player last touched rumbles, or every connected one if
they have not touched one yet. On a phone the single motor gets the stronger
of the two.

**Nobody has felt these yet.** They were written by numbers, and they need a
person holding a pad. SETTINGS → CONTROLS has a TRY IT button next to the
strength slider.

## What the player controls

| Setting | Where | Turns off |
|---|---|---|
| Particles | INTERFACE | every burst and standing emitter |
| Game speed: Instant | INTERFACE | particles **and** card motion (the reduced-motion setting) |
| Vibration, Vibration strength | CONTROLS | haptics; they do **not** follow game speed |

## A mod

The registries are `feel`, `particles`, `motions` and `haptics` (merged
key by key), and `card_states` (merged by `id`), so a pack changes one preset
without restating the others:

```json
{ "particles": { "shards": { "texture": "user://mods/my_pack/shard.png", "amount": 30 } } }
```

A texture in `user://` is read from its bytes, since Godot's importer never
sees a mod's files. A name that nothing defines, a motion kind that does not
exist, or a texture that does not load is reported once when the game loads,
and does nothing in play.
