// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TokenVesting} from "../../src/TokenVesting.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract TokenVestingTest is Test {
    TokenVesting tokenVesting;
    MockERC20 mockERC20;
    uint256 constant INITIAL_SUPPLY = 10000 ether;
    uint256 start;

    address Ada = makeAddr("ada");
    address Owner = makeAddr("owner");

    function setUp() public {
        vm.startPrank(Owner);
        tokenVesting = new TokenVesting();
        mockERC20 = new MockERC20();
        mockERC20.mint(Owner, INITIAL_SUPPLY);
        mockERC20.approve(address(tokenVesting), INITIAL_SUPPLY);

        vm.stopPrank();
        start = block.timestamp + 1 days;
    }

    function _scheduleCreated() internal {
        vm.prank(Owner);
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 30 days, 100 days, true);
    }

    function testVestedIsZeroBeforeCliff() public {
        _scheduleCreated();

        vm.warp(start + 20 days);

        assertEq(tokenVesting.vestedAmount(0), 0);
    }

    function testVestedAtCliff() public {
        _scheduleCreated();

        vm.warp(start + 30 days);

        assertEq(tokenVesting.vestedAmount(0), 300 ether);
    }

    function testCreateScheduleTransfersTokens() public {
        assertEq(mockERC20.balanceOf(Owner), 10000 ether);

        _scheduleCreated();

        assertEq(mockERC20.balanceOf(Owner), 9000 ether);
        assertEq(mockERC20.balanceOf(address(tokenVesting)), 1000 ether);
    }

    function testSecondScheduleGetsIdOne() public {
        // first schedule gets ID 0
        vm.expectEmit(true, true, false, true);
        emit TokenVesting.ScheduleCreated(0, Ada, 1000 ether);
        vm.prank(Owner);
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 30 days, 100 days, true);

        // second schedule must get ID 1
        vm.expectEmit(true, true, false, true);
        emit TokenVesting.ScheduleCreated(1, Ada, 500 ether);
        vm.prank(Owner);
        tokenVesting.createSchedule(Ada, address(mockERC20), 500 ether, start, 30 days, 100 days, true);

        // both schedules hold their tokens: 1000 + 500
        assertEq(mockERC20.balanceOf(address(tokenVesting)), 1500 ether);
    }

    function testCreateScheduleEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit TokenVesting.ScheduleCreated(0, Ada, 1000 ether);

        vm.prank(Owner);
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 30 days, 100 days, true);
    }

    function testVestedAtHalfway() public {
        _scheduleCreated();

        vm.warp(start + 50 days);

        assertEq(tokenVesting.vestedAmount(0), 500 ether);
    }

    function testVestedEqualsTotalAtEnd() public {
        _scheduleCreated();

        vm.warp(start + 100 days);

        assertEq(tokenVesting.vestedAmount(0), 1000 ether);
    }

    function testVestedDoesNotExceedTotalAfterEnd() public {
        _scheduleCreated();

        vm.warp(start + 500 days);

        assertEq(tokenVesting.vestedAmount(0), 1000 ether);
    }

    function testVestedIsZeroOneSecondBeforeCliff() public {
        _scheduleCreated();

        vm.warp(start + 30 days - 1);

        assertEq(tokenVesting.vestedAmount(0), 0);
    }

    function testVestedIsJustBelowTotalOneSecondBeforeEnd() public {
        _scheduleCreated();

        vm.warp(start + 100 days - 1);

        assertEq(tokenVesting.vestedAmount(0), 999_999_884_259_259_259_259);
    }

    function testCreateScheduleRevertsWhenNotOwner() public {
        vm.prank(Ada);
        vm.expectRevert(TokenVesting.TokenVesting__NotOwner.selector);
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 30 days, 100 days, true);
    }

    function testCreateScheduleRevertsWhenZeroBeneficiary() public {
        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__ZeroAddress.selector);
        tokenVesting.createSchedule(address(0), address(mockERC20), 1000 ether, start, 30 days, 100 days, true);
    }

    function testCreateScheduleRevertsWhenZeroToken() public {
        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__ZeroAddress.selector);
        tokenVesting.createSchedule(Ada, address(0), 1000 ether, start, 30 days, 100 days, true);
    }

    function testCreateScheduleRevertsWhenStartInPast() public {
        vm.warp(start + 1); // now start is behind the clock
        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__StartTimeAlreadyPassed.selector);
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 30 days, 100 days, true);
    }

    function testCreateScheduleRevertsWhenZeroAmount() public {
        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__TotalAmountZero.selector);
        tokenVesting.createSchedule(Ada, address(mockERC20), 0, start, 30 days, 100 days, true);
    }

    function testCreateScheduleRevertsWhenZeroDuration() public {
        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__ZeroDuration.selector);
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 0, 0, true);
    }

    function testCreateScheduleRevertsWhenCliffGreaterThanDuration() public {
        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__CliffIsGreaterThanDuration.selector);
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 101 days, 100 days, true);
    }

    function testCreateScheduleRevertsWhenNotApproved() public {
        // remove the approval that setUp gave
        vm.prank(Owner);
        mockERC20.approve(address(tokenVesting), 0);

        vm.prank(Owner);
        vm.expectRevert(); // the error comes from the token, not from our contract
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 30 days, 100 days, true);
    }

    function testReleasingOneScheduleDoesNotAffectAnother() public {
        // schedule 0: 1000 ether, schedule 1: 500 ether, same timing
        vm.startPrank(Owner);
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 30 days, 100 days, true);
        tokenVesting.createSchedule(Ada, address(mockERC20), 500 ether, start, 30 days, 100 days, true);
        vm.stopPrank();

        vm.warp(start + 30 days);

        // release only schedule 1: 30% of 500 = 150
        vm.prank(Ada);
        tokenVesting.release(1);
        assertEq(mockERC20.balanceOf(Ada), 150 ether);

        // schedule 0 still shows its full 300 vested
        assertEq(tokenVesting.vestedAmount(0), 300 ether);

        // and schedule 0 can still pay its own 300
        vm.prank(Ada);
        tokenVesting.release(0);
        assertEq(mockERC20.balanceOf(Ada), 450 ether); // 150 + 300
        assertEq(mockERC20.balanceOf(address(tokenVesting)), 1050 ether); // 1500 - 450
    }

    function testRevokeAtMidpointRefundsUnvested() public {
        _scheduleCreated();

        vm.warp(start + 50 days);
        vm.prank(Owner);
        tokenVesting.revoke(0);

        assertEq(mockERC20.balanceOf(Owner), 9500 ether);
        assertEq(mockERC20.balanceOf(address(tokenVesting)), 500 ether);
    }

    function testAdaCanClaimVestedAfterRevoke() public {
        _scheduleCreated();

        vm.warp(start + 50 days);
        vm.prank(Owner);
        tokenVesting.revoke(0);
        vm.warp(start + 500 days);

        vm.prank(Ada);
        tokenVesting.release(0);

        assertEq(mockERC20.balanceOf(Ada), 500 ether);
    }

    function testRevokeBeforeCliffRefundsEverything() public {
        _scheduleCreated();

        vm.warp(start + 29 days);
        vm.prank(Owner);
        tokenVesting.revoke(0);

        vm.prank(Ada);
        vm.expectRevert(TokenVesting.TokenVesting__NothingToClaim.selector);
        tokenVesting.release(0);

        assertEq(mockERC20.balanceOf(Owner), 10000 ether);
    }

    function testRevokeAfterReleaseKeepsAccountingCorrect() public {
        _scheduleCreated();

        vm.warp(start + 30 days);
        vm.prank(Ada);
        tokenVesting.release(0);

        assertEq(mockERC20.balanceOf(Ada), 300 ether);

        vm.warp(start + 50 days);
        vm.prank(Owner);
        tokenVesting.revoke(0);

        assertEq(mockERC20.balanceOf(Owner), 9500 ether);
        vm.prank(Ada);
        tokenVesting.release(0);

        assertEq(mockERC20.balanceOf(Ada), 500 ether);
        assertEq(mockERC20.balanceOf(address(tokenVesting)), 0);
    }

    function testRevokeRevertsWhenNotRevocable() public {
        vm.prank(Owner);
        tokenVesting.createSchedule(Ada, address(mockERC20), 1000 ether, start, 30 days, 100 days, false);

        vm.warp(start + 30 days);
        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__IsNotRevocable.selector);
        tokenVesting.revoke(0);
    }

    function testRevokeRevertsWhenAlreadyRevoked() public {
        _scheduleCreated();

        vm.warp(start + 30 days);
        vm.prank(Owner);
        tokenVesting.revoke(0);

        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__AlreadyRevoked.selector);
        tokenVesting.revoke(0);
    }

    function testRevokeRevertsWhenNotOwner() public {
        _scheduleCreated();

        vm.prank(Ada);
        vm.expectRevert(TokenVesting.TokenVesting__NotOwner.selector);
        tokenVesting.revoke(0);
    }

    function testRevokeAfterFullyVestedRefundsZero() public {
        _scheduleCreated();

        vm.warp(start + 100 days);
        vm.prank(Owner);
        tokenVesting.revoke(0);
        assertEq(mockERC20.balanceOf(Owner), 9000 ether);
    }

    function testRevokeEmitsEvent() public {
        _scheduleCreated();

        vm.warp(start + 50 days);
        vm.prank(Owner);
        vm.expectEmit(true, false, false, true);
        emit TokenVesting.ScheduleRevoked(0, 500 ether);
        tokenVesting.revoke(0);
    }

    function testVestingIsFrozenAfterRevoke() public {
        _scheduleCreated();

        vm.warp(start + 50 days);
        vm.prank(Owner);
        tokenVesting.revoke(0);

        vm.warp(start + 60 days);
        uint256 vested = tokenVesting.vestedAmount(0);
        assertEq(vested, 500 ether);
    }

    function testRevokeRevertsWhenScheduleDoesNotExist() public {
        _scheduleCreated();

        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__ScheduleNotFound.selector);
        tokenVesting.revoke(99);
    }

    function testReleaseRevertsWhenScheduleDoesNotExist() public {
        _scheduleCreated();

        vm.prank(Ada);
        vm.expectRevert(TokenVesting.TokenVesting__ScheduleNotFound.selector);
        tokenVesting.release(99);
    }

    function testReleaseRevertsWhenNotBeneficiary() public {
        _scheduleCreated();

        vm.prank(Owner);
        vm.expectRevert(TokenVesting.TokenVesting__NotBeneficiary.selector);
        tokenVesting.release(0);
    }

    function testReleaseRevertsBeforeCliff() public {
        _scheduleCreated();
        vm.warp(start + 20 days);

        vm.prank(Ada);
        vm.expectRevert(TokenVesting.TokenVesting__NothingToClaim.selector);
        tokenVesting.release(0);
    }

    function testReleaseAtCliff() public {
        _scheduleCreated();
        vm.warp(start + 30 days);

        vm.expectEmit(true, true, false, true);
        emit TokenVesting.Released(0, Ada, 300 ether);

        vm.prank(Ada);
        tokenVesting.release(0);

        assertEq(mockERC20.balanceOf(Ada), 300 ether);
        assertEq(mockERC20.balanceOf(address(tokenVesting)), 700 ether);
    }

    function testReleaseTwiceAtSameTimeReverts() public {
        _scheduleCreated();
        vm.warp(start + 30 days);

        vm.prank(Ada);
        tokenVesting.release(0);

        vm.prank(Ada);
        vm.expectRevert(TokenVesting.TokenVesting__NothingToClaim.selector);
        tokenVesting.release(0);
    }

    function testSecondReleasePaysOnlyTheDifference() public {
        _scheduleCreated();

        vm.warp(start + 30 days);
        vm.prank(Ada);
        tokenVesting.release(0); // Ada has 300

        vm.warp(start + 50 days);
        vm.prank(Ada);
        tokenVesting.release(0); // vested 500 minus 300 already taken = 200 more

        assertEq(mockERC20.balanceOf(Ada), 500 ether);
    }

    function testReleaseAfterEndPaysExactlyTotal() public {
        _scheduleCreated();

        vm.warp(start + 30 days);
        vm.prank(Ada);
        tokenVesting.release(0); // 300

        vm.warp(start + 500 days);
        vm.prank(Ada);
        tokenVesting.release(0); // the remaining 700

        assertEq(mockERC20.balanceOf(Ada), 1000 ether);
        assertEq(mockERC20.balanceOf(address(tokenVesting)), 0);
    }

    function testGetScheduleReturnsStoredValues() public {
        _scheduleCreated();

        TokenVesting.Schedule memory schedule = tokenVesting.getSchedule(0);
        assertEq(schedule.beneficiary, Ada);
        assertEq(schedule.totalAmount, 1000 ether);
        assertEq(schedule.released, 0);
        assertTrue(schedule.revocable);
        assertFalse(schedule.revoked);
        assertEq(schedule.token, address(mockERC20));
        assertEq(schedule.start, start);
        assertEq(schedule.cliff, 30 days);
        assertEq(schedule.duration, 100 days);
    }

    function testGetScheduleAfterRevoke() public {
        _scheduleCreated();

        vm.warp(start + 50 days);
        vm.prank(Owner);
        tokenVesting.revoke(0);

        TokenVesting.Schedule memory schedule = tokenVesting.getSchedule(0);
        assertEq(schedule.beneficiary, Ada);
        assertEq(schedule.totalAmount, 500 ether);
        assertEq(schedule.released, 0);
        assertTrue(schedule.revocable);
        assertTrue(schedule.revoked);
        assertEq(schedule.token, address(mockERC20));
        assertEq(schedule.start, start);
        assertEq(schedule.cliff, 30 days);
        assertEq(schedule.duration, 100 days);
    }

    function testGetScheduleAfterRelease() public {
        _scheduleCreated();

        vm.warp(start + 30 days);
        vm.prank(Ada);
        tokenVesting.release(0);

        TokenVesting.Schedule memory schedule = tokenVesting.getSchedule(0);
        assertEq(schedule.beneficiary, Ada);
        assertEq(schedule.totalAmount, 1000 ether);
        assertEq(schedule.released, 300 ether);
        assertTrue(schedule.revocable);
        assertFalse(schedule.revoked);
        assertEq(schedule.token, address(mockERC20));
        assertEq(schedule.start, start);
        assertEq(schedule.cliff, 30 days);
        assertEq(schedule.duration, 100 days);
    }
}
