# Canon — Clara's words in the game

This file holds every Line in the game that is quoted from Clara's story
"Amy and the Rain Forest", byte for byte, including her spelling, in story
order. It is the reference the canon test checks against.

Terms are as defined in the [glossary](../GLOSSARY.md). How to write and
approve new Lines in her voice is in the [style guide](style-guide.md).

## The rule

1. **Canon Lines are locked.** Nobody changes a canon Line, its spelling,
   its punctuation or its capitals, unless Clara says so, and then only in
   a PR the owner approves that edits this file and the content together.
2. **A Line is canon when it is made only of Clara's words, whoever
   speaks it**: either an unchanged excerpt of her text ("Exact") or one
   of the adaptations listed below ("Adapted"). A Line that mixes her
   words with game text is split into a canon Line and a game Line. Any
   new adaptation needs Clara's approval.
3. **Tier 1 tests check canon byte for byte.** Every Line marked `canon`
   in content (`src/content/chapters/<n>/data.luau`) must match a row of
   the "Canon Line" column below, with the same Quest, Dialogue, Speaker
   and order, and every row must be in content as a canon Line.
   `tests/lune/content/Canon.spec.luau` checks this, and checks the other
   Lines against the Game Lines table the same way;
   `tests/lune/content/CanonGolden.spec.luau` checks every row is shown in
   the walkthrough's
   [golden file](../../tests/fixtures/golden/walkthrough.json). In every
   table here the Line is the only backticked text in its row.
4. **Never "corrected".** Spell checkers, formatters and translation must
   not touch canon Lines, which is why automatic translation stays off
   (see the [release checklist](../RELEASE_CHECKLIST.md)).

## Decisions

| Date | Decision |
|---|---|
| 2026-10-08 | The owner corrected Clara's "vilage" to "village" throughout the game, in canon and game Lines alike. Every other spelling of Clara's stays exactly as written. The published text quoted at the end of this file is unchanged, because it records her page as it is. Applied to StoryData in PR #17. |
| 2026-10-09 | The owner approved splitting canon Line 9 into a canon Line and a game Line (rule 2). The player sees the same words in the same Dialogue, now as two Lines. The golden walkthrough's one message for that Dialogue was edited to match; the engine walkthrough on CI verifies it. |

## Canon Lines

"Dialogue" is which of the Quest's Dialogues holds the Line. The
"Adapted" Lines split one of Clara's sentences across Lines or change its
joining word; they were written that way with the game and are kept as
they are.

| # | Quest | Dialogue | Speaker | Canon Line, byte for byte | Relation to Clara's text |
|---|---|---|---|---|---|
| 1 | chapter1.ask_dad | intro | Narrator | `One beautyfull sunday, Amy asked to go outside.` | Adapted: her sentence continues "— her dad said"; the Line ends it with a full stop. |
| 2 | chapter1.ask_dad | dialogue | Dad | `No, it to Dangerous because of the huge rain forest.` | Exact. |
| 3 | chapter1.sneak_out_1 | outro | Narrator | `She tryed to go out side but thier dog Sam always brought her back in.` | Exact. |
| 4 | chapter1.sneak_out_2 | outro | Narrator | `She tryed again but Sam brang her back.` | Exact. |
| 5 | chapter2.walk_to_forest | intro | Narrator | `One day when her dog was out at a farm, Amy managed to get outside.` | Exact. |
| 6 | chapter2.walk_to_forest | outro | Narrator | `Then suddenly a dark forest loomed infront of her.` | Exact. |
| 7 | chapter2.enter_forest | outro | Narrator | `As soon as she went in Amy saw it was a world parallel to thier own!` | Exact. |
| 8 | chapter2.enter_forest | outro | Narrator | `It was a bautyfull paradise!` | Exact. |
| 9 | chapter3.meet_squirrel | intro | Narrator | `Amy discoverd so many animals!` | Exact. Split from a mixed Line on 2026-10-09; see Decisions. |
| 10 | chapter3.rush_home | intro | Narrator | `She rushed Home...` | Adapted: the start of her sentence, ending in "..."; it continues in the next canon Line. |
| 11 | chapter3.tell_mum | dialogue | Narrator | `...and told her mum who told her dad who told the village.` | Adapted: continues "She rushed Home"; her sentence goes on "— who made", the Line ends with a full stop. |
| 12 | chapter4.stand_in_front | intro | Narrator | `The village made a giant tree-chopping machine and they decided to chop down the forest because they thought it was a thret to humankind.` | Adapted: her text reads "who made"; the Line starts "The village made". |
| 13 | chapter4.explain | dialogue | Narrator | `Lukily Amy managed to stop them by staying in front of it just long enugh to explain to them that they should be proud of it and take care of it.` | Exact. |
| 14 | chapter4.explain | dialogue | Narrator | `They took her seriously and stoped.` | Exact. |

