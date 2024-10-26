// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Xefers Referral Contract (BTTC Compatible)
/// @dev A contract that handles tracking referrals and rewards in both ETH and ERC-20 tokens.
contract Xefers is Pausable, ReentrancyGuard {

    /// @notice The total number of successful referrals for each campaign
    mapping(uint256 => uint256) public referralCount;

    /// @notice Mapping to track if an address has been referred per campaign
    mapping(uint256 => mapping(address => bool)) public hasBeenReferred;

    /// @notice Metadata structure to store details about a Xefers campaign
    struct CampaignMetadata {
        string title;               // Title of the Xefers campaign
        string redirectUrl;         // URL to redirect to after a referral
        address owner;              // The owner/creator of the campaign
        uint256 referralReward;     // Reward in wei (ETH) for successful referrals
        IERC20 token;               // ERC-20 token for rewards (if used)
        uint256 tokenReward;        // Reward in token amount (if applicable)
        uint256 referralCap;        // Maximum number of referrals allowed per campaign
        uint256 expiryTime;         // Expiration timestamp for the campaign
        bool isActive;              // Status of the campaign (active or not)
    }

    /// @notice Campaigns metadata for multiple campaigns
    mapping(uint256 => CampaignMetadata) public campaigns;

    /// @notice Event emitted when a referral is successful
    event ReferralSuccessful(uint256 indexed campaignId, address indexed referrer, address indexed referral, string redirectUrl);

    /// @notice Event emitted when the owner withdraws tokens or ETH
    event FundsWithdrawn(uint256 indexed campaignId, address owner, uint256 amount, address token);

    /// @notice Event emitted when a campaign is paused or unpaused
    event CampaignStatusUpdated(uint256 indexed campaignId, bool isActive);

    /// @notice Create a new referral campaign with ETH and/or token rewards
    function createCampaign(
        uint256 campaignId,
        string memory _title,
        uint256 _referralReward,
        IERC20 _token,
        uint256 _tokenReward,
        string memory _redirectUrl,
        uint256 _referralCap,
        uint256 _expiryTime
    ) external {
        require(campaigns[campaignId].owner == address(0), "Campaign ID already exists");
        require(_expiryTime > block.timestamp, "Expiry time must be in the future");
        
        campaigns[campaignId] = CampaignMetadata({
            title: _title,
            redirectUrl: _redirectUrl,
            owner: msg.sender,
            referralReward: _referralReward,
            token: _token,
            tokenReward: _tokenReward,
            referralCap: _referralCap,
            expiryTime: _expiryTime,
            isActive: true
        });
    }

    /// @notice Refer someone and claim a reward (ETH or tokens)
    function makeReferral(uint256 campaignId) external whenNotPaused nonReentrant {
        CampaignMetadata storage campaign = campaigns[campaignId];
        require(campaign.isActive, "Campaign is not active");
        require(block.timestamp <= campaign.expiryTime, "Campaign has expired");
        require(!hasBeenReferred[campaignId][msg.sender], "User has already been referred for this campaign");
        require(referralCount[campaignId] < campaign.referralCap, "Referral cap reached for this campaign");

        // Mark the sender as referred
        hasBeenReferred[campaignId][msg.sender] = true;

        // Increment the referral count
        referralCount[campaignId] += 1;

        uint256 ethReward = campaign.referralReward;
        uint256 tokenReward = campaign.tokenReward;

        // Pay out ETH reward
        if (ethReward > 0) {
            require(address(this).balance >= ethReward, "Insufficient contract balance for ETH reward");
            payable(msg.sender).transfer(ethReward);
        }

        // Pay out Token reward
        if (tokenReward > 0 && address(campaign.token) != address(0)) {
            require(campaign.token.balanceOf(address(this)) >= tokenReward, "Insufficient token balance for reward");
            campaign.token.transfer(msg.sender, tokenReward);
        }

        // Emit event for successful referral
        emit ReferralSuccessful(campaignId, campaign.owner, msg.sender, campaign.redirectUrl);
    }

    /// @notice Withdraw contract funds (ETH or tokens)
    function withdrawFunds(uint256 campaignId, uint256 _amount, address _token) external onlyOwner(campaignId) nonReentrant {
        if (_token == address(0)) {
            // Withdraw ETH
            require(address(this).balance >= _amount, "Insufficient ETH balance");
            payable(msg.sender).transfer(_amount);
        } else {
            // Withdraw ERC-20 tokens
            IERC20 token = IERC20(_token);
            require(token.balanceOf(address(this)) >= _amount, "Insufficient token balance");
            token.transfer(msg.sender, _amount);
        }
        emit FundsWithdrawn(campaignId, msg.sender, _amount, _token);
    }

    /// @notice Update the active status of a campaign
    function setCampaignStatus(uint256 campaignId, bool _isActive) external onlyOwner(campaignId) {
        campaigns[campaignId].isActive = _isActive;
        emit CampaignStatusUpdated(campaignId, _isActive);
    }

    /// @notice Updates the redirect URL for a campaign
    function updateRedirectUrl(uint256 campaignId, string memory _redirectUrl) external onlyOwner(campaignId) {
        campaigns[campaignId].redirectUrl = _redirectUrl;
    }

    /// @notice Updates the referral reward (ETH and/or tokens) for a campaign
    function updateReferralRewards(uint256 campaignId, uint256 _referralReward, uint256 _tokenReward) external onlyOwner(campaignId) {
        campaigns[campaignId].referralReward = _referralReward;
        campaigns[campaignId].tokenReward = _tokenReward;
    }

    /// @notice Transfer ownership of the campaign
    function transferOwnership(uint256 campaignId, address newOwner) external onlyOwner(campaignId) {
        require(newOwner != address(0), "New owner cannot be zero address");
        campaigns[campaignId].owner = newOwner;
    }

    /// @notice Modifier to ensure only the campaign owner can call certain functions
    modifier onlyOwner(uint256 campaignId) {
        require(msg.sender == campaigns[campaignId].owner, "Only campaign owner can call this function");
        _;
    }

    /// @notice Pause the contract in case of emergency
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract when the emergency is over
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Fallback function to receive ETH
    receive() external payable {}
}