// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MedianOracle} from "../../src/oracle/MedianOracle.sol";

contract MedianOracleTest is Test {
    MedianOracle oracle;
    address u1 = makeAddr("u1");
    address u2 = makeAddr("u2");
    address u3 = makeAddr("u3");
    address u4 = makeAddr("u4");

    int256 constant MIN = 100 * 1e8;        // $100
    int256 constant MAX = 1_000_000 * 1e8;  // $1M
    uint256 constant STALE = 1 hours;
    uint256 constant QUORUM = 2;

    function setUp() public {
        vm.warp(1_700_000_000);
        oracle = new MedianOracle(8, STALE, MIN, MAX, QUORUM, address(this));
        oracle.addUpdater(u1);
        oracle.addUpdater(u2);
        oracle.addUpdater(u3);
    }

    function _report(address u, int256 p) internal {
        vm.prank(u);
        oracle.report(p);
    }

    function test_decimals() public view {
        assertEq(oracle.decimals(), 8);
    }

    function test_medianOdd() public {
        _report(u1, 49_000 * 1e8);
        _report(u2, 50_000 * 1e8);
        _report(u3, 51_000 * 1e8);
        (, int256 ans,,,) = oracle.latestRoundData();
        assertEq(ans, 50_000 * 1e8);
    }

    function test_medianEven() public {
        oracle.addUpdater(u4);
        _report(u1, 49_000 * 1e8);
        _report(u2, 50_000 * 1e8);
        _report(u3, 51_000 * 1e8);
        _report(u4, 52_000 * 1e8);
        (, int256 ans,,,) = oracle.latestRoundData();
        assertEq(ans, 50_500 * 1e8, "avg of the two middle values");
    }

    function test_outlierCannotMoveMedian() public {
        _report(u1, 50_000 * 1e8);
        _report(u2, 50_100 * 1e8);
        _report(u3, 1_000 * 1e8); // a single compromised/faulty updater, far off
        (, int256 ans,,,) = oracle.latestRoundData();
        // sorted: [1000, 50000, 50100] → median 50000; the outlier can't control it.
        assertEq(ans, 50_000 * 1e8);
    }

    function test_quorumEnforced() public {
        _report(u1, 50_000 * 1e8); // only 1 fresh, quorum is 2
        vm.expectRevert(abi.encodeWithSelector(MedianOracle.InsufficientFreshReports.selector, 1, 2));
        oracle.latestRoundData();
    }

    function test_stalenessExcludesOldReports() public {
        _report(u1, 50_000 * 1e8);
        _report(u2, 50_000 * 1e8);
        (, int256 a1,,,) = oracle.latestRoundData();
        assertEq(a1, 50_000 * 1e8);

        // Advance past staleness; only u3 reports fresh → 1 < quorum → revert.
        vm.warp(block.timestamp + STALE + 1);
        _report(u3, 60_000 * 1e8);
        vm.expectRevert(abi.encodeWithSelector(MedianOracle.InsufficientFreshReports.selector, 1, 2));
        oracle.latestRoundData();
    }

    function test_oldestContributingTimestampReturned() public {
        _report(u1, 50_000 * 1e8);         // u1 reports now
        vm.warp(block.timestamp + 100);
        _report(u2, 50_000 * 1e8);         // u2 reports 100s later
        (,, uint256 startedAt, uint256 updatedAt,) = oracle.latestRoundData();
        // Conservative: returns the OLDEST contributing report's timestamp — i.e.
        // u1's, which is now 100s old. (Order-independent of any captured local.)
        assertEq(block.timestamp - updatedAt, 100, "oldest contributing report is 100s old");
        assertEq(startedAt, updatedAt);
    }

    function test_reportOutOfBoundsReverts() public {
        vm.prank(u1);
        vm.expectRevert(abi.encodeWithSelector(MedianOracle.OutOfBounds.selector, int256(50 * 1e8)));
        oracle.report(50 * 1e8); // below MIN
        vm.prank(u1);
        vm.expectRevert(abi.encodeWithSelector(MedianOracle.OutOfBounds.selector, int256(2_000_000 * 1e8)));
        oracle.report(2_000_000 * 1e8); // above MAX
    }

    function test_reportRoleGated() public {
        vm.prank(makeAddr("rando"));
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        oracle.report(50_000 * 1e8);
    }

    function test_removeUpdaterClearsReport() public {
        _report(u1, 50_000 * 1e8);
        _report(u2, 50_000 * 1e8);
        _report(u3, 50_000 * 1e8);
        oracle.removeUpdater(u3);
        assertEq(oracle.updaterCount(), 2);
        (int256 p, uint64 ts) = oracle.reports(u3);
        assertEq(p, 0);
        assertEq(ts, 0);
        assertFalse(oracle.hasRole(oracle.UPDATER_ROLE(), u3));
        (, int256 ans,,,) = oracle.latestRoundData();
        assertEq(ans, 50_000 * 1e8, "still serves with the remaining quorum");
    }

    function test_addUpdaterGuards() public {
        vm.expectRevert(bytes("already updater"));
        oracle.addUpdater(u1);
        vm.expectRevert(bytes("zero updater"));
        oracle.addUpdater(address(0));
        vm.prank(makeAddr("rando"));
        vm.expectRevert(); // not admin
        oracle.addUpdater(makeAddr("x"));
    }

    function test_constructorGuards() public {
        vm.expectRevert(bytes("bad bounds"));
        new MedianOracle(8, STALE, int256(0), MAX, QUORUM, address(this));
        vm.expectRevert(bytes("zero quorum"));
        new MedianOracle(8, STALE, MIN, MAX, 0, address(this));
        vm.expectRevert(bytes("bad decimals"));
        new MedianOracle(0, STALE, MIN, MAX, QUORUM, address(this));
    }
}
