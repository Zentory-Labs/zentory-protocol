// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title ZENT Token
/// @notice Fixed-supply ERC-20 governance token with vote-escrowed governance support.
///         Total supply: 1,000,000,000 tokens with 18 decimals.
///         No mint or admin function exists on mainnet; a testnet-only mint is
///         included for development/auditing only and is permanently disabled on
///         mainnet (chain != 998).
contract ZENT is ERC20Votes, ERC20Permit {
    /// @notice Cap on total supply (fixed at 1B tokens)
    uint256 public constant CAP = 1_000_000_000 * 10 ** 18;

    /// @notice Immutable deployer address — set once in constructor.
    address public immutable DEPLOYER;

    /// @notice Flag to permanently disable testnet minting after first use.
    bool private _testnetMintDone;

    /// @notice Testnet-only mint. Reverts on any chain other than HyperEVM testnet (998).
    ///         Can only be called once by the deployer. Prevents accidental mainnet use.
    modifier onlyTestnet() {
        require(block.chainid == 998, "ZENT: not testnet");
        _;
    }

    constructor() ERC20("Zentory Token", "ZENT") ERC20Permit("Zentory Token") {
        DEPLOYER = msg.sender;
        _mint(msg.sender, CAP);
    }

    /// @notice Mint tokens for testing on HyperEVM testnet only.
    ///         Disabled after first call. Restricted to deployer.
    /// @param to    Recipient address.
    /// @param amount Amount to mint (in ZENT wei — 18 decimals).
    function mintForTestnet(address to, uint256 amount) external onlyTestnet {
        require(msg.sender == DEPLOYER, "ZENT: not deployer");
        require(!_testnetMintDone, "ZENT: testnet mint disabled");
        _testnetMintDone = true;
        _mint(to, amount);
    }

    /// @notice Allow any holder to burn their own tokens.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Burn tokens from a specific address (requires prior approval).
    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /// @dev Resolves diamond conflict: both ERC20 and ERC20Votes define _update.
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @dev Resolves diamond conflict: ERC20Permit and Nonces both define nonces.
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
