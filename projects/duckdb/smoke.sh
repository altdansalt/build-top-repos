#!/bin/sh
# Black-box smoke: run the built duckdb binary with basic SQL. $PROJECT = built tree.
set -e
cd "$PROJECT"
./build/duckdb --version
echo "SELECT 42 AS answer;" | ./build/duckdb
echo "SELECT sum(i) FROM range(10) t(i);" | ./build/duckdb
echo DUCKDB_SMOKE_OK
