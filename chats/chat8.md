# Card design improvements discussion

_Started 2026-08-24 22:34 UTC_

---

## User

Continuing from "Game balance and UI improvements".

## Assistant

We've been building Parlour, a roguelike deckbuilder where you read tarot for sitters across a night, managing nerve (your stamina) and their denial (shield that thickens) and spiral (deepening clock). Core mechanic is momentum — a directional multiplier chain around an elemental ring that lifts small cards over denial's floor.

**Current design state:**

- Four signs per element (▽ water, ◇ air, △ fire, □ earth). You pick one at start, get 7 neutrals, 2 of your sign, 1 borrowed. Three of your seven starter cards are free or energy-refunding (Coat, Hermit, Shuffle); Say Their Name costs 2 energy for 5 mend and is always heard.
- Spreads are four-card sentences, laid left to right with no reorder — you plan the full turn, then play it all at once. No ✕ button; said is said.
- Denial thickens by +2 per unhealed sitter (more for Cancer/Virgo). Pinpoint cards bypass it. Spiral is a clock: deepens each reading, resets when the next sitter knocks. Nerve lasts the whole night and carries between sitters; mended ones restore +8, back room +10 and raise your ceiling, new night resets to full.
- Nerve guard cards (Pour The Tea, Sit In The Silence −2; High Priestess, Let Them Say The Worst −3) and rarer heals (The Star +4, Hermit +3, Glass Of Water −1 per read). Base spiral is one point lower to survive 8 knocks.
- Nights are 8 encounters with rests at knock 3 and 6. Centimes: +6 per mended sitter, +3 per unmended.
- Card basics each have distinct hooks (sit +3 if first, cloth next +3, lamp +2 closer, top card draw 2, shuffle draw 1).

**Open:** Test whether nerve staying across fights is too generous; guards may already solve it. Check pacing over a few full nights.

**File:** Parlour v19.dc.html

## User

Let's give it a go and try to make this better. First, flavor text is good to have answers like that, but sometimes, they could have a surprise effect maybe ? Also, make some cards "exhaust", like for example don't set the table twice. Also, before going into designing, try to find some design flaws inside the logic. Also, I think the cycle would be more obvious if it followed the orders of the signs as they appear in the astrological calendar, so fire then earth then air then water.

## Assistant

_[tool: grep]_

_[tool: list_files]_

_[tool: grep]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

Copying to v20, then making the changes.

_[tool: copy_files]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: grep]_

_[tool: str_replace_edit]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: str_replace_edit]_

_[tool: ready_for_verification]_

**Parlour v20** is up (v19 kept intact).

Ring is now calendar order — △ fire → □ earth → ◇ air → ▽ water → back to fire. Opposites moved with it (fire/air, earth/water), and the "follows" cards that pointed at the old predecessor were repointed: Name The Feeling now wants □ before it, Give Them One Instruction wants ▽.

Exhaust: the room rituals and the once-only moves leave the deck for the rest of that sitter — Coat, Sit, Cloth, Lamp, Sit In The Silence, Check The Date, Cry A Little, Let Them Say The Worst, Promise A Date, Burn The Letter, Have It Out, High Priestess, Star, Emperor, Devil. The four setup basics got buffed to pay for being one-shot (Coat +2 energy, Sit +4 opener, Cloth +5 next, Lamp +4 closer). Cards read "ONCE ONLY" and the pile counter shows "SPOKEN FOR GOOD".

Surprise answers: roughly one reading in three, the sitter's line does something instead of just landing — they pace (spiral +1), give in (denial −3), push coins over (+4), pour for you (+2 nerve), name it themselves (denial −4), ask who reads for you (−2 nerve), ask you to just sit (+3 nerve), or admit they knew before knocking (spiral −1 for good). Two per element, shown as a separate violet line under the quote.

Flaws I found while reading the logic, and what I did about them:

- **Calm stacking was unbounded.** Sit In The Silence / Check The Date / High Priestess permanently lowered the spiral and could be replayed every turn until it hit zero — infinite nerve, guaranteed win. Exhaust fixes it; the spiral can now only be flattened once per sitter.
- **Extra-turn cards made fights unlosable.** Promise A Date and The Star each added a reading and could recur, so the turn limit never arrived. Both exhaust now. They also inflated the win bonus, since unused readings pay 4 faith each — that leak closes with them.
- **Wild cards double-dipped elements.** The Magician, The World and Ask Who Told Them That read as the sitter's element for momentum but still used their printed element for tattoo bonuses, so The World scored off a salt tattoo while playing as air. Now everything uses the read element.

Still open and untouched, since they're balance calls rather than bugs: overheal converts to faith with no cap, so one huge finisher pays better than a clean fight; and there's no limit on spread length beyond energy, so refund cards can push a reading past four cards even though the cross only has four slots. Say the word if you want either tightened.

## User

any ideas to flesh it out before v21 ?

## Assistant

A few directions, roughly in order of how much they'd add per unit of work:

**The sitter should push back mid-sentence.** Right now denial is a flat wall and the only feedback loop is the answer at the end. Give each sign one *interrupt* — a condition that fires while you're laying, not after. Aries interrupts the moment you play a second fire card ("I said I know"); Gemini flips the element you're carrying; Virgo raises denial the instant you repeat a sign. It turns the plan-then-speak turn into a read of their sign, which is currently only a passive modifier.

**The village between sitters.** You earn centimes and faith but the night has no texture between knocks. Two or three lines of consequence — a sitter you mended sends their cousin (a bonus sitter with lower denial), a sitter who came apart puts a rumour in the deck as a permanent scar card in your draw pile. Scars exist as tags now but don't touch the cards you hold.

**Cards that remember.** Exhaust is a one-way door; the mirror is a card that gets *better* the second night — Read For Yourself accumulating, Say Their Name mending more for a sitter you've read before. Cheap to build, gives the deck a history.

**A cost for the fourth card.** Four slots but energy is the only limit, and the last slot is always correct to fill. Make the fourth thing you say cost nerve instead of energy — the sentence that goes one beat too long. That's a real decision every turn and it does more for pacing than any number tweak.

**Boss sitters who cannot be mended, only heard.** The mayor, the priest — win condition is surviving N readings at a certain denial rather than filling the bar. One per night, at knock 8.

**Smaller things:** a discard/tell mechanic (throw a card away to see the sitter's next interrupt); denial that thins when you say nothing at all for a whole reading; the back room offering to burn a card permanently instead of healing.

If I were picking one, it's the interrupts — the signs are the most flavourful thing in the game and currently the least felt.

## User

Take the clean interface of the hand game of the version 10 and adapt it to the v20 gameplay, we want it clean and readable. Add hands that hold the cards and the rings will be directly on them. Objective is less and less text. Also, remove the text from the cards until passed on them. Remove every useless piece of information, but let it be accessible by hovering for example.

## Assistant

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

Substantial UI rework — building it as v21.

_[tool: run_script]_

_[tool: str_replace_edit]_

_[tool: show_html]_

_[tool: show_html]_

_[tool: save_screenshot]_

_[tool: save_screenshot]_

_[tool: run_script]_

_[tool: save_screenshot]_

_[tool: run_script]_

_[tool: show_html]_

_[tool: save_screenshot]_

_[tool: run_script]_

_[tool: show_html]_

_[tool: save_screenshot]_

_[tool: run_script]_

_[tool: show_html]_

_[tool: save_screenshot]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: show_html]_

_[tool: save_screenshot]_

_[tool: run_script]_

_[tool: ready_for_verification]_

