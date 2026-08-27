// Validate Foundry tests compile with solc.
const fs = require("fs");
const path = require("path");
const solc = require("solc");

const ROOT = path.join(__dirname, "test");
const SRC = path.join(__dirname, "src");
const OZ = path.join(__dirname, "node_modules", "@openzeppelin");

function findSol(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
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
      // Leave @-remappings alone — handled by the import callback.
      if (imp.startsWith("@")) return m;
      // Leave forge-std/ imports alone — they're stubbed via the import callback.
      if (imp.startsWith("forge-std/")) return m;
      // Leave already-absolute paths alone.
      if (path.isAbsolute(imp)) return m;
      const abs = path.resolve(dir, imp).replace(/\\/g, "/");
      return m.replace(/["'][^"']+["']/, JSON.stringify(abs));
    }
  );
}

const sources = {};
// Include src files (test files import them) — but skip their bodies via
// a stub trick is overkill; let's just include both directories.
for (const file of findSol(SRC)) {
  const original = fs.readFileSync(file, "utf8");
  sources[file] = { content: rewriteImports(original, file) };
}
for (const file of findSol(ROOT)) {
  const original = fs.readFileSync(file, "utf8");
  sources[file] = { content: rewriteImports(original, file) };
}

function findImport(importPath) {
  if (importPath.startsWith("@openzeppelin/contracts/")) {
    const rel = importPath.slice("@openzeppelin/contracts/".length);
    const abs = path.join(OZ, "contracts", rel);
    if (fs.existsSync(abs)) return { contents: fs.readFileSync(abs, "utf8") };
    // Mock subpackage (not part of core release on some installs) — stub it.
    if (rel.startsWith("mocks/")) {
      return {
        contents:
          "// OpenZeppelin mocks/* stub (not installed)\n" +
          "pragma solidity ^0.8.0;\n" +
          "import {IERC20} from \"@openzeppelin/contracts/token/ERC20/IERC20.sol\";\n" +
          "import {ERC20} from \"@openzeppelin/contracts/token/ERC20/ERC20.sol\";\n" +
          "contract ERC20Mock is ERC20 {\n" +
          "  constructor() ERC20(\"Mock\", \"MOCK\") {}\n" +
          "  function mint(address, uint256) external {}\n" +
          "  function burn(address, uint256) external {}\n" +
          "}",
      };
    }
  }
  if (importPath === "forge-std/Vm.sol") {
    return {
      contents:
        "// forge-std/Vm.sol stub\n" +
        "pragma solidity ^0.8.0;\n" +
        "interface Vm {\n" +
        "  struct Log { bytes32[] topics; bytes data; address emitter; }\n" +
        "  function prank(address) external;\n" +
        "  function startPrank(address) external;\n" +
        "  function stopPrank() external;\n" +
        "  function warp(uint256) external;\n" +
        "  function roll(uint256) external;\n" +
        "  function deal(address, uint256) external;\n" +
        "  function expectRevert() external;\n" +
        "  function expectRevert(bytes calldata) external;\n" +
        "  function expectRevert(bytes4) external;\n" +
        "  function expectEmit() external;\n" +
        "  function expectEmit(bool, bool, bool, bool) external;\n" +
        "  function expectEmit(bool, bool, bool, bool, address) external;\n" +
        "  function mockCall(address, bytes calldata, bytes calldata) external;\n" +
        "  function clearMockedCalls() external;\n" +
        "  function recordLogs() external;\n" +
        "  function getRecordedLogs() external returns (Log[] memory);\n" +
        "  function label(address, string calldata) external;\n" +
        "  function addr(uint256) external pure returns (address);\n" +
        "  function envUint(string calldata) external pure returns (uint256);\n" +
        "  function envInt(string calldata) external pure returns (int256);\n" +
        "  function envAddress(string calldata) external pure returns (address);\n" +
        "  function envBool(string calldata) external pure returns (bool);\n" +
        "  function envString(string calldata) external pure returns (string memory);\n" +
        "  function envBytes(string calldata) external pure returns (bytes memory);\n" +
        "  function sign(uint256, bytes32) external pure returns (uint8, bytes32, bytes32);\n" +
        "  function assume(bool) external pure;\n" +
        "  function store(address, bytes32, bytes32) external;\n" +
        "  function load(address, bytes32) external pure returns (bytes32);\n" +
        "  function chainId(uint256) external;\n" +
        "  function envOr(string calldata, bool) external pure returns (bool);\n" +
        "  function envOr(string calldata, uint256) external pure returns (uint256);\n" +
        "  function envOr(string calldata, string calldata) external pure returns (string memory);\n" +
        "  function envOr(string calldata, address) external pure returns (address);\n" +
        "  function skip(bool) external;\n" +
        "  function toString(bytes32) external pure returns (string memory);\n" +
        "  function toString(address) external pure returns (string memory);\n" +
        "  function toString(uint256) external pure returns (string memory);\n" +
        "  function ffi(string[] calldata) external pure returns (bytes memory);\n" +
        "  function parseBytes(string calldata) external pure returns (bytes memory);\n" +
        "  function parseAddress(string calldata) external pure returns (address);\n" +
        "  function parseUint(string calldata) external pure returns (uint256);\n" +
        "  function parseInt(string calldata) external pure returns (int256);\n" +
        "  function parseBool(string calldata) external pure returns (bool);\n" +
        "  function toBytes32(address) external pure returns (bytes32);\n" +
        "  function parseJsonBytes32(string calldata) external pure returns (bytes32);\n" +
        "  function parseJsonAddress(string calldata) external pure returns (address);\n" +
        "}\n",
    };
  }
  if (importPath.startsWith("forge-std/")) {
    // Test.sol stub: imports Vm from a sibling stub so its `Vm.Log` type
    // matches the type returned by `vm.getRecordedLogs()` when Vm.sol is
    // also imported by the same test file.
    return {
      contents:
        "// forge-std/Test.sol stub\n" +
        "pragma solidity ^0.8.0;\n" +
        "import {Vm} from \"forge-std/Vm.sol\";\n" +
        "abstract contract Test {\n" +
        "  Vm internal constant vm = Vm(address(uint160(uint256(keccak256(\"hevm cheat code\")))));\n" +
        "  function expectRevert() internal pure {}\n" +
        "  function expectRevert(bytes calldata) internal pure {}\n" +
        "  function expectRevert(bytes4) internal pure {}\n" +
        "  function expectEmit(bool, bool, bool, bool) internal pure {}\n" +
        "  function expectEmit(bool, bool, bool, bool, address) internal pure {}\n" +
        "  function prank(address) internal pure {}\n" +
        "  function startPrank(address) internal pure {}\n" +
        "  function stopPrank() internal pure {}\n" +
        "  function warp(uint256) internal pure {}\n" +
        "  function roll(uint256) internal pure {}\n" +
        "  function deal(address, uint256) internal pure {}\n" +
        "  function mockCall(address, bytes calldata, bytes calldata) internal pure {}\n" +
        "  function clearMockedCalls() internal pure {}\n" +
        "  function recordLogs() internal pure {}\n" +
        "  function getRecordedLogs() internal pure returns (Vm.Log[] memory) { return new Vm.Log[](0); }\n" +
        "  function makeAddr(string memory) internal pure returns (address) { return address(uint160(uint256(keccak256(abi.encodePacked(\"makeAddr\"))))); }\n" +
        "  function makeAccount(string memory) internal pure returns (address) { return address(uint160(uint256(keccak256(abi.encodePacked(\"makeAccount\"))))); }\n" +
        "  function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) { return x < min ? min : (x > max ? max : x); }\n" +
        "  function bound(uint128 x, uint128 min, uint128 max) internal pure returns (uint128) { return x < min ? min : (x > max ? max : x); }\n" +
        "  function bound(uint64 x, uint64 min, uint64 max) internal pure returns (uint64) { return x < min ? min : (x > max ? max : x); }\n" +
        "  function bound(int256 x, int256 min, int256 max) internal pure returns (int256) { return x < min ? min : (x > max ? max : x); }\n" +
        "  // DSTest global asserts\n" +
        "  function assertTrue(bool b) internal pure { require(b, \"assertTrue\"); }\n" +
        "  function assertTrue(bool b, string memory err) internal pure { require(b, err); }\n" +
        "  function assertFalse(bool b) internal pure { require(!b, \"assertFalse\"); }\n" +
        "  function assertFalse(bool b, string memory err) internal pure { require(!b, err); }\n" +
        "  function assertEq(uint256 a, uint256 b) internal pure { require(a == b, \"assertEq uint\"); }\n" +
        "  function assertEq(uint256 a, uint256 b, string memory err) internal pure { require(a == b, err); }\n" +
        "  function assertEq(int256 a, int256 b) internal pure { require(a == b, \"assertEq int\"); }\n" +
        "  function assertEq(int256 a, int256 b, string memory err) internal pure { require(a == b, err); }\n" +
        "  function assertEq(address a, address b) internal pure { require(a == b, \"assertEq addr\"); }\n" +
        "  function assertEq(address a, address b, string memory err) internal pure { require(a == b, err); }\n" +
        "  function assertEq(bytes32 a, bytes32 b) internal pure { require(a == b, \"assertEq b32\"); }\n" +
        "  function assertEq(bytes32 a, bytes32 b, string memory err) internal pure { require(a == b, err); }\n" +
        "  function assertEq(bool a, bool b) internal pure { require(a == b, \"assertEq bool\"); }\n" +
        "  function assertEq(bool a, bool b, string memory err) internal pure { require(a == b, err); }\n" +
        "  function assertEq(string memory a, string memory b) internal pure { require(keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)), \"assertEq str\"); }\n" +
        "  function assertEq(string memory a, string memory b, string memory err) internal pure { require(keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)), err); }\n" +
        "  function assertEq(bytes memory a, bytes memory b) internal pure { require(keccak256(a) == keccak256(b), \"assertEq bytes\"); }\n" +
        "  function assertEq(bytes memory a, bytes memory b, string memory err) internal pure { require(keccak256(a) == keccak256(b), err); }\n" +
        "  function assertGt(uint256 a, uint256 b) internal pure { require(a > b, \"assertGt\"); }\n" +
        "  function assertGt(int256 a, int256 b) internal pure { require(a > b, \"assertGt\"); }\n" +
        "  function assertGt(uint256 a, uint256 b, string memory err) internal pure { require(a > b, err); }\n" +
        "  function assertGt(int256 a, int256 b, string memory err) internal pure { require(a > b, err); }\n" +
        "  function assertGe(uint256 a, uint256 b) internal pure { require(a >= b, \"assertGe\"); }\n" +
        "  function assertGe(uint256 a, uint256 b, string memory err) internal pure { require(a >= b, err); }\n" +
        "  function assertGe(int256 a, int256 b) internal pure { require(a >= b, \"assertGe\"); }\n" +
        "  function assertGe(int256 a, int256 b, string memory err) internal pure { require(a >= b, err); }\n" +
        "  function assertLt(uint256 a, uint256 b) internal pure { require(a < b, \"assertLt\"); }\n" +
        "  function assertLt(uint256 a, uint256 b, string memory err) internal pure { require(a < b, err); }\n" +
        "  function assertLt(int256 a, int256 b) internal pure { require(a < b, \"assertLt\"); }\n" +
        "  function assertLt(int256 a, int256 b, string memory err) internal pure { require(a < b, err); }\n" +
        "  function assertLe(uint256 a, uint256 b) internal pure { require(a <= b, \"assertLe\"); }\n" +
        "  function assertLe(uint256 a, uint256 b, string memory err) internal pure { require(a <= b, err); }\n" +
        "  function assertLe(int256 a, int256 b) internal pure { require(a <= b, \"assertLe\"); }\n" +
        "  function assertLe(int256 a, int256 b, string memory err) internal pure { require(a <= b, err); }\n" +
        "  function assertNotEq(uint256 a, uint256 b) internal pure { require(a != b, \"assertNotEq\"); }\n" +
        "  function assertNotEq(uint256 a, uint256 b, string memory err) internal pure { require(a != b, err); }\n" +
        "  function assertNotEq(int256 a, int256 b) internal pure { require(a != b, \"assertNotEq\"); }\n" +
        "  function assertNotEq(int256 a, int256 b, string memory err) internal pure { require(a != b, err); }\n" +
        "  function assertApproxEqAbs(uint256 a, uint256 b, uint256 maxDelta) internal pure { uint256 d = a > b ? a - b : b - a; require(d <= maxDelta, \"assertApproxEqAbs\"); }\n" +
        "  function assertApproxEqAbs(uint256 a, uint256 b, uint256 maxDelta, string memory err) internal pure { uint256 d = a > b ? a - b : b - a; require(d <= maxDelta, err); }\n" +
        "  function assertApproxEqRel(uint256 a, uint256 b, uint256 maxPercentDelta) internal pure { require(b != 0, \"assertApproxEqRel zero b\"); uint256 d = a > b ? a - b : b - a; require(d * 1e18 <= maxPercentDelta * b, \"assertApproxEqRel\"); }\n" +
        "  function assertApproxEqRel(uint256 a, uint256 b, uint256 maxPercentDelta, string memory err) internal pure { require(b != 0, err); uint256 d = a > b ? a - b : b - a; require(d * 1e18 <= maxPercentDelta * b, err); }\n" +
        "}\n" +
        "library console2 {\n" +
        "  function log() internal pure {}\n" +
        "  function log(string memory) internal pure {}\n" +
        "  function log(string memory, uint256) internal pure {}\n" +
        "  function log(string memory, int256) internal pure {}\n" +
        "  function log(string memory, address) internal pure {}\n" +
        "  function log(string memory, bool) internal pure {}\n" +
        "  function log(uint256) internal pure {}\n" +
        "  function log(int256) internal pure {}\n" +
        "  function log(address) internal pure {}\n" +
        "  function log(bool) internal pure {}\n" +
        "  function log(uint256, uint256) internal pure {}\n" +
        "  function log(address, uint256) internal pure {}\n" +
        "  function logBytes32(bytes32) internal pure {}\n" +
        "  function logBytes(bytes memory) internal pure {}\n" +
        "}\n" +
        "library console {\n" +
        "  function log() internal pure {}\n" +
        "  function log(string memory) internal pure {}\n" +
        "  function log(uint256) internal pure {}\n" +
        "  function log(int256) internal pure {}\n" +
        "  function log(address) internal pure {}\n" +
        "  function log(bool) internal pure {}\n" +
        "  function log(bytes memory) internal pure {}\n" +
        "}\n",
    };
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
  console.error(`\n❌ ${errorCount} hard errors in tests:`);
  for (const e of errors) console.error(e);
  process.exit(1);
}
console.log(`\n✅ Compiled ${Object.keys(output.contracts || {}).length} contracts+tests, 0 hard errors`);
