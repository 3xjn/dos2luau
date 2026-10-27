import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { parseProgram } from "../compiler/src/formats";
import { compile } from "../compiler/src/cli";

const root = path.resolve(import.meta.dir, "..");
class Assembler {
  bytes: number[] = [];
  labels = new Map<string, number>();
  patches: { at: number; label: string; relative: boolean; width: number }[] =
    [];
  emit(...bytes: number[]) {
    this.bytes.push(...bytes);
  }
  word(value: number) {
    this.emit(value & 255, (value >>> 8) & 255);
  }
  label(name: string) {
    this.labels.set(name, this.bytes.length + 0x100);
  }
  address(name: string) {
    this.patches.push({
      at: this.bytes.length,
      label: name,
      relative: false,
      width: 2,
    });
    this.word(0);
  }
  branch(op: number, name: string, width = 1) {
    this.emit(op);
    this.patches.push({
      at: this.bytes.length,
      label: name,
      relative: true,
      width,
    });
    for (let i = 0; i < width; i++) this.emit(0);
  }
  finish() {
    for (const p of this.patches) {
      const target = this.labels.get(p.label);
      if (target === undefined) throw Error(p.label);
      const value = target - (p.relative ? p.at + 0x100 + p.width : 0);
      if (p.relative && p.width === 1 && (value < -128 || value > 127))
        throw Error("short jump overflow");
      for (let j = 0; j < p.width; j++)
        this.bytes[p.at + j] = (value >>> (j * 8)) & 255;
    }
    return new Uint8Array(this.bytes);
  }
}
const a = new Assembler();
a.emit(0xfb, 0xfc); // STI; CLD
a.emit(0xb8, 0x13, 0x00, 0xcd, 0x10); // BIOS mode 13
a.emit(0xb8, 0x00, 0xa0, 0x8e, 0xc0); // ES=A000
a.emit(0xb0, 0xb6, 0xe6, 0x43); // PIT ch2 square wave, low/high
a.emit(0xe4, 0x61, 0x0c, 0x03, 0xe6, 0x61); // speaker enable
a.emit(0xbe);
a.address("notes");
a.emit(0xb3, 1); // BL=frame color
a.label("frame");
a.emit(0xad, 0xe6, 0x42, 0x88, 0xe0, 0xe6, 0x42); // LODSW; divisor low/high
a.emit(0x81, 0xfe);
a.address("notesEnd");
a.branch(0x72, "noteReady");
a.emit(0xbe);
a.address("notes");
a.label("noteReady");
a.emit(0x31, 0xff, 0xb9, 0x00, 0xfa, 0x88, 0xd8, 0xf3, 0xaa); // 64000 pixels
a.emit(0xfe, 0xc3); // INC BL
a.emit(0xb4, 1, 0xcd, 0x16); // key available?
a.branch(0x74, "frame");
a.emit(0xb4, 0, 0xcd, 0x16, 0x3c, 0x1b); // read key, Escape quits
a.branch(0x75, "color");
a.emit(0xe4, 0x61, 0x24, 0xfc, 0xe6, 0x61, 0xb8, 0, 0x4c, 0xcd, 0x21);
a.label("color");
a.emit(0x88, 0xc3);
a.branch(0xeb, "frame");
a.label("notes");
[2712, 2416, 2152, 2032, 1810, 1612, 1436, 1356].forEach((n) => a.word(n));
a.label("notesEnd");
await mkdir(path.join(root, "examples/assets"), { recursive: true });
await writeFile(path.join(root, "examples/demo.com"), a.finish());
await writeFile(
  path.join(root, "examples/assets/README.TXT"),
  "dos2luau demonstration assets\r\n",
);
console.log(
  "Demo:",
  await compile(
    parseProgram(a.finish()),
    path.join(root, "runtime/Out"),
    path.join(root, "examples/assets"),
  ),
);

// Generated parity fixture intentionally combines direct and fallback instructions.
const parity = Uint8Array.from([
  0xb8, 0xff, 0x7f, 0x05, 1, 0, 0xbb, 0xff, 0xff, 0x43, 0x3d, 0, 0x80, 0x75, 3,
  0x35, 0x55, 0xaa, 0xa3, 0, 3, 0xb9, 5, 0, 0x49, 0x75, 0xfd, 0xf4,
]);
await mkdir(path.join(root, "tests/fixtures"), { recursive: true });
await writeFile(path.join(root, "tests/fixtures/parity.com"), parity);
console.log(
  "Parity:",
  await compile(parseProgram(parity), path.join(root, "runtime/OutParity")),
);

const mzCode = Uint8Array.from([
  0xb8, 0, 0, 0x8e, 0xd8, 0xb8, 7, 0, 0x05, 8, 0, 0xa3, 0, 3, 0xf4,
]);
const mz = new Uint8Array(32 + mzCode.length),
  mzv = new DataView(mz.buffer);
