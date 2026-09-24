# L'atelier — guide pour qui dessine et anime Parlour

Ce guide est pour toi si tu dessines, animes ou fais des effets pour le jeu.
Tu n'as besoin d'écrire aucune ligne de code. Tu déposes des images dans des
dossiers, tu changes quelques nombres dans deux fichiers texte, et tu regardes
le résultat **dans le jeu, en direct**.

Les guides détaillés, en anglais, sont `docs/ART_GUIDE.md` (les images) et
`docs/FEEL_GUIDE.md` (les effets). Celui-ci est le mode d'emploi.

---

## 1. Lancer l'atelier

1. Installe **Godot 4.7** : c'est un seul fichier, à télécharger sur
   <https://godotengine.org/download>. Rien d'autre à installer.
2. Ouvre le dossier `godot/` du projet dans Godot (bouton *Importer*, puis
   choisis `godot/project.godot`) et lance le jeu (▶ en haut à droite).
3. Dans le jeu : **ATELIER**, sur le menu principal (ou **CRÉDITS → ATELIER**).

Pour arriver directement dans l'atelier à chaque lancement, en ligne de
commande :

```
godot --path godot -- --studio
```

### Les deux vues : travailler, jouer

Le jeu a deux visages, et **F12** passe de l'un à l'autre sur l'écran où tu es.

- **La vue atelier** : les boutons ATELIER, BIBLIOTHÈQUE et MODS, les réglages
  de travail, la version du build. Un petit « VUE ATELIER » dans le coin
  rappelle qu'on n'est pas dans ce que voit un joueur.
- **La vue joueur** : le jeu, et rien sur la façon dont il est fait.

Les cartes jouent exactement pareil dans les deux ; seul ce que les écrans
proposent change.

Lancé depuis Godot, le jeu s'ouvre dans la vue atelier. `-- --play` ouvre
directement la vue joueur. Sur un build exporté, envoyé à quelqu'un, l'atelier
est caché : on l'ouvre en composant **3615 ATEL** sur le Minitel du jeu. Ensuite
il reste disponible sur cette machine, et F12 marche. Un joueur qui ne compose
jamais ce code ne voit rien de tout ça.

## 2. Ce que fait l'atelier

En haut, une rangée de boutons :

