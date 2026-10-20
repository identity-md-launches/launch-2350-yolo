// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Yolo (YOLO)
/// @notice A fixed-supply ERC-20 token. The whole supply of 1,000,000,000 YOLO (18 decimals) is
/// minted once, to the deployer, in the constructor. Nothing can mint afterwards, nothing can burn,
/// and no address holds any privilege over another holder's balance: there is no owner, no pause,
/// no blocklist, no fee and no upgrade path. Transfers are plain balance moves.
/// @dev Written without external dependencies so the project builds offline with only the pinned
/// compiler. Follows ERC-20 and uses the ERC-6093 custom error names so tooling that understands
/// OpenZeppelin's errors decodes these the same way.
contract YoloToken {
    // ---------------------------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------------------------

    /// @notice Token name.
    string public constant name = "Yolo";

    /// @notice Token symbol.
    string public constant symbol = "YOLO";

    /// @notice Token decimals.
    uint8 public constant decimals = 18;

    /// @notice The fixed total supply: 1,000,000,000 YOLO in minor units (18 decimals).
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    // ---------------------------------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------------------------------

    /// @notice Balance of each account.
    mapping(address account => uint256) public balanceOf;

    /// @notice Remaining allowance granted by an owner to a spender.
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    // ---------------------------------------------------------------------------------------------
    // Events and errors (ERC-20 / ERC-6093)
    // ---------------------------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidSpender(address spender);

    // ---------------------------------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------------------------------

    /// @notice Mints the whole supply to the deployer, once.
    /// @dev The deployer is `msg.sender`: at launch that is the factory, which pays the supply out.
    constructor() {
        balanceOf[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // ERC-20
    // ---------------------------------------------------------------------------------------------

    /// @notice Total supply, fixed at deployment.
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @notice Moves `value` tokens from the caller to `to`.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Sets the caller's allowance for `spender` to `value`.
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /// @notice Moves `value` tokens from `from` to `to` using the caller's allowance.
    /// @dev An allowance of `type(uint256).max` is treated as unlimited and is not decremented.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert ERC20InsufficientBalance(from, fromBalance, value);
        unchecked {
            // fromBalance >= value, checked above.
            balanceOf[from] = fromBalance - value;
            // The sum of all balances is TOTAL_SUPPLY, so no balance can exceed it.
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 current = allowance[owner][spender];
        if (current != type(uint256).max) {
            if (current < value) revert ERC20InsufficientAllowance(spender, current, value);
            unchecked {
                allowance[owner][spender] = current - value;
            }
        }
    }
}
