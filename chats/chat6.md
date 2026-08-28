# Card game mechanics brainstorm

_Started 2026-07-30 18:21 UTC_

---

## User

Continuing from "Healing deckbuilder roguelike".

## Assistant

We've been reworking v17 as a roguelike deckbuilder with a healing/HP combat loop instead of a puzzle mechanic. The core insight: you couldn't design clean synergies around displacement, so we pivoted to momentum-based scoring tied to element sequences.

Current design:
- The cross layout is now purely narrative (the order you speak cards in), not mechanically gated.
- All synergy lives in the **momentum chain**: each card matching or stepping to an adjacent element on the ring climbs a multiplier (×1 → ×1.4 → ×1.8 → ×2.3 → ×2.8). Jumping to the opposite element breaks it.
- The enemy has a flat +3 per card, so it's not an archetype lever—keeps all playstyles viable.
- A chain strip above the cross shows live multiplier tracking.
- Card bonuses now read as "+6 if it follows feeling" (element continuity), making the rule language clearer.

We removed positional feeding, heart bonuses, and arm mechanics—they were cluttering the synergy space.

The page loads clean with no console errors. The verifier timed out but the build is live and playable.

Next steps: test whether momentum chains create distinct archetype feels (mono-element depth, ring-walking sequences, pierce-burst strategies, faith banking). If the loop still feels flat, we may need to add card-text effects that *reward* specific chain states, rather than trying to bake it into position.

File: Parlour v17.dc.html

## User

I think we are onto something. Denial and Spiral are nice as they represent like blocks and permabuffs, other ideas around that before we iterate ? Change heal to mend, and also you only have "she" characters, they should exist of all genders. Now to make common archetypes of all cards ? Should the starting deck already have elements ? I don't know where to go, what do you think ?

## Assistant

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: grep]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

what did you do ?

## Assistant

v18 is live (v17 untouched). Two changes:

**Mend, not heal** — every "heals/heal" in card text, marks, previews, and labels now reads "mends". Internal `healLabel` → `mendLabel`.

**All genders** — sitters now carry their own pronouns and every line about them is templated through one `fill()` helper. So the cross labels ("BEHIND HER / HIM / THEM"), "SHE/HE/THEY ANSWER TO · THEIR SIGN", the coat line, quirk rules, answer lines, win/lose headers, and reward copy all agree with whoever is at the table. Card names went neutral so they work for anyone ("Hold Their Hand", "Read Their Palm", "Weigh What They Brought"), and card text that referenced the sitter's spiral now says "the spiral".

Cast rebalanced: Sylvie Aubert → **Aurel Aubert** (they/them, electrician), Ilse Marchand → **Ambroise Marchand** (he), plus a new sitter **Odile Vasseur, the clockmaker** (she — four minutes fast since March). Now 4 she / 4 he / 1 they, boss still he.

Your three open design questions I did *not* build — they need a decision from you:

**More Denial/Spiral-family enemy mechanics.** The pattern you liked is "a number that eats your output" (Denial) and "a number that grows against you" (Spiral). Others in that family worth trying: **Composure cap** — the bar's ceiling drops each reading, so late damage is worth less (punishes slow ramp); **Guard** — one element is walled off entirely tonight (forces route changes on the ring, interacts hard with momentum); **Echo** — repeating the same card name in one night does nothing the second time (anti-mono-deck); **Patience** — they only accept N cards per reading, so wide 5-card crosses aren't always right.

**Card archetypes.** Yes — I'd give every card exactly one archetype tag and print it on the face, so a deck's plan is visible: *deepener* (rewards staying in element), *turner* (rewards the ring step), *piercer* (ignores denial), *banker* (faith instead of composure), *engine* (draw/energy), *quieter* (spiral control), *risk* (big number, deeper spiral). Right now those behaviours exist but are invisible.

**Starting deck elements.** Currently your 15 starters span all four elements, which means turn one you can build momentum by accident and never learn the rule. I'd start you in **two adjacent elements only** (water + air, say) — you learn "stay or step" immediately, and the reward screen's "one step along the ring" offer becomes the real growth decision.

## User

Ok, the archetypes need to be written in small and mostly descriptory. Words could be : 
- Digging instead of deepener
- Switch instead of turner
- Pinpoint instead of piercer (to ignore denial)
- Channel instead of engine and banker, merge them.
- Meds instead of spiral control ? I don't know
- risk, not used, more like an archetype for fire.

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Starting deck elements, let's do just the one. First one, aries, fire, two fire cards, 8 cards total. Then you can have starting decks of each element being represented by different characters. Let's go.

## Assistant

_[tool: run_script]_

_[tool: grep]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

