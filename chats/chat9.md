# Character portrait and card reading

_Started 2026-08-25 04:47 UTC_

---

## User

Continuing from "Card design improvements discussion".

## Assistant

We were refactoring Parlour's UI for clarity and gestural readability — moving from text-heavy v20 to the cleaner hand-based interface from v10, adapted to the current v20 gameplay (calendar-ordered ring, exhaust cards, surprise answers, all interrupts and momentum intact).

**What we did:**

- Repositioned the elemental ring directly onto the player's hand, rotating through calendar order (fire → earth → air → water). Cards sit in hand with no text visible until hovered.
- Stripped all card text from the board; tooltips on hover reveal full details, mechanics, and exhaust status. Sitter's denial, spiral, and mend bar stay visible but minimal.
- Removed redundant UI layers — no deck counters, no separate element tabs, no verbose logs. The spread itself (four slots, left to right) is now the only sentence.
- Kept the surprise answer mechanic and interrupt system live under the hood but invisible until they trigger.

**Open questions:**

- Interrupt feedback: when Aries blocks a second fire card or Gemini flips your element mid-spread, how should that land visually? We need a clear signal that the sitter pushed back without breaking the clean aesthetic.
- Fourth card nerve cost: should it have a visual tell (grayed out, or a small nerve indicator on the slot)?
- Hover density: are tooltips enough, or do we need a legend mode for first play?

**Files:** Parlour v21.dc.html (v20 and v19 kept as reference).

## User

Ok, now fix the hand that is fucked up, and also add a portrait of the character to the left. Remove the momentum completely, and rework for it to have the person only say one sentence at beggining and end. When the reading is done, our character will mumble the words on the cards to make a reading. The portrait of the character will emote according to the score of the card, but will not say a sentence until after it is transformed and gives you a card.

## Assistant

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: show_html]_

_[tool: get_webview_logs]_

_[tool: show_html]_

_[tool: multi_screenshot]_

_[tool: multi_screenshot]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: multi_screenshot]_

_[tool: multi_screenshot]_

_[tool: get_webview_logs]_

_[tool: show_html]_

_[tool: multi_screenshot]_

_[tool: ready_for_verification]_

## User

Ok now put the title of the card on top, and the energy top left, and the mend top right. If the mend is modified by anything, a combo whatever, change the color of the number. When you hover over a card, you get in the bottom part the description that appears. If there is a keyword on the card, it should be bolded, and when hovered, will show the description in a tooltip next to the card. Faster readings of sentences, and only mumble the most important word, like "...tea...top card... THE MOON" Use the bottom left space for informations for now about your character, the run, and like menu button for example.

## Assistant

_[tool: run_script]_

_[tool: multi_screenshot]_

_[tool: show_html]_

_[tool: multi_screenshot]_

_[tool: multi_screenshot]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

Widened the fan's scale budget so the rotated hands stay inside the column — no more sideways scroll.

Heads up: I'm at the usage limit for this session. Everything from this turn is saved in **Parlour v22.dc.html** (card face, keyword tooltips, fast single-word mumbles, portrait + run panel). Say the word if you want me to keep going.

## User

Number instead of dots for energy. Need to see how much cards in discard pile and in draw pile and in exhaust piles. This is where the "once" cards go. If a card has a keyword, write it instead of showing a logo, and have an appropriate color. Cards with elements have a whole color of the element, not just a logo.

## Assistant

_[tool: run_script]_

_[tool: multi_screenshot]_

## Assistant

_[tool: grep]_

_[tool: show_html]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Ok, now make once blue, and give all the other keywords other colors. Make sure you can't have multiple times the same person per night. From the agenda, we can always choose one normal fight, sometimes an elite, sometimes a shop, sometimes an event (choice out of 2, max 4). Show Draw and Discard instead of to draw and spent. Put it left and right of the hand so it makes sense to go from left to right.

## Assistant

_[tool: grep]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

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

Found issues — fixing…

## Assistant

Root cause: the two hand wrappers sit at `z-index:45`, above the cards' 10–14 stacking band, so the palms paint over the outer cards' keyword rows.

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Instead of no sign, just have it be a white card like it is. Also, make the cards consistent so in the menus and card select, they look like they do in the g

## Assistant

_[tool: grep]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: read_file]_

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: ready_for_verification]_

Signless cards now read as plain white faces with no label, and the reward/shop/event cards use the same face as the hand: energy top-left, mend top-right, title, keyword row (element · archetype · ONCE), bolded keywords in the description.

