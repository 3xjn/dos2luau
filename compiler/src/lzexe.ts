import type { Program, Relocation } from "./formats";

// The LZ90/91 stub signatures and decoding layout are based on UNLZEXE 0.8
// (Kou, David Kirschbaum, Alan Modra and Vesselin Bontchev), distributed with
// Fabrice Bellard's LZEXE 0.91 package. UNLZEXE is described as public domain:
// https://pushbx.org/ecm/doc/lzexe.htm
// https://bellard.org/lzexe/  (LZEXE itself is separate software.)
const SIG90 =
  "060e1f8b0e0c008bf14e89f78cdb031e0a008ec3b40031edfdac01c5aae2fa8b160e008ac229c58ac629c539d5740cba9101b409cd21b8ff4ccd2153b8530050cb2e8b2e08008cda89e83d00107603b8001029c529c229c38eda8ec3b103d3e089c1d1e048488bf08bf8f3a509ed75d8fc8ec28edb31f631ffba1000ad89c5d1ed4a7505ad89c5b2107303a4ebf131c9d1ed4a7505ad89c5b2107222d1ed4a7505ad89c5b210d1d1d1ed4a7505ad89c5b210d1d14141acb7ff8ad8e91300ad8bd8b103d2ef80cfe080e407740c88e14141268a01aae2faeba6ac08c074403c01740588c141ebea89";
const SIG91 =
  "060e1f8b0e0c008bf14e89f78cdb031e0a008ec3fdf3a453b82b0050cb2e8b2e08008cda89e83d00107603b8001029c529c229c38eda8ec3b103d3e089c1d1e048488bf08bf8f3a509ed75d8fc8ec28edb31f631ffba1000ad89c5d1ed4a7505ad89c5b2107303a4ebf131c9d1ed4a7505ad89c5b2107222d1ed4a7505ad89c5b210d1d1d1ed4a7505ad89c5b210d1d14141acb7ff8ad8e91300ad8bd8b103d2ef80cfe080e407740c88e14141268a01aae2faeba6ac08c074343c01740588c141ebea89fb83e70f81c70020b104d3eb8cc001d82d00028ec089f383e60fd3eb8cd801d88ed8e972";
const bytes = (hex: string) =>
  Uint8Array.from(hex.match(/../g)!.map((x) => parseInt(x, 16)));
export const LZ_SIGNATURES = { 90: bytes(SIG90), 91: bytes(SIG91) };
const word = (b: Uint8Array, p: number) => b[p]! + b[p + 1]! * 256;

export function unpackLzStream(input: Uint8Array, limit = 0xa0000): Uint8Array {
  let pos = 0,
    bits = 0,
    remaining = 0;
  const output = new Uint8Array(limit);
  let used = 0;
  function read() {
    if (pos >= input.length)
      throw new Error("truncated LZEXE compressed stream");
    return input[pos++]!;
  }
  function readWord() {
    const a = read();
    return a + read() * 256;
  }
  function bit() {
    if (remaining === 0) {
      bits = readWord();
      remaining = 16;
    }
    const result = bits & 1;
    bits >>>= 1;
    remaining--;
    if (remaining === 0) {
      bits = readWord();
      remaining = 16;
    }
    return result;
  }
  for (;;) {
    if (bit()) {
      if (used >= limit) throw new Error("LZEXE output exceeds memory limit");
      output[used++] = read();
      continue;
    }
    let count: number, span: number;
    if (!bit()) {
      count = bit() * 2 + bit() + 2;
      span = read() - 256;
    } else {
      const lo = read(),
        hi = read();
      span = (lo | ((hi & 0xf8) << 5) | 0xe000) - 65536;
      count = (hi & 7) + 2;
      if (count === 2) {
        const extra = read();
        if (extra === 0) break;
        if (extra === 1) continue;
        count = extra + 1;
      }
    }
    if (span >= 0 || used + span < 0)
      throw new Error("invalid LZEXE back-reference");
    if (used + count > limit)
      throw new Error("LZEXE output exceeds memory limit");
    for (let i = 0; i < count; i++) {
      output[used] = output[used + span]!;
      used++;
    }
  }
  return output.slice(0, used);
}

