# Roguelike deckbuilder apprentissage

_Started 2026-07-27 00:41 UTC_

---

## User

Tu es un maître de game design de roguelike deckbuilder. Tu as des références comme Slay the Spire, Inscryption ou Balatro. Tu vas m'aider à voir comment apprendre le game design pour faire un jeu de ce style. Je travaille avec une amie dessinatrice, et moi je ferais le code, en utilisant mes compétences et l'IA

## Assistant

_[tool: questions_v2]_

## User

Questions answered:
- niveau: Zéro théorie, mais j'ai des bonnes idées de concept vu que je passe ma vie sur ces jeux.
- livrable: Un prototype jouable de deckbuilder minimal, commenté, comme support d'apprentissage
- code: Pas encore décidé — conseille-moi
- ambition: Jeu commercial Steam, 1-2 ans
- idee: Je pense qu'un concept fort qui mêle direction artistique et game design est primordial pour un roguelike. En plus d'avoir une boucle intéressante bien sûr. Donc dans l'idée, une bonne idée de gameplay avec un univers agréable, ça peut suffire. Pense Balatro ou Slay the Spire, ou même Inscryption. Ce sont des jeux excellents qui tiennent au game design et à son intégration dans le feeling du jeu.
- amie: À définir — j'aimerais des conseils sur la collaboration
- axes: Boucle de jeu et économie des tours, Design de cartes et synergies, Playtest et itération, Structure de run, méta-progression, débloquages
- differenciation: Je ne sais pas encore — aide-moi à trouver
- temps: 20
- langue: Anglais
- exemples: Oui, essentiel

## Assistant

_[tool: dc_write]_

_[tool: ready_for_verification]_

**The Deckbuilder Lab** — a playable 3-fight prototype ("ECHO") plus the reasoning layer around it.

- **Play first, read second.** Three fights, telegraphed intents, block/energy/draw, reward screens with a real skip option.
- The twist is **tone chaining** — match the previous card's tone and its Echo clause fires. It exists to demonstrate the method: add one axis of decision for one integer of state.
- Tweaks panel: energy, hand size, HP. Change one, replay, name the feeling. That loop is the whole job.
- Then: number-by-number teardown, a 12-week path at 20h/week, artist-collaboration ground rules (including the money conversation), and an inversion table for finding your own twist.

My stack call: **Godot 4 + C#**.

Two things I'd want next: your rough concept so I can prototype *your* twist instead of Echo, or a fill-in GDD + card-spec sheet your artist can work from.

## User

Found issues — fixing…

## Assistant

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

## User

Ok so, this is how I see things. Slay the Spire is like forcing the archetype with impeccable balance. The perfection is not only in the deckbuilding but how tight it is. Lots of the game is in pathing, potions, shops, etc... Around the deck. 
Balatro is for the autists, but also with ADHD.
Inscryption bends it backwards, the deckbuilding is almost secondary to the world-building and the story (which slay the spire contains none).
I say this because I feel like autistic people love these games.
To me, the best bet is to do something Balatro-like in that its simplicity and feeling makes it all. This gives equal parts to me and my artist, and we can both discuss and make it work together.
Automation, I feel, is rarely as good and satisfying. Your prototype was good but notes : 
Would be way more interesting to have the echo chain continue over turns. 
It feels too much like slay the spire and if it's too samey, won't be played when you can play the goat.

## Assistant

Sharp read. Building a second prototype around the Balatro-shaped structure — and a written argument for why that's the right bet for a two-person team.

_[tool: dc_write]_

_[tool: dc_js_str_replace]_

_[tool: ready_for_verification]_

## User

I'll be blunt. Continuo feels like balatro but shit. But what's good about Balatro is what you said. How easy to make and iterate it is. 
Fresco seems fun, but it also looks like a mindfuck to make. I'd like to see a prototype of that.
Metronome feels crazy as fuck but I'm not sure. I feel like rythm games and card games seem a bit hard to make together.

