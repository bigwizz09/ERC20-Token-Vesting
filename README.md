# ERC-20 Token Vesting

A token vesting contract built with **Solidity and Foundry**. An owner locks ERC-20 tokens inside the contract for a beneficiary, and the beneficiary can claim them gradually over a defined vesting period, after an optional cliff.

The project demonstrates how a smart contract can manage time-based token releases, track claimed amounts accurately, and let an owner revoke a schedule without taking away tokens the beneficiary has already earned.

## Overview

The vesting lifecycle looks like this:

```text
Owner approves the vesting contract
     ↓
Owner creates a schedule
     ↓
Tokens are pulled into the contract
     ↓
Time passes
     ↓
Cliff ends
     ↓
Beneficiary calls release()
     ↓
Vested tokens are sent to the beneficiary
     ↓
Beneficiary releases again later
     ↓
After the end, the full amount has been released
```

With a revocable schedule, the owner can step in:

```text
Owner calls revoke()
     ↓
Vested amount at that moment is calculated
     ↓
Unvested tokens return to the owner
     ↓
Schedule is frozen at the vested amount
     ↓
Beneficiary can still release what was earned
```

## How Vesting Works

```text
start            start + cliff                 start + duration
  |-----------------|----------------------------------|
  nothing claimable    claimable amount grows linearly     fully vested
```

* **Cliff:** a waiting period after `start`. Nothing can be claimed until it ends. When it ends, everything earned so far unlocks at once.
* **Duration:** the total time until the full amount has vested.
* **Linear vesting:** after the cliff, tokens vest in proportion to the time passed since `start`.

```text
vested = totalAmount * (now - start) / duration
```

The vested amount is never stored. It is calculated from timestamps whenever it is needed.

| Time | Vested |
| --- | --- |
| Before `start + cliff` | 0 |
| Between the cliff and the end | `totalAmount * elapsed / duration` |
| At or after `start + duration` | `totalAmount` |

Example with 1000 tokens, a 30 day cliff and a 100 day duration:

| Day after start | Vested |
| --- | --- |
| 20 | 0 |
| 30 | 300 |
| 50 | 500 |
| 100 and later | 1000 |

## Features

* One contract holds many vesting schedules, each with its own ID.
* One beneficiary can have several schedules.
* Tokens are pulled into the contract when a schedule is created, so every schedule is fully funded from the start.
* Nothing can be claimed before the cliff.
* A beneficiary can never claim more than has vested.
* Already-claimed tokens are tracked per schedule.
* Revocable schedules let the owner recover only the unvested tokens.
* After a revoke, vesting stops growing but earned tokens stay claimable.
* Works with any standard ERC-20 token.
* Custom errors are used for gas-efficient reverts.
* Events are emitted for schedule creation, token release and revocation.

## Technologies

* **Solidity `^0.8.30`**
* **Foundry**
* **OpenZeppelin** (`IERC20`, `SafeERC20`, `ERC20` for the test mock)
* **Anvil**

## Project Structure

```text
ERC20-Token-Vesting/
│
├── src/
│   └── TokenVesting.sol
│
├── script/
│   └── DeployTokenVesting.s.sol
│
├── test/
│   ├── mocks/
│   │   └── MockERC20.sol
│   └── unit/
│       └── TokenVestingTest.t.sol
│
├── lib/
│   ├── forge-std/
│   └── openzeppelin-contracts/
│
├── foundry.toml
└── README.md
```

## Vesting Contract

The main contract is:

```text
src/TokenVesting.sol
```

### Schedule

Each schedule stores:

```solidity
struct Schedule {
    address beneficiary;
    address token;
    uint256 totalAmount;
    uint256 start;
    uint256 cliff;
    uint256 duration;
    uint256 released;
    bool revocable;
    bool revoked;
}
```

Schedules are stored in a mapping and numbered from 0:

```solidity
mapping(uint256 => Schedule) private s_schedules;
```

`start` is an absolute timestamp. `cliff` and `duration` are lengths of time in seconds, so the cliff ends at `start + cliff` and vesting ends at `start + duration`.

### Roles

| Role | Can do |
| --- | --- |
| Owner (the deployer) | Create schedules, revoke revocable schedules |
| Beneficiary | Release vested tokens from their own schedules |
| Anyone | Read vested amounts and schedule data |

### Functions

| Function | Who | Description |
| --- | --- | --- |
| `createSchedule(...)` | Owner | Validates the inputs, stores the schedule and pulls `totalAmount` tokens into the contract. |
| `vestedAmount(scheduleId)` | Anyone | Returns the tokens vested so far, including those already claimed. |
| `release(scheduleId)` | Beneficiary | Sends the vested but unclaimed tokens to the beneficiary. |
| `revoke(scheduleId)` | Owner | Returns the unvested tokens to the owner and freezes vesting. |
| `getSchedule(scheduleId)` | Anyone | Returns all stored fields of a schedule. |

## Creating a Schedule

The owner must first approve the vesting contract to spend the tokens, because a contract cannot take tokens from a wallet by itself:

```text
token.approve(vestingContract, amount)
```

Then the owner creates the schedule:

```solidity
createSchedule(
    beneficiary,
    token,
    totalAmount,
    start,
    cliff,
    duration,
    revocable
);
```

The function rejects:

* A zero beneficiary or token address
* A `start` in the past
* A zero total amount
* A zero duration
* A cliff longer than the duration
* Any caller who is not the owner

## Releasing Tokens

```solidity
release(scheduleId)
```

The function:

1. Checks that the schedule exists.
2. Checks that the caller is the beneficiary.
3. Calculates `releasable = vested - released`.
4. Reverts if there is nothing to claim.
5. Adds the amount to `released`.
6. Emits `Released`.
7. Transfers the tokens to the beneficiary.

