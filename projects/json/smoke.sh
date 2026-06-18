#!/bin/sh
# Black-box smoke: compile a tiny C++ snippet against the nlohmann/json header
# and verify parse + value access + round-trip dump. $PROJECT = built tree.
set -e
cd "$PROJECT"

# Write a small test program that uses the header-only library.
cat > /tmp/smoke_json.cpp << 'EOF'
#include "single_include/nlohmann/json.hpp"
#include <iostream>
#include <cassert>
using json = nlohmann::json;
int main() {
    // Parse JSON
    auto j = json::parse(R"({"name":"nlohmann","version":3,"active":true,"tags":["c++","json"]})");
    assert(j["name"] == "nlohmann");
    assert(j["version"] == 3);
    assert(j["active"] == true);
    assert(j["tags"][0] == "c++");
    // Round-trip: dump then re-parse
    std::string s = j.dump();
    auto j2 = json::parse(s);
    assert(j2 == j);
    // Construction from scratch
    json k;
    k["x"] = 1;
    k["y"] = 2;
    assert(k.dump() == "{\"x\":1,\"y\":2}");
    std::cout << "parsed: " << j["name"] << " v" << j["version"] << std::endl;
    return 0;
}
EOF

g++-14 -std=c++17 -I . /tmp/smoke_json.cpp -o /tmp/smoke_json
/tmp/smoke_json
echo JSON_SMOKE_OK