If I can give you an art direction, and also, I like the chain idea, if maybe it was not so central, I think it could be cool if it was astrology or elements based. Like, finding a way to make maybe cards be elements or astrological signs, and "jokers" be like Tarot cards ?

## Assistant

Blunt is useful. Dropping Continuo and Metronome — building Fresco with your astrology/tarot direction, and proving it's a small build.

_[tool: dc_write]_

_[tool: dc_html_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

## User

Ok, forget about the drawings going together or whatever, this feels really uninteresting. Let's pick a concept with this art direction which is simply explainable and can be crack like Balatro. Quick fast, easy to show and to get into. So same thing with cards and jokers but with signs and Arcana ? And then the story would be that you're stuck in an arcana/witch's den or something. But I need a concept that makes it click together like "oh yeah poker but with jokers", so... 
Also, I'd like some entity to be the enemys, but they could also just be portraits that talk to you and add like a debuff or twist to the thing. So it's not a fight like in a STS sense but not only numbers like Balatro.

## Assistant

Got it. The hook was missing. Here it is: **poker, but the hands are horoscopes — and you're bluffing a client who's sitting right across the table.**

_[tool: dc_write]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: dc_html_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

## User

Ok so, I think here's what to keep and what to change :
- The portrait of the character can be an endless excuse. What they say will be the meta-progression feeling in a way, like Hades. Slowly-drip feeding lore history after history.
- I think the story would be that you HAVE to keep the village together by fortune-telling correctly so society doesn't collapse. Each loss against each enemy would be like : The only electrician of the village died and with no lights, everybody eaten by wolves or something. Like spooky cute game, but every death feels different because you have failed society as the village's fortune-teller/psychologist. The fact that you're a fraud could make it hilarious.
- UI Wise, I love the idea of having your hands show and literally have cards up your sleeve as jokers (or potions if we do it STS like). 
- I'm not sure I like the ambiguity of the signs. I don't know if it being meaningless kills the feeling of connexion with the characters or whatever.

## Assistant

Good notes — especially #4. Fixing that properly: the villagers *are* signs, and what you read changes what happens to them.

_[tool: dc_write]_

_[tool: ready_for_verification]_

**Bad Fortune** — v2 with your four notes applied.

The important one was #4. Fix: **every villager is a sign.** Sylvie is an Aquarius, so Aquarius cards double for her and Leo cards *provoke* her (no Insight, big Conviction — telling someone what they don't want to hear is a valid play). The zodiac stops being wallpaper and becomes the cast list.

Second addition you didn't ask for but it follows: **the element you lead with picks the ending.** Pass Bastien with a fire-heavy spread and he burns the oldest hive; with water he finally buries his wife's hat. Four strings per villager, and it's the reason to replay someone you already beat.

Failure no longer ends the run — the village takes a specific wound you carry. Lights go out → hand size −1. Priest calls you a witch → everyone after needs 25% more belief. Three wounds and it collapses.

Hands and sleeve are placeholder-framed, not badly drawn — the fan is angled as if held, Arcana hang from a cuff.

## User

Found issues — fixing…

## Assistant

_[tool: run_script]_

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

## User

What's good : 
- Failing, the debuff feels fun, opportunities for lore. Also, after each spread, we can have lines for each character reacting to it.

What's bad : 
- Not having a card up my sleeve and having a debuff feels bad. The two should be decorrelated.
- Flair-wise, it feels like it should be inverted. You should have a deck of tarot cards to play, maybe minor and major tarot up your sleeve that you get sometimes after fights (like potions in balatro, one time use, limited slots). Then, when you win with a villager, you always choose a blessing that comes from its element (relics from sts2). Maybe they would be slightly buffed if you get the sun sign of the person. I don't know

## Assistant



## User

What's good : 
- Failing, the debuff feels fun, opportunities for lore. Also, after each spread, we can have lines for each character reacting to it.

What's bad : 
- Not having a card up my sleeve and having a debuff feels bad. The two should be decorrelated.
- Flair-wise, it feels like it should be inverted. You should have a deck of tarot cards to play, maybe minor, you get one after each fight, and major tarot up your sleeve that you get sometimes after fights (like potions in balatro, one time use, limited slots). Then, when you win with a villager, you get nothing but the absence of a debuff, but you still get to choose a minor card. Maybe they would be slightly buffed if you get the sun sign of the person. I don't know

## Assistant

Good split — decorrelating them fixes the real problem. Rebuilding the economy: Minors are the deck, Majors are consumables, rewards are unconditional.

_[tool: dc_write]_

_[tool: dc_js_str_replace]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: ready_for_verification]_

