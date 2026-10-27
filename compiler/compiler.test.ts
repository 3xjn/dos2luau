import { test, expect } from "bun:test";
import { parseProgram } from "./src/formats";
import { decode, discover, key } from "./src/decode";
import { compile, parseTrace } from "./src/cli";
import {
  mkdtemp,
  readFile,
  rm,
  mkdir,
  writeFile,
  readdir,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
test("COM entry and branch discovery", () => {
  const p = parseProgram(
    Uint8Array.from([0xb8, 0x34, 0x12, 0x74, 0x01, 0x90, 0xf4]),
  );
  const d = discover(p);
  expect(d.map((x) => x.ip)).toEqual([0x100, 0x103, 0x105, 0x106]);
  expect(decode(p, 0, 0x103).targets).toEqual([key(0, 0x106), key(0, 0x105)]);
});
test("rejects truncated MZ and invalid relocation", () => {
  expect(() => parseProgram(Uint8Array.from([0x4d, 0x5a]))).toThrow();
  const b = new Uint8Array(64);
  b.set([0x4d, 0x5a, 64, 0, 1, 0, 1, 0, 2, 0]);
  b[24] = 28;
  b[28] = 0xff;
  expect(() => parseProgram(b)).toThrow("relocation");
});
test("emits direct and fallback with instruction budgets", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    const stats = await compile(
      parseProgram(Uint8Array.from([0xb0, 1, 0xcd, 0x21])),
      dir,
    );
    expect(stats.direct).toBe(1);
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    expect(code).toContain("CPU.setReg(cpu, 0, 8, 1)");
    expect(code).toContain("Interpreter.step(cpu, bus)");
    expect(code).toContain("budget - cost");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("trace keys are hexadecimal segment offsets", () =>
  expect(parseTrace("0001:0100\nnoise")).toEqual([key(1, 0x100)]));
test("direct chains retain budget checkpoints and expanded code range", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    const p = parseProgram(
      Uint8Array.from([0xb0, 1, 0x04, 2, 0x74, 0x00, 0xf4]),
    );
    await compile(p, dir);
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8"),
      meta = await readFile(join(dir, "Program_Meta.luau"), "utf8");
    expect(code).toContain(
      "if budget <= 0 then return cpu.currentBlockKey, budget end",
    );
    expect(code).toContain('CPU.alu(cpu, "add"');
    expect(code).toContain("if zf then cpu.ip");
    expect(meta).toContain("[256] = {cs=0, ip=256, length=4}");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("unsupported executable headers and truncated instructions fail safely", () => {
  expect(() => parseProgram(Uint8Array.from([0x4c, 0x45, 0]))).toThrow(
    "truncated",
  );
  const p = parseProgram(Uint8Array.from([0xb8, 0]));
  expect(() => decode(p, 0, 0x100)).toThrow("truncated");
  expect(discover(p)).toEqual([]);
});
test("JSON discovered blocks support arrays and keyed maps", () => {
  expect(parseTrace('[256,"0001:0100",{"cs":2,"ip":32}]')).toEqual([
    256,
    key(1, 0x100),
    key(2, 32),
  ]);
  expect(parseTrace('{"discoveredBlocks":{"256":true,"257":false}}')).toEqual([
    256,
  ]);
  expect(() => parseTrace("{oops")).toThrow("invalid trace JSON");
});
test("versioned trace uses relative CS and validates bounds", () => {
  expect(parseTrace('{"version":1,"blocks":[{"relCS":3,"ip":256}]}')).toEqual([
    key(3, 256),
  ]);
  expect(() => parseTrace('{"blocks":[{"relCS":65536,"ip":1}]}')).toThrow(
    "invalid trace block",
  );
});
test("direct memory operations isolate writes for code invalidation", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(
      parseProgram(Uint8Array.from([0xb0, 1, 0xa2, 0, 1, 0x90, 0xf4])),
      dir,
    );
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8"),
      meta = await readFile(join(dir, "Program_Meta.luau"), "utf8");
    expect(code).toContain("bus:write8(bus.segOffToPhys(cpu.ds, 256)");
    expect(meta).toContain("[256] = {cs=0, ip=256, length=2}");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("compare and branch share a block while preserving intermediate flags", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(parseProgram(Uint8Array.from([0x3c, 1, 0x74, 0, 0xf4])), dir);
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8"),
      meta = await readFile(join(dir, "Program_Meta.luau"), "utf8");
    expect(meta).toContain("[256] = {cs=0, ip=256, length=4}");
    const first = code.slice(
      code.indexOf("blocks[256]"),
      code.indexOf("blocks[258]"),
    );
    expect(first).toContain('CPU.alu(cpu, "cmp"');
    expect(first).toContain(
      "if budget <= 0 then return cpu.currentBlockKey, budget end",
    );
    expect(first).toContain("if cmpA == cmpB then");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("overwritten compare flags are eliminated only with two instructions budgeted", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(parseProgram(Uint8Array.from([0x3c, 1, 0x3c, 2, 0xf4])), dir);
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    const first = code.slice(
      code.indexOf("blocks[256]"),
      code.indexOf("blocks[258]"),
    );
    expect(first).toContain("if budget >= 2 then");
    expect(first).toContain("else");
    expect(first.match(/CPU\.alu\(cpu, "cmp"/g)?.length).toBe(3);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("arithmetic dead flags are skipped only before guaranteed CMP", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(parseProgram(Uint8Array.from([0x04, 3, 0x3c, 2, 0xf4])), dir);
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    const first = code.slice(
      code.indexOf("blocks[256]"),
      code.indexOf("blocks[258]"),
    );
    expect(first).toContain("if budget >= 2 then");
    expect(first).toContain("CPU.getReg(cpu, 0, 8) + 3");
    expect(first).toContain('CPU.alu(cpu, "add"');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("long dead-flag prefix has a full-prefix budget guard", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(
      parseProgram(Uint8Array.from([0x04, 1, 0x40, 0x3c, 2, 0xf4])),
      dir,
    );
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    const first = code.slice(
      code.indexOf("blocks[256]"),
      code.indexOf("blocks[258]"),
    );
    expect(first).toContain("if budget >= 3 then");
    expect(first).toContain("CPU.getReg(cpu, 0, 16) + 1");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("lifts x87 constants with runtime stack layout", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(
      parseProgram(Uint8Array.from([0xd9, 0xe8, 0xd9, 0xee, 0xf4])),
      dir,
    );
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    expect(code).toContain("cpu.fpuTop = (cpu.fpuTop - 1) % 8");
    expect(code).toContain("cpu.fpu[cpu.fpuTop + 1] = 1");
    expect(code).toContain("cpu.fpu[cpu.fpuTop + 1] = 0");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("interrupts and indirect calls discover their return successors", () => {
  for (const bytes of [
    [0xcd, 0x21, 0xb0, 1, 0xf4],
    [0xff, 0xd0, 0xb0, 1, 0xf4],
    [0x9a, 0, 0, 0, 0, 0xb0, 1, 0xf4],
  ]) {
    const p = parseProgram(Uint8Array.from(bytes));
    const d = discover(p);
    expect(d.some((i) => i.opcode === 0xb0)).toBe(true);
  }
});
test("links i386 COFF DIR32 and REL32 references and rejects unresolved symbols", () => {
  const b = new Uint8Array(140),
    v = new DataView(b.buffer);
  v.setUint16(0, 0x14c, true);
  v.setUint16(2, 1, true);
  v.setUint32(8, 120, true);
  v.setUint32(12, 1, true);
  b.set(new TextEncoder().encode(".text"), 20);
  v.setUint32(36, 8, true);
  v.setUint32(40, 60, true);
  v.setUint32(44, 68, true);
  v.setUint16(52, 2, true);
  v.setUint32(56, 0x20, true);
  v.setUint32(68, 0, true);
  v.setUint32(72, 0, true);
  v.setUint16(76, 6, true);
  v.setUint32(78, 4, true);
  v.setUint32(82, 0, true);
  v.setUint16(86, 20, true);
  b.set(new TextEncoder().encode("_start"), 120);
  v.setUint32(128, 0, true);
  v.setUint16(132, 1, true);
  const p = parseProgram(b),
    out = new DataView(p.image.buffer);
  expect(p.format).toBe("coff");
  expect(p.entryIP).toBe(0x1000);
  expect(out.getUint32(0, true)).toBe(0x1000);
  expect(out.getUint32(4, true)).toBe(0xfffffff8);
  v.setUint16(132, 0, true);
  expect(() => parseProgram(b)).toThrow("unresolved");
});
test("flat 32-bit decoder emits safe fallback blocks with SIB lengths", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    const p = {
      format: "coff" as const,
      mode32: true,
      imageBase: 0,
      image: Uint8Array.from([
        0xb8, 1, 0, 0, 0, 0x8b, 0x44, 0x8d, 0x10, 0xcd, 0x21, 0xf4,
      ]),
      entryCS: 0,
      entryIP: 0,
      initialSS: 0,
      initialSP: 0x80000,
      relocations: [],
    };
    const d = discover(p);
    expect(d.map((i) => i.ip)).toEqual([0, 5, 9, 11]);
    expect(d.map((i) => i.length)).toEqual([5, 4, 2, 1]);
    await compile(p, dir);
    const blocks = await readFile(join(dir, "Blocks_001.luau"), "utf8"),
      meta = await readFile(join(dir, "Program_Meta.luau"), "utf8"),
      aggregate = await readFile(join(dir, "Blocks.luau"), "utf8");
    expect(blocks).toContain("blocks[5]");
    expect(blocks).toContain("Interpreter.step(cpu, bus)");
    expect(meta).toContain("mode32 = true");
    expect(aggregate).toContain("script.Parent.Blocks_001");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("loads a raw LE page and rejects nonempty fixups", () => {
  const b = new Uint8Array(0xe4),
    v = new DataView(b.buffer);
  b.set([0x4c, 0x45]);
  v.setUint16(8, 2, true);
  v.setUint32(0x14, 1, true);
  v.setUint32(0x18, 1, true);
  v.setUint32(0x20, 1, true);
  v.setUint32(0x24, 4, true);
  v.setUint32(0x28, 4, true);
  v.setUint32(0x2c, 4, true);
  v.setUint32(0x40, 0xb0, true);
  v.setUint32(0x44, 1, true);
  v.setUint32(0x48, 0xc8, true);
  v.setUint32(0x68, 0xcc, true);
  v.setUint32(0x80, 0xe0, true);
  v.setUint32(0xb0, 4, true);
  v.setUint32(0xb4, 0x1000, true);
  v.setUint32(0xb8, 0x2007, true);
  v.setUint32(0xbc, 1, true);
  v.setUint32(0xc0, 1, true);
  b[0xca] = 1;
  b.set([0x90, 0xf4, 0, 0], 0xe0);
  const p = parseProgram(b);
  expect(p.format).toBe("le");
  expect(p.entryIP).toBe(0x1000);
  expect(Array.from(p.image.slice(0))).toEqual([0x90, 0xf4, 0, 0]);
  v.setUint32(0xd0, 1, true);
  expect(() => parseProgram(b)).toThrow("fixups");
});
test("MZ relocation overlap forces instruction interpreter fallback", () => {
  const image = Uint8Array.from([0xb8, 0, 0, 0xf4]);
  const p = {
    format: "mz" as const,
    image,
    entryCS: 0,
    entryIP: 0,
    initialSS: 0,
    initialSP: 0xfffe,
    relocations: [{ segment: 0, offset: 1 }],
  };
  expect(decode(p, 0, 0).direct).toBe(false);
  expect(discover(p)[0]!.direct).toBe(false);
});
test("discovery reports in-image unknown instruction boundaries", () => {
  const p = parseProgram(Uint8Array.from([0x0f]));
  const warnings: string[] = [];
  discover(p, [], warnings);
  expect(warnings[0]).toContain("unsupported opcode");
});
test("flat direct lifting uses 32-bit registers and preserves full EIP", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    const p = {
      format: "coff" as const,
      mode32: true,
      imageBase: 0x10000,
      image: Uint8Array.from([
        0xb8, 0x78, 0x56, 0x34, 0x12, 0x05, 1, 0, 0, 0, 0x74, 0, 0xf4,
      ]),
      entryCS: 0,
      entryIP: 0x10000,
      initialSS: 0,
      initialSP: 0x80000,
      relocations: [],
    };
    const stats = await compile(p, dir);
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    expect(stats.direct).toBe(3);
    expect(code).toContain("CPU.setReg(cpu, 0, 32, 305419896)");
    expect(code).toContain("cpu.ip = 65541");
    expect(code).toContain(
      'CPU.alu(cpu, "add", CPU.getReg(cpu, 0, 32), 1, 32)',
    );
    expect(code).toContain("if zf then cpu.ip = 65548");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("x87 arithmetic and trig are directly lifted with underflow checks", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    const p = parseProgram(Uint8Array.from([0xd8, 0xc1, 0xd9, 0xfe, 0xf4]));
    const stats = await compile(p, dir),
      code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    expect(stats.direct).toBe(2);
    expect(code).toContain("cpu.fpu[slot] = a + v");
    expect(code).toContain("cpu.fpu[slot] = math.sin(v)");
    expect(code).toContain("x87 stack underflow");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("x87 direct memory load and store wrap segment offsets", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    const stats = await compile(
        parseProgram(
          Uint8Array.from([
            0xd9, 0x06, 0xff, 0xff, 0xdd, 0x1e, 0xff, 0xff, 0xf4,
          ]),
        ),
        dir,
      ),
      code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    expect(stats.direct).toBe(2);
    expect(code).toContain("buffer.readf32(tmp, 0)");
    expect(code).toContain("buffer.writef64(tmp, 0, v)");
    expect(code).toContain("(65535 + j) % 65536");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("32-bit near Jcc is directly lifted with full-width target", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    const p = {
      format: "coff" as const,
      mode32: true,
      imageBase: 0x10000,
      image: Uint8Array.from([0x0f, 0x84, 0, 0, 0, 0, 0xf4]),
      entryCS: 0,
      entryIP: 0x10000,
      initialSS: 0,
      initialSP: 0x80000,
      relocations: [],
    };
    const stats = await compile(p, dir),
      code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    expect(stats.direct).toBe(1);
    expect(code).toContain("if zf then cpu.ip = 65542");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("FS and GS overrides remain interpreter-backed without losing boundaries", () => {
  const p = parseProgram(Uint8Array.from([0x64, 0xb8, 1, 0, 0x65, 0x90, 0xf4]));
  const d = discover(p);
  expect(d.map((i) => i.length)).toEqual([4, 2, 1]);
  expect(d[0]!.direct).toBe(false);
  expect(d[1]!.direct).toBe(false);
});
test("MZ allocation paragraphs are preserved in generated metadata", async () => {
  const b = new Uint8Array(33),
    v = new DataView(b.buffer);
  b.set([0x4d, 0x5a]);
  v.setUint16(2, 33, true);
  v.setUint16(4, 1, true);
  v.setUint16(8, 2, true);
  v.setUint16(10, 0x120e, true);
  v.setUint16(12, 0x2949, true);
  v.setUint16(24, 28, true);
  b[32] = 0xf4;
  const p = parseProgram(b);
  expect(p.minExtraParagraphs).toBe(0x120e);
  expect(p.maxExtraParagraphs).toBe(0x2949);
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(p, dir);
    const meta = await readFile(join(dir, "Program_Meta.luau"), "utf8");
    expect(meta).toContain(
      "minExtraParagraphs = 4622, maxExtraParagraphs = 10569",
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
import { unpackLzStream, LZ_SIGNATURES } from "./src/lzexe";
test("LZEXE stream literals, overlap copying, bit refill and limits", () => {
  expect(
    Array.from(unpackLzStream(Uint8Array.from([0x0b, 0, 65, 66, 0, 0, 0]))),
  ).toEqual([65, 66]);
  expect(
    Array.from(unpackLzStream(Uint8Array.from([0x41, 0, 65, 255, 0, 0, 0]))),
  ).toEqual([65, 65, 65]);
  const refill = Uint8Array.from([
    255,
    255,
    ...Array(15).fill(65),
    2,
    0,
    65,
    0,
    0,
    0,
  ]);
  expect(unpackLzStream(refill)).toEqual(Uint8Array.from(Array(16).fill(65)));
  expect(() => unpackLzStream(Uint8Array.from([0, 0, 255]))).toThrow();
  expect(() =>
    unpackLzStream(Uint8Array.from([0x0b, 0, 65, 66, 0, 0, 0]), 1),
  ).toThrow("limit");
});
test("LZ91 fixture restores original registers, allocation and relocation data", () => {
  const b = new Uint8Array(80 + 0x158 + 4),
    v = new DataView(b.buffer);
  b.set([0x4d, 0x5a]);
  v.setUint16(2, b.length % 512, true);
  v.setUint16(4, Math.ceil(b.length / 512), true);
  v.setUint16(8, 2, true);
  v.setUint16(10, 9, true);
  v.setUint16(12, 20, true);
  v.setUint16(20, 16, true);
  v.setUint16(22, 3, true);
  v.setUint16(24, 28, true);
  b.set([76, 90, 57, 49], 28);
  b.set([0x17, 0, 65, 66, 67, 0, 0, 0], 64);
  v.setUint16(80 + 4, 0x100, true);
  v.setUint16(80 + 8, 1, true);
  b.set(LZ_SIGNATURES[91], 96);
  b.set([1, 0, 1, 0], 80 + 0x158);
  const p = parseProgram(b);
  expect(p.packing).toBe("lzexe91");
  expect(Array.from(p.image)).toEqual([65, 66, 67]);
  expect(p.initialSP).toBe(0x100);
  expect(p.minExtraParagraphs).toBe(0);
  expect(p.maxExtraParagraphs).toBe(11);
  expect(p.relocations).toEqual([{ segment: 0, offset: 1 }]);
  expect(() => parseProgram(b.slice(0, 110))).toThrow("LZEXE");
});
test("LZ90 restores segment-grouped relocations", () => {
  const base = 80,
    b = new Uint8Array(base + 0x19d + 34),
    v = new DataView(b.buffer);
  b.set([0x4d, 0x5a]);
  v.setUint16(2, b.length % 512, true);
  v.setUint16(4, Math.ceil(b.length / 512), true);
  v.setUint16(8, 2, true);
  v.setUint16(10, 9, true);
  v.setUint16(12, 20, true);
  v.setUint16(20, 16, true);
  v.setUint16(22, 3, true);
  v.setUint16(24, 28, true);
  b.set([76, 90, 48, 57], 28);
  b.set([0x17, 0, 65, 66, 67, 0, 0, 0], 64);
  v.setUint16(base + 8, 1, true);
  b.set(LZ_SIGNATURES[90], base + 16);
  v.setUint16(base + 0x19d, 1, true);
  v.setUint16(base + 0x19f, 1, true);
  const p = parseProgram(b);
  expect(p.packing).toBe("lzexe90");
  expect(p.relocations).toEqual([{ segment: 0, offset: 1 }]);
  expect(Array.from(p.image)).toEqual([65, 66, 67]);
});
test("far call and jump discover in-image relative segment targets", () => {
  for (const opcode of [0x9a, 0xea]) {
    const image = new Uint8Array(40);
    image.set([opcode, 0, 0, 1, 0, 0xf4]);
    image[16] = 0xb0;
    image[17] = 7;
    image[18] = 0xf4;
    const p = {
      format: "mz" as const,
      image,
      entryCS: 0,
      entryIP: 0,
      initialSS: 0,
      initialSP: 0xfffe,
      relocations: [{ segment: 0, offset: 3 }],
    };
    const d = discover(p);
    expect(d.some((i) => i.cs === 1 && i.ip === 0 && i.opcode === 0xb0)).toBe(
      true,
    );
    expect(d[0]!.direct).toBe(false);
    expect(d.some((i) => i.cs === 0 && i.ip === 5)).toBe(opcode === 0x9a);
  }
});
test("16-bit operand and address overrides decode 32-bit immediate and SIB conservatively", () => {
  const p = parseProgram(
    Uint8Array.from([
      0x66, 0xb8, 1, 2, 3, 4, 0x67, 0x8b, 0x04, 0x25, 0, 0, 0, 0, 0xf4,
    ]),
  );
  const d = discover(p);
  expect(d.map((i) => i.length)).toEqual([6, 8, 1]);
  expect(d[0]!.direct).toBe(false);
  expect(d[1]!.direct).toBe(false);
});
test("metadata distinguishes direct blocks and generated chunks request native mode", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(parseProgram(Uint8Array.from([0xb0, 1, 0xcd, 0x21])), dir);
    const meta = await readFile(join(dir, "Program_Meta.luau"), "utf8"),
      code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    const direct = meta.slice(
      meta.indexOf("directBlocks"),
      meta.indexOf("blockRanges"),
    );
    expect(direct).toContain("[256] = true");
    expect(direct).not.toContain("[258]");
    expect(code).toContain("--!native");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("CMP signed branch fusion reads operands and retains the flag checkpoint", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(
      parseProgram(Uint8Array.from([0x3c, 0x80, 0x7c, 0x01, 0xf4, 0xf4])),
      dir,
    );
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    const first = code.slice(
      code.indexOf("blocks[256]"),
      code.indexOf("blocks[258]"),
    );
    expect(first).toContain('CPU.alu(cpu, "cmp", cmpA, cmpB, 8)');
    expect(first).toContain(
      "if budget <= 0 then return cpu.currentBlockKey, budget end",
    );
    expect(first).toContain("if cmpA >= 128 then cmpA - 256 else cmpA");
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("register TEST and JZ fuse bitwise condition while materializing flags", async () => {
  const dir = await mkdtemp(join(tmpdir(), "dos2luau-"));
  try {
    await compile(
      parseProgram(Uint8Array.from([0x84, 0xc0, 0x74, 0x01, 0xf4, 0xf4])),
      dir,
    );
    const code = await readFile(join(dir, "Blocks_001.luau"), "utf8");
    const first = code.slice(
      code.indexOf("blocks[256]"),
      code.indexOf("blocks[258]"),
    );
    expect(first).toContain('CPU.alu(cpu, "test", cmpA, cmpB, 8)');
    expect(first).toContain("if bit32.band(cmpA, cmpB) == 0 then");
    expect(first).toContain(
      "if budget <= 0 then return cpu.currentBlockKey, budget end",
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
test("large generated sources stay under Studio limits and preserve binary data", async () => {
  const root = await mkdtemp(join(tmpdir(), "dos2luau-large-")),
    out = join(root, "out"),
    assetDir = join(root, "files");
  try {
    await mkdir(assetDir);
    const original = Uint8Array.from(
      { length: 600000 },
      (_, i) => (i * 37) & 255,
    );
    await writeFile(join(assetDir, "large.bin"), original);
    const code = new Uint8Array(6001);
    code.fill(0x90);
    code[6000] = 0xf4;
    const stats = await compile(parseProgram(code), out, assetDir);
    const names = await readdir(out);
    expect(stats.instructions).toBe(6001);
    expect(stats.chunks).toBeGreaterThan(4);
    for (const name of names) {
      const source = await readFile(join(out, name), "utf8");
      expect(source.length).toBeLessThanOrEqual(180000);
    }
    expect(names.some((n) => n.startsWith("Meta_Ranges_"))).toBe(true);
    expect(names.some((n) => n.startsWith("Asset_Data_"))).toBe(true);
    const assetTable = await readFile(
      join(out, names.find((n) => n.startsWith("VFS_Files_"))!),
      "utf8",
    );
    const rootName = assetTable.match(
      /require\(script\.Parent\.(Asset_Data_\d+)\)/,
    )![1]!;
    async function readParts(name: string): Promise<Uint8Array> {
      const src = await readFile(join(out, name + ".luau"), "utf8");
      if (src.includes("table.concat")) {
        const children = [
          ...src.matchAll(/require\(script\.Parent\.(Asset_Data_\d+)\)/g),
        ].map((m) => m[1]!);
        const parts = await Promise.all(children.map(readParts));
        const result = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
        let pos = 0;
        for (const part of parts) {
          result.set(part, pos);
          pos += part.length;
        }
        return result;
      }
      const encoded = src.match(/return "(.*)"/)![1]!;
      return Uint8Array.from(
        [...encoded.matchAll(/\\(\d{3})/g)].map((m) => Number(m[1])),
      );
    }
    expect(await readParts(rootName)).toEqual(original);
    await writeFile(join(out, "Unrelated.luau"), "return 42");
    await compile(parseProgram(Uint8Array.from([0xf4])), out);
    const remaining = await readdir(out);
    expect(remaining).toContain("Unrelated.luau");
    expect(remaining.some((n) => n.startsWith("Asset_Data_"))).toBe(false);
    expect(remaining).not.toContain("Blocks_002.luau");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
test("direct stack, ALU, shifts, call, return and memory load match interpreter at budget one", async () => {
  if (!Bun.which("lune")) return;
  const root = await mkdtemp(join(tmpdir(), "dos2luau-parity-"));
  try {
    for (const n of ["CPUState", "Bus", "Interpreter"]) {
      let source = await readFile(
        join(process.cwd(), "runtime", `${n}.luau`),
        "utf8",
      );
      source = source.replaceAll(
        "require(script.Parent.CPUState)",
        'require("./CPUState")',
      );
      await writeFile(join(root, `${n}.luau`), source);
    }
    const cases = [
      [0x50],
      [0x54],
      [0x58],
      [0x5c],
      [0x80, 0xc0, 0xff],
      [0x81, 0xe8, 0x34, 0x12],
      [0x83, 0xd8, 0xff],
      [0x83, 0xf8, 0x80],
      [0xd0, 0xe0],
      [0xd0, 0xe8],
      [0xd0, 0xf8],
      [0xd1, 0xe0],
      [0xd1, 0xe8],
      [0xd1, 0xf8],
      [0xe8, 0, 0],
      [0xc3],
      [0xc2, 0x04, 0],
      [0x8a, 0x46, 0xff],
      [0x8b, 0x06, 0xff, 0xff],
    ];
    const rows: string[] = [];
    for (let i = 0; i < cases.length; i++) {
      const path = join(root, `F${i}`);
      await compile(parseProgram(Uint8Array.from(cases[i]!)), path);
      const blockPath = join(path, "Blocks_001.luau");
      let source = await readFile(blockPath, "utf8");
      source = source
        .replaceAll(
          "require(script.Parent.Parent.CPUState)",
          'require("../CPUState")',
        )
        .replaceAll(
          "require(script.Parent.Parent.Interpreter)",
          'require("../Interpreter")',
        );
      await writeFile(blockPath, source);
      rows.push(
        `{blocks = require("./F${i}/Blocks_001"), bytes = {${cases[i]!.join(",")}}}`,
      );
    }
    const script = `local CPU = require("./CPUState")\nlocal Bus = require("./Bus")\nlocal Interpreter = require("./Interpreter")\nlocal cases = {${rows.join(",")}}\nfor ci, case in cases do\n for _,value in {0,1,127,128,255,32767,32768,65535} do\n  local function create()\n   local c=CPU.new(0x1000);c.cs=0x1000;c.ds=0x1100;c.ss=0x1200;c.ip=0x100;c.flags=0x0ad7\n   for r=0,7 do CPU.setReg(c,r,16,if r==4 then 1 elseif r==5 then 0 else value) end\n   local b=Bus.new();for n,v in case.bytes do b:write8(0x10000+0xff+n,v) end\n   b:writeSeg16(c.ss,1,0xa55a);b:writeSeg16(c.ss,65535,0x2345);b:writeSeg16(c.ds,65535,0xbeef)\n   return c,b\n  end\n  local a,x=create();local c,y=create();local next,remaining=case.blocks[256](a,x,1);local expected,cost=Interpreter.step(c,y)\n  assert(remaining==0 and cost==1 and next==expected, 'next/cost '..ci)\n  assert(a.ip==c.ip and a.flags==c.flags, 'ip/flags '..ci..' value '..value)\n  assert(buffer.tostring(a.regs)==buffer.tostring(c.regs), 'regs '..ci..' value '..value)\n  assert(buffer.tostring(x.ram)==buffer.tostring(y.ram), 'memory '..ci..' value '..value)\n end\nend\nprint("parity passed")\n`;
    const scriptPath = join(root, "run.luau");
    await writeFile(scriptPath, script);
    const result = Bun.spawnSync(["lune", "run", scriptPath]);
    expect(result.exitCode).toBe(0);
    expect(new TextDecoder().decode(result.stderr)).toBe("");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}, 30000);
test("64-instruction direct chains preserve every budget checkpoint", async () => {
  if (!Bun.which("lune")) return;
  const root = await mkdtemp(join(tmpdir(), "dos2luau-chain-"));
  try {
    for (const n of ["CPUState", "Bus", "Interpreter"]) {
      let s = await readFile(
        join(process.cwd(), "runtime", `${n}.luau`),
        "utf8",
      );
      s = s.replaceAll(
        "require(script.Parent.CPUState)",
        'require("./CPUState")',
      );
      await writeFile(join(root, `${n}.luau`), s);
    }
    const bytes: number[] = [0xb8, 0xff, 0x7f];
    for (let n = 0; n < 31; n++) bytes.push(0x83, 0xc0, 0xff, 0xd1, 0xe8);
    bytes.push(0x3d, 0x12, 0x34, 0x74, 0x00, 0xf4);
    const out = join(root, "Out");
    await compile(parseProgram(Uint8Array.from(bytes)), out);
    const file = join(out, "Blocks_001.luau");
    let block = await readFile(file, "utf8");
    block = block
      .replaceAll(
        "require(script.Parent.Parent.CPUState)",
        'require("../CPUState")',
      )
      .replaceAll(
        "require(script.Parent.Parent.Interpreter)",
        'require("../Interpreter")',
      );
    await writeFile(file, block);
    const script = `local CPU=require('./CPUState')\nlocal Bus=require('./Bus')\nlocal I=require('./Interpreter')\nlocal blocks=require('./Out/Blocks_001')\nlocal bytes={${bytes.join(",")}}\nfor budget=1,64 do\n local function create() local c=CPU.new(4096);c.cs=4096;c.ip=256;c.flags=0xad7;local b=Bus.new();for n,v in bytes do b:write8(65535+256+n,v) end;return c,b end\n local a,x=create();local c,y=create();local next,remaining=blocks[256](a,x,budget);for _=1,budget-remaining do I.step(c,y) end\n assert(next==CPU.key(c) and a.ip==c.ip and a.flags==c.flags and buffer.tostring(a.regs)==buffer.tostring(c.regs), 'budget '..budget)\nend\nprint('chain parity passed')\n`;
    const fileScript = join(root, "run.luau");
    await writeFile(fileScript, script);
    const result = Bun.spawnSync(["lune", "run", fileScript]);
    expect(new TextDecoder().decode(result.stderr)).toBe("");
    expect(result.exitCode).toBe(0);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}, 30000);
