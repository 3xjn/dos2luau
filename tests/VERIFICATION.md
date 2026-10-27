# Verification record

Verified on Windows with Bun 1.3.4, Lune 0.10.4, and official Luau CLI 0.744.

| Check | Result |
| --- | --- |
| `bun test compiler` | 37 tests, 452 assertions, zero failures |
| `bun run test:runtime` | 34 checks, zero failures |
| `bun run test:performance` | 5 REP parity and safety groups pass |
| `bun run test:video` | 9 raster, display-setting and text-region checks pass |
| `bun run test:input` | 18 routing, focus, assist and device checks pass |
| `bun run test:settings-runtime` | 4 speed, gain, initialization and legacy keyboard checks pass |
| `bun run test:settings` | Setting dispatch, shortcuts and touch override checks pass |
| `bun run test:player-isolation` | Sound, Humanoid, emote state and cleanup checks pass |
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
- Directly lifted instructions executed by the AOT build: **1,358,986**.
- Interpreted instructions in that build: **4,814,878**.
- Compared RAM: **1,048,576 bytes**.
- Compared VGA framebuffer: **256,000 bytes** (320 × 200 × RGBA).
- Static discovery: **35,925 blocks**, including **21,345 direct blocks**,
  emitted in **65 chunks**, each below 180,000 source characters. This is
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

The updated UI was also checked in the live client: black bars cover the 3D
world in 4:3 mode; aspect/filter choices persist through repeated video mode
changes; integer scaling responds to viewport changes; F10 and Right Control +
comma toggle the modal without selecting a DOS choice. Simulated gamepad input
draws a choice outline and confirms with A. Injected I/O keyboard events appear
as `io` at the guest name prompt. The native TextBox focus/FocusLost bridge
submitted `asher` into the guest, with normal key injection suppressed during
TextBox focus. Physical mobile and console keyboards were not tested.
The shared selector was checked with injected keyboard arrows and Enter,
advancing from the main menu to professions. Native mouse-movement events
showed the hover outline and cleared it on exit. Simulated stick tests cover
neutral hysteresis, direction changes and raw directional fallback outside
menus; a physical thumbstick was not tested.
The final production LocalScript boots without privileged diagnostic helpers.
Its camera remains Scriptable after a competing type change, the emote wheel
stays disabled after the Period shortcut, local character Sound volumes are
zero, and the Humanoid's movement/jump settings are disabled. Optional restricted
Roblox event subscriptions are guarded so they cannot abort startup.

## Performance and input regressions

REP tests compare both directions, all ten string forms, comparison termination,
overlap and offset wrapping, ROM, unknown hooks, code invalidation, Mode X, and
deadline resumption. Video tests cover raster pixels, cursor/blink, current text
regions and settings persistence. Input tests cover queue backpressure,
independent held sources, controller mappings, calibration/turbo, stale context,
direct InputObject-to-GuiObject coordinate normalization, processed keyboard
events with TextBox focus, opt-in screen assist and last-input-type touch gating.

Local Lune microbenchmarks on this machine (30 renders per video mode) compare
the previous GitHub snapshot with the optimized raster, with identical pixels:

| Operation | Previous | Optimized | Ratio |
| --- | --- | --- | --- |
| Mode 03h text raster | 64.00 ms | 1.46 ms | 43.8x |
| Mode 04h CGA raster | 9.99 ms | 0.50 ms | 19.9x |
| Mode 06h CGA raster | 9.73 ms | 0.77 ms | 12.6x |
| Mode 13h VGA raster | 4.89 ms | 0.20 ms | 24.6x |
| Ten 32,000-word STOSW clears | 229.72 ms | 1.13 ms | 203.6x |

These are host microbenchmarks, not Roblox FPS or a guarantee of one-frame guest
drawing. Guest drawing loops, image upload and platform limits still contribute.
Graphics menu recognition detects choices 1–6 and 1–4 in the captured Oregon
menus. Labels are approximate, and the real game's BGI continue-prompt font has
not been verified. Synthetic CP437 SPACE/continue recognition passes.

This record does not establish a full Oregon playthrough, audible audio
playback, sustained Roblox frame-time performance, or DOOM /
Quake compatibility. LE fixups, full 386/protected-mode and x87 behavior,
sample-accurate OPL synthesis and other limits remain documented in README.md.
