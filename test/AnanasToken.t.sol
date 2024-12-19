pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {AnanasToken} from "../src/AnanasToken.sol";

contract AnanasTokenTest is Test {
    AnanasToken public ananasToken;

    function setUp() public {
        AnanasToken.Task[] memory initialTasks = new AnanasToken.Task[](3);
        initialTasks[0] = AnanasToken.Task({id: 1, reward: 100});
        initialTasks[1] = AnanasToken.Task({id: 2, reward: 200});
        initialTasks[2] = AnanasToken.Task({id: 3, reward: 3000});
        ananasToken = new AnanasToken(initialTasks);
    }

    function test_Basic() public {
        StudentBot student = new StudentBot(ananasToken);

        // Owner can mark tasks as completed
        // TODO: maybe make some integration with task system
        ananasToken.markTaskAsCompleted(address(student), 2);
        assertEq(ananasToken.balanceOf(address(student)), 3000);

        // Student can roll casino for 10 ananases (currently just looses them)
        // TODO: make rolls random probaly using [Chainlink VRF](https://docs.chain.link/vrf)
        student.rollCasino();
        assertEq(ananasToken.balanceOf(address(student)), 2990);

        // Student can buy real ananas for 1000 anans tokens
        student.buyAnanas();
        AnanasToken.AnanasUnfulfilledPurchase[] memory unfullfilled = ananasToken.getUnfulfilledAnanas();
        assertEq(unfullfilled.length, 1);
        assertEq(unfullfilled[0].buyer, address(student));
        // Then after giving ananas teacher fulfills purchase
        ananasToken.fulfillAnanas(unfullfilled[0].id);
        unfullfilled = ananasToken.getUnfulfilledAnanas();
        assertEq(unfullfilled.length, 0);

        // ERC20 operations are default, so transfers are possible
        StudentBot student2 = new StudentBot(ananasToken);
        StudentBot student3 = new StudentBot(ananasToken);
        ananasToken.markTaskAsCompleted(address(student2), 2);
        student2.transfer(address(student3), 2000);
        assertEq(ananasToken.balanceOf(address(student3)), 2000);

        // TODO: May be some DAO vote or something
    }
}

contract StudentBot {
    AnanasToken public ananasToken;

    constructor(AnanasToken initAnanasToken) {
        ananasToken = initAnanasToken;
    }

    function rollCasino() external {
        ananasToken.rollCasino();
    }

    function buyAnanas() external {
        ananasToken.buyAnanas();
    }

    function transfer(address to, uint256 amount) external {
        ananasToken.transfer(to, amount);
    }
}
