1. Get Zig 0.13
2. `cd` into repo root
3. Run `zig build run`

Note: To build for web, I have to do the following:
1. Get emsdk/emscripten installed and working.
2. Edit `emcc.zig` (part of raylib-zig), add `-sUSE_OFFSET_CONVERTER` to the args for `emcc` on line 100.
3. `zig build -Doptimize=ReleaseFast -Dtarget=wasm32-emscripten --sysroot /usr/lib/emsdk/upstream/emscripten`
