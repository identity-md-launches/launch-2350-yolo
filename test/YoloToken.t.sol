// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {YoloToken} from "../src/YoloToken.sol";

/// @notice Deploys the token from inside a contract call, as the factory does at launch.
contract DeployHelper {
    function deploy() external returns (YoloToken) {
        return new YoloToken();
    }
}

/// @notice Unit, failure and fuzz tests for the Yolo token.
/// @dev The deployer is a named address (`FACTORY`) rather than the test contract, because at
/// launch the factory deploys the token and receives the supply.
contract YoloTokenTest is TestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address internal constant FACTORY = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA501);

    YoloToken internal token;

    function setUp() public {
        vm.startPrank(FACTORY);
        token = new YoloToken();
        vm.stopPrank();
        vm.label(FACTORY, "factory");
        vm.label(ALICE, "alice");
        vm.label(BOB, "bob");
        vm.label(CAROL, "carol");
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and initial state
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Yolo", "name");
        assertEq(token.symbol(), "YOLO", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.totalSupply(), SUPPLY, "totalSupply");
        assertEq(token.totalSupply(), 1_000_000_000_000_000_000_000_000_000, "totalSupply literal");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "TOTAL_SUPPLY constant");
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(FACTORY), SUPPLY, "deployer holds the whole supply");
        assertEq(token.balanceOf(address(this)), 0, "the test contract holds nothing");
        assertEq(token.balanceOf(address(0)), 0, "the zero address holds nothing");
    }

    function test_constructorMintsToAContractDeployerAndEmits() public {
        // At launch the deployer is a contract (the factory). Deploying through a helper contract
        // checks that msg.sender, not tx.origin, receives the supply, and that the mint is logged.
        DeployHelper helper = new DeployHelper();
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(helper), SUPPLY);
        YoloToken fresh = helper.deploy();
        assertEq(fresh.balanceOf(address(helper)), SUPPLY, "the deploying contract holds the supply");
        assertEq(fresh.balanceOf(address(this)), 0, "the outer caller holds nothing");
        assertEq(fresh.totalSupply(), SUPPLY, "a second deployment has the same fixed supply");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer: success
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_000 * 10 ** 18;
        vm.expectEmit(true, true, true, true);
        emit Transfer(FACTORY, ALICE, amount);
        vm.prank(FACTORY);
        bool ok = token.transfer(ALICE, amount);
        assertTrue(ok, "transfer returned false");
        assertEq(token.balanceOf(ALICE), amount, "recipient balance");
        assertEq(token.balanceOf(FACTORY), SUPPLY - amount, "sender balance");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferWholeBalance() public {
        vm.prank(FACTORY);
        assertTrue(token.transfer(ALICE, SUPPLY), "transfer returned false");
        assertEq(token.balanceOf(ALICE), SUPPLY, "recipient holds everything");
        assertEq(token.balanceOf(FACTORY), 0, "sender holds nothing");
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0), "zero transfer returned false");
        assertEq(token.balanceOf(BOB), 0, "nothing moved");
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 500);
        vm.prank(ALICE);
        assertTrue(token.transfer(ALICE, 500), "self transfer returned false");
        assertEq(token.balanceOf(ALICE), 500, "self transfer kept the balance");
    }

    function test_launchFlowsArriveWhole() public {
        // The swarm's share, then a claim, then the requester's remainder: every hop is exact.
        address distributor = address(0xD157);
        address claimant = address(0xC1A1);
        address remainderTo = address(0x5E57);
        uint256 swarm = SUPPLY / 10;
        uint256 pool = (SUPPLY * 8_000) / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        vm.startPrank(FACTORY);
        assertTrue(token.transfer(distributor, swarm), "swarm transfer returned false");
        assertTrue(token.transfer(remainderTo, remainder), "remainder transfer returned false");
        vm.stopPrank();
        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm), "claim transfer returned false");

        assertEq(token.balanceOf(claimant), swarm, "claim arrived short");
        assertEq(token.balanceOf(distributor), 0, "distributor kept something");
        assertEq(token.balanceOf(remainderTo), remainder, "remainder arrived short");
        assertEq(token.balanceOf(FACTORY), pool, "factory keeps exactly the pool share");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged by launch flows");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer: failure
    // ---------------------------------------------------------------------------------------------

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 100);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, ALICE, 100, 101));
        token.transfer(BOB, 101);
        assertEq(token.balanceOf(ALICE), 100, "balance untouched after revert");
        assertEq(token.balanceOf(BOB), 0, "nothing arrived after revert");
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, BOB, 0, 1));
        token.transfer(ALICE, 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.prank(FACTORY);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(FACTORY), SUPPLY, "nothing burned");
    }

    // ---------------------------------------------------------------------------------------------
    // approve / transferFrom: success
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(ALICE, BOB, 777);
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 777), "approve returned false");
        assertEq(token.allowance(ALICE, BOB), 777, "allowance set");
        assertEq(token.allowance(BOB, ALICE), 0, "reverse allowance untouched");
    }

    function test_approveOverwritesAllowance() public {
        vm.startPrank(ALICE);
        token.approve(BOB, 777);
        token.approve(BOB, 5);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), 5, "approve overwrites, it does not add");
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, 600);

        vm.expectEmit(true, true, true, true);
        emit Transfer(ALICE, CAROL, 400);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, 400), "transferFrom returned false");

        assertEq(token.balanceOf(ALICE), 600, "owner balance");
        assertEq(token.balanceOf(CAROL), 400, "recipient balance");
        assertEq(token.balanceOf(BOB), 0, "spender holds nothing");
        assertEq(token.allowance(ALICE, BOB), 200, "allowance decremented");
    }

    function test_transferFromWithUnlimitedAllowanceDoesNotDecrement() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1_000);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "unlimited allowance stays unlimited");
        assertEq(token.balanceOf(CAROL), 1_000, "recipient balance");
    }

    function test_transferFromExactAllowanceLeavesZero() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, 1_000);
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1_000);
        assertEq(token.allowance(ALICE, BOB), 0, "allowance fully spent");
        assertEq(token.balanceOf(BOB), 1_000, "spender received");
    }

    // ---------------------------------------------------------------------------------------------
    // approve / transferFrom: failure
    // ---------------------------------------------------------------------------------------------

    function test_approveZeroSpenderReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromWithoutAllowanceReverts() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 1_000);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 1_000, "balance untouched");
    }

    function test_transferFromAboveAllowanceReverts() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, 500);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientAllowance.selector, BOB, 500, 501));
        token.transferFrom(ALICE, CAROL, 501);
        assertEq(token.allowance(ALICE, BOB), 500, "allowance untouched after revert");
    }

    function test_transferFromAboveBalanceRevertsEvenWithAllowance() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 100);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, ALICE, 100, 101));
        token.transferFrom(ALICE, CAROL, 101);
    }

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(FACTORY);
        token.approve(ALICE, 10);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(FACTORY, address(0), 10);
    }

    function test_deployerCannotPullFromHolderWithoutAllowance() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, 1_000);
        vm.prank(FACTORY);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientAllowance.selector, FACTORY, 0, 1));
        token.transferFrom(ALICE, FACTORY, 1);
        assertEq(token.balanceOf(ALICE), 1_000, "holder keeps the balance");
    }

    // ---------------------------------------------------------------------------------------------
    // No privileged surface
    // ---------------------------------------------------------------------------------------------

    function test_noMintOrAdminFunctionExists() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        address attacker = address(0xBEEF);
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool okAttacker,) = address(token).call(data);
            assertFalse(okAttacker, signatures[i]);
            vm.prank(FACTORY);
            (bool okDeployer,) = address(token).call(data);
            assertFalse(okDeployer, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
        assertEq(token.balanceOf(attacker), 0, "attacker minted nothing");
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        vm.prank(FACTORY);
        token.transfer(ALICE, SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, true);
            vm.prank(FACTORY);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.balanceOf(ALICE), held, "holder balance untouched");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2), "holder can still transfer");
        assertEq(token.balanceOf(BOB), held / 2, "holder's transfer delivered");
    }

    function test_plainEtherAndUnknownCalldataAreRejected() public {
        (bool okValue,) = address(token).call{value: 0}("");
        assertFalse(okValue, "no receive or fallback");
        (bool okData,) = address(token).call(hex"deadbeef");
        assertFalse(okData, "unknown selector rejected");
    }

    function test_runtimeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length > 0, "runtime present");
        assertLe(runtime.length, 24_576, "runtime within EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != FACTORY);
        amount = amount % (SUPPLY + 1);
        vm.prank(FACTORY);
        assertTrue(token.transfer(to, amount), "transfer returned false");
        assertEq(token.balanceOf(to), amount, "recipient");
        assertEq(token.balanceOf(FACTORY), SUPPLY - amount, "sender");
        assertEq(token.balanceOf(to) + token.balanceOf(FACTORY), SUPPLY, "conservation");
        assertEq(token.totalSupply(), SUPPLY, "supply fixed");
    }

    function testFuzz_transferAboveBalanceReverts(uint256 balance, uint256 excess) public {
        balance = balance % SUPPLY;
        excess = 1 + (excess % (type(uint256).max - SUPPLY));
        vm.prank(FACTORY);
        token.transfer(ALICE, balance);
        uint256 amount = balance + excess;
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), balance, "balance untouched");
    }

    function testFuzz_transferFromAccountsAllowance(address spender, uint256 allowed, uint256 amount) public {
        vm.assume(spender != address(0) && spender != ALICE && spender != BOB);
        allowed = allowed % SUPPLY; // strictly below the unlimited sentinel
        amount = amount % (allowed + 1);
        vm.prank(FACTORY);
        token.transfer(ALICE, allowed);
        vm.prank(ALICE);
        token.approve(spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(ALICE, BOB, amount), "transferFrom returned false");
        assertEq(token.allowance(ALICE, spender), allowed - amount, "allowance accounted");
        assertEq(token.balanceOf(BOB), amount, "recipient");
        assertEq(token.balanceOf(ALICE), allowed - amount, "owner");
    }

    function testFuzz_transferFromAboveAllowanceReverts(uint256 allowed, uint256 excess) public {
        allowed = allowed % SUPPLY;
        excess = 1 + (excess % (SUPPLY - allowed));
        uint256 amount = allowed + excess;
        vm.prank(FACTORY);
        token.transfer(ALICE, SUPPLY);
        vm.prank(ALICE);
        token.approve(BOB, allowed);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientAllowance.selector, BOB, allowed, amount));
        token.transferFrom(ALICE, CAROL, amount);
        assertEq(token.allowance(ALICE, BOB), allowed, "allowance untouched");
        assertEq(token.balanceOf(ALICE), SUPPLY, "balance untouched");
    }

    function testFuzz_approveAnyValue(address spender, uint256 value) public {
        vm.assume(spender != address(0) && spender != FACTORY);
        vm.prank(ALICE);
        assertTrue(token.approve(spender, value), "approve returned false");
        assertEq(token.allowance(ALICE, spender), value, "allowance");
        assertEq(token.balanceOf(spender), 0, "approve moves nothing");
    }

    function testFuzz_chainedTransfersConserveSupply(uint256 a, uint256 b) public {
        a = a % (SUPPLY + 1);
        b = b % (a + 1);
        vm.prank(FACTORY);
        token.transfer(ALICE, a);
        vm.prank(ALICE);
        token.transfer(BOB, b);
        assertEq(token.balanceOf(FACTORY) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY, "conservation");
        assertEq(token.balanceOf(ALICE), a - b, "alice");
        assertEq(token.balanceOf(BOB), b, "bob");
    }
}