## User

The problem now is the balatro aspect. Keep everything, the up your sleeve (except slots when used can be refilled). The cards need to do something on their own, have their own effect, not be just score like in Balatro. I messed up when saying minor arcanes. Also, this should not be about scoring, in a way. Hmmm... It should really feel like you're the psychologist or the seer and you need to feel like you're making the right decision for the person.

## Assistant

Big pivot — that's the right instinct. Rebuilding the core: no scoring, you're diagnosing a person.

_[tool: dc_write]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

## User

Ok, in a way... This feels weird. Like a good concept forced into non fitting context. What is good : the cheats, but make them more scarce, like sts potions.
Secondly, this is not readable. 
Is there a way for it to be non scoring based, but something else ? Also being able to play more than 5 cards, but have sequences ? I don't know.

## Assistant

Right — v4 was a guessing game in a deckbuilder costume. Rebuilding around the sequence itself: no score, no hidden info, you walk a person from one state to another.

_[tool: dc_write]_

_[tool: ready_for_verification]_

**v5 — The Thread.** No score anywhere.

The villager is in a **state** — one word. Every Arcanum is a move: *Strength turns FRIGHTENED into READY.* You can only play a card if its left side matches where they are, so the reading is a **path**, and your deck is the set of paths you can walk. Sylvie comes in FRIGHTENED and must leave READY. Get there before patience runs out.

Why this fixes your three complaints:
- **Readable** — nothing hidden. Every card says what it does in four words, illegal cards are dimmed, the state map is on the right.
- **Sequence, not scoring** — cards chain by *necessity*, not bonus. A hand of five great cards can be five illegal ones.
- **More than five cards** — a reading is 4–8 long, and the laid line is the screenshot: `FRIGHTENED → The Moon → WATCHFUL → Strength → READY`.

Cheats are now proper potions: 2 slots, and you only earn one by finishing with patience to spare.

Your suit-chain from round one survives as the small economy — two of a suit in a row wins back a patience.

## User

Found issues — fixing…

## Assistant

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_set_props]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

Root cause: the transition graph is under-connected, and `wrongEnd` only checked the *destination*, not whether the destination can still reach the goal — so each patch just moves the dead end. Replacing it with a reachability check over your actual deck.

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: ready_for_verification]_

## User

So, i'd say great idea, terrible execution. Make it so the basic cards are like counseling, therapy for example. Like, they are... uninteresting shitty tarot cards in a way. And then each round you gain one major arcana that is really good, and not just a state change.

## Assistant

Right — the base deck should be dull on purpose. Making commons mundane counseling moves, and Majors the rare, rule-bending payoff.

_[tool: dc_write]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

Root cause: a RESOLVED state that isn't this villager's goal is a trap, and `canReach` treated the single wildcard `Blame The Weather` as a real exit. Fixing the rule, not the graph.

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

Root cause: every goal is two cards away against 6–10 patience, and the rails made bad plays impossible. Two decisive changes — deepen the graph so goals need three steps, and turn the rails into warnings you're allowed to ignore.

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: run_script]_

_[tool: run_script]_

_[tool: dc_set_props]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

