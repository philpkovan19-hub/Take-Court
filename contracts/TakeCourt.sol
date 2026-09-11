// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title TakeCourt — put your take on trial, community stakes BOT to Crown or Bonk it
///        Pari-mutuel: winning side splits the losing side's pool proportionally.
contract TakeCourt is Ownable, ReentrancyGuard, Pausable {

    enum Verdict { Pending, Crowned, Bonked, Tied, Cancelled }

    struct Take {
        uint256 id;
        address author;
        string content;         // the take itself
        uint256 filedAt;
        uint256 votingEndsAt;
        uint256 crownPool;      // total BOT staked to Crown
        uint256 bonkPool;       // total BOT staked to Bonk
        Verdict verdict;
        bool distributed;       // pool has been paid out
    }

    struct Vote {
        uint256 amount;
        bool isCrown;
        bool claimed;
    }

    uint256 public filingFee = 0.005 ether;   // fee to file a take
    uint256 public platformFeeBps = 300;      // 3% of the losing pool goes to platform
    uint256 public constant BPS_DENOM = 10000;
    uint256 public defaultTrialDuration = 1 days;

    uint256 public takeCount;
    uint256 public feesCollected;

    mapping(uint256 => Take) public takes;
    mapping(uint256 => mapping(address => Vote)) public voteBy;   // takeId => voter => vote
    mapping(address => uint256[]) public takesByAuthor;

    event TakeFiled(uint256 indexed id, address indexed author, string content, uint256 votingEndsAt);
    event Voted(uint256 indexed id, address indexed voter, bool isCrown, uint256 amount);
    event Adjudicated(uint256 indexed id, Verdict verdict, uint256 crownPool, uint256 bonkPool);
    event Claimed(uint256 indexed id, address indexed voter, uint256 payout);
    event TakeCancelled(uint256 indexed id);

    constructor() Ownable(msg.sender) {}

    // ---------- Core actions ----------

    function fileTake(string calldata content, uint256 durationSecs) external payable whenNotPaused nonReentrant returns (uint256) {
        require(msg.value >= filingFee, "Insufficient filing fee");
        require(bytes(content).length > 0 && bytes(content).length <= 512, "Content 1-512 chars");
        uint256 dur = durationSecs == 0 ? defaultTrialDuration : durationSecs;
        require(dur >= 1 hours && dur <= 30 days, "Duration 1h-30d");

        takeCount++;
        uint256 id = takeCount;

        takes[id] = Take({
            id: id,
            author: msg.sender,
            content: content,
            filedAt: block.timestamp,
            votingEndsAt: block.timestamp + dur,
            crownPool: 0,
            bonkPool: 0,
            verdict: Verdict.Pending,
            distributed: false
        });
        takesByAuthor[msg.sender].push(id);
        feesCollected += msg.value;

        emit TakeFiled(id, msg.sender, content, block.timestamp + dur);
        return id;
    }

    function voteCrown(uint256 id) external payable whenNotPaused nonReentrant { _vote(id, true, msg.value); }
    function voteBonk(uint256 id) external payable whenNotPaused nonReentrant { _vote(id, false, msg.value); }

    function _vote(uint256 id, bool isCrown, uint256 amount) internal {
        require(id > 0 && id <= takeCount, "Invalid take");
        require(amount > 0, "Must stake BOT");
        Take storage T = takes[id];
        require(T.verdict == Verdict.Pending, "Trial closed");
        require(block.timestamp < T.votingEndsAt, "Voting ended");

        Vote storage V = voteBy[id][msg.sender];
        if (V.amount == 0) {
            V.isCrown = isCrown;
        } else {
            require(V.isCrown == isCrown, "Cannot vote both sides");
        }
        V.amount += amount;

        if (isCrown) T.crownPool += amount; else T.bonkPool += amount;
        emit Voted(id, msg.sender, isCrown, amount);
    }

    /// @notice Anyone can trigger the adjudication once voting has ended.
    function adjudicate(uint256 id) external nonReentrant {
        require(id > 0 && id <= takeCount, "Invalid take");
        Take storage T = takes[id];
        require(T.verdict == Verdict.Pending, "Already adjudicated");
        require(block.timestamp >= T.votingEndsAt, "Voting still open");

        if (T.crownPool == 0 && T.bonkPool == 0) {
            T.verdict = Verdict.Cancelled;
        } else if (T.crownPool > T.bonkPool) {
            T.verdict = Verdict.Crowned;
        } else if (T.bonkPool > T.crownPool) {
            T.verdict = Verdict.Bonked;
        } else {
            T.verdict = Verdict.Tied;
        }
        emit Adjudicated(id, T.verdict, T.crownPool, T.bonkPool);
    }

    /// @notice Winning voters call this to claim; losing side gets nothing.
    ///         If Tied or Cancelled, everyone gets their stake back.
    function claim(uint256 id) external nonReentrant {
        require(id > 0 && id <= takeCount, "Invalid take");
        Take storage T = takes[id];
        require(T.verdict != Verdict.Pending, "Not yet adjudicated");
        Vote storage V = voteBy[id][msg.sender];
        require(V.amount > 0, "Nothing to claim");
        require(!V.claimed, "Already claimed");
        V.claimed = true;

        uint256 payout = 0;
        if (T.verdict == Verdict.Tied || T.verdict == Verdict.Cancelled) {
            payout = V.amount;
        } else {
            bool wonSide = (T.verdict == Verdict.Crowned && V.isCrown) ||
                           (T.verdict == Verdict.Bonked  && !V.isCrown);
            if (wonSide) {
                uint256 winPool = V.isCrown ? T.crownPool : T.bonkPool;
                uint256 losePool = V.isCrown ? T.bonkPool : T.crownPool;
                uint256 fee = (losePool * platformFeeBps) / BPS_DENOM;
                uint256 distributable = losePool - fee;
                if (!T.distributed) {
                    feesCollected += fee;
                    T.distributed = true;
                }
                // stake back + proportional slice of the losing pool
                payout = V.amount + (V.amount * distributable) / winPool;
            } else {
                payout = 0;
            }
        }
        if (payout > 0) {
            (bool ok, ) = payable(msg.sender).call{value: payout}("");
            require(ok, "Payout failed");
        }
        emit Claimed(id, msg.sender, payout);
    }

    // ---------- Views ----------

    function getTake(uint256 id) external view returns (Take memory) {
        require(id > 0 && id <= takeCount, "Invalid take");
        return takes[id];
    }

    function getVote(uint256 id, address who) external view returns (Vote memory) {
        return voteBy[id][who];
    }

    function getTakesByAuthor(address who) external view returns (uint256[] memory) {
        return takesByAuthor[who];
    }

    function getRecent(uint256 limit) external view returns (Take[] memory) {
        if (limit > takeCount) limit = takeCount;
        Take[] memory out = new Take[](limit);
        for (uint256 i = 0; i < limit; i++) { out[i] = takes[takeCount - i]; }
        return out;
    }

    function isVotingOpen(uint256 id) external view returns (bool) {
        if (id == 0 || id > takeCount) return false;
        Take memory T = takes[id];
        return T.verdict == Verdict.Pending && block.timestamp < T.votingEndsAt;
    }

    // ---------- Admin ----------

    function setFilingFee(uint256 v) external onlyOwner { filingFee = v; }
    function setPlatformFeeBps(uint256 v) external onlyOwner { require(v <= 1000, "Max 10%"); platformFeeBps = v; }
    function setDefaultTrialDuration(uint256 v) external onlyOwner { require(v >= 1 hours && v <= 30 days, "1h-30d"); defaultTrialDuration = v; }
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
    function withdrawFees(address payable to) external onlyOwner nonReentrant {
        uint256 amt = feesCollected;
        feesCollected = 0;
        (bool ok, ) = to.call{value: amt}("");
        require(ok, "Withdraw failed");
    }
}
