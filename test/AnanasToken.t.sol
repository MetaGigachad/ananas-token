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

    function test_Auctions() public {
        StudentBot student1 = new StudentBot(ananasToken);
        StudentBot student2 = new StudentBot(ananasToken);

        ananasToken.mintTokens(address(student1), 100);
        ananasToken.mintTokens(address(student2), 200);

        ananasToken.registerAuction({id: 0, description: "Auction for 3 ananases", initialBet: 50, minimalStep: 10});

        student1.makeAuctionBet(0, 100);

        vm.expectRevert("Insufficient bet amount"); // too small step
        student1.makeAuctionBet(0, 105);

        student2.makeAuctionBet(0, 150);

        vm.expectRevert("Insufficient tokens to make a bet in an auction"); // not enougth tokens
        student1.makeAuctionBet(0, 200);

        address winner;

        vm.expectRevert("Not enough time has passed since the last bet");
        winner = ananasToken.finalizeAuction(0);

        vm.warp(block.timestamp + 100);
        winner = ananasToken.finalizeAuction(0);

        assertEq(winner, address(student2));
    }

    function test_Polls() public {
        StudentBot student1 = new StudentBot(ananasToken);
        StudentBot student2 = new StudentBot(ananasToken);

        ananasToken.mintTokens(address(student1), 100);
        ananasToken.mintTokens(address(student2), 300);

        ananasToken.registerPoll({id: 0, description: "Which is better: canned (op. 0) or fresh (op. 1) ananases", optionsCount: 2, votePrice: 100, voteLimit: 2});

        student1.makeVote(0, 0);

        vm.expectRevert("Insufficient tokens to make a vote"); // not enougth tokens
        student1.makeVote(0, 0);

        student2.makeVote(0, 1);
        student2.makeVote(0, 1);

        vm.expectRevert("User out of votes");
        student2.makeVote(0, 1);

        uint256 winner = ananasToken.finalizePoll(0);
        assertEq(winner, 1); // Fresh ananases are better!
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

    function makeAuctionBet(uint256 id, uint256 bet) external {
        ananasToken.makeAuctionBet(id, bet);
    }

    function makeVote(uint256 id, uint256 option) external {
        ananasToken.makeVote(id, option);
    }
}
