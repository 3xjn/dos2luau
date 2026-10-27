# dos2luau

An offline DOS binary-to-Luau compiler with a Roblox runtime. It translates
supported x86 instructions to static ModuleScripts, interprets dynamic code,
and exposes BIOS/DOS services, graphics, keyboard input, and audio adapters.
There is no runtime `loadstring` or generated-source evaluation.

This is an initial implementation, with a tested subset of the requested
hardware and executable formats. It is not a complete PC emulator. The
compatibility boundaries below are part of the public interface.

## Run the included demo

Install [Bun](https://bun.sh/) and [Lune](https://lune-org.github.io/docs/).
The compiler and tests have no package dependencies.

```powershell
bun run demo
bun test compiler
bun run test:runtime
bun run build:studio
lune run tests/model.luau
```

The checked-in `runtime/Out` is a precompiled COM demo: mode 13h colors,
keyboard input, and PIT speaker notes. Any key changes color; Escape exits.

Open `dist/dos2luau.rbxmx` or the verified binary `dist/dos2luau.rbxm` in Studio.
Move `DOS2Luau` into `ReplicatedStorage`, and move `DOSDemo` into
`StarterPlayerScripts`. Alternatively, sync `default.project.json` with Rojo.
Play on the client. The example creates a full-screen, pixelated ImageLabel.
Press **F10** or **Right Control + comma**, or tap the small fading gear, to open
emulator settings. Aspect ratio, filtering, scanlines, speed, volume, touch
controls and menu assist apply immediately. Settings last for the current client session.

Keyboard/mouse and gamepad input keep the touch quick bar and thumb ring hidden.
Auto mode uses the last active input type, including on touchscreen laptops.
Left touch drag holds directional keys by default. Screen assist is opt-in:
numbered menu clicks, continue taps, gamepad choice highlighting and the waiting
quick bar are disabled for the generic runtime. The `--oregon` build enables
them explicitly. Menu assist can also be toggled in settings. With it enabled,
D-pad and the left thumbstick move the choice outline; A confirms the selected
digit plus Enter. Mouse hover also outlines a choice. On PC, the first arrow
press activates the selector, subsequent arrows wrap through choices, and Enter
confirms. Typing a digit or Backspace returns to manual entry.
Holding a menu direction scrolls after 320 ms, then every 110 ms. Outside menus,
held keyboard keys use BIOS typematic repeat with buffer backpressure. Numbered
name forms stay in text-entry mode; detected confirmation questions show explicit
Yes/No buttons while screen assist is enabled.
Confirmation buttons submit the answer and Enter; pass `confirmationEnter=false`
to the input router for games whose confirmation takes a single keystroke.
The Type button opens the platform keyboard where supported. Force On/Off touch
overrides are available in settings; they do not enable menu assist.

The full-screen black backing layer covers the Roblox world in fitted aspect
modes. The example disables local avatar movement, jumping, character sounds and
the emote wheel, and uses a scriptable camera while active. Cleanup restores
the prior character/UI state. DOS audio remains separately controlled.

The runtime and demo default to `rbxassetid://9040512330` for the PC speaker's
440 Hz square wave and `rbxassetid://9040512197` for the approximate nine-voice
OPL2 pool's 440 Hz sine wave. Both use frequency / 440 pitch modulation.
Override `speakerAssetId` or `oplAssetId` to supply your own looped waveforms;
`examples/square-440.wav` is also available to upload. Headless runs do not create
default sounds. PCM playback maps
FNV-1a sample hashes to separately supplied Roblox audio assets.
Short speaker pulses retain at least a 50 ms hold, and Turbo temporarily uses
XT instruction pacing while the speaker gate is active.

Published experiences must enable the Mesh/Image APIs and meet Roblox's
EditableImage eligibility requirements. See the official
[EditableImage documentation](https://create.roblox.com/docs/reference/engine/classes/EditableImage).
Native annotations are optimization requests; correctness does not depend
on native compilation being available on the client.

## Compile a program

```powershell
bun compiler/src/cli.ts C:\Games\GAME.EXE --assets C:\Games --out runtime/Out
bun compiler/src/cli.ts C:\Games\GAME.EXE --assets C:\Games --out runtime/Out --trace-log discovered_blocks.json
```

The output includes `Program_Meta.luau`, chunked `Blocks_001.luau` modules,
the aggregate `Blocks.luau`, and binary-safe `VFS_Assets.luau`. Large code,
assets and metadata are split into sibling modules below 180,000 source
characters to fit Studio's 200,000-character Source limit. Rebuild the
Studio model after compiling. Output must be a child of the runtime module,
because generated blocks require their parent runtime's CPU and interpreter.
Keep the original executable and assets together when code loads `.BGI` files.

```lua
local DOS = require(game.ReplicatedStorage.DOS2Luau)
local machine = DOS.new({
    imageLabel = display,
    programPath = "C:\\GAME.EXE",
    commandTail = "",
    speakerAssetId = "rbxassetid://YOUR_OWNED_ASSET",
})
machine:start()
-- machine:stop(), machine:destroy()
```

For tests use `headless=true` and `machine:step(dt)`. Pass explicit `meta`,
`blocks`, and `assets` tables to choose another compiled program.
`machine.scheduler:keyEvent("A", true/false)` injects an input event.
`machine:exportTrace()` returns a JSON-ready versioned table:

```json
{"version":1,"blocks":[{"relCS":0,"ip":256}]}
```

Flat 32-bit traces use `{ "eip": 4096 }`. Serialize this through HttpService
in Studio. Traces identify fallback addresses; code generated or unpacked only
at runtime cannot be recovered from address-only traces of the packed file.

`Video:setDisplaySettings({aspectMode="stretch",resampleMode="Pixelated"})`
also accepts aspect modes `"4:3"`, `"16:10"`, `"integer"` and filter `"Default"`.
Roblox resampler enum values are accepted. Layout and filter survive guest video
mode changes. Integer scaling recalculates when the viewport changes.
`scheduler:setSpeedPreset("turbo"|"xt"|"286"|"386")` selects approximate
instruction rates, and `audio:setMasterGain(0..1)` changes all playing channels.
The MHz labels identify speed profiles; they do not model processor cycles.
`VirtualInputRouter.new(machine, options)` accepts `smartMenuClick`,
`tapToContinue`, `gamepadMenuHighlight`, `touchQuickBar` (all default false), and
`touchThumbstick` (default true). `router:setMenuAssist(boolean)` toggles the
first four together. Native INT 33h mouse forwarding stays active.

## Implemented paths and boundaries

| Area | Implemented | Material boundary |
| --- | --- | --- |
| Executables | COM, MZ relocations and allocation limits, LZEXE 0.90/0.91 unpacking, local-symbol i386 COFF DIR32/REL32, raw-page LE | LE fixups/imports/compression, arbitrary DOS extenders, PE/NE/LX are rejected |
| Compiler | Recursive discovery, bounded direct blocks, guarded dead-flag removal, direct CMP/TEST-Jcc comparisons, selected direct 16/32-bit and x87 lifting | General CFG superblocks, jump-table recovery and full flag liveness are incomplete |
| CPU | Aliased 8/16/32-bit registers; 16-bit and SIB addressing; stack/control/string operations; exact integer MUL/DIV; IVT interrupts | 8086/186/386 instruction coverage is a subset; unsupported operations fail with address/opcode |
| Dispatch | Compiled/interpreted execution, instruction budgets, first-run byte checks, code-page invalidation | Dynamic code remains interpreted until represented in compile-time inputs |
| OS | PSP/environment, conventional memory blocks, in-memory VFS, BIOS/DOS subsets, mouse state, selected DPMI descriptors/memory/vectors/real-mode simulation | Descriptor limits/privileges and exception gates are not a protected-mode machine; mouse callbacks are not dispatched |
| Video | CP437 text/cursor, CGA 4/5/6, VGA 13h, basic Mode X, DAC, BIOS scroll; live Studio image upload verified | VGA latches/write modes/CRTC behavior and sustained frame-time validation are incomplete |
| x87 | Host-double stack, selected loads/stores/arithmetic/trigonometry/status | No 80-bit precision, rounding-mode enforcement or full exception behavior |
| Audio | Continuously looping speaker gate/pitch, approximate OPL carrier/envelopes, DMA sample hashes and completion IRQs | OPL is not sample-accurate FM; PCM requires pre-registered audio assets |
| Scheduling | First three PIT ticks use 20,000 instructions each; interactive turbo then targets 3.5M IPS with wall-clock PIT, bounded REP batching and 512-instruction deadline checks; backpressured input queue | Headless/deterministic runs retain exact instruction pacing; speed profiles are approximate |
| Input/UI | Full-screen display settings, native text bridge, touch/gamepad routing, current text VRAM regions and graphics menu recognition | Graphics labels are approximate; unusual BGI fonts/backgrounds can prevent hit-testing or continue-prompt recognition; physical mobile/console keyboards are unverified |

DOS file writes affect the in-memory VFS. Persist the resulting data explicitly
if an experience needs saves across sessions. Unknown BIOS interrupts have
guest-visible return stubs; unknown DOS/DPMI services report an error.

## Verification

`bun run test` includes compiler, runtime, REP, video, input and settings suites.
`bun run test:runtime` stages static Roblox module paths as relative Lune
imports, then runs the original typed module bodies. It checks full CPU/RAM
parity at budget boundaries, relocation, self-modifying code, register/flag
semantics, 128 independently generated BigInt arithmetic vectors, x87,
interrupt flags, keyboard waits, MCB allocation, video, audio and scheduling.
`bun run demo` deterministically rebuilds the test binaries and golden vectors.

For syntax and strict analysis, install official Luau CLI binaries as
`.tools/luau/luau-compile` and `.tools/luau/luau-analyze` (with `.exe` on
Windows), or put them on PATH, then run `bun run check:luau` after staging.
The root `.luaurc` declares the Roblox host globals. This check validates
Luau types, not Roblox API permissions or a live client display.

The optional Oregon Trail probe uses a locally downloaded graphical 1990
DOS edition with VGA and BGI assets. It has reached the real VGA main menu,
profession selection, and wagon-leader naming prompt through guest execution.
The same menus and party naming have also been tested in a live Studio client
using Studio MCP keyboard input and native EditableImage output. This is a
startup/input compatibility result, not a complete playthrough.
DOOM and Quake have not been verified.

The downloaded test edition is the Internet Archive's
[Oregon Trail 1990 DOS archive](https://archive.org/details/msdos_Oregon_Trail_The_1990).
Its LZEXE unpacking happens offline. The AOT build discovers 35,925 instruction
blocks, with 21,345 directly lifted before runtime invalidation. The optional
parity probe compares the full CPU, 1 MiB RAM and VGA framebuffer against
interpreter-only execution for the menu-to-naming scenario.

```powershell
bun compiler/src/cli.ts .local-games/Oregon1990/oregont/OREGON.EXE --assets .local-games/Oregon1990/oregont --out runtime/OutOregon
bun run test:oregon One Return One Return
bun scripts/render-frame.ts
bun scripts/verify-oregon.ts
bun scripts/build-studio.ts --oregon
lune run tests/model.luau dist/dos2luau-oregon.rbxmx
```

The optional probe writes its framebuffer, RAM, DOS call log, CPU state and
discovered addresses beneath `.local-games/`. Downloaded game data and its
generated modules are ignored by Git. The self-contained suite does not
need game downloads or an Internet connection.

See [compiler/contract.md](compiler/contract.md) for the shared interfaces and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for font and palette attribution.
The exact tested scenarios and remaining verification limits are recorded in
[tests/VERIFICATION.md](tests/VERIFICATION.md).
