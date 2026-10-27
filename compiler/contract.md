# dos2luau shared contract v1 (locked before fan-out)

Runtime modules are strict Luau ModuleScripts. `require(script.Parent.Types)` for
types and `require(script.Parent.Name)` for siblings; tests translate these requires
to relative file paths for Lune. No loadstring in runtime or generated code.
Use native annotations where supported, without depending on native compilation.

## CPU / keys
`runtime/Types.luau` is authoritative. AX,CX,DX,BX,SP,BP,SI,DI use the 16-byte
`regs` buffer at 0,2,4,6,8,10,12,14. AL,CL,DL,BL,AH,CH,DH,BH alias
0,2,4,6,1,3,5,7. Extra state is allowed via the indexer; do not change this layout.
32-bit register upper halves can use `regsHigh` (16 bytes), `mode32` selects flat
EIP keys. Real-mode key = bit32.bor(bit32.lshift(bit32.band(cs-loadSegment,65535),16),bit32.band(ip,65535)).
CompiledBlockFn `(cpu,bus,budget)->(nextBlockKey,remainingBudget)` MUST update
cpu.cs/ip/currentBlockKey at exits. Budget is INSTRUCTIONS, not host cycles.
Count executed instructions exactly, stop at exhaustion and preserve resumable IP.

## Core modules (agent 2)
`CPUState.new(loadSegment?: number)->CPUState`; `CPUState.key(cpu)->number`;
`CPUState.getReg(cpu,index,width)->number`, `setReg(cpu,index,width,value)`;
`CPUState.alu(cpu,operation,a,b,width)->number` (operation lowercase add,adc,sub,sbb,
cmp,inc,dec,and,or,xor,test); flags CF=1 PF=4 AF=16 ZF=64 SF=128 IF=512 DF=1024 OF=2048.
`Bus.new(size?: number)->Bus` defaults 1 MiB; physical byte/word accesses wrap at
RAM length. `readSeg16(seg,off)`/`writeSeg16(seg,off,val)` wrap OFFSET before
translation; read16/write16 wrap PHYSICAL addresses. `read32/write32` supported.
`bus.video` optional object with vramDirty; `bus.codePageBitmap`,
`bus.invalidatedPages` tables keyed by floor(physical/4096). `bus:markCode(addr,length)`;
`bus:load(addr,data:buffer)` is privileged initialization including ROM.
Port handler callbacks are closures with no self: `readFn()`/`writeFn(value)`.
Optional `bus.memoryReadHook(addr)->number?`, `memoryWriteHook(addr,value)->boolean`
allow video planar VRAM mapping. true means write consumed.
`Interpreter.step(cpu,bus)->(nextKey,cost)` executes ONE instruction, cost>=1.
Before decoding call `bus.hle:handleTrap(cpu,bus)` if present; true means handled
as one instruction. INT calls `Interpreter.interrupt(cpu,bus,vector)` pushing
FLAGS,CS,return IP via SS:SP then reading IVT; no direct HLE bypass.
`Interpreter.stepUntilCompiledBlock(cpu,bus,blocks,budget)->(nextKey,remainingBudget)`.
`Dispatcher.new(blocks?, meta?)->dispatcher`; `dispatcher:run(cpu,bus,budget)->remainingBudget`;
optional `deadline` numeric os.clock() deadline. Check code page invalidations and
mark pages for compiled block coverage. Compiler metadata `blockRanges[key] =
{cs=relativeCS,ip=start,length=byteLength}` for guard. Unsupported instruction
MUST fail diagnostically (include CS:IP/opcode), never silently nop.

