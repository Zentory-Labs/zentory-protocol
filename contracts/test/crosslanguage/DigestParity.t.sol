// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {StrategyExecutor} from "../../src/keeper/StrategyExecutor.sol";
import {HyperCoreAdapter} from "../../src/keeper/HyperCoreAdapter.sol";

/// @title DigestParityTest
/// @notice Verifies EIP-712 digest parity between Solidity StrategyExecutor
///         and the Python signer in engine/src/signals/signer.py.
///
/// HOW TO USE:
/// 1. Run `forge test --match-path "**/DigestParity*" -vv`
/// 2. Copy the values from `test_digestParity_printVector` output
/// 3. Run the Python signer with those exact values
/// 4. Verify the Python output matches the signature produced here
///
/// Example Python verification:
///   cd engine
///   pip install eth_account eth_hash web3
///   python3 -c "
///     from src.signals.signer import SignalSigner
///     s = SignalSigner('0x' + 'fa19' * 32)
///     sig = s.sign_hex(vault='0x...', direction=1, size=..., price=...,
///                       nonce=0, expiry=2**256-1, chain_id=998,
///                       executor_address='0x...')
///     print(sig)
///   "
contract DigestParityTest is Test {
    StrategyExecutor public executor;
    HyperCoreAdapter public adapter;

    uint256 internal constant SIGNAL_SIGNER_KEY = 0xFA19;

    function setUp() external {
        adapter = new HyperCoreAdapter(address(this));
        executor = new StrategyExecutor(address(adapter), address(this));
        executor.setAuthorizedSigner(vm.addr(SIGNAL_SIGNER_KEY));
    }

    // ─── Print test vector for Python signer comparison ───────────────────────
    //
    // Run this test to get the exact values to feed into the Python signer.
    // The Python signer output should match the signature produced by `forge test`.
    function test_digestParity_printVector() external view {
        address vault = address(0x1234567890123456789012345678901234567890);
        uint8 direction = 1;
        uint256 size = 1_000_000;
        uint64 price = 65_000_00000;
        uint256 nonce = 0;
        uint256 expiry = type(uint256).max;

        bytes32 domainSep = executor.DOMAIN_SEPARATOR();
        bytes32 typehash = executor.SIGNAL_TYPEHASH();

        console2.log("=== Verification Vector for Python Signer ===");
        console2.log("chain_id:    ", block.chainid);
        console2.log("executor:    ", address(executor));
        console2.log("vault:       ", vault);
        console2.log("direction:   ", direction);
        console2.log("size:       ", size);
        console2.log("price:      ", price);
        console2.log("nonce:      ", nonce);
        console2.log("expiry:     ", expiry);
        console2.log("DOMAIN_SEP:  ");
        console2.logBytes32(domainSep);
        console2.log("TYPEHASH:    ");
        console2.logBytes32(typehash);
        console2.log("SIGNER_KEY:  ", vm.addr(SIGNAL_SIGNER_KEY));
        console2.log("============================================");
    }

    // ─── Canonical end-to-end: sign in Solidity, verify on-chain ───────────
    //
    // This test proves that:
    // 1. Solidity's DOMAIN_SEPARATOR + SIGNAL_TYPEHASH are correctly set
    // 2. The digest constructed with them can be signed by vm.sign()
    // 3. StrategyExecutor.accepts the signature via executeSignal()
    //
    // NOTE: We use nonce 1 to avoid collision with the printVector test.
    // The test runs after printVector in Forge's default ordering.
    function test_digestParity_soliditySignVerify() external {
        address vault = address(0x1234567890123456789012345678901234567890);
        uint256 nonce = 1; // Avoid collision with printVector (nonce 0)

        bytes32 domainSep = keccak256(abi.encode(
            keccak256("EIP712Domain(uint256 chainId,address executor)"),
            block.chainid,
            address(executor)
        ));

        bytes32 structHash = keccak256(abi.encode(
            executor.SIGNAL_TYPEHASH(),
            vault,
            uint8(1),
            uint256(1_000_000),
            uint64(65_000_00000),
            nonce,
            type(uint256).max
        ));

        bytes32 digest = keccak256(abi.encodePacked(
            bytes1(0x19), bytes1(0x01),
            domainSep,
            structHash
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNAL_SIGNER_KEY, digest);
        bytes memory sig = abi.encodePacked(r, s, bytes1(v));

        executor.grantRole(executor.KEEPER_ROLE(), address(this));
        executor.executeSignal(vault, 1, 1_000_000, 65_000_00000, nonce, type(uint256).max, sig);

        assertEq(executor.nonces(vault), 1, "nonce should be consumed");
        console2.log("Digest parity confirmed: Solidity sign + on-chain verify SUCCESS");
    }

    // ─── Domain separator stability check ──────────────────────────────────
    //
    // Verifies the contract's DOMAIN_SEPARATOR matches what we compute
    // from the source-of-truth constructor code.
    function test_digestParity_domainSeparatorMatchesSource() external view {
        bytes32 actual = executor.DOMAIN_SEPARATOR();
        bytes32 expected = keccak256(abi.encode(
            keccak256("EIP712Domain(uint256 chainId,address executor)"),
            block.chainid,
            address(executor)
        ));

        assertEq(actual, expected, "DOMAIN_SEPARATOR does not match expected computation");
        assertTrue(actual != bytes32(0), "DOMAIN_SEPARATOR should not be zero");

        console2.log("Domain separator verified:");
        console2.logBytes32(actual);
    }

    // ─── Signal typehash correctness ───────────────────────────────────────
    //
    // Verifies SIGNAL_TYPEHASH matches the canonical string from signer.py.
    function test_digestParity_signalTypehashMatchesPython() external view {
        bytes32 actual = executor.SIGNAL_TYPEHASH();
        bytes32 expected = keccak256(
            "TradeSignal(address vault,uint8 direction,uint256 size,uint64 price,uint256 nonce,uint256 expiry)"
        );

        assertEq(actual, expected, "SIGNAL_TYPEHASH mismatch with Python signer definition");
        console2.log("SIGNAL_TYPEHASH verified:");
        console2.logBytes32(actual);
    }
}
