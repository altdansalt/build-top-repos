#!/bin/sh
# Black-box smoke: use echo as a library — define a route and serve a request
# in-process. $PROJECT = restored build tree (the echo module).
set -e
cd "$PROJECT"
mkdir -p smokecmd
cat > smokecmd/main.go <<'EOF'
package main

import (
	"net/http/httptest"

	"github.com/labstack/echo/v5"
)

func main() {
	e := echo.New()
	e.GET("/ping", func(c *echo.Context) error { return c.String(200, "pong") })
	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/ping", nil)
	e.ServeHTTP(w, req)
	if w.Code != 200 || w.Body.String() != "pong" {
		panic("echo smoke failed")
	}
	println("ECHO_SMOKE_OK")
}
EOF
go run ./smokecmd