export function unpackLzExe(b: Uint8Array): Program | undefined {
  if (b.length < 2 || b[0] !== 0x4d || b[1] !== 0x5a) return undefined;
  const marked = b.length >= 32 ? String.fromCharCode(...b.slice(28, 32)) : "";
  const markedVersion =
    marked === "LZ91"
      ? 91
      : marked === "LZ09" || marked === "LZ90"
        ? 90
        : undefined;
  if (b.length < 28) {
    if (markedVersion) throw new Error("truncated LZEXE header");
    return undefined;
  }
  const header = word(b, 8),
    cs = word(b, 22),
    ip = word(b, 20),
    base = (header + cs) * 16,
    entry = base + ip;
  let version: 90 | 91 | undefined;
  for (const n of [90, 91] as const) {
    const sig = LZ_SIGNATURES[n];
    if (
      entry >= 0 &&
      entry + sig.length <= b.length &&
      sig.every((v, i) => b[entry + i] === v)
    ) {
      version = n;
      break;
    }
  }
  if (!version) {
    if (markedVersion) throw new Error("unsupported or truncated LZEXE stub");
    return undefined;
  }
  if (markedVersion && markedVersion !== version)
    throw new Error("LZEXE version mismatch");
  const pages = word(b, 4),
    last = word(b, 2),
    fileSize = (pages - 1) * 512 + (last || 512);
  if (!pages || last > 511 || fileSize > b.length || fileSize < base + 16)
    throw new Error("invalid LZEXE MZ size");
  if (entry + LZ_SIGNATURES[version].length > fileSize)
    throw new Error("LZEXE stub exceeds declared MZ size");
  b = b.subarray(0, fileSize);
  if (base + 16 > b.length) throw new Error("truncated LZEXE information");
  const info = Array.from({ length: 8 }, (_, i) => word(b, base + i * 2)),
    start = (header + cs - info[4]!) * 16;
  if (start < header * 16 || start >= base || base > b.length)
    throw new Error("invalid LZEXE compressed data bounds");
  const image = unpackLzStream(b.subarray(start, base));
  const relocations: Relocation[] = [];
  let pos = base + (version === 91 ? 0x158 : 0x19d);
  const read = () => {
    if (pos >= b.length) throw new Error("truncated LZEXE relocation table");
    return b[pos++]!;
  };
  const readWord = () => {
    const lo = read();
    return lo + read() * 256;
  };
  const add = (segment: number, offset: number) => {
    if (segment * 16 + offset + 1 >= image.length)
      throw new Error("LZEXE relocation outside image");
    if (relocations.length >= 65535)
      throw new Error("too many LZEXE relocations");
    relocations.push({ segment, offset });
  };
  if (version === 90) {
    for (let segment = 0; segment < 0x10000; segment += 0x1000) {
      const count = readWord();
      for (let i = 0; i < count; i++) add(segment, readWord());
    }
  } else {
    let linear = 0;
    for (;;) {
      let delta = read();
      if (delta === 0) {
        delta = readWord();
        if (delta === 1) break;
        if (delta === 0) {
          linear += 0xfff0;
          if (linear > 0xfffff) throw new Error("LZEXE relocation overflow");
          continue;
        }
      }
      linear += delta;
      if (linear > 0xfffff) throw new Error("LZEXE relocation overflow");
      add(linear >>> 4, linear & 15);
    }
  }
  const packedMin = word(b, 10),
    packedMax = word(b, 12);
  let min = packedMin,
    max = packedMax;
  if (packedMax !== 0) {
    const overhead = info[5]! + Math.ceil(info[6]! / 16) + 9;
    if (overhead > packedMin)
      throw new Error("invalid LZEXE allocation metadata");
    min = packedMin - overhead;
    if (packedMax !== 0xffff) {
      max = packedMax - overhead;
      if (max < min) throw new Error("invalid LZEXE maximum allocation");
    }
  }
  if (info[1]! * 16 + info[0]! >= image.length)
    throw new Error("LZEXE entry outside image");
  return {
    format: "mz",
    image,
    entryIP: info[0]!,
    entryCS: info[1]!,
    initialSP: info[2]!,
    initialSS: info[3]!,
    minExtraParagraphs: min,
    maxExtraParagraphs: max,
    relocations,
    packing: `lzexe${version}`,
  };
}
