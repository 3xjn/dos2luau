import { unpackLzExe } from "./lzexe";
export type Relocation = { offset: number; segment: number };
export type Program = {
  format: "com" | "mz" | "coff" | "le";
  image: Uint8Array;
  entryCS: number;
  entryIP: number;
  initialSS: number;
  initialSP: number;
  relocations: Relocation[];
  mode32?: boolean;
  imageBase?: number;
  minExtraParagraphs?: number;
  maxExtraParagraphs?: number;
  packing?: string;
};
const u16 = (b: Uint8Array, o: number) => b[o]! | (b[o + 1]! << 8);
const u32 = (b: Uint8Array, o: number) =>
  (u16(b, o) + u16(b, o + 2) * 65536) >>> 0;
export function parseProgram(b: Uint8Array): Program {
  if (!b.length) throw new Error("empty executable");
  const unpacked = unpackLzExe(b);
  if (unpacked) return unpacked;
  if (b[0] === 0x4c && b[1] === 0x01) return parseCoff(b);
  if (b[0] === 0x4c && b[1] === 0x45) return parseLE(b, 0);
  if (b.length >= 64 && b[0] === 0x4d && b[1] === 0x5a) {
    const at = u32(b, 60);
    if (at >= 64 && at + 2 <= b.length && b[at] === 0x4c && b[at + 1] === 0x45)
      return parseLE(b, at);
    if (at >= 64 && at + 20 <= b.length && b[at] === 0x4c && b[at + 1] === 0x01)
      return parseCoff(b.slice(at));
  }
  if (b[0] === 0x4c && (b[1] === 0x45 || b[1] === 0x58))
    throw new Error("unsupported LE/LX executable");
  if (b[0] !== 0x4d || b[1] !== 0x5a) {
    if (b.length > 0xff00) throw new Error("COM image exceeds segment");
    return {
      format: "com",
      image: b,
      entryCS: 0,
      entryIP: 0x100,
      initialSS: 0,
      initialSP: 0xfffe,
      relocations: [],
    };
  }
  if (b.length < 28) throw new Error("truncated MZ header");
  const last = u16(b, 2),
    pages = u16(b, 4),
    n = u16(b, 6),
    header = u16(b, 8) * 16,
    ro = u16(b, 24);
  if (!pages || last > 511) throw new Error("invalid MZ page count");
  const size = (pages - 1) * 512 + (last || 512);
  if (size > b.length || header < 28 || header > size || ro + n * 4 > header)
    throw new Error("invalid MZ size or relocation table");
  if (b.length >= 64) {
    const p = (b[60]! | (b[61]! << 8) | (b[62]! << 16) | (b[63]! << 24)) >>> 0;
    if (p + 2 <= b.length) {
      const sig = String.fromCharCode(b[p]!, b[p + 1]!);
      if (sig === "LE" || sig === "LX" || sig === "PE" || sig === "NE")
        throw new Error(`unsupported ${sig} executable or relocations`);
    }
  }
  const image = b.slice(header, size),
    relocations: Relocation[] = [];
  for (let i = 0; i < n; i++) {
    const offset = u16(b, ro + i * 4),
      segment = u16(b, ro + i * 4 + 2);
    if (segment * 16 + offset + 1 >= image.length)
      throw new Error("MZ relocation outside image");
    relocations.push({ offset, segment });
  }
  const entryCS = u16(b, 22),
    entryIP = u16(b, 20);
  if (entryCS * 16 + entryIP >= image.length)
    throw new Error("MZ entry outside image");
  return {
    format: "mz",
    image,
    entryCS,
    entryIP,
    initialSS: u16(b, 14),
    initialSP: u16(b, 16),
    minExtraParagraphs: u16(b, 10),
    maxExtraParagraphs: u16(b, 12),
    relocations,
  };
}

