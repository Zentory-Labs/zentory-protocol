// One-off: compile changed Solidity files with solc 0.8.28 and emit only
// hard errors. We can't use Foundry in this env, so we use the standalone
// solc-js compiler with a manual import resolver. Relative imports are
// rewritten inline to absolute paths before compilation; the import
// callback handles the @openzeppelin remapping.

const fs = require("fs");
const path = require("path");
const solc = require("solc");

const ROOT = path.join(__dirname, "src");
const OZ = path.join(__dirname, "node_modules", "@openzeppelin");

function findSol(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      findSol(full, out);
    } else if (entry.isFile() && entry.name.endsWith(".sol")) {
      out.push(full);
    }
  }
  return out;
}

function rewriteImports(content, filePath) {
  const dir = path.dirname(filePath);
  return content.replace(
    /import\s+(?:\{[^}]+\}\s+from\s+)?["']([^"']+)["']\s*;/g,
    (m, imp) => {
      // Don't rewrite @openzeppelin — the import callback handles it.
      if (imp.startsWith("@")) return m;
      const abs = path.resolve(dir, imp);
      const absNorm = abs.replace(/\\/g, "/");
      // Replace the relative path with the absolute path, keeping the rest
      // of the import statement shape.
      return m.replace(/["'][^"']+["']/, JSON.stringify(absNorm));
    }
  );
}

const sources = {};
for (const file of findSol(ROOT)) {
  const original = fs.readFileSync(file, "utf8");
  sources[file] = { content: rewriteImports(original, file) };
}

function findImport(importPath) {
  if (importPath.startsWith("@openzeppelin/contracts/")) {
    const rel = importPath.slice("@openzeppelin/contracts/".length);
    const abs = path.join(OZ, "contracts", rel);
    if (fs.existsSync(abs)) {
      return { contents: fs.readFileSync(abs, "utf8") };
    }
  }
  if (importPath.startsWith("forge-std/")) {
    return { error: "forge-std not installed (Foundry-only)" };
  }
  // Absolute paths (rewritten from relative imports) — resolve directly.
  if (fs.existsSync(importPath)) {
    return { contents: fs.readFileSync(importPath, "utf8") };
  }
  return { error: "File not found: " + importPath };
}

const input = {
  language: "Solidity",
  sources,
  settings: {
    outputSelection: { "*": { "*": ["abi"] } },
    optimizer: { enabled: true, runs: 200 },
  },
};

const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImport }));
let errorCount = 0;
const errors = [];
for (const file of Object.keys(output.contracts || {})) {
  for (const c of Object.keys(output.contracts[file])) {
    if (output.contracts[file][c].errors) {
      for (const e of output.contracts[file][c].errors) {
        if (e.severity === "error") {
          errorCount++;
          errors.push(`[${path.relative(__dirname, file)}] ${c}: ${e.formattedMessage || e.message}`);
        }
      }
    }
  }
}
if (output.errors) {
  for (const e of output.errors) {
    if (e.severity === "error") {
      errorCount++;
      errors.push(`[general] ${e.formattedMessage || e.message}`);
    }
  }
}

if (errorCount > 0) {
  console.error(`\n❌ ${errorCount} hard errors:`);
  for (const e of errors) console.error(e);
  process.exit(1);
}
console.log(`\n✅ Compiled ${Object.keys(output.contracts || {}).length} contracts, 0 hard errors`);