## Game Lines, not canon

Every other Line in the game, in story order. These were written for the
game, in Amy's, Dad's, Mum's, the animals' or the Narrator's voice. They
can be edited under the [style guide](style-guide.md); they are never
checked against Clara's text.

| # | Quest | Dialogue | Speaker | Game Line, byte for byte | Note |
|---|---|---|---|---|---|
| 1 | chapter1.ask_dad | dialogue | Amy | `Dad, can I go outside? Please? It's the most beautiful Sunday there has ever been!` |  |
| 2 | chapter1.ask_dad | dialogue | Amy | `But Dad--` |  |
| 3 | chapter1.ask_dad | dialogue | Dad | `No buts, Amy. Nobody from the village ever goes near those trees. And besides... Sam is watching you.` |  |
| 4 | chapter1.ask_dad | dialogue | Narrator | `By the garden gate, Sam the dog tilted his head and thumped his tail. He was ALWAYS watching.` |  |
| 5 | chapter1.sneak_out_1 | intro | Amy | `Hmph. 'Too dangerous.' I'll just have a tiny little look. What Dad doesn't know can't worry him...` |  |
| 6 | chapter1.sneak_out_1 | outro | Sam | `WOOF!` |  |
| 7 | chapter1.sneak_out_1 | outro | Amy | `Saaaam! Let go of my jumper! Fine. FINE. I'm going.` |  |
| 8 | chapter1.sneak_out_2 | intro | Amy | `Okay. New plan. Tip-toes this time. Sam can't hear tip-toes. Nobody can hear tip-toes.` |  |
| 9 | chapter1.sneak_out_2 | outro | Sam | `Woof woof!` |  |
| 10 | chapter1.sneak_out_2 | outro | Amy | `You are the best guard dog in the whole world, Sam, and it is EXTREMELY annoying.` |  |
| 11 | chapter2.walk_to_forest | intro | Amy | `No Dad. No Sam. Just me, the grass, and... oh my. THAT.` |  |
| 12 | chapter2.walk_to_forest | outro | Amy | `The trees are like a giant wall... they're holding hands so nobody can get in. But look -- there's a little gap. Just my size.` |  |
| 13 | chapter2.enter_forest | intro | Amy | `She decided to explore the unexplored world. That's me. I'm the she. Here goes nothing...` | Quotes Clara's sentence "She decided to Explore the unexplored world." with "Explore" lower-cased, inside a game Line. Not canon because it is not byte-identical. |
| 14 | chapter2.enter_forest | outro | Amy | `The colours! The flowers are singing... no wait, that's birds. no, wait. it might be the flowers.` |  |
| 15 | chapter3.meet_squirrel | intro | Narrator | `Something maroon was hopping between the roots...` | Split from canon Line 9; see Decisions. |
| 16 | chapter3.meet_squirrel | dialogue | Amy | `A squirrel! A MAROON squirrel! You're the colour of my nanna's favourite cardigan.` |  |
| 17 | chapter3.meet_squirrel | dialogue | Squirrel | `And you're the first human I've ever seen! Are all of you this leafless?` |  |
| 18 | chapter3.meet_squirrel | dialogue | Amy | `You can TALK?!` |  |
| 19 | chapter3.meet_squirrel | dialogue | Squirrel | `Everything talks on this side of the trees. You just have to come in and listen.` |  |
| 20 | chapter3.meet_fox | dialogue | Fox | `Ooooh, a visitor. I'm sorry about the squirrel. He says 'leafless' to everyone.` |  |
| 21 | chapter3.meet_fox | dialogue | Amy | `You're the orangest fox I have ever seen. You look like a sunset with a tail.` |  |
| 22 | chapter3.meet_fox | dialogue | Fox | `Thank you! We take very good care of our colours here. The forest looks after us, and we look after the forest.` |  |
| 23 | chapter3.meet_lion | dialogue | Amy | `A lion. A golden lion. Right. Be brave, Amy. He probably had a big breakfast.` |  |
| 24 | chapter3.meet_lion | dialogue | Lion | `Peace, little explorer. No one is eaten in the paradise. It is against the whole idea of a paradise.` |  |
| 25 | chapter3.meet_lion | dialogue | Lion | `You have seen our world now, Amy. When you go home... tell them what you saw. Tell them the truth about us.` |  |
| 26 | chapter3.meet_lion | dialogue | Amy | `I will. I promise. Mum is NOT going to believe this!` |  |
| 27 | chapter3.tell_mum | dialogue | Amy | `MUM! The rain forest isn't dangerous, it's a paradise! There's a maroon squirrel and an orange fox and a golden lion and they TALK!` |  |
| 28 | chapter3.tell_mum | dialogue | Mum | `A golden... lion? That talks? Oh Amy. WAIT until your father hears about this.` |  |
| 29 | chapter3.tell_mum | dialogue | Narrator | `But the village did not hear 'paradise'. The village heard 'LION'.` |  |
| 30 | chapter4.stand_in_front | intro | Amy | `No no no no NO. Not my paradise. Not my friends. MOVE, legs!` |  |
| 31 | chapter4.stand_in_front | outro | Narrator | `Amy planted her feet in the grass, right between the whirring blade and the giant trees, and did not move.` |  |
| 32 | chapter4.stand_in_front | outro | Amy | `STOP! Everybody just... STOP!` |  |
| 33 | chapter4.explain | dialogue | Dad | `Amy! Get away from there, it isn't safe!` |  |
| 34 | chapter4.explain | dialogue | Amy | `It IS safe, Dad. I've been inside. It isn't a threat -- it's a paradise, a whole world parallel to ours!` |  |
| 35 | chapter4.explain | dialogue | Amy | `There's a squirrel the colour of nanna's cardigan, and a fox like a sunset, and the golden lion is GENTLE, Dad. Nobody is eaten in a paradise. It's against the whole idea.` |  |
| 36 | chapter4.explain | dialogue | Amy | `You shouldn't be scared of the forest. You should be PROUD of it. We should take care of it!` |  |
| 37 | chapter4.explain | dialogue | Dad | `...Proud of it. Well. I suppose it IS the biggest, greenest thing any village ever had.` |  |
| 38 | Ending | Ending | Narrator | `The great machine rolled backwards, away from the trees, and its terrible blade went still.` |  |
| 39 | Ending | Ending | Narrator | `And from the very top of the giant trees, a maroon squirrel, an orange fox and a golden lion watched the girl who saved their world.` |  |
| 40 | Ending | Ending | Dad | `Alright, alright. But next time you explore a parallel universe, young lady... you take the dog.` |  |
| 41 | Ending | Ending | Sam | `Woof!` |  |
| 42 | Ending | Ending | Amy | `Deal.` |  |

