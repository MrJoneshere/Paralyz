#!/usr/bin/env node
// Paralyz / scripts/build.mjs
//
// Packs loader.luau + src/*.luau into a single self-contained file,
// dist/paralyz.bundle.luau, for when the repo is still private (HttpGet cannot
// read a private repo, so the module-by-module download path is unavailable).
//
// The dev path stays intact: loader.luau fetches src/*.luau over raw.githubusercontent.com
// one file at a time. The bundle only swaps in a literal table of the same
// sources behind the `local PARALYZ_MODULES = nil -- PARALYZ_BUNDLE` sentinel.
//
//   node scripts/build.mjs

import { readFile, writeFile, readdir, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SENTINEL = /local PARALYZ_MODULES = nil -- PARALYZ_BUNDLE/;

const loaderPath = path.join(root, "loader.luau");
const srcDir = path.join(root, "src");
const distDir = path.join(root, "dist");

const loader = await readFile(loaderPath, "utf8");

const sentinelCount = loader.match(new RegExp(SENTINEL.source, "g"))?.length ?? 0;
if (sentinelCount !== 1) {
	console.error(`expected exactly one bundle sentinel in loader.luau, found ${sentinelCount}`);
	process.exit(1);
}

const entries = (await readdir(srcDir))
	.filter((name) => name.endsWith(".luau"))
	.sort();

if (entries.length === 0) {
	console.error("src/ has no .luau files");
	process.exit(1);
}

const sources = [];
for (const name of entries) {
	const body = await readFile(path.join(srcDir, name), "utf8");
	const key = name.replace(/\.luau$/, "");
	sources.push({ key, body });
}

// Pick a long-bracket level that cannot collide with the sources themselves.
let level = 1;
const closers = () => "]".repeat(level) + "[".repeat(level);
for (;;) {
	const closer = closers();
	if (sources.every(({ body }) => !body.includes(closer)) && !loader.includes(closer)) {
		break;
	}
	level += 1;
	if (level > 16) {
		console.error("could not find a safe long-bracket level");
		process.exit(1);
	}
}
const open = "[" + "=".repeat(level) + "[";
const close = "]" + "=".repeat(level) + "]";

const table = [
	"local PARALYZ_MODULES = {",
	...sources.map(({ key, body }) => `\t[${JSON.stringify(key)}] = ${open}\n${body}${close},`),
	"}",
].join("\n");

const bundled = loader.replace(SENTINEL, () => table);

await mkdir(distDir, { recursive: true });
const outPath = path.join(distDir, "paralyz.bundle.luau");
await writeFile(outPath, bundled, "utf8");

const kb = (n) => (n / 1024).toFixed(1) + " KB";
console.log(`built ${path.relative(root, outPath)}  ${kb(Buffer.byteLength(bundled))}`);
for (const { key, body } of sources) {
	console.log(`  src/${key}.luau ${kb(Buffer.byteLength(body))}`);
}
console.log(`  loader.luau ${kb(Buffer.byteLength(loader))}`);
