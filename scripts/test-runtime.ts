import { readdir, readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";

const root = path.resolve(import.meta.dir, "..");
const staging = path.join(root, ".test-runtime");

async function stage(directory: string) {
  for (const entry of await readdir(path.join(root, directory), {
    withFileTypes: true,
  })) {
    const relative = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      await stage(relative);
      continue;
    }
    if (!entry.name.endsWith(".luau")) continue;
    const sourcePath = path.join(root, relative);
    let source = await readFile(sourcePath, "utf8");
    // Resolve only static Roblox ModuleScript paths. Source is never evaluated or
    // stripped of types: Lune compiles the same module bodies as Roblox.
    source = source.replace(
      /require\(script((?:\.[A-Za-z_][A-Za-z_0-9]*)+)\)/g,
      (_match, chain: string) => {
        let target =
          entry.name === "init.luau"
            ? path.dirname(sourcePath)
            : sourcePath.replace(/\.luau$/, "");
        for (const member of chain.slice(1).split(".")) {
          target =
            member === "Parent"
              ? path.dirname(target)
              : path.join(target, member);
        }
        let modulePath = path
          .relative(path.dirname(sourcePath), target)
          .replaceAll("\\", "/");
        if (!modulePath.startsWith(".")) modulePath = "./" + modulePath;
        return `require(${JSON.stringify(modulePath)})`;
      },
    );
    // Lune treats init.luau imports relative to the importing directory. Stage
    // the root ModuleScript under an ordinary filename for identical file imports.
    const destination = path.join(
      staging,
      relative === path.join("runtime", "init.luau")
        ? "runtime/DOS.luau"
        : relative,
    );
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, source);
  }
}

await stage("runtime");
await stage("tests");
const testScript = process.argv[2] ?? "tests/runtime.luau";
const result = spawnSync(
  "lune",
  ["run", path.join(staging, testScript), ...process.argv.slice(3)],
  { cwd: root, stdio: "inherit" },
);
if (result.error) throw result.error;
process.exit(result.status ?? 1);
