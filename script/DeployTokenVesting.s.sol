// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

contract DeployTokenVesting is Script {
    function run() external returns (TokenVesting) {
        vm.startBroadcast();
        TokenVesting tokenVesting = new TokenVesting();
        vm.stopBroadcast();

        return tokenVesting;
    }
}
