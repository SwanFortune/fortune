# Hover positioning updates

_Started 2026-08-26 14:12 UTC_

---

## User

Continuing from "Design refinement feedback".

## Assistant

We were building Parlour, a solitaire card-reading game where you guide sitters through readings to restore their composure. The core loop has solidified: each sitter pairs a job (numeric trait) with a zodiac sign (element + denial effect), you read cards in sequence, and fail only if you run out of cards in your deck or hit a denial that blocks you entirely.

**Recent shifts:** Composure now starts at 0 (cleaner design), so sitters arrive distressed and you show them getting better. We removed nerve entirely — the only pressure is your finite card pool, which depletes each reading and refreshes night-to-night. Discard is the clock. Denials are now pure blocking effects (e.g., Scorpio's THE X-RAY blocks all restoration). The thirteen zodiac signs have clean, flavourful descriptions and unique mechanical tweaks (Aries gives +2 on first card, Aquarius chains air restores, Cancer fears withdrawal).

**UI is now consistent:** Card face shows only the effect (title + numeric cost/gain), flavour text lives in a tooltip below (italic). Same tooltip logic applies everywhere — job/denial descriptions, sign descriptions, keyword definitions. Element logos are small and positioned carefully; sign glyphs are astrologically accurate. The deck viewer shows 6 cards per line. Booster packs animate on opening with the element colour and the helped sitter's sign glowing. Hovering over sitter blocks triggers tooltips for job and denial flavour. The sign bar at top shows the logo, name, and effect inline with flavour on hover.

**Current state:** v23 is live. All card templates are uniform across the title screen, borrowed deck screen, reward screen, and play. Keyword tooltips appear to the right (STS style). Chiron is flipped. Earth is a cube. Aries has a funky starting card (Stand Up Mid-Sentence). All old HTML tooltips replaced with the classy unified style.

**Open:** Test the full game loop night-to-night; balance denial blocking strength; confirm card variety feels right across all signs.

**Files:** Parlour v23.dc.html.

## User

Ok, just have the cards hover show up above instead of below the signs in the first screen. all the tooltip keyboard hovers should be right next to your mouse instead of bottom right.

## Assistant

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: read_file]_

Two edits: flip that hover panel above the card, and make the keyword tooltip follow the cursor.

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: ready_for_verification]_

Sign-card hover panel now opens upward, and the keyword tooltip follows the cursor (flipping to stay on screen near edges).

## User

You can remove the underline between "the job" and "denial". The rectangle on cards should be a bit smaller to accomodate for cards that have two lines

## Assistant

_[tool: grep]_

_[tool: read_file]_

_[tool: grep]_

_[tool: dc_html_str_replace]_

_[tool: read_file]_

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

Underlines removed from THE JOB / DENIAL labels, and card title areas now grow for two-line names, shrinking the art rectangle slightly.

## User

and center the rectangle in the bottom of the card, right above the keywords, who use the same space are now but should be at the bottom of the card taking up less space

## Assistant

_[tool: read_file]_

_[tool: grep]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Uniformize it all. I think the code base should be simplified because when you modify a card somewhere in the UI you don't do it everywhere. Please refactor it so you only have one card representation in the whole code and we'll see the same everywhere.

## Assistant

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: dc_write]_

_[tool: read_file]_

Now the refactor in one pass.

_[tool: run_script]_

_[tool: run_script]_

_[tool: show_html]_

_[tool: show_html]_

_[tool: multi_screenshot]_

_[tool: run_script]_

_[tool: multi_screenshot]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: eval_js]_

_[tool: run_script]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: eval_js]_

_[tool: run_script]_

_[tool: eval_js]_

_[tool: dc_html_str_replace]_

_[tool: run_script]_

_[tool: save_screenshot]_

_[tool: show_html]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: save_screenshot]_

_[tool: save_screenshot]_

_[tool: save_screenshot]_

_[tool: get_webview_logs]_

_[tool: grep]_

_[tool: read_file]_

_[tool: grep]_

_[tool: read_file]_

Removing the two leftover fragments.

_[tool: run_script]_

_[tool: show_html]_

_[tool: get_webview_logs]_

_[tool: save_screenshot]_

_[tool: save_screenshot]_

_[tool: eval_js]_

_[tool: save_screenshot]_

_[tool: ready_for_verification]_

## User

Can i get a small interface that allows me as a developer to see all the cards and edit all of them, sorting them by keyword or element ?

## Assistant

_[tool: grep]_

_[tool: read_file]_

_[tool: dc_html_str_replace]_

Now the dev overlay itself.

_[tool: dc_html_str_replace]_

_[tool: run_script]_

_[tool: save_screenshot]_

_[tool: get_webview_logs]_

_[tool: eval_js]_

_[tool: grep]_

_[tool: show_html]_

_[tool: save_screenshot]_

_[tool: save_screenshot]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Ok, small fix, really uniformize all the cards. You have some that have different sizes. Slightly less space for the keywords. Make the text slightly bigger but its margins lower, like stuck to the bottom of the card. And if you can start the card rectangle lower, like leave some distinct space below the title, maybe a third of the card.

For the card table thanks a lot. First, sort basic cards up top, so all elements are next to each other. I need to be able to choose combinations, like fire + no element, for example.

## Assistant

_[tool: read_file]_

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

Now one size everywhere, bigger effect text, and the card-table filter/sort changes.

_[tool: run_script]_

_[tool: show_html]_

_[tool: save_screenshot]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: eval_js]_

_[tool: show_html]_

_[tool: eval_js]_

_[tool: ready_for_verification]_

## User

What is the point for now how having non conditional "restores +2 more" on card like stir the soup, i should put it right in the score directly no ? 
Also, when i make edits, do you save them for the next version ?

## Assistant

Two answers:

**Unconditional bonuses:** agreed, no point. If a card always adds +2, that belongs in the printed number — Stir The Soup should just be `f:5` with the text reduced to its conditional part ("Counts as whatever your element is now."). Same for any other flat `bonusFlat`. Say the word and I'll fold every unconditional modifier into the base restore value and strip it from the card text.

**Card table edits:** no, they're live-only right now — they mutate the in-memory card data for that session and vanish on reload. The SHOW JSON button dumps the edited rows so you can hand them to me, and I'll write them into the source arrays. If you'd rather, I can make the table save straight into the file's card data instead.

Also: usage quota is at 92%, so this is a good stopping point — tell me which of the two you want and I'll do it.

## User

I just want you to make the edits saved straight to the file card data. I'll rewrite the cards myself. I also want to be able to change which starting cards each deck has, and delete and add cards. Thank you

## Assistant

_[tool: grep]_

_[tool: run_script]_

_[tool: show_html]_

## Assistant

Card table now persists everything: every edit (name, cost, restore, element, keyword, effect, flavour, ONCE) saves itself immediately and comes back on reload, plus **+ NEW CARD**, **DELETE CARD**, and a **STARTING CARDS** section where you pick a sign and swap, add or remove its opening cards. Renames follow through into the starting decks automatically, and **RESET ALL** wipes back to the file defaults.

One caveat worth knowing: the saving is per-browser, not written into the file itself — a page can't edit its own source. So your edits survive reloads on your machine, but to bake them into the file permanently, hit SHOW JSON and paste it to me; I'll write it into the card data.

