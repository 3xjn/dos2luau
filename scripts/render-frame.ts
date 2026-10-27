import { readFile, writeFile } from "node:fs/promises";
import { deflateSync } from "node:zlib";
const state = JSON.parse(
  await readFile(".local-games/oregon-state.json", "utf8"),
);
const pixels = await readFile(".local-games/oregon-frame.rgba");
function crc32(b: Buffer) {
  let c = 0xffffffff;
  for (const x of b) {
    c ^= x;
    for (let j = 0; j < 8; j++) c = (c >>> 1) ^ (c & 1 ? 0xedb88320 : 0);
  }
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type: string, data: Buffer) {
  const tag = Buffer.from(type),
    out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length);
  tag.copy(out, 4);
  data.copy(out, 8);
  out.writeUInt32BE(crc32(Buffer.concat([tag, data])), 8 + data.length);
  return out;
}
const header = Buffer.alloc(13);
header.writeUInt32BE(state.width);
header.writeUInt32BE(state.height, 4);
header[8] = 8;
header[9] = 6;
const rows = Buffer.alloc(state.height * (state.width * 4 + 1));
for (let y = 0; y < state.height; y++)
  pixels.copy(
    rows,
    y * (state.width * 4 + 1) + 1,
    y * state.width * 4,
    (y + 1) * state.width * 4,
  );
await writeFile(
  ".local-games/oregon-frame.png",
  Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0)),
  ]),
);
console.log("Wrote .local-games/oregon-frame.png");
