import { readFile, readdir, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dir, "..");
const oregon = process.argv.includes("--oregon");
function xml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
let nextId = 0;
function item(
  className: string,
  name: string,
  source: string | undefined,
  children = "",
): string {
  return `<Item class="${className}" referent="RBX${nextId++}"><Properties><string name="Name">${xml(name)}</string>${source === undefined ? "" : `<ProtectedString name="Source">${xml(source)}</ProtectedString>`}</Properties>${children}</Item>`;
}
async function moduleTree(directory: string, name: string): Promise<string> {
  const entries = await readdir(directory, { withFileTypes: true });
  const init = entries.find((e) => e.name === "init.luau");
  const children: string[] = [];
  for (const e of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (e.name === "init.luau") continue;
    if (
      e.isDirectory() &&
      e.name.startsWith("Out") &&
      e.name !== "Out" &&
      !(oregon && e.name === "OutOregon")
    )
      continue;
    if (e.isDirectory())
      children.push(await moduleTree(path.join(directory, e.name), e.name));
    else if (e.name.endsWith(".luau"))
      children.push(
        item(
          "ModuleScript",
          e.name.slice(0, -5),
          await readFile(path.join(directory, e.name), "utf8"),
        ),
      );
  }
  return item(
    init ? "ModuleScript" : "Folder",
    name,
    init
      ? await readFile(path.join(directory, "init.luau"), "utf8")
      : undefined,
    children.join(""),
  );
}
const runtime = await moduleTree(path.join(root, "runtime"), "DOS2Luau");
let client = await readFile(
  path.join(root, "examples/Demo.client.luau"),
  "utf8",
);
if (oregon) {
  if (!client.includes("-- DOS2LUAU_PROGRAM_OPTIONS"))
    throw Error("Missing program insertion marker");
  client = client.replace(
    "-- DOS2LUAU_PROGRAM_OPTIONS",
    `
  meta=require(ReplicatedStorage.DOS2Luau.OutOregon.Program_Meta),
  blocks=require(ReplicatedStorage.DOS2Luau.OutOregon.Blocks),
  assets=require(ReplicatedStorage.DOS2Luau.OutOregon.VFS_Assets),
  programPath='C:\\\\OREGON.EXE',`,
  );
  if (!client.includes("-- DOS2LUAU_INPUT_OPTIONS"))
    throw Error("Missing input insertion marker");
  client = client.replace(
    "-- DOS2LUAU_INPUT_OPTIONS",
    "smartMenuClick = true, tapToContinue = true, gamepadMenuHighlight = true, touchQuickBar = true,",
  );
}
const demo = item("LocalScript", "DOSDemo", client);
const document = `<roblox version="4">${item("Folder", "dos2luau", undefined, runtime + demo)}</roblox>`;
await mkdir(path.join(root, "dist"), { recursive: true });
const destination = oregon
  ? "dist/dos2luau-oregon.rbxmx"
  : "dist/dos2luau.rbxmx";
await writeFile(path.join(root, destination), document);
console.log(
  `Built ${destination} (insert model; move DOS2Luau to ReplicatedStorage and DOSDemo to StarterPlayerScripts).`,
);
