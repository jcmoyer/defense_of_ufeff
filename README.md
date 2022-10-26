# Building

Requires a zig compiler, and optionally python3 to install dependencies.

```
>python3 install-deps.py
>zig build
```

# Dependencies

- [SDL](https://www.libsdl.org/). zlib license.
- [zmath](https://github.com/michal-z/zig-gamedev). MIT license.
- [stb_image, stb_vorbis](https://github.com/nothings/stb). MIT license.
- [zig-opengl](https://github.com/MasterQ32/zig-opengl/). Bindings are in the
  public domain.

# License

All code under `src/` explicitly has no license, with the exception of:

1. `src/sdl.zig`: this file contains handwritten bindings with portions of code
   copied from SDL. It is likewise licensed under the zlib license.

`thirdparty/stb/` contains additional zig bindings that are likewise licensed
under the MIT License or as Public Domain (unlicense.org), whichever you prefer.