Root cause: the prose in the document is the spec, and it was written against the pre-balance numbers — three strings now contradict the code. Syncing them in one pass (Nod stays a flat cost; its joke is that it does nothing, which the note now says).

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Ok so, two many cards in the base deck. Second, cards are too obvious and states too ? Like, maybe just remove that information but nudge your way into it

## Assistant

Right — strip the machinery off the surface. Fewer cards, no state words, and a notebook that fills in as you learn what each card does.

_[tool: dc_write]_

_[tool: snip]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

Root cause: LISTENING and TIRED never interconvert, so the single WATCHFUL fork is one-way — pick the wrong deepener and no goal is reachable. Connecting the two mid states.

_[tool: dc_js_str_replace]_

_[tool: run_script]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## User

Check didn’t complete

## User

Check didn’t complete

## Assistant

## User

Also, arcana should be added to the deck with other cards. Is there a way to make this game feel engaging and not like a solved thing you just do once ? By this I mean, make it cryptic at first, but actually be a balanced deckbuilding experience ? The idea is to make it a bit spooky but actually be engaging puzzle hands with repeatability.

## Assistant

Right — this is the repeatability problem. Fixing it at the cause: Arcana go in the deck, and each villager gets a **required detour** ("he will not find peace until he has been angry about it"), randomized per run, so there's no single memorized solution.

_[tool: dc_write]_

_[tool: snip]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

Root cause: the thread stores the card played but not where it landed, so undo recomputes the route and guesses wrong for Wheel of Fortune's random destination. Storing the resolved landing instead.

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: ready_for_verification]_

## User

Check didn’t complete

## Assistant

## User

Ok, let's start over. Firstly, this is not engaging, because it still feels like a fixed machine state. You need to feel the power creep, and I think this has to be numbers anyways, so this was maybe not a good idea for a deckbuilder. Let's keep the balatro scalability idea, and the story, and the theme. Still the same principle, but now it's all with scoring and combos on the cards. And you play a few cards each turn too, with energy still. They now have a HP bar that is like the amount of counsel they need. The elements could be tied to the combos, but still be cards with the same flavor, like serve tea, let them talk, etc... 
Maybe 4 arcanes or elements, which represent wellness/wellbeing, psychology, action and something else.

## Assistant

Rebuilding as a scoring deckbuilder: energy per turn, spreads that score, four schools that combo, and counsel totals that scale like Balatro antes.

_[tool: dc_write]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

Scaling the fan overlap to hand size so it always fits the column.

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

## User

Ok, so now remake the schools with elements. Water is emotion, Fire is reckless action, Earth is stability and materiality and Air is the last one that I forgot. Also, on the shown hands, there would be rings, or tattoos, or scars, that would be like permanent buffs akin to relics in sts2. Up your sleeves would still be one time use like options. Combos need to be important, but you need to be pushed by the procedurality of the sun sign of the person that comes. When she drops a card, it will be buffed if it's the same school/element

## Assistant

_[tool: dc_write]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: dc_html_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: snip]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

Making the lift negative (cards rise) and giving the strip clearance.

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

## User

Ok, good, feels better but : 
- Tattoos or rings should be obtained through quests or events like STS2. 
- Always show cards at the end, but give a bonus twist if it's the sun sign's element of the person, should appear once every 3 times.

## Assistant

Marks move to between-reading events, and reward cards can now come blessed under the sign.

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

Now the render values and the event panel.

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: dc_html_str_replace]_

_[tool: ready_for_verification]_

## User

Found issues — fixing…

## Assistant

_[tool: dc_html_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: dc_js_str_replace]_

_[tool: snip]_

_[tool: ready_for_verification]_

Done. Marks now only come from village events (every second reading, two choices, usually with a price like the next villager needing more counsel), and reward screens are always three Arcana with a ~1-in-3 chance one arrives blessed under the departing villager's sign — permanently stronger.

