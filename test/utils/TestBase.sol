// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The subset of Foundry cheatcodes these tests use, declared here so the project needs no
/// vendored test library. The signatures match forge's `Vm` interface.
interface Vm {
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function assume(bool condition) external pure;
    function label(address account, string calldata newLabel) external;
}

/// @notice A tiny assertion base. A failed assertion reverts with its message, which forge reports
/// as the test failure.
abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool condition, string memory err) internal pure {
        if (!condition) revert(err);
    }

    function assertFalse(bool condition, string memory err) internal pure {
        if (condition) revert(err);
    }

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        if (a != b) revert(err);
    }

    function assertEq(address a, address b, string memory err) internal pure {
        if (a != b) revert(err);
    }

    function assertEq(string memory a, string memory b, string memory err) internal pure {
        if (keccak256(bytes(a)) != keccak256(bytes(b))) revert(err);
    }

    function assertLe(uint256 a, uint256 b, string memory err) internal pure {
        if (a > b) revert(err);
    }
}
