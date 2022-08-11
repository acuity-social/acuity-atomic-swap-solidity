// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./ERC20.sol";

contract AcuityAtomicSwapERC20 {

    /**
     * @dev Mapping of sell token address to buy assetId to linked list of accounts, starting with the largest.
     */
    mapping (address => mapping (bytes32 => mapping (address => address))) tokenAssetIdAccountLL;

    /**
     * @dev Mapping of sell token address to buy assetId to selling account to value.
     */
    mapping (address => mapping (bytes32 => mapping (address => uint))) tokenAssetIdAccountValue;

    /**
     * @dev Mapping of lockId to value stored in the lock.
     */
    mapping (bytes32 => uint256) lockIdValue;

    /**
     * @dev Value has been added to a stash.
     * @param token Address of token.
     * @param account Account adding to a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param value How much value has been added to the stash.
     */
    event StashAdd(address indexed token, address indexed account, bytes32 indexed assetId, uint256 value);

    /**
     * @dev Value has been removed from a stash.
     * @param token Address of token.
     * @param account Account removing from a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param value How much value has been removed from the stash.
     */
    event StashRemove(address indexed token, address indexed account, bytes32 indexed assetId, uint256 value);

    /**
     * @dev Value has been locked with sell asset info.
     * @param token Address of token.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param hashedSecret Hash of the secret required to unlock the value.
     * @param timeout Time after which sender can retrieve the value.
     * @param value Value being locked.
     * @param lockId Intrinisic lockId.
     * @param sellAssetId assetId the value is paying for.
     * @param sellPrice Price the asset is being sold for.
     */
    event BuyLock(address indexed token, address indexed sender, address indexed recipient, bytes32 hashedSecret, uint256 timeout, uint256 value, bytes32 lockId, bytes32 sellAssetId, uint256 sellPrice);

    /**
     * @dev Value has been locked.
     * @param token Address of token.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param hashedSecret Hash of the secret required to unlock the value.
     * @param timeout Time after which sender can retrieve the value.
     * @param value Value being locked.
     * @param lockId Intrinisic lockId.
     * @param buyAssetId The asset of the buy lock this lock is responding to.
     * @param buyLockId The buy lock this lock is responding to.
     */
    event SellLock(address indexed token, address indexed sender, address indexed recipient, bytes32 hashedSecret, uint256 timeout, uint256 value, bytes32 lockId, bytes32 buyAssetId, bytes32 buyLockId);

    /**
     * @dev Lock has been declined by the recipient.
     * @param token Address of token.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param lockId Intrinisic lockId.
     */
    event DeclineByRecipient(address indexed token, address indexed sender, address indexed recipient, bytes32 lockId);

    /**
     * @dev Value has been unlocked by the sender.
     * @param token Address of token.
     * @param sender Account that locked the value.
     * @param recipient Account that received the value.
     * @param lockId Intrinisic lockId.
     * @param secret The secret used to unlock the value.
     */
    event UnlockBySender(address indexed token, address indexed sender, address indexed recipient, bytes32 lockId, bytes32 secret);

    /**
     * @dev Value has been unlocked by the recipient.
     * @param token Address of token.
     * @param sender Account that locked the value.
     * @param recipient Account that received the value.
     * @param lockId Intrinisic lockId.
     * @param secret The secret used to unlock the value.
     */
    event UnlockByRecipient(address indexed token, address indexed sender, address indexed recipient, bytes32 lockId, bytes32 secret);

    /**
     * @dev Value has been timed out.
     * @param token Address of token.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param lockId Intrinisic lockId.
     */
    event Timeout(address indexed token, address indexed sender, address indexed recipient, bytes32 lockId);

    /**
     * @dev No value was provided.
     */
    error ZeroValue();

    /**
     * @dev The stash is not big enough.
     * @param token Address of token.
     * @param owner Account removing from a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param value How much value was attempted to be removed from the stash.
     */
    error StashNotBigEnough(address token, address owner, bytes32 assetId, uint256 value);

    /**
     * @dev Value has already been locked with this lockId.
     * @param lockId Lock already locked.
     */
    error LockAlreadyExists(bytes32 lockId);

    /**
     * @dev The lock has already timed out.
     * @param lockId Lock timed out.
     */
    error LockTimedOut(bytes32 lockId);

    /**
     * @dev The lock has not timed out yet.
     * @param lockId Lock not timed out.
     */
    error LockNotTimedOut(bytes32 lockId);

    /**
     * @dev
     */
    error TokenTransferFailed(address token, address from, address to, uint value);

    /**
     * @dev
     */
    function safeTransfer(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transfer.selector, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, address(this), to, value);
    }

    /**
     * @dev
     */
    function safeTransferFrom(address token, address from, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(ERC20.transferFrom.selector, from, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed(token, from, to, value);
    }

    /**
     * @dev Add value to stash be sold for a specific asset.
     * @param token Address of sell token.
     * @param assetId Asset the stash is to be sold for.
     * @param value Size of deposit to add. Must be greater than 0.
     */
    function stashAdd(address token, bytes32 assetId, uint value) internal {
        mapping (address => address) storage accountLL = tokenAssetIdAccountLL[token][assetId];
        mapping (address => uint) storage accountValue = tokenAssetIdAccountValue[token][assetId];
        // Get new total.
        uint total = accountValue[msg.sender] + value;
        // Search for new previous.
        address prev = address(0);
        while (accountValue[accountLL[prev]] >= total) {
            prev = accountLL[prev];
        }
        bool replace = false;
        // Is sender already in the list?
        if (accountValue[msg.sender] > 0) {
            // Search for old previous.
            address oldPrev = address(0);
            while (accountLL[oldPrev] != msg.sender) {
                oldPrev = accountLL[oldPrev];
            }
            // Is it in the same position?
            if (prev == oldPrev) {
                replace = true;
            }
            else {
                // Remove sender from current position.
                accountLL[oldPrev] = accountLL[msg.sender];
            }
        }
        if (!replace) {
            // Insert into linked list.
            accountLL[msg.sender] = accountLL[prev];
            accountLL[prev] = msg.sender;
        }
        // Update the value deposited.
        accountValue[msg.sender] = total;
        // Log info.
        emit StashAdd(token, msg.sender, assetId, value);
    }

    /**
     * @dev Remove value from stash be sold for a specific asset.
     * @param token Address of sell token.
     * @param assetId Asset the stash is to be sold for.
     * @param value Size of deposit to remove. Must be bigger than or equal to deposit value.
     */
    function stashRemove(address token, bytes32 assetId, uint value) internal {
        mapping (address => address) storage accountLL = tokenAssetIdAccountLL[token][assetId];
        mapping (address => uint) storage accountValue = tokenAssetIdAccountValue[token][assetId];
        // Get new total.
        uint total = accountValue[msg.sender] - value;
        // Search for old previous.
        address oldPrev = address(0);
        while (accountLL[oldPrev] != msg.sender) {
            oldPrev = accountLL[oldPrev];
        }
        // Is there still a stash?
        if (total > 0) {
            // Search for new previous.
            address prev = address(0);
            while (accountValue[accountLL[prev]] >= total) {
                prev = accountLL[prev];
            }
            // Is it in a new position?
            if (prev != msg.sender) {
                // Remove sender from old position.
                accountLL[oldPrev] = accountLL[msg.sender];
                // Insert into new position.
                accountLL[msg.sender] = accountLL[prev];
                accountLL[prev] = msg.sender;
            }
        }
        else {
            // Remove sender from list.
            accountLL[oldPrev] = accountLL[msg.sender];
        }
        // Update the value deposited.
        accountValue[msg.sender] = total;
        // Log info.
        emit StashRemove(token, msg.sender, assetId, value);
    }

    /**
     * @dev Stash value to be sold for a specific asset.
     * @param sellToken Address of sell token.
     * @param assetId Asset the stash is to be sold for.
     * @param value Size of deposit.
     */
    function depositStash(address sellToken, bytes32 assetId, uint value) external {
        // Ensure value is nonzero.
        if (value == 0) revert ZeroValue();
        // Move the token.
        safeTransferFrom(sellToken, msg.sender, address(this), value);
        // Record the deposit.
        stashAdd(sellToken, assetId, value);
    }

    /**
     * @dev Move value from one stash to another.
     * @param sellToken Address of sell token.
     * @param assetIdFrom Asset the source stash is to be sold for.
     * @param assetIdTo Asset the destination stash is to be sold for.
     * @param value Value to move.
     */
    function moveStash(address sellToken, bytes32 assetIdFrom, bytes32 assetIdTo, uint value) external {
         // Check there is enough.
         if (tokenAssetIdAccountValue[sellToken][assetIdFrom][msg.sender] < value) revert StashNotBigEnough(sellToken, msg.sender, assetIdFrom, value);
         // Move the deposit.
         stashRemove(sellToken, assetIdFrom, value);
         stashAdd(sellToken, assetIdTo, value);
     }

    /**
     * @dev Withdraw value from a stash.
     * @param sellToken Address of sell token.
     * @param assetId Asset the stash is to be sold for.
     * @param value Value to withdraw.
     */
    function withdrawStash(address sellToken, bytes32 assetId, uint value) external {
        // Check there is enough.
        if (tokenAssetIdAccountValue[sellToken][assetId][msg.sender] < value) revert StashNotBigEnough(sellToken, msg.sender, assetId, value);
        // Remove the deposit.
        stashRemove(sellToken, assetId, value);
        // Send the funds back.
        safeTransfer(sellToken, msg.sender, value);
    }

    /**
     * @dev Withdraw all value from a stash.
     * @param sellToken Address of sell token.
     * @param assetId Asset the stash is to be sold for.
     */
    function withdrawStash(address sellToken, bytes32 assetId) external {
        uint value = tokenAssetIdAccountValue[sellToken][assetId][msg.sender];
        // Remove the deposit.
        stashRemove(sellToken, assetId, value);
        // Send the funds back.
        safeTransfer(sellToken, msg.sender, value);
    }

    /**
     * @dev Lock value.
     * @param recipient Account that can unlock the lock.
     * @param token Address of token to lock.
     * @param hashedSecret Hash of the secret.
     * @param timeout Timestamp when the lock will open.
     * @param sellAssetId assetId the value is paying for.
     * @param sellPrice Price the asset is being sold for.
     * @param value Value of token to lock.
     */
    function lockBuy(address token, address recipient, bytes32 hashedSecret, uint256 timeout, bytes32 sellAssetId, uint256 sellPrice, uint value) external {
        // Ensure value is nonzero.
        if (value == 0) revert ZeroValue();
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(token, msg.sender, recipient, hashedSecret, timeout));
        // Ensure lockId is not already in use.
        if (lockIdValue[lockId] != 0) revert LockAlreadyExists(lockId);
        // Move value into buy lock.
        safeTransferFrom(token, msg.sender, address(this), value);
        lockIdValue[lockId] = value;
        // Log info.
        emit BuyLock(token, msg.sender, recipient, hashedSecret, timeout, value, lockId, sellAssetId, sellPrice);
    }

    /**
     * @dev Lock stashed value.
     * @param sellToken Address of sell token.
     * @param recipient Account that can unlock the lock.
     * @param hashedSecret Hash of the secret.
     * @param timeout Timestamp when the lock will open.
     * @param stashAssetId Asset the stash is to be sold for.
     * @param value Value from the stash to lock.
     * @param buyLockId The buy lock this lock is responding to.
     */
    function lockSell(address sellToken, address recipient, bytes32 hashedSecret, uint256 timeout, bytes32 stashAssetId, uint256 value, bytes32 buyLockId) external {
        // Ensure value is nonzero.
        if (value == 0) revert ZeroValue();
        // Check there is enough.
        if (tokenAssetIdAccountValue[sellToken][stashAssetId][msg.sender] < value) revert StashNotBigEnough(sellToken, msg.sender, stashAssetId, value);
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(sellToken, msg.sender, recipient, hashedSecret, timeout));
        // Ensure lockId is not already in use.
        if (lockIdValue[lockId] != 0) revert LockAlreadyExists(lockId);
        // Move value into sell lock.
        stashRemove(sellToken, stashAssetId, value);
        lockIdValue[lockId] = value;
        // Log info.
        emit SellLock(sellToken, msg.sender, recipient, hashedSecret, timeout, value, lockId, stashAssetId, buyLockId);
    }

    /**
     * @dev Transfer value back to the sender (called by recipient).
     * @param token Address of token.
     * @param sender Sender of the value.
     * @param hashedSecret Hash of the secret.
     * @param timeout Timeout of the lock.
     */
    function declineByRecipient(address token, address sender, bytes32 hashedSecret, uint256 timeout) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(token, sender, msg.sender, hashedSecret, timeout));
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value back to the sender.
        safeTransfer(token, msg.sender, value);
        // Log info.
        emit DeclineByRecipient(token, sender, msg.sender, lockId);
    }

    /**
     * @dev Transfer value from lock to recipient (called by sender).
     * @param token Address of token.
     * @param recipient Recipient of the value.
     * @param secret Secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function unlockBySender(address token, address recipient, bytes32 secret, uint256 timeout) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(token, msg.sender, recipient, keccak256(abi.encodePacked(secret)), timeout));
        // Check lock has not timed out.
        if (timeout <= block.timestamp) revert LockTimedOut(lockId);
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        safeTransfer(token, recipient, value);
        // Log info.
        emit UnlockBySender(token, msg.sender, recipient, lockId, secret);
    }

    /**
     * @dev Transfer value from lock to recipient (called by recipient).
     * @param token Address of token.
     * @param sender Sender of the value.
     * @param secret Secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function unlockByRecipient(address token, address sender, bytes32 secret, uint256 timeout) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(token, sender, msg.sender, keccak256(abi.encodePacked(secret)), timeout));
        // Check lock has not timed out.
        if (timeout <= block.timestamp) revert LockTimedOut(lockId);
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        safeTransfer(token, msg.sender, value);
        // Log info.
        emit UnlockByRecipient(token, sender, msg.sender, lockId, secret);
    }

    /**
     * @dev Transfer value from lock back to sender's stash.
     * @param token Address of token.
     * @param recipient Recipient of the value.
     * @param hashedSecret Hash of secret recipient unlock the value.
     * @param timeout Timeout of the lock.
     */
    function timeoutStash(address token, address recipient, bytes32 hashedSecret, uint256 timeout, bytes32 stashAssetId) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(token, msg.sender, recipient, hashedSecret, timeout));
        // Check lock has timed out.
        if (timeout > block.timestamp) revert LockNotTimedOut(lockId);
        // Get lock value;
        uint256 value = lockIdValue[lockId];
        // Ensure lock has value
        if (value == 0) revert ZeroValue();
        // Delete lock.
        delete lockIdValue[lockId];
        // Return funds.
        stashAdd(token, stashAssetId, value);
        // Log info.
        emit Timeout(token, msg.sender, recipient, lockId);
    }

    /**
     * @dev Transfer value from lock back to sender.
     * @param token Address of token.
     * @param recipient Recipient of the value.
     * @param hashedSecret Hash of secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function timeoutValue(address token, address recipient, bytes32 hashedSecret, uint256 timeout) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(token, msg.sender, recipient, hashedSecret, timeout));
        // Check lock has timed out.
        if (timeout > block.timestamp) revert LockNotTimedOut(lockId);
        // Get lock value;
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        safeTransfer(token, msg.sender, value);
        // Log info.
        emit Timeout(token, msg.sender, recipient, lockId);
    }

    /**
     * @dev Get a list of deposits for a specific asset.
     * @param token Address of token stashed.
     * @param assetId Asset the stash is to be sold for.
     * @param offset Number of deposits to skip from the start of the list.
     * @param limit Maximum number of deposits to return.
     */
    function getStashes(address token, bytes32 assetId, uint offset, uint limit) view external returns (address[] memory accounts, uint[] memory values) {
        mapping (address => address) storage accountLL = tokenAssetIdAccountLL[token][assetId];
        mapping (address => uint) storage accountValue = tokenAssetIdAccountValue[token][assetId];
        // Find first account after offset.
        address start = address(0);
        while (offset > 0) {
          if (accountLL[start] == address(0)) {
            break;
          }
          start = accountLL[start];
          offset--;
        }
        // Count how many accounts to return.
        address account = start;
        uint _limit = 0;
        while (accountLL[account] != address(0) && _limit < limit) {
            account = accountLL[account];
            _limit++;
        }
        // Allocate the arrays.
        accounts = new address[](_limit);
        values = new uint[](_limit);
        // Populate the array.
        account = accountLL[start];
        for (uint i = 0; i < _limit; i++) {
            accounts[i] = account;
            values[i] = accountValue[account];
            account = accountLL[account];
        }
    }

    /**
     * @dev Get value held in a stash.
     * @param token Address of token stashed.
     * @param assetId Asset the stash is to be sold for.
     * @param seller Owner of the stash.
     * @return value Value held in the stash.
     */
    function getStashValue(address token, bytes32 assetId, address seller) view external returns (uint256 value) {
        value = tokenAssetIdAccountValue[token][assetId][seller];
    }

    /**
     * @dev Get value locked.
     * @param token Address of token.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param hashedSecret Hash of the secret required to unlock the value.
     * @param timeout Time after which sender can retrieve the value.
     * @return value Value held in the lock.
     */
    function getLockValue(address token, address sender, address recipient, bytes32 hashedSecret, uint256 timeout) view external returns (uint256 value) {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(token, sender, recipient, hashedSecret, timeout));
        value = lockIdValue[lockId];
    }

    /**
     * @dev Get value locked.
     * @param lockId Lock to examine.
     * @return value Value held in the lock.
     */
    function getLockValue(bytes32 lockId) view external returns (uint256 value) {
        value = lockIdValue[lockId];
    }

}
