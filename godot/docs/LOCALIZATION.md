# Localization

The game ships English (the source language) and a partially-filled French
locale. Adding a language, or finishing French, means editing one JSON file —
no code changes.

## The short version

```
godot --headless --path godot -s tests/gen_locale_template.gd -- fr
```

That writes/refreshes `data/base/locale/fr.json` with **every** translatable
string in the game. Fill in the values, relaunch, pick the language in
Settings. Untranslated strings show English, so a half-finished locale is
perfectly playable.

## How the file is laid out

```json
{
  "_source": {
    "ui/BACK": "BACK",
    "card/pour-the-tea/n": "Pour The Tea",
    "card/pour-the-tea/fl": "It is for you as much as for them."
  },
  "locale_fr": {
    "ui/BACK": "RETOUR",
    "card/pour-the-tea/n": "Servir le thé",
    "card/pour-the-tea/fl": ""
  }
}
```

- `_source` is the English original, regenerated every time. **Don't edit
  it** — it's there so you can translate inside this one file without
  cross-referencing the data files.
- `locale_fr` is your work. An **empty string means "not translated yet"**
  and the game falls back to the English in `_source`. It does *not* mean
  "render nothing".

Two kinds of key:

| Key shape | What it is |
|---|---|
| `ui/<English text>` | Interface chrome. The English source text *is* the key. |
| `<kind>/<slug>/<field>` | Game content, addressed by the same slug ids the art manifest uses (`card/pour-the-tea`, `sitter/mme-perrot`, `sign/aries`, `element/fire`, `job/the-priest`, `mark/a-silver-ring`, `event/the-misdeal`, `reader/serpentarius`). |

Using the English text as the UI key (rather than a code like
`UI_BACK_BUTTON`) means call sites stay readable, there's no key registry to
keep in sync, and a missing translation degrades to correct English instead
of showing a raw identifier to the player.

## Regenerating safely

Re-run the generator whenever content or UI strings change. It:

- **preserves** every translation you've written;
- adds new keys as empty;
- **reports keys whose English source changed** since you translated them, so
  a stale translation can't quietly survive a rewrite of the original line;
- reports keys that no longer exist and were dropped.

## Current French status

Roughly 265 of 533 keys are filled: all UI chrome, all card names, sign names
and denial names, element labels, and reader names. **Deliberately left
empty** is the long-form prose — card flavor lines, sitter dialogue
(`brings`/`win`/`fail`), reader `line`/`rule`, and sign `rule` text.

That's not laziness about the remaining 250 strings; it's that they're the
game's authorial voice. The English was written to sound like it had *already
been translated from French* — a small French village, a fraud fortune-teller,
dry and melancholic. Machine-plausible French would read as a translation of
a translation and you'd end up rewriting all of it. Those lines want the same
person who wrote the English, writing them fresh in French.

The mechanical half — which is what has to be *correct* rather than *good* —
is done.

### Pronoun tokens

Sign rules, job traits and elite twists contain **pronoun tokens** the game
substitutes from each sitter's own pronoun at display time, so one sentence
reads correctly for a he, she or they sitter:

```
"{S} {is} already ahead of you. The first card of every reading restores nothing."
   →  "He is already ahead of you. …"   /   "They are already ahead of you. …"
```

The words come from `data/base/pronouns.json`, and `I18n.fill()` substitutes
them **after** translation — so a locale supplies its own pronoun words, under
the `pronoun/<key>/<token>` ids, and they show up in the generated template
like any other string. An unrecognised token is left visible as `{token}`
rather than dropped, so a typo is obvious instead of silently eating half a
sentence.

For French, the eight *pronoun* tokens (`S`/`s`, `O`/`o`, `P`/`p`, `R`/`r`)
are filled in: elle/il/iel and the reflexives. **The five verb-agreement
tokens are deliberately left empty** — `{is}`, `{es}`, `{has}`, `{do}`,
`{goes}` encode English singular-vs-plural agreement and have no French
equivalent, and `{P}`/`{p}` is a further trap: French possessives agree with
the *noun*, not the possessor, so son/sa is the same word regardless of who is
being talked about.

The practical consequence for whoever writes the French: **write French
sentences that don't rely on the verb tokens.** Conjugate directly and let the
sentence carry the pronoun — "Iel est déjà en avance sur vous" rather than
trying to reconstruct "{S} {is}". If you do want gendered agreement on
adjectives, the clean way is to add French-specific tokens to
`pronouns.json` (it's an ordinary moddable registry) and use them in the
French strings only; the English strings will never see them.

This is a real design decision rather than a mechanical translation, which is
another reason the prose strings are left for a human.

### Plurals — a known limitation

There is no plural-forms system. Strings that carry a count use the "(s)"
dodge — "%s record(s) in %s", "%s problem(s)", "%d card(s) changed" — which is
ugly but never *wrong* in either language, and the French translations follow
the same convention.

This is fine for English and French and will not stay fine forever: languages
with more than two plural categories (Polish, Russian, Arabic) cannot be served
by it at all. If one of those is ever added, the honest fix is a real plural
selector (a key per category, chosen by count) rather than more parentheses —
and the place to put it is `I18n.t()`, alongside `fill()`, since both are
"post-process the looked-up string" steps.

Watch for this when translating: a French string that inflects a noun or a past
participle after a number ("1 entrées", "1 cartes trouvées") is a bug, not a
style choice. Prefer a form that does not inflect.

## Adding a language

1. Add it to `LOCALES` in `autoload/I18n.gd` (e.g. `"es": "Español"`).
2. `godot --headless --path godot -s tests/gen_locale_template.gd -- es`
3. Add `"locale/es.json"` to the `files` list in `data/base/mod.json` — the
   loader only reads files a manifest lists.
4. Fill it in.

## Mods can translate too

A locale table is an ordinary content registry (`locale_fr`), merged by
ModLoader key-by-key like any other. So a mod ships translations — of its own
cards, or of the base game's strings — exactly the way it ships cards: a JSON
file with a `locale_fr` key, listed in its `mod.json`. It only needs to
include the keys it cares about. Higher-priority packs win, so a
"better French" mod is a thing someone can just make.

## Testing

```
godot --headless --path godot -s tests/test_i18n.gd
```

Checks that switching locale changes lookups, that untranslated strings fall
back to English rather than blanking or leaking keys, that locale data
arrives through the mod pipeline, and that the template covers every id the
game asks for at runtime. To *see* a locale:

```
xvfb-run -a godot --path godot -s tests/screenshot.gd -- read out.png 1.2 fr
```
