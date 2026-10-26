// Package shared holds the files scripts/export-shared.sh generates from the Swift sources. Do not edit the JSON by hand.
package shared

import _ "embed"

// Collections are the built-in collections (Collection.builtIn in Typing.swift).
//
//go:embed collections.json
var Collections []byte

// Unicode holds the scalar ranges Collection.parse treats as wide or as whitespace.
//
//go:embed unicode.json
var Unicode []byte

// Vectors are inputs with the Swift results; typer's tests replay them. Not embedded in the app.
const VectorsFile = "vectors.json"
