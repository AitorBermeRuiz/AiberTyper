# Glossary

AiberTyper is typing practice: the user types quotes from a collection and gets a score for each round. Use these names in code, docs and commits.

## Texts

**Collection**:
A named set of quotes in Spanish and English, built in or loaded from a file the user imports.
_Avoid_: pack

**Quote**:
The unit a collection holds and a round picks whole: one or more sentences, typed in a single go. The UI calls it "frase".
_Avoid_: sentence, text, phrase

**Source**:
Who said or wrote a quote and where: author and work. Every quote in a built-in themed collection has one; in the General collection and in user collections it may be missing.
_Avoid_: author, reference

## Practice

**Round**:
One attempt at a text made of quotes: what has been typed, every keystroke and the live score. It is forgotten once it ends; only its round result is kept.
_Avoid_: test, session, game

**Round result**:
A finished round as kept in the history: date, language, WPM, accuracy and seconds.
_Avoid_: score, attempt

**History**:
Every round result, in every language and collection.

## Score

**WPM**:
Correct characters typed per minute, divided by five. Mistakes, even corrected ones, add nothing.
_Avoid_: speed

**Accuracy**:
The share of keystrokes that were right, counting mistakes the user later corrected.

**Recent WPM**:
The average WPM of the last 10 round results in the history, in any language. It sets how long the next round is.
_Avoid_: average, mean

**Record**:
A round result whose WPM beats every earlier round result in the history, in any language.
_Avoid_: best, personal best
