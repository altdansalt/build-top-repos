#!/bin/sh
# Black-box smoke: run the built dsl-schema tool (polars-plan internal tool) to
# generate the full polars DSL plan JSON schema. Verifies the schema contains the
# root DslPlan type — exercises the polars-plan schema serialisation path.
# $PROJECT = built tree.
set -e
BIN="$PROJECT/target/debug/dsl-schema"
"$BIN" generate /tmp/polars-dsl-schema.json
test -s /tmp/polars-dsl-schema.json
grep -q '"DslPlan"' /tmp/polars-dsl-schema.json
echo POLARS_SMOKE_OK
