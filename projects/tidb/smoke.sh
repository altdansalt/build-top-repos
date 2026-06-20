#!/bin/sh
# Black-box smoke: verify the tidb-server binary starts and reports version/help.
# TiDB is a distributed SQL database server; version and help flags exit cleanly
# without requiring a TiKV/PD cluster. $PROJECT = built tree.
set -e
cd "$PROJECT"
./tidb-server -V
./tidb-server --help 2>&1 | grep -qi "tidb"
echo TIDB_SMOKE_OK
