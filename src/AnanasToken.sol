// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AnanasToken is ERC20 {
    address public owner;

    struct AnanasPurchase {
        address buyer;
        bool fulfilled;
    }
    struct AnanasUnfulfilledPurchase {
        address buyer;
        uint256 id;
    }
    AnanasPurchase[] public ananasPurchases;

    // Task-related mappings and structs
    struct Task {
        uint256 id;
        uint256 reward;
    }
    Task[] public tasks;
    mapping(address => mapping(uint256 => bool)) public userCompletedTasks;

    event AnanasBought(address indexed user);
    event AnanasFulfilled(address indexed user);
    event TaskCompleted(address indexed user, uint256 taskId, uint256 reward);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    constructor(Task[] memory initialTasks) ERC20("Ananas Token", "ANNS") {
        owner = msg.sender;

        // Add initial tasks
        for (uint256 i = 0; i < initialTasks.length; i++) {
            tasks.push(initialTasks[i]);
        }
    }

    // Casino roll function (user always loses)
    function rollCasino() external returns (string memory) {
        require(balanceOf(msg.sender) >= 10, "Insufficient tokens to roll casino");

        _burn(msg.sender, 10); // Deduct 1000 tokens
        return "You rolled... and lost! Better luck next time!";
    }

    // Function to exchange 1000 ananas tokens for real life ananas
    function buyAnanas() external {
        require(balanceOf(msg.sender) >= 1000, "Insufficient tokens to buy an ananas");

        _burn(msg.sender, 1000);
        ananasPurchases.push(AnanasPurchase({buyer: msg.sender, fulfilled: false}));

        emit AnanasBought(msg.sender);
    }

    // Owner can mark an ananas purchase as fulfilled
    function fulfillAnanas(uint256 purchaseIndex) external onlyOwner {
        require(purchaseIndex < ananasPurchases.length, "Invalid purchase index");
        require(!ananasPurchases[purchaseIndex].fulfilled, "Ananas already fulfilled");

        ananasPurchases[purchaseIndex].fulfilled = true;

        emit AnanasFulfilled(ananasPurchases[purchaseIndex].buyer);
    }

    // Get list of users who have bought an ananas but not fulfilled
    function getUnfulfilledAnanas() external view onlyOwner returns (AnanasUnfulfilledPurchase[] memory) {
        uint256 count = 0;

        // Count unfulfilled ananas purchases
        for (uint256 i = 0; i < ananasPurchases.length; i++) {
            if (!ananasPurchases[i].fulfilled) {
                count++;
            }
        }

        // Create an array of unfulfilled purchases
        AnanasUnfulfilledPurchase[] memory unfulfilled = new AnanasUnfulfilledPurchase[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < ananasPurchases.length; i++) {
            if (!ananasPurchases[i].fulfilled) {
                unfulfilled[index] = AnanasUnfulfilledPurchase({buyer: ananasPurchases[i].buyer, id: i});
                index++;
            }
        }

        return unfulfilled;
    }

    // Owner can mark a task as completed for a user and reward them
    function markTaskAsCompleted(address user, uint256 taskId) external onlyOwner {
        require(taskId < tasks.length, "Invalid task ID");
        require(!userCompletedTasks[user][taskId], "Task already completed by this user");

        userCompletedTasks[user][taskId] = true;
        _mint(user, tasks[taskId].reward);

        emit TaskCompleted(user, taskId, tasks[taskId].reward);
    }
}
