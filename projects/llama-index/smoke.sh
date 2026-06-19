#!/bin/sh
# Black-box smoke: verify llama-index-core installs and core API is usable.
# Full use requires LLM API keys (OpenAI, Anthropic, etc.) and optionally
# model downloads — neither available here.
# $PROJECT = restored tree (with the .venv).
set -e
PY="$PROJECT/.venv/bin/python"

# Version from installed metadata
"$PY" -c "
import importlib.metadata
v = importlib.metadata.version('llama-index-core')
print('llama-index-core', v)
"

# Core imports and basic Document API (no LLM or embedding calls)
"$PY" -c "
from llama_index.core import Document
from llama_index.core.schema import TextNode
from llama_index.core.node_parser import SentenceSplitter

# Create a document
doc = Document(text='LlamaIndex makes it easy to ingest and query your data with LLMs.')
print('Document text:', doc.text[:40], '...')
print('Document id:', doc.doc_id[:8], '...')

# Split into nodes (offline text splitter; no model download)
splitter = SentenceSplitter(chunk_size=64, chunk_overlap=0)
nodes = splitter.get_nodes_from_documents([doc])
print('nodes from splitter:', len(nodes))
"

echo LLAMA_INDEX_SMOKE_OK