The record is updated before the token transfer, following the checks-effects-interactions pattern.

## Revoking a Schedule

```solidity
revoke(scheduleId)
```

Only the owner can revoke, and only schedules created with `revocable = true`, and only once.

Example with 1000 tokens, revoked on day 50:

```text
vested at revoke        = 500
refund to owner         = 1000 - 500 = 500
totalAmount after       = 500
vested at any later time = 500
```

After a revoke, `totalAmount` is frozen at the vested amount and `vestedAmount()` returns it directly. This stops vesting from growing while keeping `released <= vested <= totalAmount` true.

If the beneficiary had already released part of the tokens, the accounting still balances:

```text
contract held          1000
beneficiary released    300
owner refunded          500
left for beneficiary    200  (500 vested - 300 released)
```

## Custom Errors

The contract uses custom errors including:

```solidity
TokenVesting__ZeroAddress()
TokenVesting__TotalAmountZero()
TokenVesting__ZeroDuration()
TokenVesting__CliffIsGreaterThanDuration()
TokenVesting__NotOwner()
TokenVesting__StartTimeAlreadyPassed()
TokenVesting__ScheduleNotFound()
TokenVesting__NotBeneficiary()
TokenVesting__NothingToClaim()
TokenVesting__IsNotRevocable()
TokenVesting__AlreadyRevoked()
```

## Events

```solidity
event ScheduleCreated(uint256 indexed scheduleId, address indexed beneficiary, uint256 totalAmount);
event Released(uint256 indexed scheduleId, address indexed beneficiary, uint256 released);
event ScheduleRevoked(uint256 indexed scheduleId, uint256 refundAmount);
```

## Security Design

* **Calculate, don't store.** Vested amounts are derived from timestamps, so nothing has to be updated every second.
* **Multiply before dividing** in the vesting formula, to avoid losing precision.
* **Checks, effects, interactions.** State is updated before any token transfer.
* **`SafeERC20`** is used for all transfers, so tokens that return `false` instead of reverting are handled.
* **Beneficiary-only release.** Tokens can only be claimed by the person they are meant for.
* **Owner-only creation and revocation**, using an immutable owner set at deployment.
* **Fully funded schedules.** The contract pulls the tokens in at creation, so a schedule can never exist without its tokens.

### Invariants

```text
released <= vested <= totalAmount
released never decreases
vested never decreases over time
after the end, total released == totalAmount
a schedule can be revoked only once
```

## Testing

Run the complete test suite with:

```bash
forge test
```

For more detail:

```bash
forge test -vvv
```

The test suite covers:

* Schedule creation and stored values
* Token transfer into the contract
* `ScheduleCreated` event and incrementing schedule IDs
* Vested amount before the cliff
* Vested amount exactly at the cliff
* Vested amount halfway and at the end
* Vested amount long after the end
* Boundary cases one second before the cliff and one second before the end
* Every revert path in `createSchedule`
* Release before the cliff
* Release at the cliff and the `Released` event
* Releasing twice at the same time
* A second release paying only the difference
* Releasing the full amount after the end
* Wrong caller and missing schedule on `release`
* Releasing one schedule without affecting another
* Revoke before the cliff, mid-vesting, and after full vesting
* Revoke after a partial release
* Beneficiary claiming earned tokens after a revoke
* Vesting frozen after a revoke
* Revoking twice, revoking a non-revocable schedule, wrong caller, missing schedule
* `ScheduleRevoked` event
* Stored schedule values after creation, release and revoke

### Mock Token

Tests use a `MockERC20` with an open `mint` function so each test can create exactly the tokens it needs. It lives in `test/mocks/` and is never deployed for real.

### Example Test Flow

```text
setUp()
     ↓
Deploy mock token
     ↓
Deploy TokenVesting as the owner
     ↓
Mint tokens to the owner
     ↓
Owner approves the vesting contract
     ↓
Create schedule
     ↓
vm.warp() to a chosen time
     ↓
release() / revoke()
     ↓
Assert balances, events and stored values
```

## Deployment

The deployment script is:

```text
script/DeployTokenVesting.s.sol
```

It deploys `TokenVesting`. The account that sends the transaction becomes the owner. No token is deployed, because the contract works with any ERC-20 whose address is passed to `createSchedule`.

Start a local chain:

```bash
anvil
```

Then deploy with one of the test private keys Anvil prints:

```bash
forge script script/DeployTokenVesting.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key <anvil-test-key>
```

Sensitive credentials should never be committed to the repository.



## Limitations and Future Work

* Fee-on-transfer tokens are not supported, because the contract assumes it receives exactly `totalAmount`.
* Ownership cannot be transferred.
* Vesting is linear only, with no stepped or custom curves.
* Fuzz and invariant tests have not been added yet.

## Learning Objectives

This project was built to understand and practice:

* ERC-20 and `IERC20`
* Token transfers and approvals
* `SafeERC20`
* Time-based calculations with `block.timestamp`
* Vesting schedules, cliffs and durations
* Mappings and struct storage
* Access control with modifiers
* Accounting for claimed amounts
* Checks-effects-interactions
* Custom errors and events
* Foundry unit testing
* Foundry cheatcodes such as `vm.warp`, `vm.prank`, `vm.expectRevert` and `vm.expectEmit`
* Writing and running a deploy script

## Development Notes

This project is intended as a learning and portfolio project. It follows one design rule throughout: don't store what you can calculate safely. Instead of updating every beneficiary's balance as time passes, the contract calculates the vested amount from timestamps at the moment someone claims.

## License

This project is licensed under the MIT License.