## Titles that borrow Clara's words

These are not Lines, so the canon test does not cover them, but they come
from her text, keep her spelling, and change only with her say-so.

| Where | Text | From |
|---|---|---|
| chapter1 card subtitle | One Beautyfull Sunday | "One beautyfull sunday", in title case |
| chapter2 card subtitle | The Unexplored World | "the unexplored world", in title case |
| Ending card title | The end ♥ | her last line, exactly |

## Clara's story as published

For reference: the full text of the story as published on Clara's story
page (linked from the [README](../../README.md)), retrieved 2026-10-07, with
its paragraph breaks. Two of its sentences are not in the game yet:

- "She decided to Explore the unexplored world." (Amy paraphrases it in
  game Line 13.)
- "There wos a maroon squirrel, an orch fox and a golden lion."

> One beautyfull sunday, Amy asked to go outside — her dad said "No, it to Dangerous because of the huge rain forest." She tryed to go out side but thier dog Sam always brought her back in. She tryed again but Sam brang her back.
>
> One day when her dog was out at a farm, Amy managed to get outside. Then suddenly a dark forest loomed infront of her. She decided to Explore the unexplored world. As soon as she went in Amy saw it was a world parallel to thier own! It was a bautyfull paradise!
>
> Amy discoverd so many animals! There wos a maroon squirrel, an orch fox and a golden lion. She rushed Home and told her mum who told her dad who told the vilage — who made a giant tree-chopping machine and they decided to chop down the forest because they thought it was a thret to humankind. Lukily Amy managed to stop them by staying in front of it just long enugh to explain to them that they should be proud of it and take care of it. They took her seriously and stoped.
>
> The end ♥
