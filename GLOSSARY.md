# Glossary

Domain terms. Use these names in code, docs and commits.

- **Round**: one attempt at a text: the sentences picked for it, what has been typed, every keystroke and the live score. It lives in memory only and knows nothing of history or settings. Code: `Round`.
- **Round result**: a finished round as saved in the history: date, language, WPM, accuracy and seconds. Code: `RoundResult`, `History`.
- **Collection**: a named set of sentences in Spanish and English, built in or loaded from a JSON file. A round picks its sentences from the chosen collection. Code: `Collection`.
