// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract TokenVesting {
    using SafeERC20 for IERC20;

    error TokenVesting__ZeroAddress();
    error TokenVesting__TotalAmountZero();
    error TokenVesting__ZeroDuration();
    error TokenVesting__CliffIsGreaterThanDuration();
    error TokenVesting__NotOwner();
    error TokenVesting__StartTimeAlreadyPassed();
    error TokenVesting__ScheduleNotFound();
    error TokenVesting__NotBeneficiary();
    error TokenVesting__NothingToClaim();
    error TokenVesting__IsNotRevocable();
    error TokenVesting__AlreadyRevoked();

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

    uint256 private s_scheduleCount;
    address private immutable i_owner;
    mapping(uint256 => Schedule) private s_schedules;

    event ScheduleCreated(uint256 indexed scheduleId, address indexed beneficiary, uint256 totalAmount);
    event Released(uint256 indexed scheduleId, address indexed beneficiary, uint256 released);
    event ScheduleRevoked(uint256 indexed scheduleId, uint256 refundAmount);

    constructor() {
        i_owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == i_owner, TokenVesting__NotOwner());
        _;
    }

    function createSchedule(
        address beneficiary,
        address token,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        bool revocable
    ) external onlyOwner {
        require(beneficiary != address(0) && token != address(0), TokenVesting__ZeroAddress());
        require(start >= block.timestamp, TokenVesting__StartTimeAlreadyPassed());
        require(totalAmount > 0, TokenVesting__TotalAmountZero());
        require(duration > 0, TokenVesting__ZeroDuration());
        require(cliff <= duration, TokenVesting__CliffIsGreaterThanDuration());

        s_schedules[s_scheduleCount] = Schedule({
            beneficiary: beneficiary,
            token: token,
            totalAmount: totalAmount,
            start: start,
            cliff: cliff,
            duration: duration,
            released: 0,
            revocable: revocable,
            revoked: false
        });

        emit ScheduleCreated(s_scheduleCount, beneficiary, totalAmount);

        s_scheduleCount++;

        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
    }

    function vestedAmount(uint256 scheduleId) public view returns (uint256) {
        Schedule memory schedule = s_schedules[scheduleId];
        require(schedule.beneficiary != address(0), TokenVesting__ScheduleNotFound());

        if (schedule.revoked) {
            return schedule.totalAmount;
        }

        uint256 cliffEnd = schedule.start + schedule.cliff;
        uint256 vestingEnd = schedule.start + schedule.duration;

        if (block.timestamp < cliffEnd) {
            return 0;
        }

        if (block.timestamp >= vestingEnd) {
            return schedule.totalAmount;
        }

        uint256 elapsed = block.timestamp - schedule.start;
        return (schedule.totalAmount * elapsed) / schedule.duration;
    }

    function release(uint256 scheduleId) external {
        Schedule storage schedule = s_schedules[scheduleId];
        require(schedule.beneficiary != address(0), TokenVesting__ScheduleNotFound());
        require(schedule.beneficiary == msg.sender, TokenVesting__NotBeneficiary());
        uint256 releasable = vestedAmount(scheduleId) - schedule.released;
        require(releasable > 0, TokenVesting__NothingToClaim());
        schedule.released += releasable;

        emit Released(scheduleId, schedule.beneficiary, releasable);

        IERC20(schedule.token).safeTransfer(msg.sender, releasable);
    }

    function revoke(uint256 scheduleId) external onlyOwner {
        Schedule storage schedule = s_schedules[scheduleId];
        require(schedule.beneficiary != address(0), TokenVesting__ScheduleNotFound());
        require(schedule.revocable, TokenVesting__IsNotRevocable());
        require(!schedule.revoked, TokenVesting__AlreadyRevoked());

        uint256 vested = vestedAmount(scheduleId);
        uint256 refund = schedule.totalAmount - vested;
        schedule.revoked = true;
        schedule.totalAmount = vested;

        emit ScheduleRevoked(scheduleId, refund);
        IERC20(schedule.token).safeTransfer(msg.sender, refund);
    }

    function getSchedule(uint256 scheduleId) external view returns (Schedule memory) {
        return s_schedules[scheduleId];
    }
}
