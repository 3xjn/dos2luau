import type { Program } from "./formats";
export type Instruction = {
  cs: number;
  ip: number;
  offset: number;
  bytes: number[];
  length: number;
  opcode: number;
  targets: number[];
  terminal: boolean;
  direct: boolean;
  flat?: boolean;
};
const signed8 = (n: number) => (n < 128 ? n : n - 256);
const signed16 = (n: number) => (n < 32768 ? n : n - 65536);
export const key = (cs: number, ip: number) =>
  ((cs & 65535) * 65536 + (ip & 65535)) >>> 0;
// Conservative 8086 length decoder. Unknown encodings stop discovery and are never skipped.
export function decode(p: Program, cs: number, ip: number): Instruction {
  const offset = p.format === "com" ? cs * 16 + ip - 0x100 : cs * 16 + ip;
  if (offset < 0 || offset >= p.image.length)
    throw new Error(
      `instruction outside image at ${cs.toString(16)}:${ip.toString(16)}`,
    );
  let pos = offset;
  const get = () => {
    if (pos >= p.image.length)
      throw new Error(
        `truncated instruction at ${cs.toString(16)}:${ip.toString(16)}`,
      );
    return p.image[pos++]!;
  };
  let op = get();
  let prefix = false;
  while ([0x26, 0x2e, 0x36, 0x3e, 0x64, 0x65, 0xf0, 0xf2, 0xf3].includes(op)) {
    prefix = true;
    if (pos - offset >= 15) throw new Error("too many prefixes");
    op = get();
  }
  if (op === 0x66 || op === 0x67) return decode32(p, ip, cs);
  let modrm = -1,
    imm = 0,
    terminal = false,
    relative = 0,
    conditional = false;
  if (
    (op <= 0x3b && (op & 7) <= 3) ||
    [
      0x62, 0x63, 0x69, 0x6b, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
      0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f, 0xc0, 0xc1, 0xc4, 0xc5,
      0xc6, 0xc7, 0xd0, 0xd1, 0xd2, 0xd3, 0xd8, 0xd9, 0xda, 0xdb, 0xdc, 0xdd,
      0xde, 0xdf, 0xf6, 0xf7, 0xfe, 0xff,
    ].includes(op)
  ) {
    modrm = get();
    const mod = modrm >> 6,
      rm = modrm & 7;
    if (mod === 0 && rm === 6) {
      get();
      get();
    } else if (mod === 1) get();
    else if (mod === 2) {
      get();
      get();
    }
    if ([0x69, 0x81, 0xc7].includes(op)) imm = 2;
    if ([0x6b, 0x80, 0x82, 0x83, 0xc0, 0xc1, 0xc6].includes(op)) imm = 1;
    if ((op === 0xf6 || op === 0xf7) && ((modrm >> 3) & 7) <= 1)
      imm = op === 0xf6 ? 1 : 2;
    if (op === 0xff && [2, 3, 4, 5].includes((modrm >> 3) & 7)) terminal = true;
  } else if (
    (op <= 0x3d && (op & 7) === 4) ||
    [0x6a, 0xa8, 0xcd, 0xd4, 0xd5, 0xe4, 0xe5, 0xe6, 0xe7].includes(op) ||
    (op >= 0xb0 && op <= 0xb7)
  )
    imm = 1;
  else if (
    (op <= 0x3d && (op & 7) === 5) ||
    [0x68, 0xa0, 0xa1, 0xa2, 0xa3, 0xa9, 0xc2, 0xca].includes(op) ||
    (op >= 0xb8 && op <= 0xbf)
  )
    imm = 2;
  else if (op === 0x9a || op === 0xea) {
    imm = 4;
    terminal = true;
  } else if (op === 0xc8) imm = 3;
  else if ((op >= 0x70 && op <= 0x7f) || (op >= 0xe0 && op <= 0xe3)) {
    relative = 1;
    conditional = true;
  } else if (op === 0xeb) {
    relative = 1;
    terminal = true;
  } else if (op === 0xe8 || op === 0xe9) {
    relative = 2;
    terminal = true;
  } else if ([0xc3, 0xcb, 0xcf, 0xcc, 0xcd, 0xce, 0xf4].includes(op))
    terminal = true;
  else if (
    !(
      (op >= 0x40 && op <= 0x5f) ||
      (op >= 0x90 && op <= 0x9f) ||
      (op >= 0xa4 && op <= 0xaf) ||
      (op >= 0xec && op <= 0xef) ||
      (op >= 0xf5 && op <= 0xfd) ||
      [
        0x06, 0x07, 0x0e, 0x16, 0x17, 0x1e, 0x1f, 0x27, 0x2f, 0x37, 0x3f, 0x60,
        0x61, 0x98, 0x99, 0x9b, 0xc9, 0xd6, 0xd7,
      ].includes(op)
    )
  )
    throw new Error(
      `unsupported opcode 0x${op.toString(16)} at ${cs.toString(16)}:${ip.toString(16)}`,
    );
  for (let i = 0; i < imm; i++) get();
  if (
    op === 0xcd ||
    op === 0xcc ||
    op === 0xce ||
    op === 0xf4 ||
    op === 0xc2 ||
    op === 0xca
  )
    terminal = true;
  let delta = 0;
  if (relative === 1) delta = signed8(get());
  else if (relative === 2) {
    const lo = get(),
      hi = get();
    delta = signed16(lo | (hi << 8));
  }
  if (pos - offset > 15) throw new Error("instruction longer than 15 bytes");
  const length = pos - offset,
    next = (ip + length) & 65535,
    targets = relative ? [key(cs, (next + delta) & 65535)] : [];
  if (op === 0x9a || op === 0xea) {
    const targetIP = p.image[pos - 4]! + p.image[pos - 3]! * 256;
    const targetCS = p.image[pos - 2]! + p.image[pos - 1]! * 256;
    const targetOffset =
      targetCS * 16 + targetIP - (p.format === "com" ? 0x100 : 0);
    if (targetOffset >= 0 && targetOffset < p.image.length)
      targets.push(key(targetCS, targetIP));
  }
  if (conditional) targets.push(key(cs, next));
  if (
    op === 0xe8 ||
    op === 0x9a ||
    op === 0xcd ||
    op === 0xcc ||
    op === 0xce ||
    (op === 0xff && [2, 3].includes((modrm >> 3) & 7))
  )
    targets.push(key(cs, next));
  const direct =
    !prefix &&
    ((op >= 0xb0 && op <= 0xbf) ||
      op === 0x90 ||
      (op >= 0x40 && op <= 0x4f) ||
      (op <= 0x3d && ((op & 7) === 4 || (op & 7) === 5)) ||
      (op >= 0x70 && op <= 0x7f) ||
      op === 0xeb ||
      op === 0xe9 ||
      (op >= 0xa0 && op <= 0xa3) ||
      (op === 0xd9 &&
        [0xe8, 0xeb, 0xee, 0xe0, 0xe1, 0xfa, 0xfe, 0xff].includes(modrm)) ||
      ((op === 0xd9 || op === 0xdd) &&
        modrm >> 6 === 0 &&
        (modrm & 7) === 6 &&
        [0, 3].includes((modrm >> 3) & 7)) ||
      (op === 0xd8 &&
        modrm >= 0xc0 &&
        [0, 1, 4, 5, 6, 7].includes((modrm >> 3) & 7)) ||
      (modrm >= 0 &&
        modrm >> 6 === 3 &&
        ((op <= 0x3b && (op & 7) <= 3) ||
          op === 0x84 ||
          op === 0x85 ||
          (op >= 0x88 && op <= 0x8b))));
  const relocated = p.relocations.some((r) => {
    const at = r.segment * 16 + r.offset;
    return at < offset + length && at + 2 > offset;
  });
  return {
    cs,
    ip,
    offset,
    bytes: Array.from(p.image.slice(offset, pos)),
    length,
    opcode: op,
    targets,
    terminal: terminal || conditional,
    direct: direct && !relocated,
  };
}
export function discover(
  p: Program,
  extra: number[] = [],
  warnings: string[] = [],
): Instruction[] {
  if (p.mode32) return discover32(p, extra, warnings);
  const queue = [key(p.entryCS, p.entryIP), ...extra],
    seen = new Set<number>(),
    out: Instruction[] = [];
  while (queue.length) {
    let k = queue.shift()!;
    while (!seen.has(k)) {
      const cs = k >>> 16,
        ip = k & 65535;
      let ins: Instruction;
      try {
        ins = decode(p, cs, ip);
      } catch (e) {
        const off = p.format === "com" ? cs * 16 + ip - 0x100 : cs * 16 + ip;
        if (off >= 0 && off < p.image.length)
          warnings.push(
            `Discovery stopped at ${cs.toString(16)}:${ip.toString(16)}: ${(e as Error).message}`,
          );
        break;
      }
      seen.add(k);
      out.push(ins);
      queue.push(...ins.targets);
      if (ins.terminal) break;
      k = key(cs, (ip + ins.length) & 65535);
    }
  }
  return out.sort((a, b) => key(a.cs, a.ip) - key(b.cs, b.ip));
}