// Statically link a single i386 COFF object into a bounded, flat image.
function parseCoff(b: Uint8Array): Program {
  const check = (o: number, n: number) => {
    if (!Number.isSafeInteger(o) || o < 0 || n < 0 || o + n > b.length)
      throw new Error("truncated COFF");
  };
  check(0, 20);
  const count = u16(b, 2),
    symoff = u32(b, 8),
    nsyms = u32(b, 12),
    opt = u16(b, 16);
  if (!count || count > 96 || opt !== 0)
    throw new Error("unsupported COFF header");
  check(20, count * 40);
  if (nsyms) {
    check(symoff, nsyms * 18);
  }
  type Section = {
    base: number;
    size: number;
    raw: number;
    rawSize: number;
    rel: number;
    nrel: number;
    name: string;
  };
  const sections: Section[] = [];
  let cursor = 0x1000;
  for (let i = 0; i < count; i++) {
    const at = 20 + i * 40,
      name = String.fromCharCode(...b.slice(at, at + 8)).replace(/\0.*$/, "");
    const size = u32(b, at + 16),
      raw = u32(b, at + 20),
      rel = u32(b, at + 24),
      nrel = u16(b, at + 32),
      flags = u32(b, at + 36);
    if (nrel === 0xffff || (flags & 0x01000000) !== 0)
      throw new Error("unsupported COFF extended relocations");
    if (size && raw) check(raw, size);
    if (nrel) check(rel, nrel * 10);
    if (!raw && size && (flags & 0x80) === 0)
      throw new Error("COFF section lacks data");
    cursor = (cursor + 15) & ~15;
    sections.push({
      base: cursor,
      size,
      raw,
      rawSize: raw ? size : 0,
      rel,
      nrel,
      name,
    });
    cursor += size;
    if (cursor > 0x70000) throw new Error("COFF image too large");
  }
  const image = new Uint8Array(cursor);
  for (const sec of sections)
    if (sec.rawSize)
      image.set(b.slice(sec.raw, sec.raw + sec.rawSize), sec.base);
  const symbol = (idx: number) => {
    if (idx >= nsyms) throw new Error("invalid COFF symbol index");
    const at = symoff + idx * 18,
      section = u16(b, at + 12);
    if (section === 0 || section > sections.length)
      throw new Error("unsupported unresolved COFF symbol");
    const sec = sections[section - 1]!,
      value = u32(b, at + 8);
    if (value > sec.size) throw new Error("COFF symbol outside section");
    return sec.base + value;
  };
  const view = new DataView(image.buffer);
  for (const sec of sections)
    for (let i = 0; i < sec.nrel; i++) {
      const at = sec.rel + i * 10,
        off = u32(b, at),
        idx = u32(b, at + 4),
        type = u16(b, at + 8);
      if (type === 0) continue;
      if (type !== 6 && type !== 20)
        throw new Error(`unsupported COFF relocation ${type}`);
      if (off + 4 > sec.size)
        throw new Error("COFF relocation outside section");
      const loc = sec.base + off,
        target = symbol(idx),
        addend = view.getUint32(loc, true);
      view.setUint32(
        loc,
        (addend + target - (type === 20 ? loc + 4 : 0)) >>> 0,
        true,
      );
    }
  const text = sections.find((s) => s.name === ".text");
  if (!text || !text.size) throw new Error("COFF requires .text entry section");
  let entry = text.base;
  for (let i = 0; i < nsyms; ) {
    const at = symoff + i * 18,
      inline = b.slice(at, at + 8);
    let name = "";
    if (u32(b, at) !== 0)
      name = String.fromCharCode(...inline).replace(/\0.*$/, "");
    if (name === "_start" || name === "start") entry = symbol(i);
    i += 1 + b[at + 17]!;
    if (i > nsyms) throw new Error("invalid COFF auxiliary symbols");
  }
  return {
    format: "coff",
    mode32: true,
    imageBase: 0x1000,
    image: image.slice(0x1000),
    entryCS: 0,
    entryIP: entry,
    initialSS: 0,
    initialSP: 0x80000,
    relocations: [],
  };
}

