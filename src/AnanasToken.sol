// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract AnanasTokenCasino is VRFConsumerBaseV2Plus {
    LinkTokenInterface LINKTOKEN;
    address public link_token_contract = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address public vrfCoordinator;
    bytes32 public s_keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae; // 500 gwei lane
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;
    uint256 public s_subscriptionId;

    AnanasToken public ananasToken;

    mapping(address => int8) public rollStatuses;
    mapping(uint256 => address) public requestIdToRoller;
    mapping(uint256 => bool) public rollResults;

    event RollStart(uint256 indexed requestId, address indexed roller);
    event RollEnd(uint256 indexed requestId, bool indexed result);

    constructor(address _ananasToken, address _vrfCoordinator) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        LINKTOKEN = LinkTokenInterface(link_token_contract);
        _createNewSubscription();
        ananasToken = AnanasToken(_ananasToken);
        vrfCoordinator = _vrfCoordinator;
    }

    function doRoll(address roller) external onlyOwner {
        require(rollStatuses[roller] == 0, "Another roll is in progress");

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );

        requestIdToRoller[requestId] = roller;
        rollStatuses[roller] = 1;
        emit RollStart(requestId, roller);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        bool win = (randomWords[0] & 1) == 1;

        rollResults[requestId] = win;
        rollStatuses[requestIdToRoller[requestId]] = 0;

        if (win) {
            ananasToken.mintTokens(requestIdToRoller[requestId], 20);
        }

        emit RollEnd(requestId, win);
    }

    // Assumes this contract owns link.
    // 1000000000000000000 = 1 LINK
    function topUpSubscription(uint256 amount) external onlyOwner {
        LINKTOKEN.transferAndCall(
            address(s_vrfCoordinator),
            amount,
            abi.encode(s_subscriptionId)
        );
    }

    function _createNewSubscription() private onlyOwner {
        s_subscriptionId = s_vrfCoordinator.createSubscription();
        s_vrfCoordinator.addConsumer(s_subscriptionId, address(this));
    }
}