mz.set([0x4d, 0x5a]);
mzv.setUint16(2, mz.length, true);
mzv.setUint16(4, 1, true);
mzv.setUint16(6, 1, true);
mzv.setUint16(8, 2, true);
mzv.setUint16(16, 0x400, true);
mzv.setUint16(24, 28, true);
mzv.setUint16(28, 1, true);
mz.set(mzCode, 32);
await writeFile(path.join(root, "tests/fixtures/relocation.exe"), mz);
console.log(
  "MZ:",
  await compile(parseProgram(mz), path.join(root, "runtime/OutMZ")),
);

const flatCode = Uint8Array.from([
  0xb8, 0xff, 0xff, 0xff, 0x7f, 0x05, 1, 0, 0, 0, 0xbb, 0, 0, 2, 0, 0x89, 0x03,
  0xf4,
]);
const coff = new Uint8Array(60 + flatCode.length),
  cv = new DataView(coff.buffer);
cv.setUint16(0, 0x14c, true);
cv.setUint16(2, 1, true);
coff.set(new TextEncoder().encode(".text"), 20);
cv.setUint32(36, flatCode.length, true);
cv.setUint32(40, 60, true);
cv.setUint32(56, 0x20, true);
coff.set(flatCode, 60);
await writeFile(path.join(root, "tests/fixtures/flat.coff"), coff);
console.log(
  "COFF:",
  await compile(parseProgram(coff), path.join(root, "runtime/OutCOFF")),
);
const le = new Uint8Array(0x200 + flatCode.length),
  lv = new DataView(le.buffer);
le.set([0x4c, 0x45]);
lv.setUint16(8, 2, true);
lv.setUint32(0x14, 1, true);
lv.setUint32(0x18, 1, true);
lv.setUint32(0x20, 1, true);
lv.setUint32(0x24, 0x2000, true);
lv.setUint32(0x28, 0x1000, true);
lv.setUint32(0x2c, flatCode.length, true);
lv.setUint32(0x40, 0xb0, true);
lv.setUint32(0x44, 1, true);
lv.setUint32(0x48, 0xc8, true);
lv.setUint32(0x68, 0xcc, true);
lv.setUint32(0x80, 0x200, true);
lv.setUint32(0xb0, 0x2000, true);
lv.setUint32(0xb4, 0x10000, true);
lv.setUint32(0xb8, 0x2007, true);
lv.setUint32(0xbc, 1, true);
lv.setUint32(0xc0, 1, true);
le[0xca] = 1;
le.set(flatCode, 0x200);
await writeFile(path.join(root, "tests/fixtures/flat.le"), le);
console.log(
  "LE:",
  await compile(parseProgram(le), path.join(root, "runtime/OutLE")),
);

// Independent BigInt oracles catch precision loss in 32x32 multiplication and
// 64/32 division in Luau's double-based number representation.
let seed = 0x12345678;
function random32() {
  seed ^= seed << 13;
  seed ^= seed >>> 17;
  seed ^= seed << 5;
  return seed >>> 0;
}
const vectors: string[] = [];
for (let i = 0; i < 64; i++) {
  const a = BigInt(random32()),
    b = BigInt(random32());
  const product = a * b;
  vectors.push(
    `{op=0xe3,a=${a},b=${b},hi=${product >> 32n},lo=${product & 0xffffffffn}},`,
  );
  const divisor = BigInt(random32() || 1),
    quotient = BigInt(random32()),
    remainder = BigInt(random32()) % divisor;
  const dividend = divisor * quotient + remainder;
  vectors.push(
    `{op=0xf3,a=${dividend & 0xffffffffn},d=${dividend >> 32n},b=${divisor},hi=${remainder},lo=${quotient}},`,
  );
}
await writeFile(
  path.join(root, "tests/fixtures/arithmetic.luau"),
  "--!strict\nreturn {\n" + vectors.join("\n") + "\n}\n",
);

// One second, exactly 440 cycles. Upload this user-owned waveform and configure
// speakerAssetId in Demo.client.luau to enable audible PC speaker output.
const rate = 44100,
  samples = rate,
  wav = Buffer.alloc(44 + samples * 2);
wav.write("RIFF");
wav.writeUInt32LE(wav.length - 8, 4);
wav.write("WAVEfmt ", 8);
wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20);
wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(rate, 24);
wav.writeUInt32LE(rate * 2, 28);
wav.writeUInt16LE(2, 32);
wav.writeUInt16LE(16, 34);
wav.write("data", 36);
wav.writeUInt32LE(samples * 2, 40);
for (let i = 0; i < samples; i++)
  wav.writeInt16LE((i * 440) % rate < rate / 2 ? 8192 : -8192, 44 + i * 2);
await writeFile(path.join(root, "examples/square-440.wav"), wav);
