# Game balance and UI improvements

_Started 2026-07-31 02:50 UTC_

---

## User

Continuing from "Card game mechanics brainstorm".

## Assistant

We've been building Parlour, a roguelike deckbuilder where you read tarot for sitters across a night, trading mend (HP) output for enemy composure. The core mechanic is momentum — a directional multiplier chain around an elemental ring.

**Current design state:**

- Four signs per element (▽ water, ◇ air, △ fire, □ earth), with glyphs on cards and everywhere else. You choose a sign at the start, getting 10 cards: 7 neutral whites (no sign, no combo), 2 of your sign, 1 borrowed from an adjacent sign (Neow-style pick).
- Momentum climbs when you step forward around the ring, holds when you repeat, halves when you go backward, breaks when you hit the opposite. Whites carry momentum through unchanged.
- Multiplier curve is flat: ×1, ×1.2, ×1.4, ×1.6, ×1.8.
- Six archetypes visible on cards: digging, switch, pinpoint, channel, salve, plus no label for plain cards. Each has a tooltip on hover.
- Fights are now longer (hand 5, energy 3, reduced base mend). Sitters sit ~28–30 composure with denial 5–8 and 7–8 readings per night.
- Enemy denial and spiral are now color-solid blocks on the bar (violet for denial, red for spiral underneath), much more readable. Denial swallows your output; spiral takes back at night end.
- Cards carry StS rarity pips (common/uncommon/rare), weighted so rarer cards are stranger. Rewards roll on win: three offers weighted toward the mended sitter's sign, rare chance for signless Arcana.
- Six archetypes (digging, switch, pinpoint, channel, salve) + no-label plain cards. Hover tooltips on each.
- Sitters have pronouns (4 she / 4 he / 1 they). Card text, crosses, and all flavor text are templated through pronouns.
- Three extra signs (Gemini, Taurus, Scorpio) are unlockable later; currently all four are open for testing.

**Open:** Balance testing. Need to play a few nights and report whether chained reads feel clearly better than flat ones, and if the pacing feels right.

**File:** Parlour v19.dc.html

## User

Mana is not enough scarce resource because basic cards are free too much. A night should be 8 encounters/shops, so make more. I think maybe, it would be cooler to not fill the middle card, and only be able to play four ? Also read the middle one last, which could instead show the scoring and why. This is where the info should be. Also when doing sentences, please remove the "beneath", etc... Just do the sentence.

## Assistant

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

Done — the heart now shows per-card lines once, then the aggregate (gross → denial → composure → spiral).

Changes in v19: four spoken positions with the heart as the scoring readout (left preview panel and chain strip removed, since that info lives there now); sentences read plainly with no "beneath/above all" lead-ins; free cards cut to three that hand something back (coat, silence, hermit) with the rest at 1 and strong uncommons at 2; nights run 8 knocks with breathers at knocks 3 and 6, gentler per-knock scaling, boss at night 3's last knock, and end-run tiers rescaled.

## User

I'm not sure about the cross now. What about... Letting people place them where they want, and like reaarrange but have no fixable max cards except for energy. Also still too many free cards. Have 1 that costs 2 from the base element cards

## Assistant

_[tool: read_file]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

The cross is gone. Cards now lay in a line left to right — click from hand to say it, ◀ ▶ to move it in the sentence, ✕ to take it back (dimmed on draw cards, which can't be undone). No card limit; energy is the only ceiling.

Free cards are down to two that hand energy back (Take Their Coat, The Hermit), and Say Their Name is now the 2-energy basic at 6 mend.

## User

The problem is that denial and spiral are a bit similar, any idea of different flavors ? Also, basic cards should have more flavor to differenciate them.

## Assistant

_[tool: grep]_

_[tool: run_script]_

_[tool: grep]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

**Denial** is no longer a tax — it's a floor. Any single card that comes to less than it ("under 5") isn't heard at all; it mends nothing. Momentum is how you lift a small card over the line, and pinpoint cards ignore the floor entirely. So denial is now a puzzle about card size, while **spiral** stays the accelerating clock — and the two now interact: every card they didn't hear deepens the spiral by 1.

Basics each got their own hook instead of being interchangeable filler: coat (free, +1 energy), sit (+3 if first), cloth (next card +3), shuffle (draw 1), lamp (+4 if last), name (2 energy, 6, always heard), top card (draw 2).

## User

Ok so lamp too stronk, lower data, the floor is a bad idea because it feels really bad. Maybe spiral should just damage you and denial be the shield that gets bigger ?

## Assistant

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

The two are properly different now:

**Denial** is their shield — it holds off the first points of every reading and thickens by 2 each time they sit through one (more for Virgo/Cancer), so a sentence that worked once stops working. Pinpoint cards go straight past it.

**Spiral** doesn't touch their composure at all — it comes out of your nerve, deepening each reading. Nerve resets when the next one knocks, so it's the clock on how long you can stay with one sitter; run out and they let themselves out in whatever state you left them. Rest's twenty minutes now buys +3 nerve permanently. Lamp is down to +2 closer, and Say Their Name to 5 mend.

## User

Ok so now, centimes every fight, non movable cards, once you play it you play it for ease of UI and understanding, just plan your turn. I don't know if spiral is better than a nerve that is lasting through fights. some cards can protect your nerve or more rarely heal it.

## Assistant

_[tool: run_script]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: grep]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: grep]_

_[tool: run_script]_

_[tool: ready_for_verification]_

All four in:

- **Said is said.** No reorder, no take-back — the spread just fills left to right, so the whole turn is planned before you speak.
- **Nerve lasts the night.** It carries sitter to sitter; a mended sitter gives +8 back, the back room +10 and +2 to your ceiling, a new night restores all of it. Sitter spiral base is a point lower so the arithmetic survives 8 knocks.
- **Nerve cards.** Guard (Pour The Tea −2, Sit In The Silence −2, High Priestess −3, Let Them Say The Worst Of It −3) and the rarer heals (The Star +4, The Hermit +3), plus a new boon, A Glass Of Water (−1 every reading).
- **Centimes every fight** — +6 when they go home mended, +3 when they don't.

Worth a couple of nights to check nerve isn't now too generous, since it only ever goes down by 2–4 a reading with guards in the deck.

