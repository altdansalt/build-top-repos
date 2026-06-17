#!/bin/sh
# Black-box smoke: use gin as a library the way an app would — define a route and
# serve a request in-process. $PROJECT = restored build tree (the gin module).
set -e
cd "$PROJECT"
mkdir -p smokecmd
cat > smokecmd/main.go <<'EOF'
package main

import (
	"net/http"
	"net/http/httptest"

	"github.com/gin-gonic/gin"
)

func main() {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/ping", func(c *gin.Context) { c.String(200, "pong") })
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/ping", nil)
	r.ServeHTTP(w, req)
	if w.Code != 200 || w.Body.String() != "pong" {
		panic("gin smoke failed")
	}
	println("GIN_SMOKE_OK")
}
EOF
go run ./smokecmd