| Bouton | Ce qu'il fait |
|---|---|
| **MOMENTS** | Chaque moment du jeu (une carte posée, une carte qui traverse le mur, le verdict…) sous forme de bouton. Il se joue sur une vraie carte, et on fait défiler les 56 cartes avec ◀ ▶. Les réglages du moment s'affichent en dessous. |
| **CARTES EN MAIN** | Les cartes qui s'animent toutes seules en main (une carte rare qui scintille…), chacune sur un exemple. |
| **LA PIÈCE** | Ce que devient chaque carte dans la pièce (voir la partie 6) : appuie sur une règle pour voir la carte se transformer en objet sur la table. |
| **IMAGES** | Les 87 images dont le jeu a besoin : cartes, consultants, voyantes, objets. Pour chacune : comment elle rend aujourd'hui, si elle est faite, et le **nom exact du fichier** attendu. Appuie sur une vignette pour copier ce nom. |
| **RALENTI** | Tout passe au quart de la vitesse, pour regarder une animation image par image. |
| **RÉPÉTER** | Rejoue le dernier moment en boucle pendant que tu règles. |
| **CRÉER LES GABARITS** | Écrit des feuilles vierges aux bonnes tailles (avec la grille des planches d'animation) et ouvre le dossier. |

**L'atelier surveille les fichiers.** Enregistre un PNG ou une modification
de `feel.json` : l'écran se recharge tout seul dans la seconde, avec le nom
du fichier qui a changé en vert. Pas besoin de relancer.

## 3. Les images

| Quoi | Taille | Où l'enregistrer |
|---|---|---|
| Illustration de carte | **768 × 576**, paysage | `assets/art/card/<nom>.png` |
| Portrait (consultant ou voyante) | **768 × 1024**, portrait | `assets/art/sitter/<nom>.png` ou `assets/art/reader/<nom>.png` |

Le `<nom>` est celui que l'onglet **IMAGES** copie pour toi : minuscules,
tirets, sans accents (`pere-renaud`, `pour-the-tea`). Toute l'image est
affichée, rien n'est recadré ni dessiné par-dessus. Une carte se voit en
petit dans la main (environ 106 × 79), donc une silhouette claire vaut mieux
que du détail.

Pour que le jeu prenne l'image, ouvre `data/base/art_manifest.json`, trouve la
ligne de ton image et passe `"status": "missing"` à `"wip"` (en cours) ou
`"final"` (terminée). C'est la seule chose à changer.

## 4. Animer une carte ou un portrait

Deux façons, au choix, selon ce que ton logiciel exporte :

**Un dossier d'images numérotées.** C'est ce que Krita, Procreate ou Aseprite
exportent quand on demande « les images une par une ». Crée un dossier au nom
de l'image, sans `.png`, et mets-y les images :

```
assets/art/card/pour-the-tea/0001.png
assets/art/card/pour-the-tea/0002.png
assets/art/card/pour-the-tea/0003.png
```

Elles passent dans l'ordre de leurs noms, 2 avant 10 comme on compte. Rien à
déclarer d'autre que le statut.

**Une planche (sprite sheet).** Toutes les images côte à côte dans le PNG
habituel, en grille. Chaque case est à la taille normale (768 × 576 pour une
carte, donc 3072 × 1152 pour 4 × 2 cases). Dans le manifeste, ajoute la grille :

```json
"card/pour-the-tea": { "status": "wip", "frames": [4, 2], "fps": 12, ... }
```

Dans les deux cas : `"fps"` règle la vitesse (12 par défaut), et
`"loop": false` joue l'animation une fois puis s'arrête sur la dernière image.
`"count": 7` sert quand la dernière rangée d'une planche n'est pas pleine.
Garde des animations courtes (8 à 24 images) : chaque image pèse en mémoire.

## 5. Les effets : particules, mouvements, vibrations

Tout est dans **`data/base/feel.json`**, un fichier texte qu'on ouvre avec
n'importe quel éditeur. Il a quatre parties.

**`feel`** relie chaque moment à ses effets :

```json
"card_pierce": { "particles": "shards", "color": "element", "motion": "jolt", "haptic": "thud" }
```

**`particles`**, les gerbes. Pour mettre ton dessin à la place du point flou
provisoire, dépose un PNG dans `assets/particles/` et nomme-le dans `texture` :

```json
"shards": { "texture": "eclat.png", "amount": 16, "lifetime": 0.5, ... }
```

- une particule **blanche** sur fond transparent prend le mieux la couleur de
  l'élément ;
- **une planche animée** : `"frames": [4, 2]` (colonnes, rangées) ;
  `"cycles": 2` la joue deux fois pendant la vie d'une particule, ou
  `"random_frame": true` donne à chaque particule une image au hasard ;
- **une lueur** : `"blend": "add"` éclaire ce qui est dessous au lieu de le
  couvrir ;
- **les couleurs au fil de la vie** : `"colors": ["#ffffff", "#ffb060", "#80200000"]`
  (une étincelle qui refroidit et s'éteint ; les deux derniers chiffres sont
  l'opacité) ;
- **la taille au fil de la vie** : `"size_over_life": [0.4, 1, 0]` (naît
  petite, grossit, disparaît).

**`motions`**, les mouvements de la carte elle-même. Les plus simples ont un
type (`pulse`, `hop`, `shake`, `tilt`, `flash`, `breathe`) et une amplitude.
Pour animer comme dans un logiciel d'animation, utilise des **images clés** :

```json
"pop": { "kind": "keys", "keys": [
  { "at": 0.0 },
  { "at": 0.08, "scale": 1.12, "bright": 1.4, "ease": "out" },
  { "at": 0.32, "scale": 1.0,  "bright": 1.0, "ease": "back" } ] }
```

`at` est le temps en secondes. `scale` (taille), `turn` (degrés), `bright`
(luminosité) et `alpha` (opacité) sont **relatifs** à la carte au départ :
1 = inchangé. `ease` est la courbe pour arriver à cette clé : `linear`, `in`,
`out`, `in_out`, `back` (dépasse et revient), `elastic`, `bounce`, `snap`.

**`haptics`**, les vibrations de la manette. Chaque impulsion est
`[faible, fort, durée, pause]` : *faible* est le petit moteur (un tic), *fort*
le gros (un choc sourd), de 0 à 1. Branche une manette et teste avec
**PARAMÈTRES → COMMANDES → ESSAYER**.

**`card_states`**, les cartes qui s'animent seules en main. La première règle
qui correspond l'emporte. Une règle avec `"off": true` est désactivée ; elle
est montrée dans l'atelier pour qu'on puisse en juger.

## 6. La pièce se souvient

Certaines cartes, une fois posées, **deviennent un objet de la pièce** qui
reste là jusqu'au départ du consultant. Le thé devient une tasse fumante de
son côté de la table, son manteau part au portemanteau près de la porte, la
lettre brûle et laisse sa cendre, la lampe reste allumée. Renverser la chaise
fait trembler ce qui est sur la table.

Tout est dans **`data/base/room.json`** :

- **`traces`**, les règles : quelle carte (`when`) devient quel objet
  (`becomes`), où il atterrit (`at`) et comment il y va (`how`) :
  - `melt` : la carte glisse vers sa place et fond en vapeur ;
  - `burn` : elle brûle par les bords, en braises ;
  - `carry` : elle est emportée jusqu'à sa place.

  `once: true` veut dire un seul par visite. `haptic` est la vibration à
  l'arrivée.
- **`props`**, les objets. Chacun est dessiné en code en attendant ton dessin :
  un **PNG carré de 512 × 512, fond transparent**, dans
  `assets/art/prop/<nom>.png` (l'onglet IMAGES → OBJETS donne les noms).
  `size` est sa hauteur à l'écran. `anchor: top` le suspend par le haut (le
  manteau au crochet). `particles` laisse un effet sur lui (la vapeur du thé).
- **`spots`**, les places sur la table, en fraction de l'écran.

Dans l'atelier, l'onglet **LA PIÈCE** montre chaque règle. Appuie dessus :
la carte apparaît et se transforme sous tes yeux. **TOUT** pose tous les objets
d'un coup (pratique pour voir si la table est trop chargée), **DÉBARRASSER**
vide la table.

## 7. Si quelque chose ne s'affiche pas

- Un nom de fichier qui ne correspond à aucune image attendue, une taille
  différente de celle demandée, un statut « terminé » sans fichier : lance
  `godot --headless --path godot -s tests/test_art.gd`, il nomme le problème.
- Dans `feel.json`, un nom d'effet qui n'existe pas, une texture introuvable
  ou une planche qui ne se découpe pas juste sont signalés au lancement du jeu,
  dans la console de Godot, en commençant par `[Feel]`.
- Une virgule en trop ou oubliée dans un fichier JSON le rend illisible :
  l'éditeur de texte de Godot ou <https://jsonlint.com> la montrent.

Rien de tout ça n'empêche le jeu de tourner : une image absente reste le
dessin provisoire actuel, un effet absent ne fait rien. On peut livrer une
pièce à la fois, dans n'importe quel ordre.
