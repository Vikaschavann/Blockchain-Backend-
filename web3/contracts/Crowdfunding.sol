// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title CrowdFunding
 * @dev Secure decentralized crowdfunding platform with escrow + refund system
 * @notice Improved with gas optimizations, emergency pause, and better events
 */
contract CrowdFunding is ReentrancyGuard, Pausable {
    enum CampaignState {
        Active,
        Successful,
        Failed,
        Withdrawn
    }

    struct Campaign {
        address owner;
        string title;
        string description;
        uint256 target;
        uint256 deadline;
        uint256 amountCollected;
        string image;
        address[] donators;
        uint256[] donations;
        CampaignState state;
    }

    // Simplified struct for returning campaign data without heavy arrays
    struct CampaignInfo {
        address owner;
        string title;
        string description;
        uint256 target;
        uint256 deadline;
        uint256 amountCollected;
        string image;
        CampaignState state;
        uint256 donatorsCount;
    }

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(address => uint256)) public contributions;
    
    // Track if campaign has been finalized to prevent double finalization
    mapping(uint256 => bool) private finalized;

    uint256 public numberOfCampaigns;
    
    // Platform fee (in basis points, e.g., 250 = 2.5%)
    uint256 public platformFeeRate = 0; // Can be set by owner if needed
    address public platformFeeRecipient;

    // Admin address for emergency functions
    address public admin;

    // -------------------- EVENTS --------------------

    event CampaignCreated(
        uint256 indexed id,
        address indexed owner,
        string title,
        uint256 target,
        uint256 deadline
    );
    
    event DonationReceived(
        uint256 indexed id,
        address indexed donor,
        uint256 amount
    );
    
    event CampaignSuccessful(uint256 indexed id, uint256 amountCollected);
    
    event CampaignFailed(uint256 indexed id);
    
    event FundsWithdrawn(
        uint256 indexed id,
        address indexed owner,
        uint256 amount,
        uint256 fee
    );
    
    event RefundIssued(
        uint256 indexed id,
        address indexed donor,
        uint256 amount
    );
    
    event CampaignFinalized(uint256 indexed id, CampaignState state);

    // -------------------- MODIFIERS --------------------

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier campaignExists(uint256 _id) {
        require(_id < numberOfCampaigns, "Campaign does not exist");
        _;
    }

    // -------------------- CONSTRUCTOR --------------------

    constructor() {
        admin = msg.sender;
        platformFeeRecipient = msg.sender;
    }

    // -------------------- CREATE CAMPAIGN --------------------

    function createCampaign(
        address _owner,
        string calldata _title,
        string calldata _description,
        uint256 _target,
        uint256 _deadline,
        string calldata _image
    ) external whenNotPaused returns (uint256) {
        require(_owner != address(0), "Invalid owner");
        require(_target > 0, "Target must be > 0");
        require(_deadline > block.timestamp, "Deadline must be in future");
        require(bytes(_title).length > 0, "Title required");
        require(bytes(_title).length <= 200, "Title too long");
        require(_deadline <= block.timestamp + 365 days, "Deadline too far");

        Campaign storage campaign = campaigns[numberOfCampaigns];

        campaign.owner = _owner;
        campaign.title = _title;
        campaign.description = _description;
        campaign.target = _target;
        campaign.deadline = _deadline;
        campaign.amountCollected = 0;
        campaign.image = _image;
        campaign.state = CampaignState.Active;

        emit CampaignCreated(
            numberOfCampaigns,
            _owner,
            _title,
            _target,
            _deadline
        );

        numberOfCampaigns++;
        return numberOfCampaigns - 1;
    }

    // -------------------- DONATE --------------------

    function donateToCampaign(uint256 _id)
        external
        payable
        nonReentrant
        whenNotPaused
        campaignExists(_id)
    {
        require(msg.value > 0, "Donation must be > 0");

        Campaign storage campaign = campaigns[_id];

        require(campaign.state == CampaignState.Active, "Campaign not active");
        require(block.timestamp < campaign.deadline, "Deadline passed");

        campaign.donators.push(msg.sender);
        campaign.donations.push(msg.value);
        campaign.amountCollected += msg.value;

        contributions[_id][msg.sender] += msg.value;

        emit DonationReceived(_id, msg.sender, msg.value);

        // Auto-finalize if target reached
        if (campaign.amountCollected >= campaign.target) {
            campaign.state = CampaignState.Successful;
            finalized[_id] = true;
            emit CampaignSuccessful(_id, campaign.amountCollected);
        }
    }

    // -------------------- FINALIZE --------------------

    function finalizeCampaign(uint256 _id)
        external
        nonReentrant
        whenNotPaused
        campaignExists(_id)
    {
        Campaign storage campaign = campaigns[_id];

        require(campaign.state == CampaignState.Active, "Already finalized");
        require(block.timestamp >= campaign.deadline, "Campaign still active");
        require(!finalized[_id], "Already finalized");

        finalized[_id] = true;

        if (campaign.amountCollected >= campaign.target) {
            campaign.state = CampaignState.Successful;
            emit CampaignSuccessful(_id, campaign.amountCollected);
        } else {
            campaign.state = CampaignState.Failed;
            emit CampaignFailed(_id);
        }

        emit CampaignFinalized(_id, campaign.state);
    }

    // -------------------- OWNER WITHDRAW --------------------

    function withdrawFunds(uint256 _id)
        external
        nonReentrant
        whenNotPaused
        campaignExists(_id)
    {
        Campaign storage campaign = campaigns[_id];

        require(msg.sender == campaign.owner, "Only owner");
        require(
            campaign.state == CampaignState.Successful,
            "Campaign not successful"
        );
        require(campaign.amountCollected > 0, "No funds");

        uint256 amount = campaign.amountCollected;
        uint256 fee = 0;

        // Calculate platform fee if applicable
        if (platformFeeRate > 0 && platformFeeRecipient != address(0)) {
            fee = (amount * platformFeeRate) / 10000;
        }

        uint256 ownerAmount = amount - fee;

        campaign.amountCollected = 0;
        campaign.state = CampaignState.Withdrawn;

        // Transfer fee to platform
        if (fee > 0) {
            (bool feeSent, ) = payable(platformFeeRecipient).call{value: fee}(
                ""
            );
            require(feeSent, "Fee transfer failed");
        }

        // Transfer funds to owner
        (bool sent, ) = payable(campaign.owner).call{value: ownerAmount}("");
        require(sent, "Transfer failed");

        emit FundsWithdrawn(_id, campaign.owner, ownerAmount, fee);
    }

    // -------------------- REFUND --------------------

    function claimRefund(uint256 _id)
        external
        nonReentrant
        whenNotPaused
        campaignExists(_id)
    {
        Campaign storage campaign = campaigns[_id];

        require(campaign.state == CampaignState.Failed, "Campaign not failed");

        uint256 amount = contributions[_id][msg.sender];
        require(amount > 0, "No contribution");

        contributions[_id][msg.sender] = 0;
        campaign.amountCollected -= amount;

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Refund failed");

        emit RefundIssued(_id, msg.sender, amount);
    }

    // -------------------- BATCH REFUND (EMERGENCY) --------------------

    /**
     * @dev Emergency function to refund multiple contributors at once
     * @notice Only callable by campaign owner for failed campaigns
     */
    function batchRefund(uint256 _id, address[] calldata _contributors)
        external
        nonReentrant
        onlyAdmin
        campaignExists(_id)
    {
        Campaign storage campaign = campaigns[_id];
        require(campaign.state == CampaignState.Failed, "Campaign not failed");

        for (uint256 i = 0; i < _contributors.length; i++) {
            address contributor = _contributors[i];
            uint256 amount = contributions[_id][contributor];

            if (amount > 0) {
                contributions[_id][contributor] = 0;
                campaign.amountCollected -= amount;

                (bool sent, ) = payable(contributor).call{value: amount}("");
                if (sent) {
                    emit RefundIssued(_id, contributor, amount);
                }
            }
        }
    }

    // -------------------- VIEW FUNCTIONS --------------------

    function getCampaign(uint256 _id)
        external
        view
        campaignExists(_id)
        returns (Campaign memory)
    {
        return campaigns[_id];
    }

    /**
     * @dev Get paginated campaigns to avoid gas limits
     * @param _offset Index to start fetching from
     * @param _limit Maximum number of campaigns to return
     */
    function getCampaigns(uint256 _offset, uint256 _limit)
        external
        view
        returns (CampaignInfo[] memory)
    {
        if (_offset >= numberOfCampaigns) {
            return new CampaignInfo[](0);
        }

        uint256 end = _offset + _limit;
        if (end > numberOfCampaigns) {
            end = numberOfCampaigns;
        }

        uint256 resultSize = end - _offset;
        CampaignInfo[] memory allCampaigns = new CampaignInfo[](resultSize);

        for (uint256 i = 0; i < resultSize; i++) {
            Campaign storage campaign = campaigns[_offset + i];
            allCampaigns[i] = CampaignInfo({
                owner: campaign.owner,
                title: campaign.title,
                description: campaign.description,
                target: campaign.target,
                deadline: campaign.deadline,
                amountCollected: campaign.amountCollected,
                image: campaign.image,
                state: campaign.state,
                donatorsCount: campaign.donators.length
            });
        }

        return allCampaigns;
    }

    function getDonators(uint256 _id)
        external
        view
        campaignExists(_id)
        returns (address[] memory, uint256[] memory)
    {
        return (campaigns[_id].donators, campaigns[_id].donations);
    }

    function getContribution(uint256 _id, address _donor)
        external
        view
        returns (uint256)
    {
        return contributions[_id][_donor];
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function isCampaignFinalized(uint256 _id) external view returns (bool) {
        return finalized[_id];
    }

    // -------------------- ADMIN FUNCTIONS --------------------

    function setPlatformFee(uint256 _feeRate) external onlyAdmin {
        require(_feeRate <= 1000, "Fee too high"); // Max 10%
        platformFeeRate = _feeRate;
    }

    function setPlatformFeeRecipient(address _recipient) external onlyAdmin {
        require(_recipient != address(0), "Invalid address");
        platformFeeRecipient = _recipient;
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function transferAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "Invalid address");
        admin = _newAdmin;
    }
}