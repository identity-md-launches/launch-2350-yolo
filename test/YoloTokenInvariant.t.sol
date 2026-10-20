// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {YoloToken} from "../src/YoloToken.sol";

/// @notice Drives the token with random, bounded calls from a fixed set of actors and keeps an
/// independent ledger of what every balance and allowance should be. Failure paths are driven too:
/// a call that should revert and does not, or that reverts and still changes state, is counted.
contract YoloHandler is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    YoloToken public immutable token;
    address[] internal actors;

    // Ghost ledger, updated from the call's arguments, never from the token's own state.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public unexpectedSuccesses;
    uint256 public stateChangedOnRevert;
    uint256 public unlimitedAllowanceDecremented;
    uint256 public calls;
    uint256 public successfulMoves;

    constructor(YoloToken token_, address[] memory actors_, address holder) {
        token = token_;
        actors = actors_;
        ghostBalance[holder] = SUPPLY;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _bound(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        uint256 span = hi - lo;
        if (span == type(uint256).max) return x;
        return lo + (x % (span + 1));
    }

    /// @dev Biases amounts toward the edges: zero, one, the whole balance, and one past it.
    function _amount(uint256 seed, uint256 balance) internal pure returns (uint256) {
        uint256 pick = seed % 8;
        if (pick == 0) return 0;
        if (pick == 1) return balance == 0 ? 0 : 1;
        if (pick == 2) return balance;
        return _bound(seed >> 8, 0, balance);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        calls++;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(amountSeed, ghostBalance[from]);

        vm.prank(from);
        bool ok = token.transfer(to, amount);
        assertTrue(ok, "transfer returned false");
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        successfulMoves++;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value) external {
        calls++;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 pick = value % 4;
        if (pick == 0) value = type(uint256).max;
        else if (pick == 1) value = _bound(value >> 2, 0, ghostBalance[owner]);

        vm.prank(owner);
        bool ok = token.approve(spender, value);
        assertTrue(ok, "approve returned false");
        ghostAllowance[owner][spender] = value;
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amountSeed) external {
        calls++;
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 cap = ghostBalance[owner] < allowed ? ghostBalance[owner] : allowed;
        uint256 amount = _amount(amountSeed, cap);

        vm.prank(spender);
        bool ok = token.transferFrom(owner, to, amount);
        assertTrue(ok, "transferFrom returned false");
        if (allowed != type(uint256).max) {
            ghostAllowance[owner][spender] = allowed - amount;
        } else if (token.allowance(owner, spender) != type(uint256).max) {
            unlimitedAllowanceDecremented++;
        }
        ghostBalance[owner] -= amount;
        ghostBalance[to] += amount;
        successfulMoves++;
    }

    // ---------------------------------------------------------------------------------------------
    // Failure paths: each must revert and leave every balance and allowance as it was.
    // ---------------------------------------------------------------------------------------------

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        calls++;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = ghostBalance[from] + _bound(excess, 1, type(uint256).max - SUPPLY);
        vm.prank(from);
        try token.transfer(to, amount) {
            unexpectedSuccesses++;
        } catch {}
        _checkUnchanged(from, to);
    }

    function transferToZero(uint256 fromSeed, uint256 amountSeed) external {
        calls++;
        address from = _actor(fromSeed);
        uint256 amount = _amount(amountSeed, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            unexpectedSuccesses++;
        } catch {}
        _checkUnchanged(from, address(0));
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess)
        external
    {
        calls++;
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        if (allowed == type(uint256).max) return;
        uint256 amount = allowed + _bound(excess, 1, type(uint256).max - allowed);
        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            unexpectedSuccesses++;
        } catch {}
        _checkUnchanged(owner, to);
        if (token.allowance(owner, spender) != allowed) stateChangedOnRevert++;
    }

    function transferFromOverBalance(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excess) external {
        calls++;
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 amount = ghostBalance[owner] + _bound(excess, 1, SUPPLY);
        uint256 allowed = ghostAllowance[owner][spender];
        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            unexpectedSuccesses++;
        } catch {}
        _checkUnchanged(owner, to);
        if (token.allowance(owner, spender) != allowed) stateChangedOnRevert++;
    }

    function approveZero(uint256 ownerSeed, uint256 value) external {
        calls++;
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        try token.approve(address(0), value) {
            unexpectedSuccesses++;
        } catch {}
        if (token.allowance(owner, address(0)) != 0) stateChangedOnRevert++;
    }

    function _checkUnchanged(address a, address b) internal {
        if (token.balanceOf(a) != ghostBalance[a]) stateChangedOnRevert++;
        if (b != address(0) && token.balanceOf(b) != ghostBalance[b]) stateChangedOnRevert++;
        if (token.balanceOf(address(0)) != 0) stateChangedOnRevert++;
    }
}

/// @notice Invariants of a fixed-supply token over random call sequences.
contract YoloTokenInvariantTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant FACTORY = address(0xFAC7);

    YoloToken internal token;
    YoloHandler internal handler;
    address[] internal actors;

    function setUp() public {
        vm.prank(FACTORY);
        token = new YoloToken();
        actors.push(FACTORY);
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA501));
        actors.push(address(0xD157)); // a distributor-like holder
        handler = new YoloHandler(token, actors, FACTORY);
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply changed");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "TOTAL_SUPPLY changed");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "balances of every holder do not sum to the supply");
        assertEq(token.balanceOf(address(0)), 0, "tokens reached the zero address");
        assertEq(token.balanceOf(address(token)), 0, "tokens reached the token contract");
        assertEq(token.balanceOf(address(handler)), 0, "tokens reached the handler");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            address a = actors[i];
            assertEq(token.balanceOf(a), handler.ghostBalance(a), "balance differs from the ledger");
            assertLe(token.balanceOf(a), SUPPLY, "a balance exceeds the supply");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allowancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance differs from the ledger"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0, "allowance granted to the zero address");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_failurePathsRevertCleanly() public view {
        assertEq(handler.unexpectedSuccesses(), 0, "a call that must revert succeeded");
        assertEq(handler.stateChangedOnRevert(), 0, "a reverted call changed state");
        assertEq(handler.unlimitedAllowanceDecremented(), 0, "an unlimited allowance was decremented");
    }
}
