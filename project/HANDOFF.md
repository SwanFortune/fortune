# Parlour — handoff notes

Prototype: `Parlour v23.dc.html` (self-contained, opens in a browser).
Shared card renderer: `ParlourCard.dc.html`.

## Getting the data out

Open the prototype, click **CARD TABLE**, then the **HANDOFF** tab. It generates two
things from the live data, including any edits made in the table:

- `parlour-data.json` — every card, reader, sign, job, relic, mark, sitter, event,
  the element wheel, and the effect registry.
- `parlour-rules.md` — how a reading resolves, written out in order.

Copy both into the port repo. They are generated, not hand-maintained: regenerate
rather than edit.

## Where the rules live in the prototype

| Concern | Where |
| --- | --- |
| Effect registry (every `fx` key, one definition each) | `FX` |
| Card mechanical fields, as sentences | `EFFECTS` / `autoText()` |
| One reading, start to finish | `simulate()` |
| Element wheel and links | `NEXT`, `RING`, `linkOf()` |
| Headless auto-player, used for balance | `simFight()` / `simSweep()` |

`simulate()` is the single source of truth for scoring. The preview under the fan and
the actual resolution both call it, so a port only has to match that one function.

## Things a port should know

- Card text is generated from mechanical fields, never written by hand, unless the
  card carries `custom: true` — then the prose is authored and the generator leaves it
  alone. The **AUDIT** tab lists anything whose text disagrees with its mechanics.
- Edits made in the card table persist to `localStorage` under `parlour.cards.v2`.
  RESET ALL clears it and falls back to the values in the file.
- Composure starts at 0 and rises; the sitter leaves when readings run out.
- Card art is a deliberate empty rectangle in `ParlourCard.dc.html`, waiting on art.