// A conservative flat 32-bit decoder. Every emitted block delegates execution to
// the interpreter; unknown boundaries are left to the dispatcher.
function discover32(
  p: Program,
  extra: number[],
  warnings: string[],
): Instruction[] {
  const todo = [p.entryIP, ...extra],
    seen = new Set<number>(),
    result: Instruction[] = [];
  while (todo.length) {
    let ip = todo.shift()! >>> 0;
    while (!seen.has(ip)) {
      let d: Instruction;
      try {
        d = decode32(p, ip);
      } catch (e) {
        if (
          ip >= (p.imageBase ?? 0) &&
          ip - (p.imageBase ?? 0) < p.image.length
        )
          warnings.push(
            `Discovery stopped at EIP ${ip.toString(16)}: ${(e as Error).message}`,
          );
        break;
      }
      seen.add(ip);
      result.push(d);
      todo.push(...d.targets);
      if (d.terminal) break;
      ip = (ip + d.length) >>> 0;
    }
  }
  return result.sort((a, b) => a.ip - b.ip);
}
export function decode32(p: Program, ip: number, realCS?: number): Instruction {
  const real = realCS !== undefined;
  const start = real
    ? realCS * 16 + ip - (p.format === "com" ? 0x100 : 0)
    : ip - (p.imageBase ?? 0);
  if (start < 0 || start >= p.image.length)
    throw new Error("flat instruction outside image");
  let pos = start;
  const get = () => {
    if (pos >= p.image.length || pos - start >= 15)
      throw new Error("truncated or overlong flat instruction");
    return p.image[pos++]!;
  };
  let op = get(),
    ow = real ? 2 : 4,
    aw = real ? 2 : 4;
  while (
    [0x26, 0x2e, 0x36, 0x3e, 0x64, 0x65, 0x66, 0x67, 0xf0, 0xf2, 0xf3].includes(
      op,
    )
  ) {
    if (op === 0x66) ow = real ? 4 : 2;
    if (op === 0x67) aw = real ? 4 : 2;
    op = get();
  }
  let imm = 0,
    rel = 0,
    terminal = false,
    cond = false,
    modrm = -1,
    call = false,
    nearCondition = -1;
  if (op === 0x0f) {
    const op2 = get();
    if (op2 >= 0x80 && op2 <= 0x8f) {
      rel = ow;
      cond = true;
      nearCondition = 0x70 + (op2 & 15);
    } else throw new Error("unsupported 0f opcode");
  } else if (
    (op <= 0x3b && (op & 7) <= 3) ||
    [
      0x69, 0x6b, 0x80, 0x81, 0x83, 0x84, 0x85, 0x88, 0x89, 0x8a, 0x8b, 0x8d,
      0x8f, 0xc0, 0xc1, 0xc6, 0xc7, 0xd0, 0xd1, 0xd2, 0xd3, 0xd8, 0xd9, 0xda,
      0xdb, 0xdc, 0xdd, 0xde, 0xdf, 0xf6, 0xf7, 0xfe, 0xff,
    ].includes(op)
  ) {
    modrm = get();
    const mod = modrm >> 6,
      rm = modrm & 7;
    if (mod !== 3) {
      if (aw === 4) {
        if (rm === 4) {
          const sib = get();
          if (mod === 0 && (sib & 7) === 5) for (let n = 0; n < 4; n++) get();
        } else if (mod === 0 && rm === 5) for (let n = 0; n < 4; n++) get();
        if (mod === 1) get();
        else if (mod === 2) for (let n = 0; n < 4; n++) get();
      } else {
        if (mod === 0 && rm === 6) {
          get();
          get();
        } else if (mod === 1) get();
        else if (mod === 2) {
          get();
          get();
        }
      }
    }
    if ([0x69, 0x81, 0xc7].includes(op)) imm = ow;
    if ([0x6b, 0x80, 0x83, 0xc0, 0xc1, 0xc6].includes(op)) imm = 1;
    if ((op === 0xf6 || op === 0xf7) && ((modrm >> 3) & 7) <= 1)
      imm = op === 0xf6 ? 1 : ow;
    if (op === 0xff && [2, 3, 4, 5].includes((modrm >> 3) & 7)) {
      terminal = true;
      call = [2, 3].includes((modrm >> 3) & 7);
    }
  } else if (
    (op <= 0x3d && (op & 7) === 4) ||
    [0x6a, 0xa8, 0xcd].includes(op) ||
    (op >= 0xb0 && op <= 0xb7)
  )
    imm = 1;
  else if (
    (op <= 0x3d && (op & 7) === 5) ||
    [0x68, 0xa9].includes(op) ||
    (op >= 0xb8 && op <= 0xbf)
  )
    imm = ow;
  else if (op >= 0xa0 && op <= 0xa3) imm = aw;
  else if (op === 0xc2 || op === 0xca) {
    imm = 2;
    terminal = true;
  } else if ((op >= 0x70 && op <= 0x7f) || (op >= 0xe0 && op <= 0xe3)) {
    rel = 1;
    cond = true;
  } else if (op === 0xeb) {
    rel = 1;
    terminal = true;
  } else if (op === 0xe8 || op === 0xe9) {
    rel = ow;
    terminal = true;
    call = op === 0xe8;
  } else if ([0xc3, 0xcb, 0xcf, 0xcc, 0xce, 0xf4].includes(op)) {
    terminal = true;
    call = [0xcc, 0xce].includes(op);
  } else if (
    !(
      (op >= 0x40 && op <= 0x5f) ||
      (op >= 0x90 && op <= 0x9f) ||
      (op >= 0xa4 && op <= 0xaf) ||
      (op >= 0xec && op <= 0xef) ||
      (op >= 0xf5 && op <= 0xfd) ||
      [0x60, 0x61, 0xc9].includes(op)
    )
  )
    throw new Error("unsupported flat opcode");
  for (let n = 0; n < imm; n++) get();
  if (op === 0xcd) {
    terminal = true;
    call = true;
  }
  let delta = 0;
  if (rel) {
    let u = 0;
    for (let n = 0; n < rel; n++) u += get() * 2 ** (n * 8);
    delta = rel === 1 ? signed8(u) : rel === 2 ? signed16(u) : u | 0;
  }
  const length = pos - start,
    next = (ip + length) >>> 0,
    targets: number[] = [];
  if (rel)
    targets.push(
      real
        ? key(realCS, (next + delta) & 65535)
        : rel === 2
          ? (next + delta) & 65535
          : (next + delta) >>> 0,
    );
  if (cond || call) targets.push(real ? key(realCS, next & 65535) : next);
  const unprefixed = p.image[start] === op;
  const direct =
    !real &&
    unprefixed &&
    (nearCondition >= 0 ||
      op === 0x90 ||
      (op >= 0xb0 && op <= 0xbf) ||
      (op >= 0x40 && op <= 0x4f) ||
      (op <= 0x3d && ((op & 7) === 4 || (op & 7) === 5)) ||
      (op >= 0x70 && op <= 0x7f) ||
      op === 0xeb ||
      op === 0xe9 ||
      (op >= 0xa0 && op <= 0xa3) ||
      (modrm >= 0 &&
        modrm >> 6 === 3 &&
        ((op <= 0x3b && (op & 7) <= 3) || (op >= 0x88 && op <= 0x8b))));
  return {
    cs: real ? realCS : 0,
    ip,
    offset: start,
    bytes: Array.from(p.image.slice(start, pos)),
    length,
    opcode: nearCondition >= 0 ? nearCondition : op,
    targets,
    terminal: terminal || cond,
    direct,
    flat: !real,
  };
}
