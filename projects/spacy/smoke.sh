#!/bin/sh
# Black-box smoke: verify the spaCy CLI and Python API.
# Run the Python snippet from /tmp so the source spacy/ dir does not shadow
# the installed .so extensions in the venv site-packages.
# $PROJECT = restored tree (with .venv).
set -e

PYTHON="$PROJECT/.venv/bin/python"
SPACY="$PROJECT/.venv/bin/spacy"

# CLI info command shows version
"$SPACY" info

# Import + blank-model tokenization.  Must run from outside the source tree so
# 'import spacy' resolves to the installed wheel, not the uncompiled source dir.
cd /tmp
"$PYTHON" - <<'EOF'
import spacy

nlp = spacy.blank("en")
doc = nlp("Hello, world! spaCy tokenizes text.")
tokens = [t.text for t in doc]
assert "Hello" in tokens, "tokenization failed: Hello missing"
assert "spaCy" in tokens, "tokenization failed: spaCy missing"
print("tokens:", tokens)
print("version:", spacy.__version__)
EOF

echo SPACY_SMOKE_OK