## Loader / HLE / VFS (agent 3)
`VFS.new(assets?: {[string]: string})->vfs`; assets contain raw bytes, not base64.
`Loader.load(cpu,bus,meta,options?)->result`; options loadSegment (default 0x1000),
pspSegment (default loadSegment-0x10 for MZ, loadSegment for COM), commandTail,
programPath (default C:\\GAME.EXE). meta.image is raw binary string, relocations
as above; format='com'|'mz'|'le'|'coff'. EntryCS/SS relative to image load segment
for MZ, COM entryCS=SS=0 and IP=0x100. Loader owns initial guest RAM setup.
`InterruptsAndHLE.new(bus,options?)->hle`; options vfs,video,audio,input and clock
(function returning date table) optional. constructor sets bus.hle and IVT stubs.
`hle:handleTrap(cpu,bus)->boolean` recognizes exact F000 stub addresses and performs
HLE + IRET (or leaves trap pending for blocked keyboard); otherwise false.
`hle:patchSavedFlags(cpu,bus,mask,value)` updates SS:(SP+4) offset-wrapped.
HLE default timer vector 08 chains guest 1C using interrupt semantics; avoid
discarding hooks. Unimplemented DOS/DPMI services return explicit error status.

## Video (agent 4)
`Video.new(bus,options?)->video`; options imageLabel optional, headless boolean.
No Roblox services at module top level (headless tests must work).
`video:setMode(mode,preserve?)`; `video:render()->buffer` rasterizes and optionally
uploads, `video:present()` uploads only if dirty (may delegate render).
`video:setPalette(index,r6,g6,b6)`; `video:getPalette(index)->(r6,g6,b6)`;
`video:teletype(byte)`; optional scroll/cursor helpers HLE may implement directly.
video.mode,width,height,pixels,paletteRGBA,vramDirty,paletteDirty public fields.
`CP437Font` module returns an exactly 2048-byte buffer; document source/license.
new registers VGA port closures on bus, installs optional planar memory hooks.

## Audio / input / scheduler (agent 5)
`Audio.new(bus,options?)->audio`; options headless, speakerAssetId,oplAssetId,
pcmAssets (hash -> asset ID), onUnknownPCM optional. No fabricated asset IDs.
`audio:update(dt,cpu?)`, `audio:destroy()`; optional `audio:bell()`.
Set `audio.pendingIRQ=0x0F` on DMA completion; scheduler delivers via IVT.
`InputAndScheduler.new(cpu,bus,dispatcher,options?)->scheduler`; options audio,
video,headless,instructionsPerSecond,maxInstructionsPerFrame,frameBudgetSeconds.
`scheduler:step(dt)` deterministic manual heartbeat; `start()`, `stop()`, `destroy()`;
`scheduler:keyEvent(keyName:string,down:boolean)` headless injectable key input.
`scheduler:releaseAll()`; bus port60 handler holds scancode queue; pending IRQs
delivered only with IF and not while halted. BDA buffer initialized by Loader/HLE.
Cap execution chunks at next PIT tick so 20,000 instructions between ticks.
Time out with os.clock deadline; audio/video must update even if guest waits.

## Compiler (agent 1)
TypeScript with Bun (installed) and no mandatory external packages. CLI
`bun compiler/src/cli.ts <binary> --out runtime/Out [--assets directory]
[--trace-log file]`. Agent owns compiler/** except this immutable contract.
CLI emits Program_Meta.luau returning meta with raw-byte escaped image string,
Blocks_001.luau returning key->function table, VFS_Assets.luau raw bytes table.
Optional index init module may be emitted. Blocks require CPUState/Interpreter
from `script.Parent.Parent`. Directly lift supported instructions; unsupported
legal instructions may use Interpreter.step with explicit budget accounting;
report coverage honestly. Do not claim fallback-only code is native recompilation.
Block chunks max1500, under180 locals per function. Record blockRanges and entry.
Compiled flag liveness must preserve observable architectural flags at exits;
do not dead-eliminate flags needed by dispatcher/fallback or interrupted execution.
CLI/tests must reject malformed formats and unsupported relocation formats safely.

## Ownership / integration
Agent 1 compiler/**; agent 2 Bus,CPUState,Interpreter,Dispatcher; agent 3 Loader,VFS,
InterruptsAndHLE; agent 4 Video,CP437Font; agent 5 Audio,InputAndScheduler.
Lead owns Types, runtime/init.luau, root config, examples, tests, docs, integration.
Workers are not alone; do not revert/edit other owners' files. Send contract
proposals to lead. Tests may be added ONLY within assigned ownership; lead tests
live under tests/. Record implemented versus incomplete instructions/services.