function parseLE(b: Uint8Array, h: number): Program {
  const check = (o: number, n: number) => {
    if (!Number.isSafeInteger(o) || o < 0 || n < 0 || o + n > b.length)
      throw new Error("truncated LE");
  };
  check(h, 0xb0);
  if (
    b[h + 2] !== 0 ||
    b[h + 3] !== 0 ||
    u32(b, h + 4) !== 0 ||
    u16(b, h + 8) < 2 ||
    u16(b, h + 8) > 4
  )
    throw new Error("unsupported LE byte order, level or CPU");
  const pages = u32(b, h + 0x14),
    entryObj = u32(b, h + 0x18),
    entryOff = u32(b, h + 0x1c),
    stackObj = u32(b, h + 0x20),
    stackOff = u32(b, h + 0x24),
    pageSize = u32(b, h + 0x28),
    lastSize = u32(b, h + 0x2c),
    objOff = u32(b, h + 0x40),
    count = u32(b, h + 0x44),
    mapOff = u32(b, h + 0x48),
    fixOff = u32(b, h + 0x68),
    imports = u32(b, h + 0x74),
    dataOff = u32(b, h + 0x80);
  if (
    !count ||
    count > 96 ||
    !pageSize ||
    pageSize > 65536 ||
    pages > 4096 ||
    lastSize > pageSize ||
    imports
  )
    throw new Error("unsupported LE objects, pages or imports");
  check(h + objOff, count * 24);
  check(h + mapOff, pages * 4);
  if (!fixOff && (u32(b, h + 0x30) !== 0 || u32(b, h + 0x6c) !== 0))
    throw new Error("unsupported LE fixup table");
  if (fixOff) {
    check(h + fixOff, (pages + 1) * 4);
    for (let i = 0; i <= pages; i++)
      if (u32(b, h + fixOff + i * 4) !== 0)
        throw new Error("unsupported LE fixups");
  }
  type Obj = { size: number; base: number; first: number; count: number };
  const objs: Obj[] = [];
  let end = 0;
  for (let i = 0; i < count; i++) {
    const o = h + objOff + i * 24,
      size = u32(b, o),
      base = u32(b, o + 4),
      flags = u32(b, o + 8),
      first = u32(b, o + 12),
      n = u32(b, o + 16);
    if (
      (flags & 0x2000) === 0 ||
      (flags & ~0x2007) !== 0 ||
      base < 0x1000 ||
      base + size > 0x80000 ||
      n > Math.ceil(size / pageSize) ||
      (n && (!first || first + n - 1 > pages))
    )
      throw new Error("unsupported LE object layout");
    if (objs.some((x) => base < x.base + x.size && x.base < base + size))
      throw new Error("overlapping LE objects");
    objs.push({ size, base, first, count: n });
    end = Math.max(end, base + size);
  }
  if (
    !entryObj ||
    entryObj > count ||
    entryOff >= objs[entryObj - 1]!.size ||
    !stackObj ||
    stackObj > count ||
    stackOff > objs[stackObj - 1]!.size
  )
    throw new Error("invalid LE entry or stack");
  const image = new Uint8Array(end);
  for (const obj of objs)
    for (let i = 0; i < obj.count; i++) {
      const map = h + mapOff + (obj.first - 1 + i) * 4,
        index = b[map]! * 65536 + b[map + 1]! * 256 + b[map + 2]!,
        flags = b[map + 3]!;
      if (flags !== 0 || !index || index > pages)
        throw new Error("unsupported LE page type");
      const src = dataOff + (index - 1) * pageSize,
        available = index === pages && lastSize ? lastSize : pageSize,
        len = Math.min(available, obj.size - i * pageSize);
      check(src, len);
      image.set(b.slice(src, src + len), obj.base + i * pageSize);
    }
  const imageBase = Math.min(...objs.map((o) => o.base));
  return {
    format: "le",
    mode32: true,
    imageBase,
    image: image.slice(imageBase),
    entryCS: 0,
    entryIP: objs[entryObj - 1]!.base + entryOff,
    initialSS: 0,
    initialSP: objs[stackObj - 1]!.base + stackOff,
    relocations: [],
  };
}
