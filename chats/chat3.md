# Map tree and evening recap

_Started 2026-07-29 20:26 UTC_

---

## User

Continuing from "Balatro card scoring balance".

## Assistant

We've been building **Parlour**, a counselor deckbuilder where you score by dissolving false beliefs instead of matching numbers. The core shift from v11: villagers arrive with a lie (prose clauses like "the wiring is faulty") that you contradict by playing cards into a five-card cross. Overkill on one clause hardens the others, making long chains risky — the tension is routing, not accumulation.

The format is the appointment book: three nights, each an eight-hour ledger. You book your own route through callers, regulars, elites, the apothecary, events, rest nodes, and rival readers. Time is a visible resource; after 01:00 you tire and lose hand size.

Key decisions made: free placement in the cross (not sequential), effects trigger on play, links compute at READ IT, no knots or percentages. Signs are behavioural constraints (Aries tightens her own clause, Taurus wastes a card, Libra rejects lopsided advice). Arcana are earned only from the villager's blessed sign; minor cards split into four archetypes tied to elements — Air (intellect: mirroring, naming), Water (feeling: tea, silence, hands), Fire (action: burn, say it, tonight), Earth (material: palms, coins, the calendar).

Current state: v12 is playable end-to-end. The lie model is live, free placement works, adjacency feeding is in, the four card archetypes are sketched, and the hour ledger is rendering.

Remaining: tune the clause weights so overkill feels punishing but not unfair, playtest the sign constraints against the new lie system, flesh out the card copy so every card reads as an imperative the fortune-teller speaks, and balance apothecary costs against mark rewards.

Files: Parlour v12.dc.html

## User

Ok, the tree feeling should be shown better on the map. You must feel clearly that you are putting away a choice by choosing something else. No walk past. We need something special each night, at the end, like a phone calling, which is kind of a recap that would add lore, and kind of a big bonus that is more rule-bending, like boss relics. Also, harder balance, seems impossible to lose now.

## Assistant

## Assistant

## Assistant

## Assistant

## Assistant

## User

Ok, the tree feeling should be shown better on the map. You must feel clearly that you are putting away a choice by choosing something else. No walk past. We need something special each night, at the end, like a phone calling, which is kind of a recap that would add lore, and kind of a big bonus that is more rule-bending, like boss relics. Also, harder balance, seems impossible to lose now. Capricorn bricks the game if you have no money, just add debt in these cases.

## Assistant

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: copy_files]_

_[tool: run_script]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: str_replace_edit]_

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

_[tool: read_file]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Ok, firstly graphically the tree is still not correct, it should feel like paths that you can and cannot take, but make sense with eachother, to justify it being an agenda and not a map. Other problem, do not discard the unplayed cards. The other problem is still the struck things, does not feel organic enough, the thing about the lie, hmmm... We need yet another way of scoring. Align in the UI the feeding aspect into each other. There is something missing in the card loop. Also put the UI with the hands and the relics on it like before please. Keep the telephone.

## Assistant

_[tool: read_file]_

_[tool: read_file]_

_[tool: grep]_

_[tool: read_file]_

_[tool: copy_files]_

_[tool: run_script]_

_[tool: run_script]_

Now the template: agenda routes, cross gutters, sticky hand + relics bar.

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

Ok, now color code the cards by elements, also when you see the deck. and also make the graph a bit more visually graphic. Then, when you get a card at the end of a fight it c an be from any element BUT if the element of the card matches the element of the sign of the person, then you get a blessed arcanum instead

## Assistant

_[tool: read_file]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Ok this scoring system is fucked because you can brick your game very easily. So the arrows have to go, or they Have to be bidirectional. If not, air and earth can never be buffed, which is bad design. Then again, you should be able to win with a deck of the wrong color, it should just be less obvious/advantageous. So let's find a balance here. You can propose ideas of scoring, but the scoring can be a bar or whatever but it needs to be something that's not just like a puzzle game if you just need the right color.

## Assistant

_[tool: copy_files]_

_[tool: grep]_

_[tool: read_file]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: read_file]_

_[tool: run_script]_

_[tool: ready_for_verification]_

