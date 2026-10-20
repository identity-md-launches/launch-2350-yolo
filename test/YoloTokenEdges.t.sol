// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {YoloToken} from "../src/YoloToken.sol";

/// @notice Edge inputs the main suite does not pin: maximum values, repeated calls, a caller who is
/// not who the code assumed, and reverts that must leave every piece of state untouched.
contract YoloTokenEdgesTest is TestBase {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address internal constant FACTORY = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA501);

    YoloToken internal token;

    function setUp() public {
        vm.prank(FACTORY);
        token = new YoloToken();
    }

    function _fund(address to, uint256 amount) internal {
        vm.prank(FACTORY);
        token.transfer(to, amount);
    }

    // ---------------------------------------------------------------------------------------------
    // Maximum values
    // ---------------------------------------------------------------------------------------------

    function test_transferMaxUintReverts() public {
        vm.prank(FACTORY);
        vm.expectRevert(
            abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, FACTORY, SUPPLY, type(uint256).max)
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(FACTORY), SUPPLY, "balance untouched");
    }

    function test_transferOneWeiOverSupplyReverts() public {
        vm.prank(FACTORY);
        vm.expectRevert(
            abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, FACTORY, SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
    }

    function test_transferFromMaxUintWithUnlimitedAllowanceReverts() public {
        vm.prank(FACTORY);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, FACTORY, SUPPLY, type(uint256).max)
        );
        token.transferFrom(FACTORY, BOB, type(uint256).max);
        assertEq(token.allowance(FACTORY, ALICE), type(uint256).max, "allowance untouched");
    }

    function test_allowanceOneBelowMaxIsDecremented() public {
        // Only exactly type(uint256).max is unlimited; one below it is an ordinary allowance.
        vm.prank(FACTORY);
        token.approve(ALICE, type(uint256).max - 1);
        vm.prank(ALICE);
        token.transferFrom(FACTORY, BOB, 1);
        assertEq(token.allowance(FACTORY, ALICE), type(uint256).max - 2, "allowance decremented");
    }

    function test_wholeSupplyThroughTransferFrom() public {
        vm.prank(FACTORY);
        token.approve(ALICE, SUPPLY);
        vm.prank(ALICE);
        token.transferFrom(FACTORY, BOB, SUPPLY);
        assertEq(token.balanceOf(BOB), SUPPLY, "recipient holds everything");
        assertEq(token.balanceOf(FACTORY), 0, "owner emptied");
        assertEq(token.allowance(FACTORY, ALICE), 0, "allowance spent");
    }

    // ---------------------------------------------------------------------------------------------
    // Same call twice
    // ---------------------------------------------------------------------------------------------

    function test_secondTransferFromAfterAllowanceSpentReverts() public {
        _fund(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, 400);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 400);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientAllowance.selector, BOB, 0, 400));
        token.transferFrom(ALICE, CAROL, 400);
        assertEq(token.balanceOf(CAROL), 400, "only the first pull landed");
        assertEq(token.balanceOf(ALICE), 600, "owner keeps the rest");
    }

    function test_secondTransferOfWholeBalanceReverts() public {
        _fund(ALICE, 50);
        vm.prank(ALICE);
        token.transfer(BOB, 50);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, ALICE, 0, 50));
        token.transfer(BOB, 50);
    }

    function test_approveSameValueTwiceDoesNotAccumulate() public {
        vm.startPrank(ALICE);
        token.approve(BOB, 10);
        token.approve(BOB, 10);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), 10, "allowance does not accumulate");
    }

    function test_approveZeroRevokes() public {
        _fund(ALICE, 100);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit Approval(ALICE, BOB, 0);
        vm.prank(ALICE);
        token.approve(BOB, 0);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(ALICE, BOB, 1);
    }

    // ---------------------------------------------------------------------------------------------
    // A caller who is not who the code assumed
    // ---------------------------------------------------------------------------------------------

    function test_ownerHasNoImplicitAllowanceOverOwnTokens() public {
        _fund(ALICE, 100);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        token.transferFrom(ALICE, BOB, 1);
    }

    function test_selfApprovalLetsOwnerPullOwnTokens() public {
        _fund(ALICE, 100);
        vm.startPrank(ALICE);
        token.approve(ALICE, 60);
        token.transferFrom(ALICE, BOB, 60);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, ALICE), 0, "self allowance spent");
        assertEq(token.balanceOf(BOB), 60, "recipient");
    }

    function test_allowanceIsPerSpender() public {
        _fund(ALICE, 100);
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.prank(CAROL);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientAllowance.selector, CAROL, 0, 1));
        token.transferFrom(ALICE, CAROL, 1);
        assertEq(token.allowance(ALICE, BOB), 100, "other spender's allowance untouched");
    }

    function test_allowanceIsPerOwner() public {
        _fund(ALICE, 100);
        _fund(CAROL, 100);
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(CAROL, BOB, 1);
    }

    function test_spenderDoesNotReceiveUnlessRecipient() public {
        _fund(ALICE, 100);
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 100);
        assertEq(token.balanceOf(BOB), 0, "spender got nothing");
        assertEq(token.balanceOf(CAROL), 100, "recipient got everything");
    }

    function test_transferFromToOwnerKeepsBalanceButSpendsAllowance() public {
        _fund(ALICE, 100);
        vm.prank(ALICE);
        token.approve(BOB, 70);
        vm.prank(BOB);
        token.transferFrom(ALICE, ALICE, 70);
        assertEq(token.balanceOf(ALICE), 100, "self-directed pull keeps the balance");
        assertEq(token.allowance(ALICE, BOB), 0, "allowance still spent");
    }

    // ---------------------------------------------------------------------------------------------
    // A failing pull leaves allowance and balances exactly as they were
    // ---------------------------------------------------------------------------------------------

    function test_balanceFailureDoesNotSpendAllowance() public {
        _fund(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, ALICE, 10, 11));
        token.transferFrom(ALICE, CAROL, 11);
        assertEq(token.allowance(ALICE, BOB), 100, "allowance not spent by a failed pull");
        assertEq(token.balanceOf(ALICE), 10, "owner balance untouched");
        assertEq(token.balanceOf(CAROL), 0, "nothing delivered");
    }

    function test_zeroReceiverFailureDoesNotSpendAllowance() public {
        _fund(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, 10);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(ALICE, address(0), 10);
        assertEq(token.allowance(ALICE, BOB), 10, "allowance not spent");
        assertEq(token.balanceOf(ALICE), 10, "nothing burned");
    }

    function test_zeroAmountToZeroAddressStillReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_approveZeroSpenderZeroValueReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
    }

    function test_tokenContractCanHoldButNotMoveTokens() public {
        // Tokens sent to the token's own address are stuck: it has no function to move them. The
        // supply still counts them; nothing is created or destroyed.
        _fund(address(token), 5);
        assertEq(token.balanceOf(address(token)), 5, "token contract holds");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    // ---------------------------------------------------------------------------------------------
    // Property fuzz
    // ---------------------------------------------------------------------------------------------

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferBetweenAnyTwoHoldersConserves(address from, address to, uint256 seed, uint256 amount)
        public
    {
        if (from == address(0)) from = ALICE;
        if (to == address(0)) to = BOB;
        uint256 funded = seed % (SUPPLY + 1);
        if (from != FACTORY) _fund(from, funded);
        else funded = SUPPLY;
        amount = amount % (funded + 1);

        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        vm.prank(from);
        token.transfer(to, amount);
        if (from == to) {
            assertEq(token.balanceOf(from), beforeFrom, "self transfer changed balance");
        } else {
            assertEq(token.balanceOf(from), beforeFrom - amount, "sender");
            assertEq(token.balanceOf(to), beforeTo + amount, "recipient");
            assertEq(beforeFrom + beforeTo, token.balanceOf(from) + token.balanceOf(to), "pair conserved");
        }
        assertEq(token.totalSupply(), SUPPLY, "supply fixed");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferAnyAmountAboveBalanceReverts(uint256 funded, uint256 amount) public {
        funded = funded % (SUPPLY + 1);
        _fund(ALICE, funded);
        if (amount <= funded) amount = funded + 1 + (amount % (type(uint256).max - funded));
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(YoloToken.ERC20InsufficientBalance.selector, ALICE, funded, amount));
        token.transfer(BOB, amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_unlimitedAllowanceNeverDecrements(uint256 a, uint256 b) public {
        _fund(ALICE, SUPPLY);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        a = a % (SUPPLY + 1);
        b = b % (SUPPLY - a + 1);
        vm.startPrank(BOB);
        token.transferFrom(ALICE, CAROL, a);
        token.transferFrom(ALICE, CAROL, b);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "unlimited allowance decremented");
        assertEq(token.balanceOf(CAROL), a + b, "recipient");
        assertEq(token.balanceOf(ALICE), SUPPLY - a - b, "owner");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_splitPullsEqualOnePull(uint256 allowed, uint256 first) public {
        // Two pulls of a and allowed-a leave the same state as one pull of allowed.
        allowed = allowed % (SUPPLY + 1);
        first = first % (allowed + 1);
        _fund(ALICE, allowed);
        vm.prank(ALICE);
        token.approve(BOB, allowed);
        vm.startPrank(BOB);
        token.transferFrom(ALICE, CAROL, first);
        token.transferFrom(ALICE, CAROL, allowed - first);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), 0, "allowance fully spent");
        assertEq(token.balanceOf(CAROL), allowed, "recipient got the full allowance");
        assertEq(token.balanceOf(ALICE), 0, "owner emptied");
    }
}
