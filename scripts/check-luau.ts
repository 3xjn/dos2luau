import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
const root = path.resolve(import.meta.dir, "..");
const ext = process.platform === "win32" ? ".exe" : "";
function tool(name: string) {
  const local = path.join(root, ".tools/luau", name + ext);
  return existsSync(local) ? local : name;
}
function files(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory()
      ? files(path.join(dir, e.name))
      : e.name.endsWith(".luau") && e.name !== "init.luau"
        ? [path.join(dir, e.name)]
        : [],
  );
}
if (!existsSync(path.join(root, ".test-runtime/runtime/DOS.luau")))
  throw Error(
    "Run bun run test:runtime first to stage static ModuleScript imports.",
  );
const runtimeFiles = files(path.join(root, ".test-runtime/runtime"));
for (const [name, args] of [
  ["luau-compile", ["--null", ...runtimeFiles]],
  ["luau-analyze", ["--formatter=plain", ...runtimeFiles]],
] as const) {
  const result = spawnSync(tool(name), [...args], {
    cwd: root,
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  const output = (result.stdout ?? "") + (result.stderr ?? "");
  process.stdout.write(output);
  // Some analyzer builds print type diagnostics as warnings and return zero.
  if (result.status !== 0 || /TypeError:|SyntaxError:/.test(output))
    process.exit(1);
}
console.log(
  `Compiled and strictly analyzed ${runtimeFiles.length} staged runtime modules.`,
);