Fixed the four stray gendered lines the verifier caught (two starting-deck cards, the water legend, and the fire legend's antagonist).

v18 now has: mend language throughout, pronoun-templated sitters (4 she / 4 he / 1 they + boss), seven archetype tags on every card with a legend, and the Aries reader — 8 cards, 2 fire, 3 each neighbour, no water.

Adding the other three readers is one data block each now; say the word and I'll write Cancer (water), Libra (air), and Taurus (earth) plus a choose-your-sign opening screen.

## User

yeah but do scorpio, gemini and taurus, they will be unlockable laters but dictate your two basic cards and one passive. Let's go. Remember me the 7 archetypes ? Feels like too much

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Things that went wrong :
- Basic deck still is made up of cards with elements. Basic deck should be 10 cards : 7 of them "neutral" even if they can be vaguely based on elements like they are now, but give no combo, just a similar vibe, these are white.
- 2 of them in the sign of the bearer, one of them on the sign that feeds its sign, or that it signs feeds, for flavor, i don't know. This one could be chosen like a neow relic at the beggining of STS2.
- First enemy came as scorpio - material. This can't happen, remove the second keywords. Signs are synonyms of categories of things. Intellect is air, feeling is water, action is fire, and earth is material. But don't write those, just write signs, and write them in the color of the element with a small element logo on it.
Cards should also have small logos of elements on them.
- When an enemy is beaten, card is random and if the random finds the element of the person you just mended, you get an arcana of the sign. You can also rarely get arcana that has no sign. Cards have rarities like STS, with increasing rarity, and speciality, but not necessary strongness, it's to open more interesting combos.
And that went well : 
Feels cool to choose your sign. We just have to lock the other ones in the next version.
Spiral and Denial feel good for now, but they have to be graphic on the bar with different colors. Less text and more visuals please.

## Assistant

_[tool: run_script]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: grep]_

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

## User

Answer my questions in text and what you did

## Assistant

**The 7 archetypes, since you asked to be reminded:** digging (rewards staying in one sign), switch (rewards the step along the ring), pinpoint (ignores denial), channel (gives back cards/energy/coin/faith instead of composure), salve (quiets the spiral), timing (cares where in the sentence it falls, or buys a reading), straight (no trick, just a number).

You're right that it's too many. **Straight** isn't an archetype, it's the absence of one — I'd drop the label from those cards entirely and let a blank space mean "plain". **Timing** is only 4 cards and overlaps with what the card text already says. Cutting both gets you to 5 real ones: digging, switch, pinpoint, channel, salve. Say the word and I'll do it.

**What I did in v19** (v18 preserved):

Starting deck is 10 — 7 whites, 2 of your sign, 1 borrowed. The whites are manners with no sign (Take Their Coat, Say Their Name, Light The Lamp…) and they now *carry* the thread: they don't climb momentum but they never break it, and they pass the last sign forward, so fire → white → fire still counts as staying in it. The 10th card is a Neow-style choice at the start: one card from the sign that feeds yours, or the one yours feeds.

Signs are element-consistent now. Full zodiac, 3 per element, and a sitter can only wear a sign of their own element — no more Scorpio/material. The second keyword (feeling/intellect/action/material) is gone everywhere; signs show in their element colour with a glyph (▽ ◇ △ □), and glyphs are on every card face, in the ring, and in the "follows ▽" bonus conditions.

Rewards roll instead of being fixed: three offers, weighted toward the mended sitter's sign, and landing on their sign can turn up an Arcanum of it — signless Arcana are rare. Cards carry StS-style rarity (basic / common / uncommon / rare) as a small pip next to the archetype, weighted so rarer cards are stranger, not just bigger.

Denial and spiral are on the bar now: green fill, violet hatch for what denial swallows, gold hatch for what this reading puts back, red segment for what the spiral takes back. Readings left are pips. The two paragraphs of explanatory text under the bar are gone.

Still to do, per your note: lock the three extra signs (currently all four are open via a tweak so you can test them).

## User

When you hover over an archetype of cards, it should show a small description. "straight" is removed, when it's nothing it's nothing. Denial and spiral are unreadable. Balance and logic : momentum is upped when cycling through elements, and kept when using the same element. Lost when using opposite element and divided by 2 when used the element before. Now, make most fights longer, so hand size 5 energy 3 and less damage, and also diminish the exponential curve for now, too easy

## Assistant

_[tool: run_script]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

what did you do ?

## Assistant

_[tool: update_todos]_

Todos recorded. Here's what I did this turn, all in **Parlour v19.dc.html**:

**Momentum logic rewritten to be directional.** The ring now runs one way (▽ → ◇ → △ → □ → ▽). Going forward climbs a step. Repeating the same sign *holds* momentum where it is instead of climbing. Going back against the ring halves it. The opposite sign still wipes it. Whites carry it along unchanged. The curve is flatter too — ×1, ×1.2, ×1.4, ×1.6, ×1.8 instead of running to ×2.8.

**"Straight" is gone.** Those cards now show no archetype word at all, and the empty label is skipped entirely rather than rendering a blank. The six remaining archetype words carry a hover description.

**Denial and spiral made readable.** The bar is solid colour blocks now instead of overlapping hatches: green composure, a violet block for what denial swallows, a gold block for what this reading puts back, and the spiral as a separate solid red bar underneath, aligned to the stretch it will take away. The chip swatches match the bar exactly.

**Longer fights.** Hand size 5, energy 3. Every card's base mend came down about 30%, and the flat adders came down with it so they stop dominating the small numbers — your element gives +1, the sitter's sign +2, the Aries opener +2. Sitter ceilings went back up (night-1 sitters sit around 28–30 composure) with denial at 5–7 and 7–8 readings available, so the clock is denial and spiral rather than running out of turns.

Legends, card texts, and sign rules were all updated to match the new numbers and the glyph vocabulary.

Balance is the open question — I've tuned it twice this turn against measurements, but you should play a few nights and tell me whether a chained reading feels clearly better than a flat one.

