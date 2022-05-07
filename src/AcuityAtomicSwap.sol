// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "./ERC20.sol";

contract AcuityAtomicSwap {

    /**
     * @dev Mapping of address to ACU address.
     */
    mapping (address => bytes32) addressAcuAddress;

    /**
     * @dev Mapping of lockId to locked value.
     */
    mapping (bytes32 => uint256) lockIdValue;

    /**
     * @dev
     */
    event BuyerLock(address indexed buyer, address indexed seller, bytes32 indexed hashedSecret, uint256 timeout, uint256 value, bytes32 assetIdPrice);

    /**
     * @dev
     */
    event SellerLock(address indexed seller, address indexed buyer, bytes32 indexed hashedSecret, uint256 timeout, uint256 value);

    /**
     * @dev
     */
    event BuyerLockERC20(address indexed buyer, address indexed seller, bytes32 indexed hashedSecret, uint256 timeout, address tokenAddress, uint256 value, bytes32 assetIdPrice);

    /**
     * @dev
     */
    event SellerLockERC20(address indexed seller, address indexed buyer, bytes32 indexed hashedSecret, uint256 timeout, address tokenAddress, uint256 value);

    /**
     * @dev
     */
    event Unlock(bytes32 indexed lockId, bytes32 secret);

    /**
     * @dev
     */
    event Timeout(bytes32 indexed lockId);

    /**
     * @dev
     */
    function setAcuAddress(bytes32 acuAddress) external {
        addressAcuAddress[msg.sender] = acuAddress;
    }

    /**
     * @dev Called by buyer.
     */
    function buyerLockValue(address seller, bytes32 hashedSecret, uint256 timeout, bytes32 assetIdPrice) payable external {
        // Ensure lock has value.
        require(msg.value != 0, "Lock must have value.");
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encodePacked(msg.sender, seller, hashedSecret, timeout));
        // Ensure lockId is not already in use.
        require(lockIdValue[lockId] == 0, "Lock already exists.");
        // Store lock value.
        lockIdValue[lockId] = msg.value;
        // Log info.
        emit BuyerLock(msg.sender, seller, hashedSecret, timeout, msg.value, assetIdPrice);
    }

    /**
     * @dev Called by seller.
     */
    function sellerLockValue(address buyer, bytes32 hashedSecret, uint256 timeout) payable external {
        // Ensure lock has value.
        require(msg.value != 0, "Lock must have value.");
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encodePacked(msg.sender, buyer, hashedSecret, timeout));
        // Ensure lockId is not already in use.
        require(lockIdValue[lockId] == 0, "Lock already exists.");
        // Store lock value.
        lockIdValue[lockId] = msg.value;
        // Log info.
        emit SellerLock(msg.sender, buyer, hashedSecret, timeout, msg.value);
    }

    /**
     * @dev Called by "to". Can be called even when the lock is expired.
     */
    function unlockValue(address from, bytes32 secret, uint256 timeout) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encodePacked(from, msg.sender, keccak256(abi.encodePacked(secret)), timeout));
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        payable(msg.sender).transfer(value);
        // Log info.
        emit Unlock(lockId, secret);
    }

    /**
     * @dev Called by "from" if "to" did not unlock.
     */
    function timeoutValue(address to, bytes32 hashedSecret, uint256 timeout) external {
        // Check lock has timed out.
        require(timeout <= block.timestamp, "Lock not timed out.");
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encodePacked(msg.sender, to, hashedSecret, timeout));
        // Get lock value;
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        payable(msg.sender).transfer(value);
        // Log info.
        emit Timeout(lockId);
    }

    /**
     * @dev Called by buyer.
     */
    function buyerLockERC20Value(address seller, bytes32 hashedSecret, uint256 timeout, address tokenAddress, uint256 value, bytes32 assetIdPrice) external {
        // Ensure lock has value.
        require(value != 0, "Lock must have value.");
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encodePacked(msg.sender, seller, hashedSecret, timeout, tokenAddress));
        // Ensure lockId is not already in use.
        require(lockIdValue[lockId] == 0, "Lock already exists.");
        // Store lock value.
        lockIdValue[lockId] = value;
        // Transfer the value.
        require(ERC20(tokenAddress).transferFrom(msg.sender, address(this), value), "Token transfer failed.");
        // Log info.
        emit BuyerLockERC20(msg.sender, seller, hashedSecret, timeout, tokenAddress, value, assetIdPrice);
    }

    /**
     * @dev Called by seller.
     */
    function sellerLockERC20Value(address buyer, bytes32 hashedSecret, uint256 timeout, address tokenAddress, uint256 value) external {
        // Ensure lock has value.
        require(value != 0, "Lock must have value.");
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encodePacked(msg.sender, buyer, hashedSecret, timeout, tokenAddress));
        // Ensure lockId is not already in use.
        require(lockIdValue[lockId] == 0, "Lock already exists.");
        // Store lock value.
        lockIdValue[lockId] = value;
        // Transfer the value.
        require(ERC20(tokenAddress).transferFrom(msg.sender, address(this), value), "Token transfer failed.");
        // Log info.
        emit SellerLockERC20(msg.sender, buyer, hashedSecret, timeout, tokenAddress, value);
    }

    /**
     * @dev Called by "to". Can be called even when the lock is expired.
     */
    function unlockERC20Value(address from, bytes32 secret, uint256 timeout, address tokenAddress) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encodePacked(from, msg.sender, keccak256(abi.encodePacked(secret)), timeout, tokenAddress));
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        require(ERC20(tokenAddress).transferFrom(address(this), msg.sender, value), "Token transfer failed.");
        // Log info.
        emit Unlock(lockId, secret);
    }

    /**
     * @dev Called by "from" if "to" did not unlock.
     */
    function timeoutERC20Value(address to, bytes32 hashedSecret, uint256 timeout, address tokenAddress) external {
        // Check lock has timed out.
        require(timeout <= block.timestamp, "Lock not timed out.");
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encodePacked(msg.sender, to, hashedSecret, timeout, tokenAddress));
        // Get lock value;
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        require(ERC20(tokenAddress).transferFrom(address(this), msg.sender, value), "Token transfer failed.");
        // Log info.
        emit Timeout(lockId);
    }

    /**
     * @dev
     */
    function getAcuAddress(address seller) view external returns (bytes32 acuAddress) {
        acuAddress = addressAcuAddress[seller];
    }

    /**
     * @dev
     */
    function getLockValue(address from, address to, bytes32 hashedSecret, uint256 timeout) view external returns (uint256 value) {
        value = lockIdValue[keccak256(abi.encodePacked(from, to, hashedSecret, timeout))];
    }

    /**
     * @dev
     */
    function getLockERC20Value(address from, address to, bytes32 hashedSecret, uint256 timeout, address tokenAddress) view external returns (uint256 value) {
        value = lockIdValue[keccak256(abi.encodePacked(from, to, hashedSecret, timeout, tokenAddress))];
    }

    /**
     * @dev
     */
    function getLockValue(bytes32 lockId) view external returns (uint256 value) {
        value = lockIdValue[lockId];
    }

}
