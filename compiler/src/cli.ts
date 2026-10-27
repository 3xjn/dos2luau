import { mkdir, readFile, readdir, writeFile, unlink } from "node:fs/promises";
import { resolve, relative, join } from "node:path";
import { parseProgram, type Program } from "./formats";
import { discover, key, type Instruction } from "./decode";
const quote = (s: Uint8Array | string) =>
  '"' +
  Array.from(
    typeof s === "string" ? new TextEncoder().encode(s) : s,
    (b) => "\\" + b.toString().padStart(3, "0"),
  ).join("") +
  '"';
function direct(i: Instruction): string {
  const op = i.opcode,
    b = i.bytes;
  if (i.flat) {
    const u32 = (start: number) =>
      (b[start]! +
        b[start + 1]! * 256 +
        b[start + 2]! * 65536 +
        b[start + 3]! * 16777216) >>>
      0;
    if (op >= 0xb0 && op <= 0xb7)
      return `CPU.setReg(cpu, ${op - 0xb0}, 8, ${b[1]})`;
    if (op >= 0xb8 && op <= 0xbf)
      return `CPU.setReg(cpu, ${op - 0xb8}, 32, ${u32(1)})`;
    if (op >= 0x40 && op <= 0x4f) {
      const r = op & 7,
        operation = op < 0x48 ? "inc" : "dec";
      return `CPU.setReg(cpu, ${r}, 32, CPU.alu(cpu, "${operation}", CPU.getReg(cpu, ${r}, 32), 1, 32))`;
    }
    if (op >= 0xa0 && op <= 0xa3) {
      const addr = `(((cpu.segmentBases and cpu.segmentBases[cpu.ds]) or 0) + ${u32(1)})`,
        width = op & 1 ? 32 : 8;
      return op < 0xa2
        ? `CPU.setReg(cpu, 0, ${width}, bus:read${width}(${addr}))`
        : `bus:write${width}(${addr}, CPU.getReg(cpu, 0, ${width}))`;
    }
    if (
      b.length >= 2 &&
      b[1]! >> 6 === 3 &&
      ((op <= 0x3b && (op & 7) <= 3) || (op >= 0x88 && op <= 0x8b))
    ) {
      const m = b[1]!,
        rm = m & 7,
        r = (m >> 3) & 7,
        w = op & 1 ? 32 : 8,
        d = op & 2 ? r : rm,
        src = op & 2 ? rm : r;
      if (op >= 0x88)
        return `CPU.setReg(cpu, ${d}, ${w}, CPU.getReg(cpu, ${src}, ${w}))`;
      const operation = ["add", "or", "adc", "sbb", "and", "sub", "xor", "cmp"][
          op >> 3
        ]!,
        call = `CPU.alu(cpu, "${operation}", CPU.getReg(cpu, ${d}, ${w}), CPU.getReg(cpu, ${src}, ${w}), ${w})`;
      return operation === "cmp"
        ? `local _result = ${call}`
        : `CPU.setReg(cpu, ${d}, ${w}, ${call})`;
    }
    if (op <= 0x3d && ((op & 7) === 4 || (op & 7) === 5)) {
      const w = op & 1 ? 32 : 8,
        value = w === 8 ? b[1]! : u32(1),
        operation = ["add", "or", "adc", "sbb", "and", "sub", "xor", "cmp"][
          op >> 3
        ]!,
        call = `CPU.alu(cpu, "${operation}", CPU.getReg(cpu, 0, ${w}), ${value}, ${w})`;
      return operation === "cmp"
        ? `local _result = ${call}`
        : `CPU.setReg(cpu, 0, ${w}, ${call})`;
    }
  }
  if (!i.flat && (op === 0x84 || op === 0x85)) {
    const m = b[1]!,
      w = op & 1 ? 16 : 8;
    return `local _result = CPU.alu(cpu, "test", CPU.getReg(cpu, ${m & 7}, ${w}), CPU.getReg(cpu, ${(m >> 3) & 7}, ${w}), ${w})`;
  }
  if (op === 0x90) return "";
  if (op === 0xd9 && [0xe8, 0xeb, 0xee].includes(b[1]!)) {
    const value = b[1] === 0xe8 ? "1" : b[1] === 0xee ? "0" : "math.pi";
    return `cpu.fpuTop = (cpu.fpuTop - 1) % 8\n\tcpu.fpu[cpu.fpuTop + 1] = ${value}`;
  }
  if ((op === 0xd9 || op === 0xdd) && b[1]! >> 6 === 0 && (b[1]! & 7) === 6) {
    const width = op === 0xd9 ? 32 : 64,
      off = b[2]! + b[3]! * 256,
      sub = (b[1]! >> 3) & 7,
      read = `local tmp = buffer.create(${width / 8})\n\tfor j = 0, ${width / 8 - 1} do buffer.writeu8(tmp, j, bus:read8(bus.segOffToPhys(cpu.ds, (${off} + j) % 65536))) end`;
    if (sub === 0)
      return `${read}\n\tlocal v = buffer.readf${width}(tmp, 0)\n\tcpu.fpuTop = (cpu.fpuTop - 1) % 8\n\tcpu.fpu[cpu.fpuTop + 1] = v`;
    return `${read}\n\tlocal v = cpu.fpu[cpu.fpuTop + 1]\n\tif v == nil then error("x87 stack underflow", 0) end\n\tbuffer.writef${width}(tmp, 0, v)\n\tfor j = 0, ${width / 8 - 1} do bus:write8(bus.segOffToPhys(cpu.ds, (${off} + j) % 65536), buffer.readu8(tmp, j)) end\n\tcpu.fpu[cpu.fpuTop + 1] = nil\n\tcpu.fpuTop = (cpu.fpuTop + 1) % 8`;
  }
  if (op === 0xd9 && [0xe0, 0xe1, 0xfa, 0xfe, 0xff].includes(b[1]!)) {
    const fn =
      b[1] === 0xe0
        ? "-v"
        : b[1] === 0xe1
          ? "math.abs(v)"
          : b[1] === 0xfa
            ? "math.sqrt(v)"
            : b[1] === 0xfe
              ? "math.sin(v)"
              : "math.cos(v)";
    return `local slot = cpu.fpuTop + 1\n\tlocal v = cpu.fpu[slot]\n\tif v == nil then error("x87 stack underflow", 0) end\n\tcpu.fpu[slot] = ${fn}`;
  }
  if (op === 0xd8 && b[1]! >= 0xc0) {
    const sub = (b[1]! >> 3) & 7,
      index = b[1]! & 7,
      expr = ["a + v", "a * v", "", "", "a - v", "v - a", "a / v", "v / a"][
        sub
      ]!;
    return `local slot = cpu.fpuTop + 1\n\tlocal a = cpu.fpu[slot]\n\tlocal v = cpu.fpu[(cpu.fpuTop + ${index}) % 8 + 1]\n\tif a == nil or v == nil then error("x87 stack underflow", 0) end\n\tcpu.fpu[slot] = ${expr}`;
  }
  if (op >= 0xa0 && op <= 0xa3) {
    const off = b[1]! + b[2]! * 256;
    if (op === 0xa0)
      return `CPU.setReg(cpu, 0, 8, bus:read8(bus.segOffToPhys(cpu.ds, ${off})))`;
    if (op === 0xa1)
      return `CPU.setReg(cpu, 0, 16, bus:readSeg16(cpu.ds, ${off}))`;
    if (op === 0xa2)
      return `bus:write8(bus.segOffToPhys(cpu.ds, ${off}), CPU.getReg(cpu, 0, 8))`;
    return `bus:writeSeg16(cpu.ds, ${off}, CPU.getReg(cpu, 0, 16))`;
  }

  if (
    b.length >= 2 &&
    b[1]! >> 6 === 3 &&
    ((op <= 0x3b && (op & 7) <= 3) || (op >= 0x88 && op <= 0x8b))
  ) {
    const modrm = b[1]!,
      rm = modrm & 7,
      reg = (modrm >> 3) & 7,
      width = op & 1 ? 16 : 8,
      dest = op & 2 ? reg : rm,
      src = op & 2 ? rm : reg;
    if (op >= 0x88)
      return `CPU.setReg(cpu, ${dest}, ${width}, CPU.getReg(cpu, ${src}, ${width}))`;
    const operation = ["add", "or", "adc", "sbb", "and", "sub", "xor", "cmp"][
      op >> 3
    ]!;
    const call = `CPU.alu(cpu, "${operation}", CPU.getReg(cpu, ${dest}, ${width}), CPU.getReg(cpu, ${src}, ${width}), ${width})`;
    return operation === "cmp"
      ? `local _result = ${call}`
      : `CPU.setReg(cpu, ${dest}, ${width}, ${call})`;
  }
  if (op <= 0x3d && ((op & 7) === 4 || (op & 7) === 5)) {
    const operations = ["add", "or", "adc", "sbb", "and", "sub", "xor", "cmp"];
    const operation = operations[op >> 3]!,
      width = op & 1 ? 16 : 8,
      value = width === 8 ? b[1]! : b[1]! + b[2]! * 256;
    const call = `CPU.alu(cpu, "${operation}", CPU.getReg(cpu, 0, ${width}), ${value}, ${width})`;
    return operation === "cmp"
      ? `local _result = ${call}`
      : `CPU.setReg(cpu, 0, ${width}, ${call})`;
  }
  if (op >= 0x70 && op <= 0x7f) {
    const tests = [
      "of",
      "not of",
      "cf",
      "not cf",
      "zf",
      "not zf",
      "cf or zf",
      "not cf and not zf",
      "sf",
      "not sf",
      "pf",
      "not pf",
      "sf ~= of",
      "sf == of",
      "zf or sf ~= of",
      "not zf and sf == of",
    ];
    return `local f = cpu.flags\n\tlocal cf = bit32.band(f, 1) ~= 0\n\tlocal pf = bit32.band(f, 4) ~= 0\n\tlocal zf = bit32.band(f, 64) ~= 0\n\tlocal sf = bit32.band(f, 128) ~= 0\n\tlocal of = bit32.band(f, 2048) ~= 0\n\tif ${tests[op - 0x70]} then cpu.ip = ${i.flat ? i.targets[0]! : i.targets[0]! & 65535} else cpu.ip = ${i.flat ? (i.ip + i.length) >>> 0 : (i.ip + i.length) & 65535} end\n\tcpu.currentBlockKey = CPU.key(cpu)\n\treturn cpu.currentBlockKey, budget - 1`;
  }
  if (op === 0xeb || op === 0xe9)
    return `cpu.ip = ${i.flat ? i.targets[0]! : i.targets[0]! & 65535}\n\tcpu.currentBlockKey = CPU.key(cpu)\n\treturn cpu.currentBlockKey, budget - 1`;
  if (op >= 0xb0 && op <= 0xb7)
    return `CPU.setReg(cpu, ${op - 0xb0}, 8, ${b[1]})`;
  if (op >= 0xb8 && op <= 0xbf)
    return `CPU.setReg(cpu, ${op - 0xb8}, 16, ${b[1]! + b[2]! * 256})`;
  if (op >= 0x40 && op <= 0x4f) {
    const reg = op & 7,
      operation = op < 0x48 ? "inc" : "dec";
    return `CPU.setReg(cpu, ${reg}, 16, CPU.alu(cpu, "${operation}", CPU.getReg(cpu, ${reg}, 16), 1, 16))`;
  }
  throw new Error("internal direct opcode");
}
function withoutFlags(i: Instruction): string | undefined {
  const op = i.opcode,
    b = i.bytes;
  if ([0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d].includes(op)) return "";
  if (op >= 0x40 && op <= 0x4f) {
    const r = op & 7;
    return `CPU.setReg(cpu, ${r}, 16, CPU.getReg(cpu, ${r}, 16) ${op < 0x48 ? "+" : "-"} 1)`;
  }
  if ([0x04, 0x05, 0x2c, 0x2d].includes(op)) {
    const w = op & 1 ? 16 : 8,
      val = w === 8 ? b[1]! : b[1]! + b[2]! * 256;
    return `CPU.setReg(cpu, 0, ${w}, CPU.getReg(cpu, 0, ${w}) ${op < 0x20 ? "+" : "-"} ${val})`;
  }
  if ((op <= 3 || (op >= 0x28 && op <= 0x2b)) && b[1]! >> 6 === 3) {
    const w = op & 1 ? 16 : 8,
      m = b[1]!,
      rm = m & 7,
      r = (m >> 3) & 7,
      d = op & 2 ? r : rm,
      src = op & 2 ? rm : r;
    return `CPU.setReg(cpu, ${d}, ${w}, CPU.getReg(cpu, ${d}, ${w}) ${op < 0x20 ? "+" : "-"} CPU.getReg(cpu, ${src}, ${w}))`;
  }
  return undefined;
}

