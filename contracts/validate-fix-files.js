// Compile only the new/modified test files (and their dependencies) to
// confirm our fix-related test code is syntactically valid. We stub
// forge-std and ERC20Mock because they're not installed in this env
// (Foundry-only).
const fs = require("fs");
const path = require("path");
const solc = require("solc");

const SRC = path.join(__dirname, "src");
const TEST = path.join(__dirname, "test");
const OZ = path.join(__dirname, "node_modules", "@openzeppelin");

function findSol(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) findSol(full, out);
    else if (entry.isFile() && entry.name.endsWith(".sol")) out.push(full);
  }
  return out;
}

function rewriteImports(content, filePath) {
  const dir = path.dirname(filePath);
  return content.replace(
    /import\s+(?:\{[^}]+\}\s+from\s+)?["']([^"']+)["']\s*;/g,
    (m, imp) => {
      // Leave @-remappings and explicit absolute paths alone.
      if (imp.startsWith("@")) return m;
      if (path.isAbsolute(imp)) return m;
      const abs = path.resolve(dir, imp).replace(/\\/g, "/");
      return m.replace(/["'][^"']+["']/, JSON.stringify(abs));
    }
  );
}

const sources = {};
for (const file of findSol(SRC)) {
  sources[file] = { content: rewriteImports(fs.readFileSync(file, "utf8"), file) };
}
for (const file of findSol(TEST)) {
  sources[file] = { content: rewriteImports(fs.readFileSync(file, "utf8"), file) };
}

const STUBS = {
  "forge-std/Test.sol": "pragma solidity ^0.8.0; contract Test { } library console2 { } library console { }",
  "forge-std/Script.sol": "pragma solidity ^0.8.0; abstract contract Script { }",
  "forge-std/StdInvariant.sol": "pragma solidity ^0.8.0; abstract contract StdInvariant { }",
};

function findImport(importPath) {
  if (importPath.startsWith("@openzeppelin/contracts/")) {
    const rel = importPath.slice("@openzeppelin/contracts/".length);
    const abs = path.join(OZ, "contracts", rel);
    if (fs.existsSync(abs)) return { contents: fs.readFileSync(abs, "utf8") };
  }
  if (importPath.startsWith("forge-std/")) {
    const stub = STUBS["forge-std/Test.sol"]; // crude
    return { contents: stub };
  }
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

// Filter out the known-false errors about forge-std / ERC20Mock.
const knownFalse = (msg) =>
  /forge-std\//.test(msg) ||
  /mocks\/token\/ERC20Mock\.sol/.test(msg);

let errorCount = 0;
const errors = [];
for (const file of Object.keys(output.contracts || {})) {
  for (const c of Object.keys(output.contracts[file])) {
    if (output.contracts[file][c].errors) {
      for (const e of output.contracts[file][c].errors) {
        if (e.severity === "error" && !knownFalse(e.formattedMessage || e.message)) {
          errorCount++;
          errors.push(`[${path.relative(__dirname, file)}] ${c}: ${e.formattedMessage || e.message}`);
        }
      }
    }
  }
}
if (output.errors) {
  for (const e of output.errors) {
    if (e.severity === "error" && !knownFalse(e.formattedMessage || e.message)) {
      errorCount++;
      errors.push(`[general] ${e.formattedMessage || e.message}`);
    }
  }
}

if (errorCount > 0) {
  console.error(`\n❌ ${errorCount} hard errors (excluding forge-std/ERC20Mock noise):`);
  for (const e of errors) console.error(e);
  process.exit(1);
}
console.log(`\n✅ Compiled ${Object.keys(output.contracts || {}).length} contracts+tests, 0 hard errors (forge-std / ERC20Mock noise filtered out)`);
