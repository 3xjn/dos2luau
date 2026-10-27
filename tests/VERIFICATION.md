# Verification record

Verified on Windows with Bun 1.3.4, Lune 0.10.4, and official Luau CLI 0.744.

| Check | Result |
| --- | --- |
| `bun test compiler` | 35 tests, 221 assertions, zero failures |
| `bun run test:runtime` | 34 checks, zero failures |
| `bun run check:luau` | Generated/runtime modules compile and pass strict analysis |
| `lune run tests/model.luau` | Default model structure and binary serialization pass |
| `lune run tests/model.luau dist/dos2luau-oregon.rbxmx` | Oregon model structure and binary serialization pass |
| `bun scripts/verify-oregon.ts` | Exact CPU, RAM and framebuffer equality with interpreter-only execution |

The runtime checks include 55 instruction-budget boundaries and relocation at
three load segments, 128 independently generated BigInt MUL/DIV vectors,
physical/segmented wrapping, early and later code mutation, dispatcher reuse,
IVT flags, BIOS keyboard blocking with continued timers, audio gate/timing,
planar/CGA/linear graphics, finite MZ allocation and DPMI real-mode simulation.

The Oregon scenario boots the graphical 1990 DOS edition, selects “Travel the
trail”, selects the banker profession, and reaches the wagon-leader naming
prompt. Actual guest instructions run; the display is rasterized from VRAM.

- Executed instructions in both runs: **6,173,864**.
- Directly lifted instructions executed by the AOT build: **1,166,917**.
- Interpreted instructions in that build: **5,006,947**.
- Compared RAM: **1,048,576 bytes**.
- Compared VGA framebuffer: **256,000 bytes** (320 × 200 × RGBA).
- Static discovery: **35,925 blocks**, including **11,546 direct blocks**,
  emitted in **57 chunks**, each below 180,000 source characters. This is
  discovery coverage, not complete execution. Embedded images, assets and
  metadata also use bounded sibling modules to satisfy Studio's 200,000-character
  source-property limit.
- One discovery diagnostic remains at relative `0000:0322` (`6F`); this did
  not execute in the verified scenario. Unknown instructions remain diagnostic
  if encountered by the interpreter.

Source: [Internet Archive Oregon Trail 1990](https://archive.org/details/msdos_Oregon_Trail_The_1990).
The original downloaded `OREGON.EXE` SHA-256 is:

```text
9acb83834aeb288a3b95d1aa8ad04047f8e94551f20fd052c97074ab93c9879c
```

The executable is unpacked offline using recognized LZEXE 0.91 metadata and
relocations. Game files, generated game code, framebuffer and detailed JSON
reports remain in ignored local directories. The checked-in synthetic tests
and demo require no downloaded game.

## Live Studio verification

Imported through Studio MCP into the `dos2luau` place (117776050742798).
The live client successfully created and uploaded a 320 × 200 EditableImage,
displayed the VGA main menu and profession menu, and rendered the wagon artwork
and party naming, departure-month and supply-purchase introduction screens.
Studio MCP keyboard events passed through
UserInputService into the DOS keyboard buffer; `asher`, `alice`, `bob`, `carol`
and `dave` appeared correctly in the game. Native image data and live screen
captures were inspected. No DOS runtime errors occurred during these scenarios.

The import contains 35,925 compiled instruction blocks and reconstructs the
145,168-byte program image and 321,139-byte OTMCGA.PCL asset. The HTTP setting
used for local transfer was restored to its original disabled value after import.

This record does not establish a full Oregon playthrough, audible audio
playback, sustained Roblox frame-time performance, or DOOM /
Quake compatibility. LE fixups, full 386/protected-mode and x87 behavior,
sample-accurate OPL synthesis and other limits remain documented in README.md.