// Fuse register/immediate CMP with common branches while retaining all flags.
function fusedCompare(
  seq: Instruction[],
): { compare: string; branch: string } | undefined {
  if (seq.length < 2) return undefined;
  const cmp = seq[seq.length - 2]!,
    jcc = seq[seq.length - 1]!;
  if (
    cmp.flat ||
    ![0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x84, 0x85].includes(cmp.opcode) ||
    !jcc.terminal
  )
    return undefined;
  const op = cmp.opcode,
    b = cmp.bytes,
    w = op & 1 ? 16 : 8;
  let left: string, right: string;
  if (op === 0x84 || op === 0x85) {
    const m = b[1]!;
    left = `CPU.getReg(cpu, ${m & 7}, ${w})`;
    right = `CPU.getReg(cpu, ${(m >> 3) & 7}, ${w})`;
  } else if (op >= 0x3c) {
    left = `CPU.getReg(cpu, 0, ${w})`;
    right = String(w === 8 ? b[1]! : b[1]! + b[2]! * 256);
  } else {
    const m = b[1]!,
      rm = m & 7,
      reg = (m >> 3) & 7,
      d = op & 2 ? reg : rm,
      src = op & 2 ? rm : reg;
    left = `CPU.getReg(cpu, ${d}, ${w})`;
    right = `CPU.getReg(cpu, ${src}, ${w})`;
  }
  const sign = 2 ** (w - 1),
    mod = 2 ** w,
    sa = `(if cmpA >= ${sign} then cmpA - ${mod} else cmpA)`,
    sb = `(if cmpB >= ${sign} then cmpB - ${mod} else cmpB)`;
  const expressions: Record<number, string> = {
    0x72: "cmpA < cmpB",
    0x73: "cmpA >= cmpB",
    0x74: "cmpA == cmpB",
    0x75: "cmpA ~= cmpB",
    0x76: "cmpA <= cmpB",
    0x77: "cmpA > cmpB",
    0x7c: `${sa} < ${sb}`,
    0x7d: `${sa} >= ${sb}`,
    0x7e: `${sa} <= ${sb}`,
    0x7f: `${sa} > ${sb}`,
  };
  const isTest = op === 0x84 || op === 0x85;
  const predicate = isTest
    ? (
        {
          0x74: "bit32.band(cmpA, cmpB) == 0",
          0x75: "bit32.band(cmpA, cmpB) ~= 0",
        } as Record<number, string>
      )[jcc.opcode]
    : expressions[jcc.opcode];
  if (!predicate) return undefined;
  return {
    compare: `local cmpA = ${left}\n\tlocal cmpB = ${right}\n\tlocal _result = CPU.alu(cpu, "${isTest ? "test" : "cmp"}", cmpA, cmpB, ${w})`,
    branch: `if ${predicate} then cpu.ip = ${jcc.targets[0]! & 65535} else cpu.ip = ${(jcc.ip + jcc.length) & 65535} end\n\tcpu.currentBlockKey = CPU.key(cpu)\n\treturn cpu.currentBlockKey, budget - 1`,
  };
}

