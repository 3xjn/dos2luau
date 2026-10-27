import { spawnSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
const keys = ["One", "Return", "One", "Return"];
async function run(interpreted: boolean) {
  const result = spawnSync(
    "bun",
    [
      "scripts/test-runtime.ts",
      "tests/oregon.luau",
      ...(interpreted ? ["--interpreted"] : []),
      ...keys,
    ],
    { stdio: "inherit" },
  );
  if (result.status !== 0) throw Error("Oregon guest run failed");
  return {
    state: JSON.parse(await readFile(".local-games/oregon-state.json", "utf8")),
    ram: await readFile(".local-games/oregon.ram"),
    pixels: await readFile(".local-games/oregon-frame.rgba"),
  };
}
const aot = await run(false),
  reference = await run(true);
if (!aot.ram.equals(reference.ram)) throw Error("AOT/reference RAM mismatch");
if (!aot.pixels.equals(reference.pixels))
  throw Error("AOT/reference framebuffer mismatch");
for (const key of [
  "cs",
  "ip",
  "flags",
  "regs",
  "halted",
  "waitingForKey",
  "mode",
  "instructions",
]) {
  if (JSON.stringify(aot.state[key]) !== JSON.stringify(reference.state[key]))
    throw Error(`AOT/reference CPU mismatch: ${key}`);
}
const report = {
  status: "pass",
  scenario:
    "VGA main menu -> Travel the trail -> banker -> wagon-leader name prompt",
  instructions: aot.state.instructions,
  directInstructions: aot.state.directInstructions,
  interpretedInstructions: aot.state.interpretedInstructions,
  ramBytes: aot.ram.length,
  pixelBytes: aot.pixels.length,
  exactCPU: true,
  exactRAM: true,
  exactFramebuffer: true,
};
await writeFile(
  ".local-games/oregon-verification.json",
  JSON.stringify(report, null, 2) + "\n",
);
console.log(report);
