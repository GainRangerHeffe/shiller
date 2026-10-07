// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

contract Shiller {
    address public owner;
    IERC20 public usdc;
    uint256 public constant BASE_FEE = 2 * 10**6; // 2 USDC
    uint256 public constant EXTRA_FEE = 1 * 10**6; // 1 USDC per extra task
    uint256 public constant CAMPAIGN_DURATION = 3 days;
    uint256 public campaignCount;
    bool private locked; // Reentrancy guard

    struct Task {
        uint8 taskType; // 0=Follow, 1=Share, 2=Like, 3=Link, 4=Comment, 5=Quote, 6=Tag
        string target;
    }

    struct Proof {
        string proofUrl;
        uint256 timestamp;
        bool approved;
    }

    struct Campaign {
        address creator;
        string projectName;
        string description;
        string mediaURI;
        string rewardDetails;
        uint256 startTime;
        uint256 taskCount;
        bool active; // Explicit active status
    }

    mapping(address => uint256) public activeCampaigns;
    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => Task[]) public tasks;
    mapping(uint256 => address[]) public participants;
    mapping(uint256 => mapping(address => uint256)) public completions;
    mapping(uint256 => mapping(address => mapping(uint256 => Proof))) public proofs;

    event CampaignCreated(uint256 indexed campaignId, address indexed creator, uint256 taskCount);
    event CampaignEnded(uint256 indexed campaignId, address indexed creator);
    event TaskCompleted(uint256 indexed campaignId, address indexed participant, uint256 taskId);
    event ProofSubmitted(uint256 indexed campaignId, address indexed participant, uint256 taskId, string proofUrl);
    event ProofApproved(uint256 indexed campaignId, address indexed participant, uint256 taskId);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FundsWithdrawn(address indexed owner, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrancy guard");
        locked = true;
        _;
        locked = false;
    }

    constructor(address _usdc) {
        require(_usdc != address(0), "Invalid USDC address");
        owner = msg.sender;
        usdc = IERC20(_usdc);
    }

    function createCampaign(
        string memory _projectName,
        string memory _description,
        string memory _mediaURI,
        string memory _rewardDetails,
        Task[] memory _tasks
    ) external nonReentrant {
        require(bytes(_projectName).length > 0, "Project name required");
        require(bytes(_description).length > 0, "Description required");
        require(_tasks.length >= 3, "Need 3+ tasks");
        require(_tasks.length <= 50, "Too many tasks"); // Prevent gas issues
        for (uint256 i = 0; i < _tasks.length; i++) {
            require(_tasks[i].taskType <= 6, "Invalid task type");
            require(bytes(_tasks[i].target).length > 0, "Task target required");
        }

        uint256 fee = BASE_FEE + (_tasks.length > 3 ? (_tasks.length - 3) * EXTRA_FEE : 0);
        require(usdc.allowance(msg.sender, address(this)) >= fee, "Insufficient USDC allowance");
        require(usdc.balanceOf(msg.sender) >= fee, "Insufficient USDC balance");
        require(usdc.transferFrom(msg.sender, address(this), fee), "USDC transfer failed");

        uint256 campaignId = campaignCount++;
        campaigns[campaignId] = Campaign({
            creator: msg.sender,
            projectName: _projectName,
            description: _description,
            mediaURI: _mediaURI,
            rewardDetails: _rewardDetails,
            startTime: block.timestamp,
            taskCount: _tasks.length,
            active: true
        });

        for (uint256 i = 0; i < _tasks.length; i++) {
            tasks[campaignId].push(_tasks[i]);
        }

        activeCampaigns[msg.sender]++;
        emit CampaignCreated(campaignId, msg.sender, _tasks.length);
    }

    function submitProof(uint256 _campaignId, uint256 _taskId, string memory _proofUrl) external nonReentrant {
        require(_campaignId < campaignCount, "Invalid campaign");
        require(campaigns[_campaignId].active, "Campaign inactive");
        require(_taskId < campaigns[_campaignId].taskCount, "Invalid task");
        require(block.timestamp <= campaigns[_campaignId].startTime + CAMPAIGN_DURATION, "Campaign expired");
        require(bytes(_proofUrl).length > 0, "Proof URL required");
        require(bytes(proofs[_campaignId][msg.sender][_taskId].proofUrl).length == 0, "Proof already submitted");

        proofs[_campaignId][msg.sender][_taskId] = Proof({
            proofUrl: _proofUrl,
            timestamp: block.timestamp,
            approved: false
        });

        emit ProofSubmitted(_campaignId, msg.sender, _taskId, _proofUrl);
    }

    function approveProof(uint256 _campaignId, uint256 _taskId, address _participant) external nonReentrant {
        require(_campaignId < campaignCount, "Invalid campaign");
        require(msg.sender == campaigns[_campaignId].creator, "Only creator can approve");
        require(bytes(proofs[_campaignId][_participant][_taskId].proofUrl).length > 0, "No proof submitted");
        require(!proofs[_campaignId][_participant][_taskId].approved, "Already approved");

        proofs[_campaignId][_participant][_taskId].approved = true;
        completions[_campaignId][_participant]++;
        if (!_isParticipant(_campaignId, _participant)) {
            participants[_campaignId].push(_participant);
        }
        emit ProofApproved(_campaignId, _participant, _taskId);
        emit TaskCompleted(_campaignId, _participant, _taskId);
    }

    function approveMultipleProofs(
        uint256 _campaignId,
        uint256[] memory _taskIds,
        address[] memory _participants
    ) external nonReentrant {
        require(_campaignId < campaignCount, "Invalid campaign");
        require(msg.sender == campaigns[_campaignId].creator, "Only creator can approve");
        require(_taskIds.length == _participants.length, "Arrays mismatch");
        require(_taskIds.length <= 50, "Too many proofs"); // Prevent gas issues

        for (uint256 i = 0; i < _taskIds.length; i++) {
            uint256 taskId = _taskIds[i];
            address participant = _participants[i];
            require(taskId < campaigns[_campaignId].taskCount, "Invalid task");
            require(bytes(proofs[_campaignId][participant][taskId].proofUrl).length > 0, "No proof");
            require(!proofs[_campaignId][participant][taskId].approved, "Already approved");

            proofs[_campaignId][participant][taskId].approved = true;
            completions[_campaignId][participant]++;
            if (!_isParticipant(_campaignId, participant)) {
                participants[_campaignId].push(participant);
            }
            emit ProofApproved(_campaignId, participant, taskId);
            emit TaskCompleted(_campaignId, participant, taskId);
        }
    }

    function endCampaign(uint256 _campaignId) external nonReentrant {
        require(_campaignId < campaignCount, "Invalid campaign");
        require(msg.sender == campaigns[_campaignId].creator, "Only creator");
        require(campaigns[_campaignId].active, "Campaign already ended");

        campaigns[_campaignId].active = false;
        if (activeCampaigns[msg.sender] > 0) {
            activeCampaigns[msg.sender]--;
        }
        emit CampaignEnded(_campaignId, msg.sender);
    }

    function getCampaign(uint256 _campaignId)
        external
        view
        returns (
            address creator,
            string memory projectName,
            string memory description,
            string memory mediaURI,
            string memory rewardDetails,
            uint256 startTime,
            uint256 taskCount,
            bool active
        )
    {
        require(_campaignId < campaignCount, "Invalid campaign");
        Campaign memory c = campaigns[_campaignId];
        return (
            c.creator,
            c.projectName,
            c.description,
            c.mediaURI,
            c.rewardDetails,
            c.startTime,
            c.taskCount,
            c.active && block.timestamp <= c.startTime + CAMPAIGN_DURATION
        );
    }

    function getTask(uint256 _campaignId, uint256 _taskId)
        external
        view
        returns (uint8 taskType, string memory target)
    {
        require(_campaignId < campaignCount, "Invalid campaign");
        require(_taskId < campaigns[_campaignId].taskCount, "Invalid task");
        Task memory t = tasks[_campaignId][_taskId];
        return (t.taskType, t.target);
    }

    function getProof(uint256 _campaignId, address _participant, uint256 _taskId)
        external
        view
        returns (string memory proofUrl, uint256 timestamp, bool approved)
    {
        require(_campaignId < campaignCount, "Invalid campaign");
        require(_taskId < campaigns[_campaignId].taskCount, "Invalid task");
        Proof memory p = proofs[_campaignId][_participant][_taskId];
        return (p.proofUrl, p.timestamp, p.approved);
    }

    function getCompletions(uint256 _campaignId, address _participant)
        external
        view
        returns (uint256)
    {
        require(_campaignId < campaignCount, "Invalid campaign");
        return completions[_campaignId][_participant];
    }

    function getParticipants(uint256 _campaignId)
        external
        view
        returns (address[] memory)
    {
        require(_campaignId < campaignCount, "Invalid campaign");
        return participants[_campaignId];
    }

    function getAllCampaignsWithCompletions(address _user)
        external
        view
        returns (
            Campaign[] memory campaignsData,
            uint256[] memory completionsData
        )
    {
        Campaign[] memory camps = new Campaign[](campaignCount);
        uint256[] memory comps = new uint256[](campaignCount);
        for (uint256 i = 0; i < campaignCount; i++) {
            camps[i] = campaigns[i];
            comps[i] = completions[i][_user];
        }
        return (camps, comps);
    }

    function getLeaderboardData(uint256 _campaignId)
        external
        view
        returns (
            address[] memory participantsData,
            uint256[] memory completionCounts
        )
    {
        require(_campaignId < campaignCount, "Invalid campaign");
        address[] memory parts = participants[_campaignId];
        uint256[] memory counts = new uint256[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            counts[i] = completions[_campaignId][parts[i]];
        }
        return (parts, counts);
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, "No funds to withdraw");
        require(usdc.transferFrom(address(this), owner, balance), "Withdraw failed");
        emit FundsWithdrawn(owner, balance);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    function _isParticipant(uint256 _campaignId, address _participant) private view returns (bool) {
        for (uint256 i = 0; i < participants[_campaignId].length; i++) {
            if (participants[_campaignId][i] == _participant) {
                return true;
            }
        }
        return false;
    }

    // Deprecated function, kept for compatibility
    function completeTask(uint256 _campaignId, uint256 _taskId, address _participant) external {
        require(_campaignId < campaignCount, "Invalid campaign");
        require(msg.sender == campaigns[_campaignId].creator, "Only creator");
        require(_taskId < campaigns[_campaignId].taskCount, "Invalid task");
        completions[_campaignId][_participant]++;
        if (!_isParticipant(_campaignId, _participant)) {
            participants[_campaignId].push(_participant);
        }
        emit TaskCompleted(_campaignId, _participant, _taskId);
    }
}