function block(
  i: Instruction,
  chain: Instruction[] = [],
  flat = false,
): string {
  const k = flat ? i.ip : key(i.cs, i.ip);
  let body: string;
  if (i.direct) {
    const code = direct(i);
    body =
      (i.opcode >= 0x70 && i.opcode <= 0x7f) ||
      i.opcode === 0xeb ||
      i.opcode === 0xe9
        ? code
        : `${code}\n\tcpu.ip = ${flat ? (i.ip + i.length) >>> 0 : (i.ip + i.length) & 65535}\n\tcpu.currentBlockKey = CPU.key(cpu)\n\treturn cpu.currentBlockKey, budget - 1`;
  } else {
    body = `local nextKey, cost = Interpreter.step(cpu, bus)\n\tcpu.currentBlockKey = nextKey\n\treturn nextKey, budget - cost`;
  }
  if (chain.length) {
    const seq = [i, ...chain];
    const fusion = fusedCompare(seq);
    body =
      seq
        .map((item, index) =>
          item.opcode >= 0x70 && item.opcode <= 0x7f
            ? fusion && index === seq.length - 1
              ? fusion.branch
              : direct(item)
            : `${fusion && index === seq.length - 2 ? fusion.compare : direct(item)}\n\tcpu.ip = ${(item.ip + item.length) & 65535}\n\tcpu.currentBlockKey = CPU.key(cpu)\n\tbudget -= 1${index < seq.length - 1 ? "\n\tif budget <= 0 then return cpu.currentBlockKey, budget end" : ""}`,
        )
        .join("\n\t") +
      (seq[seq.length - 1]!.terminal
        ? ""
        : "\n\treturn cpu.currentBlockKey, budget");
  }
  const seq = [i, ...chain];
  let overwrite = -1;
  for (let n = 1; n < seq.length; n++) {
    if (withoutFlags(seq[n - 1]!) === undefined) break;
    if ([0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d].includes(seq[n]!.opcode))
      overwrite = n;
  }
  if (overwrite > 0) {
    const fusion = fusedCompare(seq);
    const fast =
      seq
        .map((item, index) => {
          if (item.terminal)
            return fusion && index === seq.length - 1
              ? fusion.branch
              : direct(item);
          const expr =
            index < overwrite
              ? withoutFlags(item)
              : fusion && index === seq.length - 2
                ? fusion.compare
                : direct(item);
          return `${expr}\n\tcpu.ip = ${(item.ip + item.length) & 65535}\n\tcpu.currentBlockKey = CPU.key(cpu)\n\tbudget -= 1${index >= overwrite && index < seq.length - 1 ? "\n\tif budget <= 0 then return cpu.currentBlockKey, budget end" : ""}`;
        })
        .join("\n\t") +
      (seq[seq.length - 1]!.terminal
        ? ""
        : "\n\treturn cpu.currentBlockKey, budget");
    body = `if budget >= ${overwrite + 1} then\n\t${fast}\nelse\n\t${body}\nend`;
  }
  return `blocks[${k}] = function(cpu: any, bus: any, budget: number): (number, number)\n\tif budget <= 0 then return CPU.key(cpu), budget end\n\t${body}\nend\n`;
}
async function assets(
  root?: string,
): Promise<{ name: string; data: Uint8Array }[]> {
  if (!root) return [];
  const files: { name: string; data: Uint8Array }[] = [];
  async function walk(dir: string) {
    for (const e of await readdir(dir, { withFileTypes: true })) {
      const path = join(dir, e.name);
      if (e.isDirectory()) await walk(path);
      else if (e.isFile())
        files.push({
          name: relative(root!, path).replaceAll("/", "\\"),
          data: await readFile(path),
        });
    }
  }
  await walk(root);
  const names = new Set<string>();
  for (const file of files) {
    const normalized = file.name.toUpperCase();
    if (names.has(normalized))
      throw new Error(`asset path collision: ${file.name}`);
    names.add(normalized);
  }
  files.sort((a, b) => a.name.localeCompare(b.name));
  return files;
}
export async function compile(
  p: Program,
  out: string,
  assetRoot?: string,
  traceKeys: number[] = [],
) {
  const warnings: string[] = [];
  const instructions = discover(p, traceKeys, warnings);
  await mkdir(out, { recursive: true });
  const ik = (i: Instruction) => (p.mode32 ? i.ip : key(i.cs, i.ip));
  const byKey = new Map(instructions.map((i) => [ik(i), i]));
  const chains = new Map<number, Instruction[]>();
  for (const first of instructions) {
    const chain: Instruction[] = [];
    let previous = first;
    while (
      !p.mode32 &&
      previous.opcode !== 0xd8 &&
      previous.opcode !== 0xd9 &&
      previous.opcode !== 0xdd &&
      previous.direct &&
      !(previous.opcode >= 0xa0 && previous.opcode <= 0xa3) &&
      !previous.terminal &&
      previous.ip + previous.length < 65536 &&
      chain.length < 15
    ) {
      const next = byKey.get(key(previous.cs, previous.ip + previous.length));
      if (
        !next ||
        !next.direct ||
        next.opcode === 0xd8 ||
        next.opcode === 0xd9 ||
        next.opcode === 0xdd ||
        (next.opcode >= 0xa0 && next.opcode <= 0xa3)
      )
        break;
      if (next.terminal) {
        if (
          next.opcode >= 0x70 &&
          next.opcode <= 0x7f &&
          (previous.opcode === 0x84 ||
            previous.opcode === 0x85 ||
            previous.opcode === 0x3c ||
            previous.opcode === 0x3d ||
            (previous.opcode >= 0x38 && previous.opcode <= 0x3b))
        )
          chain.push(next);
        break;
      }
      chain.push(next);
      previous = next;
    }
    chains.set(ik(first), chain);
  }
  const sources = new Map<string, string>();
  const SOURCE_LIMIT = 180000;
  const add = (name: string, source: string) => {
    if (source.length > SOURCE_LIMIT)
      throw new Error(
        `generated module ${name} exceeds ${SOURCE_LIMIT} characters`,
      );
    sources.set(name, source);
  };
  const numbered = (prefix: string, n: number) =>
    `${prefix}_${String(n).padStart(5, "0")}`;
  // Return a module expression for a byte string, using a tree so even very
  // large files cannot make an oversized aggregation module.
  let assetSerial = 0;
  function splitString(prefix: string, data: Uint8Array): string {
    let names: string[] = [];
    for (let at = 0; at < data.length; at += 32768) {
      const name = numbered(prefix, ++assetSerial);
      add(name, `--!strict\nreturn ${quote(data.subarray(at, at + 32768))}\n`);
      names.push(name);
    }
    if (!names.length) return quote(data);
    while (names.length > 1) {
      const next: string[] = [];
      for (let at = 0; at < names.length; at += 512) {
        const group = names.slice(at, at + 512),
          name = numbered(prefix, ++assetSerial);
        add(
          name,
          `--!strict\nreturn table.concat({${group.map((x) => `require(script.Parent.${x})`).join(",")}})\n`,
        );
        next.push(name);
      }
      names = next;
    }
    return `require(script.Parent.${names[0]})`;
  }
  function splitTable(prefix: string, entries: string[]): string[] {
    const names: string[] = [];
    let current: string[] = [];
    let size = 25;
    const flush = () => {
      if (!current.length) return;
      const name = numbered(prefix, names.length + 1);
      add(name, `--!strict\nreturn {\n${current.join("\n")}\n}\n`);
      names.push(name);
      current = [];
      size = 25;
    };
    for (const entry of entries) {
      if (entry.length + 25 > 150000)
        throw new Error(`generated table entry too large: ${prefix}`);
      if (size + entry.length + 1 > 150000) flush();
      current.push(entry);
      size += entry.length + 1;
    }
    flush();
    return names;
  }
  const rangeEntries = instructions.map(
    (i) =>
      `[${ik(i)}] = {cs=${i.cs}, ip=${i.ip}, length=${i.length + (chains.get(ik(i)) ?? []).reduce((n, x) => n + x.length, 0)}},`,
  );
  const directEntries = instructions
    .filter((i) => i.direct)
    .map((i) => `[${ik(i)}] = true,`);
  const relocationEntries = p.relocations.map(
    (r) => `{offset=${r.offset},segment=${r.segment}},`,
  );
  const warningEntries = warnings.map((w) => `${quote(w)},`);
  const header = `format = "${p.format}", packing = ${p.packing ? quote(p.packing) : "nil"}, mode32 = ${p.mode32 ? "true" : "false"}, imageBase = ${p.imageBase ?? 0},\n\tentryCS = ${p.entryCS}, entryIP = ${p.entryIP}, initialSS = ${p.initialSS}, initialSP = ${p.initialSP},\n\tminExtraParagraphs = ${p.minExtraParagraphs ?? 0}, maxExtraParagraphs = ${p.maxExtraParagraphs ?? 0},`;
  const inlineMeta = `--!strict\nreturn {\n\t${header}\n\timage = ${quote(p.image)},\n\trelocations = {${relocationEntries.join("")}},\n\twarnings = {${warningEntries.join("")}},\n\tdirectBlocks = {\n${directEntries.map((x) => "\t\t" + x).join("\n")}\n\t},\n\tblockRanges = {\n${rangeEntries.map((x) => "\t\t" + x).join("\n")}\n\t},\n}\n`;
  if (inlineMeta.length <= SOURCE_LIMIT && p.image.length <= 32768)
    add("Program_Meta", inlineMeta);
  else {
    const image = splitString("Program_Image", p.image);
    const ranges = splitTable("Meta_Ranges", rangeEntries),
      direct = splitTable("Meta_Direct", directEntries),
      relocations = splitTable("Meta_Relocations", relocationEntries),
      warningChunks = splitTable("Meta_Warnings", warningEntries);
    const mergeMap = (field: string, names: string[]) =>
      names
        .map(
          (n) =>
            `for k,v in require(script.Parent.${n}) do meta.${field}[k] = v end`,
        )
        .join("\n");
    const append = (field: string, names: string[]) =>
      names
        .map(
          (n) =>
            `for _,v in require(script.Parent.${n}) do table.insert(meta.${field}, v) end`,
        )
        .join("\n");
    add(
      "Program_Meta",
      `--!strict\nlocal meta: any = {\n\t${header}\n\timage = ${image}, relocations = {}, warnings = {}, directBlocks = {}, blockRanges = {},\n}\n${mergeMap("blockRanges", ranges)}\n${mergeMap("directBlocks", direct)}\n${append("relocations", relocations)}\n${append("warnings", warningChunks)}\nreturn meta\n`,
    );
  }
  const files = await assets(assetRoot);
  const inlineAssets = `--!strict\nreturn {\n${files.map((f) => `[${quote(f.name)}] = ${quote(f.data)},`).join("\n")}\n}\n`;
  if (
    inlineAssets.length <= SOURCE_LIMIT &&
    files.every((f) => f.data.length <= 32768)
  )
    add("VFS_Assets", inlineAssets);
  else {
    const entries = files.map(
      (f) => `[${quote(f.name)}] = ${splitString("Asset_Data", f.data)},`,
    );
    const names = splitTable("VFS_Files", entries);
    add(
      "VFS_Assets",
      `--!strict\nlocal assets: {[string]: string} = {}\n${names.map((n) => `for k,v in (require(script.Parent.${n}) :: {[string]: string}) do assets[k] = v end`).join("\n")}\nreturn assets\n`,
    );
  }
  const blockHeader = `--!strict\n--!native\nlocal CPU = require(script.Parent.Parent.CPUState)\nlocal Interpreter = require(script.Parent.Parent.Interpreter)\nlocal blocks: {[number]: (any, any, number) -> (number, number)} = {}\n`;
  const blockFooter = "return blocks\n";
  const chunkNames: string[] = [];
  let group: string[] = [];
  let groupSize = blockHeader.length + blockFooter.length;
  const flushBlock = () => {
    const name = `Blocks_${String(chunkNames.length + 1).padStart(3, "0")}`;
    add(name, blockHeader + group.join("\n") + blockFooter);
    chunkNames.push(name);
    group = [];
    groupSize = blockHeader.length + blockFooter.length;
  };
  for (const ins of instructions) {
    const code = block(ins, chains.get(ik(ins)), p.mode32);
    if (code.length + blockHeader.length + blockFooter.length > SOURCE_LIMIT)
      throw new Error(`single block exceeds source limit at ${ik(ins)}`);
    if (group.length >= 1500 || groupSize + code.length + 1 > SOURCE_LIMIT)
      flushBlock();
    group.push(code);
    groupSize += code.length + 1;
  }
  if (group.length || !chunkNames.length) flushBlock();
  add(
    "Blocks",
    `--!strict\nlocal blocks: {[number]: any} = {}\n${chunkNames.map((n) => `for k, v in require(script.Parent.${n}) do blocks[k] = v end`).join("\n")}\nreturn blocks\n`,
  );
  // Only remove files produced by this compiler, after the new set is valid.
  const generated =
    /^(?:Blocks_\d+|Program_Image_\d+|Meta_(?:Ranges|Direct|Relocations|Warnings)_\d+|Asset_Data_\d+|VFS_Files_\d+)\.luau$/;
  for (const name of await readdir(out))
    if (generated.test(name) && !sources.has(name.slice(0, -6)))
      await unlink(join(out, name));
  for (const [name, source] of sources)
    await writeFile(join(out, `${name}.luau`), source);
  const chunks = chunkNames.length;
  return {
    instructions: instructions.length,
    direct: instructions.filter((i) => i.direct).length,
    chunks,
    warnings,
  };
}
export function parseTrace(s: string): number[] {
  const keys: number[] = [];
  const add = (v: unknown) => {
    if (
      typeof v === "number" &&
      Number.isInteger(v) &&
      v >= 0 &&
      v <= 0xffffffff
    )
      keys.push(v >>> 0);
    else if (typeof v === "number") throw new Error("invalid trace block");
    else if (typeof v === "string") {
      const m = v.match(/^(?:0x)?([\da-f]{1,4}):(?:0x)?([\da-f]{1,4})$/i);
      if (m) keys.push(key(parseInt(m[1]!, 16), parseInt(m[2]!, 16)));
      else if (/^\d+$/.test(v) && Number(v) <= 0xffffffff)
        keys.push(Number(v) >>> 0);
      else throw new Error("invalid trace block");
    } else if (v && typeof v === "object") {
      const o = v as Record<string, unknown>;
      if (
        typeof o.eip === "number" &&
        Number.isInteger(o.eip) &&
        o.eip >= 0 &&
        o.eip <= 0xffffffff
      ) {
        keys.push(o.eip >>> 0);
        return;
      }
      const cs = o.relCS ?? o.cs,
        ip = o.ip;
      if (
        typeof cs === "number" &&
        Number.isInteger(cs) &&
        cs >= 0 &&
        cs <= 65535 &&
        typeof ip === "number" &&
        Number.isInteger(ip) &&
        ip >= 0 &&
        ip <= 65535
      )
        keys.push(key(cs, ip));
      else throw new Error("invalid trace block");
    } else throw new Error("invalid trace block");
  };
  const trimmed = s.trim();
  if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
    let data: unknown;
    try {
      data = JSON.parse(trimmed);
    } catch {
      throw new Error("invalid trace JSON");
    }
    if (Array.isArray(data)) data.forEach(add);
    else if (data && typeof data === "object") {
      const o = data as Record<string, unknown>;
      const entries = o.discoveredBlocks ?? o.blocks ?? o.keys;
      if (Array.isArray(entries)) entries.forEach(add);
      else {
        const table = (
          entries && typeof entries === "object" ? entries : o
        ) as Record<string, unknown>;
        for (const [k, v] of Object.entries(table)) if (v === true) add(k);
      }
    }
    return [...new Set(keys)];
  }
  for (const line of s.split(/\r?\n/)) {
    const m = line.match(
      /(?:^|\s)(?:0x)?([\da-f]{1,4}):(?:0x)?([\da-f]{1,4})(?:\s|$)/i,
    );
    if (m) keys.push(key(parseInt(m[1]!, 16), parseInt(m[2]!, 16)));
  }
  return [...new Set(keys)];
}
export async function main(args: string[]) {
  if (!args.length || args.includes("--help")) {
    console.log(
      "Usage: bun compiler/src/cli.ts <binary> --out <directory> [--assets <directory>] [--trace-log <file>]",
    );
    return;
  }
  const input = args[0]!;
  let out = "",
    assetRoot: string | undefined,
    trace: string | undefined;
  for (let i = 1; i < args.length; i++) {
    const v = args[++i];
    if (!v) throw new Error(`missing value for ${args[i - 1]}`);
    switch (args[i - 1]) {
      case "--out":
        out = v;
        break;
      case "--assets":
        assetRoot = v;
        break;
      case "--trace-log":
        trace = v;
        break;
      default:
        throw new Error(`unknown option ${args[i - 1]}`);
    }
  }
  if (!out) throw new Error("--out is required");
  const p = parseProgram(await readFile(resolve(input)));
  const stats = await compile(
    p,
    resolve(out),
    assetRoot && resolve(assetRoot),
    trace ? parseTrace(await readFile(trace, "utf8")) : [],
  );
  for (const warning of stats.warnings) console.warn(warning);
  console.log(
    `Emitted ${stats.instructions} instruction blocks, ${stats.direct} directly lifted, ${stats.instructions - stats.direct} interpreter fallback, ${stats.chunks} chunk(s).`,
  );
}
if (import.meta.main)
  main(process.argv.slice(2)).catch((e) => {
    console.error(`dos2luau: ${e.message}`);
    process.exitCode = 1;
  });