contract AnanasToken is ERC20 {
    address public owner;
    AnanasTokenCasino public casino;

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

    // Auction-related mappings and structs
    struct Auction {
        string description;
        uint256 minimalStep;
        uint256 lastBet;
        address currentWinner;
        uint256 lastTimestamp;
    }

    enum Status {
        Disabled,
        Active,
        Closed
    }

    uint256 public constant BET_TIMER = 1 minutes;

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Status) public auctionStatus;

    mapping(address => uint256) public reservedTokens; // Tokens on hold while leading the auction

    event AuctionBet(address user, uint256 auctionId, uint256 bet);
    event AuctionClosed(uint256 auctionId);

    // Polls-related mappings and structs
    struct Poll {
        uint256 id;
        string description;
        uint256 votePrice; // price in tokens for one vote
        uint256 voteLimit; // how many times can user vote in the poll
        uint256[] votes;
    }

    mapping(uint256 => uint256) public pollIndex;
    Poll[] public polls;
    mapping(uint256 => Status) public pollStatus;
    mapping(uint256 => mapping(address => uint256)) public userVotesCount;

    event PollVote(address user, uint256 option);

    modifier onlyOwner() {
        require(msg.sender == owner || msg.sender == address(casino), "Only owner can perform this action");
        _;
    }

    constructor(Task[] memory initialTasks, address vrfCoordinator) ERC20("Ananas Token", "ANNS") {
        owner = msg.sender;

        // Add initial tasks
        for (uint256 i = 0; i < initialTasks.length; i++) {
            tasks.push(initialTasks[i]);
        }
        // vrfCoordinator is 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B for prod
        // Can be mock for tests
        casino = new AnanasTokenCasino(address(this), vrfCoordinator);
    }

    // Owner can transfer some tokens to the student (for some kind of activity)
    function mintTokens(address user, uint256 amount) external onlyOwner {
        _mint(user, amount);
    }

    // Similarly, tokens can be withdrawn
    function burnTokens(address user, uint256 amount) external onlyOwner {
        _burn(user, amount);
    }

    // Casino roll function (user always loses)
    function rollCasino() external {
        require(balanceOf(msg.sender) - reservedTokens[msg.sender] >= 10, "Insufficient tokens to roll casino");

        _burn(msg.sender, 10);
        casino.doRoll(msg.sender);
    }

    // Function to exchange 1000 ananas tokens for real life ananas
    function buyAnanas() external {
        require(balanceOf(msg.sender) - reservedTokens[msg.sender] >= 1000, "Insufficient tokens to buy an ananas");

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

    // Owner can register new auction
    function registerAuction(uint256 id, string memory description, uint256 initialBet, uint256 minimalStep) external onlyOwner {
        require (auctionStatus[id] == Status.Disabled, "Incorrect transmitted ID");

        auctions[id] = Auction(description, minimalStep, initialBet, address(0), block.timestamp);
        auctionStatus[id] = Status.Active;
    }

    // Users can make a bet at the auction
    function makeAuctionBet(uint256 id, uint256 bet) external {
        require(auctionStatus[id] == Status.Active, "Incorrect auction ID");
        require(bet >= auctions[id].lastBet + auctions[id].minimalStep, "Insufficient bet amount");
        require(balanceOf(msg.sender) - reservedTokens[msg.sender] >= bet, "Insufficient tokens to make a bet in an auction");

        reservedTokens[msg.sender] += bet;
        if (auctions[id].currentWinner != address(0)) {
            reservedTokens[auctions[id].currentWinner] -= auctions[id].lastBet;
        }

        auctions[id].lastBet = bet;
        auctions[id].currentWinner = msg.sender;
        auctions[id].lastTimestamp = block.timestamp;

        emit AuctionBet(msg.sender, id, bet);
    }

    // Owner can finish the auction and get the winner
    function finalizeAuction(uint256 id) external onlyOwner returns (address) {
        require(auctionStatus[id] == Status.Active, "Incorrect auction ID");
        require(block.timestamp >= auctions[id].lastTimestamp + BET_TIMER, "Not enough time has passed since the last bet");
        require(auctions[id].currentWinner != address(0), "There have benn no bets yet");

        auctionStatus[id] = Status.Closed;
        _burn(auctions[id].currentWinner, auctions[id].lastBet);
        reservedTokens[auctions[id].currentWinner] -= auctions[id].lastBet;

        return auctions[id].currentWinner;
    }

    // Owner can cancel the auction without winner
    function cancelAuction(uint256 id) external onlyOwner {
        require(auctionStatus[id] == Status.Active, "Incorrect auction ID");

        auctionStatus[id] = Status.Closed;
        if (auctions[id].currentWinner != address(0)) {
            reservedTokens[auctions[id].currentWinner] -= auctions[id].lastBet;
        }

        emit AuctionClosed(id);
    }

    // Owner can register new poll
    function registerPoll(uint256 id, string memory description, uint256 optionsCount, uint256 votePrice, uint256 voteLimit) external onlyOwner {
        require (pollStatus[id] == Status.Disabled, "Incorrect transmitted ID");

        pollIndex[id] = polls.length;
        polls.push(Poll(id, description, votePrice, voteLimit, new uint256[](optionsCount)));
        pollStatus[id] = Status.Active;
    }

    // Users can vote for an option in poll
    function makeVote(uint256 id, uint256 option) external {
        require(pollStatus[id] == Status.Active, "Incorrect poll ID");

        uint256 p_id = pollIndex[id];
        require(balanceOf(msg.sender) - reservedTokens[msg.sender] >= polls[p_id].votePrice, "Insufficient tokens to make a vote");
        require(userVotesCount[id][msg.sender] < polls[p_id].voteLimit, "User out of votes");
        require(option < polls[p_id].votes.length, "Bad option");

        polls[p_id].votes[option] += 1;
        _burn(msg.sender, polls[p_id].votePrice);
        userVotesCount[id][msg.sender] += 1;

        emit PollVote(msg.sender, option);
    }

    // Owner can finish the poll and get winner
    function finalizePoll(uint256 id) external onlyOwner returns (uint256) {
        require(pollStatus[id] == Status.Active, "Incorrect poll ID");

        uint256 p_id = pollIndex[id];
        pollStatus[id] = Status.Closed;

        uint256 maxVotes = 0;
        uint256 winner = 0;
        for (uint256 i = 0; i < polls[p_id].votes.length; i++) {
            if (polls[p_id].votes[i] > maxVotes) {
                winner = i;
                maxVotes = polls[p_id].votes[i];
            }
        }

        return winner;
    }
}
