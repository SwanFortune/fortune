# Spiral scaling and character redesign

_Started 2026-08-25 14:17 UTC_

---

## User

Continuing from "Character portrait and card reading".

## Assistant

We were polishing Parlour's card-reading UI from v20 to v22—moving away from text-heavy design toward a clean, gestural interface with a portrait character that emotes and mumbles readings.

**What we've built:**

- Hand rotates through a calendar ring (fire, earth, air, water); cards face down, reveal on hover with tooltips for keywords and mechanics.
- Character portrait on left emotes based on card score; speaks only at start and end of reading, then mumbles key words during the spread ("...tea... top card... THE MOON").
- Card faces standardized: title top, energy (number) top-left, mend top-right (color-shifts if modified by combos). Keywords bolded as colored tags (ONCE = blue, others assigned colors). Elements fill the whole card background, not just logos.
- Bottom-left panel shows draw pile, discard pile, exhaust pile counts, plus run info and menu. Left/right of hand shows "Draw" and "Discard" slots for flow clarity.
- Agenda system: choose one normal fight per night, occasional elites/shops/events (max 4 total, choice of 2). No duplicate encounters per night.
- Signless cards render as plain white faces with the same layout as others.
- Fixed z-index layering so keyword rows don't hide under hand wrappers.

**Current state:** v22 is live with all UI elements positioned, colored, and responsive. Card tooltips and keyword descriptions are wired. Portrait and mumble timing work.

**Open:** The face-select and reward/shop menus should mirror the hand card design — we've standardized the faces themselves, but haven't confirmed menu consistency yet.

**Files:** Parlour v22.dc.html (reference v20, v19, v21 available).

## User

Scaling for spiral is too brutal. Let's say now that a character is a job and the sign. The job defines its problems, the sign defines how its denial works. Signs and jobs's effect need to be visible. The denial should be reworked accordingly as the equivalent of boss blinds in Balatro, depending on the sign.

## Assistant

_[tool: grep]_

_[tool: grep]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: copy_files]_

Now the data model: signs become named denials, jobs get visible traits.

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

Now the fight setup and turn start:

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

Now the scoring pass:

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

v23 is live. What changed:

**Spiral** — deepens by 1 every *second* reading instead of every one; night-to-night growth slowed (was /8, now /12), and signs no longer stack extra spiral.

**A sitter is a job and a sign.** The job sets the numbers and one table effect (postman: +1 energy; gravedigger: +1 reading; priest: first reading free; butcher pays 3 a reading; etc). The sign sets their element and their denial.

**Denial is now a boss-blind.** Twelve named ones, one per sign — e.g. Aries THE HEAD START (first card mends nothing), Leo THE AUDIENCE (readings under three cards mend nothing), Gemini THE CHANGED SUBJECT (a card leaves your hand each reading), Scorpio THE X-RAY (no card pays its condition), Taurus THE COLD SHOULDER (the old numeric wall), Pisces THE TIDE (wall starts at nothing, thickens 4). Only the wall signs carry a denial number now.

Both are visible in two places: labelled JOB / DENIES YOU panels on the map card before you let them in, and a persistent strip under the composure bars during the reading.

