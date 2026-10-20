# Yolo (YOLO)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum.

| Field | Value |
| --- | --- |
| Solidity contract | `YoloToken` (`src/YoloToken.sol`) |
| Token name | `Yolo` |
| Token symbol | `YOLO` |
| Decimals | 18 |
| Total supply | 1,000,000,000 YOLO = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Minted to | `msg.sender` of the constructor (the factory at launch), once |

## Design

The token is a plain ERC-20 with nothing on top:

- The whole supply is minted once in the constructor to the deployer. There is no `mint`, no
  `burn`, no minter role and no way for the supply to change afterwards. `totalSupply()` is a
  constant.
- There is no owner. No address can pause transfers, block or freeze a holder, seize a balance,
  take a fee, or upgrade the code. The contract has no `receive` or `fallback`, no `delegatecall`
  and no `selfdestruct`.
- Transfers move exactly the amount requested, from any sender to any recipient, so the launch
  flows (factory to distributor, distributor to claimants, factory into the Uniswap v4 pool,
  factory to the requester's remainder address) arrive whole, and traders can buy and sell
  through the pool manager without exemptions.
- `transferFrom` treats an allowance of `type(uint256).max` as unlimited and does not decrement
  it. Any other allowance is decremented by the amount spent.
- Transfers and approvals to the zero address revert. Burning by sending to the zero address is
  not supported.
- Errors use the ERC-6093 names (`ERC20InsufficientBalance`, `ERC20InsufficientAllowance`,
  `ERC20InvalidReceiver`, `ERC20InvalidSpender`) so explorers and wallets that know
  OpenZeppelin's errors decode them.

The contract has no external dependencies. It is written against the pinned compiler only, so
the project builds offline.

## Assumptions

- The deployer of the token is the launch factory, which receives the entire supply and pays it
  out: 10% to the launch's MerkleDistributor, 80% into the pool, and 10% to the requester's
  remainder address. Nothing in this repository holds, reserves or receives any of the supply.
- The token does not need to know the factory, pool manager or distributor: it has no transfer
  rules to exempt them from.
- Supply is final. If the requester later wants burns, taxes, vesting or governance, that is a
  new token, not a setting.

## Deployment parameters

- Chain: Ethereum mainnet (chain id 1).
- Contract: `YoloToken`, deployed from its creation bytecode by the factory through
  `ProjectFactory.launchCustom`. No constructor arguments.
- Manifest values the launch step needs: `token.contract = "YoloToken"`, `token.name = "Yolo"`,
  `token.symbol = "YOLO"`, `token.decimals = 18`, `token.constructorArgs = []`,
  `token.totalSupply = "1000000000000000000000000000"`.
- Pool (from the launch policy, not chosen here): paired with IMD
  (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), fee 12500, tick spacing 60, opening price
  derived by the deployer from the requester's economics (pool share 80%, opening market cap
  3,500 IMD, remainder to `0x612a9bb008e16ef2d24f41dae9fc661831d93367`).
- Build settings (`foundry.toml`): `solc = "0.8.26"`, optimizer on with 200 runs,
  `bytecode_hash = "none"` so the deployed bytes are reproducible without the metadata hash.

The launch manifest (`launch.json`) is written by the manifest step after this work is accepted.
It is deliberately not part of this repository.

## After launch

Nothing. The token has no settings, no owner and no setters. There is no address, key, oracle or
registry to configure.

## Operational responsibilities

- Nobody operates the token. Holders are responsible for their own keys and approvals. The
  contract cannot recover tokens sent to it or to the zero address, and cannot reverse a
  transfer.
- Approvals: holders should approve exact amounts to contracts they interact with. An unlimited
  allowance lets the spender move the holder's whole balance for as long as the allowance stands.
- Explorer verification of the deployed source is the deployer's job after launch
  (`forge verify-contract` with the same `foundry.toml` settings).
- Tests passing is not an audit. The contract is small and dependency-free, but an independent
  adversarial review before release is still the right step for anything that holds value.

## Chosen constants

| Constant | Value | Why |
| --- | --- | --- |
| `TOTAL_SUPPLY` | `1_000_000_000 * 10 ** 18` | The brief's supply, in minor units |
| `decimals` | 18 | The brief's decimals |

No number in the brief was left open, so nothing else was chosen.

## Project layout

```
foundry.toml              compiler pins and build settings
src/YoloToken.sol         the token
test/YoloToken.t.sol      unit, failure and fuzz tests
test/utils/TestBase.sol   minimal cheatcode interface and assertions (no vendored test library)
```

## Building and testing

```
forge build
forge test
forge fmt --check
```

The test suite covers metadata, the one-time mint to the deployer (including a contract
deployer, as at launch), transfers and allowance accounting on success, every revert path
(insufficient balance, insufficient allowance, zero receiver, zero spender), the launch flows
arriving whole, the absence of any mint, admin, pause, blocklist or seize entry point, the
absence of `DELEGATECALL`, `CALLCODE` and `SELFDESTRUCT` in reachable runtime code, and fuzzed
conservation of supply and allowance accounting. The tests read no environment variables and
do not depend on the calling address, so they run in any order and in parallel.
