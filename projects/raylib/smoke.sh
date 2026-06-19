#!/bin/sh
# Black-box smoke for raylib: verify the static library was built, then compile
# and run a small C program using raymath.h (header-only inline functions) —
# no window or display needed. $PROJECT = built tree.
set -e
cd "$PROJECT"

# Verify the built static library is present anywhere under build/
find build -name "libraylib.a" | grep -q . || { echo "ERROR: libraylib.a not found under build/"; exit 1; }

# Write a small program that exercises raymath.h (RAYMATH_STANDALONE avoids
# pulling in raylib.h and its window/OpenGL includes).
cat > /tmp/smoke_raylib.c << 'EOF'
#define RAYMATH_STANDALONE
#define RAYMATH_STATIC_INLINE
#include "raymath.h"
#include <stdio.h>
#include <math.h>
#include <assert.h>

int main(void) {
    /* Vector2 arithmetic */
    Vector2 a = {3.0f, 4.0f};
    Vector2 b = {1.0f, 2.0f};
    Vector2 sum = Vector2Add(a, b);
    assert(sum.x == 4.0f && sum.y == 6.0f);

    float len = Vector2Length(a);
    assert(fabsf(len - 5.0f) < 0.001f);

    /* Vector3 length: sqrt(1^2 + 2^2 + 2^2) == 3 */
    Vector3 v3 = {1.0f, 2.0f, 2.0f};
    float v3len = Vector3Length(v3);
    assert(fabsf(v3len - 3.0f) < 0.001f);

    /* Matrix identity */
    Matrix id = MatrixIdentity();
    assert(id.m0 == 1.0f && id.m5 == 1.0f && id.m10 == 1.0f && id.m15 == 1.0f);

    printf("raylib/raymath: Vector2Add=[%.1f,%.1f] len=%.1f v3len=%.1f\n",
           sum.x, sum.y, len, v3len);
    return 0;
}
EOF

gcc /tmp/smoke_raylib.c -I src -lm -o /tmp/smoke_raylib
/tmp/smoke_raylib
echo RAYLIB_SMOKE_OK
