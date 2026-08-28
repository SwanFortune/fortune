# Healing deckbuilder roguelike

_Started 2026-07-30 03:48 UTC_

---

## User

Can you do v17 and just do something more like combat based or score based. The feeling would still be the text and the tarot reading, but you need to "heal" someone with a hp bar. I can't find a way to design deck synergies that work with displacement or whatever. It's not a puzzle game, it's a roguelike deckbuillder

## Assistant

## User

Can you do v17 and just do something more like combat based or score based. The feeling would still be the text and the tarot reading, but you need to "heal" someone with a hp bar. I can't find a way to design deck synergies that work with displacement or whatever. It's not a puzzle game, it's a roguelike deckbuillder

## Assistant

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: read_file]_

Building v17 as a combat/heal model — HP bar, spiral drain, denial shield, overheal banking to score.

_[tool: dc_write]_

_[tool: ready_for_verification]_

## User

The balance is still fucked up, I can't play archetypes like this. Maybe just have elements as archetypes that can tell a sequential story, and put cards in a cross shape, but not have so many gameplay elements tied to the cross

## Assistant

Reworking v17: the cross is now just story order, and all the scoring lives in the element sequence (momentum) instead of positions and feeding.

_[tool: dc_write]_

_[tool: ready_for_verification]_

## User

Check didn’t complete

## Assistant

## Assistant

## Assistant

_[tool: show_html]_

_[tool: ready_for_verification]_

## User

Check didn’t complete

## Assistant

_[tool: get_webview_logs]_

## Assistant

## Assistant

Verification service is overloaded, but the page loads with no console errors. v17 is live.

Changes: the cross positions are now only the order you speak in — no positional elements, no arm feeding, no heart bonus. All scoring runs through **momentum**: each card that stays in its element or steps to a neighbour on the ring climbs the multiplier (×1 → ×1.4 → ×1.8 → ×2.3 → ×2.8); jumping to the opposite element resets it. Her element is just a flat +3, so archetypes (mono-element depth, ring-walking sequences, pierce-burst, faith-banking) stay playable against anyone. A chain strip above the cross shows each link and the running multiplier, and card bonuses read as "+6 if it follows feeling" instead of position rules.

