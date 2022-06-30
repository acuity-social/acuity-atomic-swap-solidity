// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

contract AcuityAtomicSwap {

    /**
     * @dev Mapping of assetId to linked list of accounts, starting with the largest.
     */
    mapping (bytes16 => mapping (address => address)) stashAssetIdAccountsLL;

    /**
     * @dev Mapping of assetId to selling address to value.
     */
    mapping (bytes16 => mapping (address => uint)) stashAssetIdAccountValue;

    /**
     * @dev Mapping of lockId to value stored in the lock.
     */
    mapping (bytes32 => uint256) lockIdValue;

    /**
     * @dev Value has been added to a stash.
     * @param account Account adding to a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param value How much value has been added to the stash.
     */
    event StashAdd(address indexed account, bytes16 indexed assetId, uint256 value);

    /**
     * @dev Value has been removed from a stash.
     * @param account Account removing from a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param value How much value has been removed from the stash.
     */
    event StashRemove(address indexed account, bytes16 indexed assetId, uint256 value);

    /**
     * @dev Value has been locked with sell asset info.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param hashedSecret Hash of the secret required to unlock the value.
     * @param timeout Time after which sender can retrieve the value.
     * @param value Value being locked.
     * @param lockId Intrinisic lockId.
     * @param sellAssetId assetId the value is paying for.
     * @param sellPrice Price the asset is being sold for.
     */
    event BuyLock(address indexed sender, address indexed recipient, bytes32 hashedSecret, uint256 timeout, uint256 value, bytes32 lockId, bytes16 sellAssetId, uint256 sellPrice);

    /**
     * @dev Value has been locked.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param hashedSecret Hash of the secret required to unlock the value.
     * @param timeout Time after which sender can retrieve the value.
     * @param value Value being locked.
     * @param lockId Intrinisic lockId.
     * @param buyAssetId The asset of the buy lock this lock is responding to.
     * @param buyLockId The buy lock this lock is responding to.
     */
    event SellLock(address indexed sender, address indexed recipient, bytes32 hashedSecret, uint256 timeout, uint256 value, bytes32 lockId, bytes16 buyAssetId, bytes32 buyLockId);

    /**
     * @dev Value has been unlocked.
     * @param sender Account that locked the value.
     * @param recipient Account that received the value.
     * @param lockId Intrinisic lockId.
     * @param secret The secret used to unlock the value.
     */
    event Unlock(address indexed sender, address indexed recipient, bytes32 lockId, bytes32 secret);

    /**
     * @dev Value has been timed out.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param lockId Intrinisic lockId.
     */
    event Timeout(address indexed sender, address indexed recipient, bytes32 lockId);

    /**
     * @dev No value was provided.
     */
    error ZeroValue();

    /**
     * @dev The stash is not big enough.
     * @param owner Account removing from a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param value How much value was attempted to be removed from the stash.
     */
    error StashNotBigEnough(address owner, bytes16 assetId, uint256 value);

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
     * @dev Add value to stash be sold for a specific asset.
     * @param assetId Asset the stash is to be sold for.
     * @param value Size of deposit to add. Must be greater than 0.
     */
    function stashAdd(bytes16 assetId, uint value) internal {
        mapping (address => address) storage accountsLL = stashAssetIdAccountsLL[assetId];
        mapping (address => uint) storage accountValue = stashAssetIdAccountValue[assetId];
        // Get new total.
        uint total = accountValue[msg.sender] + value;
        // Search for new previous.
        address prev = address(0);
        while (accountValue[accountsLL[prev]] >= total) {
            prev = accountsLL[prev];
        }
        bool replace = false;
        // Is sender already in the list?
        if (accountValue[msg.sender] > 0) {
            // Search for old previous.
            address oldPrev = address(0);
            while (accountsLL[oldPrev] != msg.sender) {
                oldPrev = accountsLL[oldPrev];
            }
            // Is it in the same position?
            if (prev == oldPrev) {
                replace = true;
            }
            else {
                // Remove sender from current position.
                accountsLL[oldPrev] = accountsLL[msg.sender];
            }
        }
        if (!replace) {
            // Insert into linked list.
            accountsLL[msg.sender] = accountsLL[prev];
            accountsLL[prev] = msg.sender;
        }
        // Update the value deposited.
        accountValue[msg.sender] = total;
        // Log info.
        emit StashAdd(msg.sender, assetId, value);
    }

    /**
     * @dev Remove value from stash be sold for a specific asset.
     * @param assetId Asset the stash is to be sold for.
     * @param value Size of deposit to remove. Must be bigger than or equal to deposit value.
     */
    function stashRemove(bytes16 assetId, uint value) internal {
        mapping (address => address) storage accountsLL = stashAssetIdAccountsLL[assetId];
        mapping (address => uint) storage accountValue = stashAssetIdAccountValue[assetId];
        // Get new total.
        uint total = accountValue[msg.sender] - value;
        // Search for old previous.
        address oldPrev = address(0);
        while (accountsLL[oldPrev] != msg.sender) {
            oldPrev = accountsLL[oldPrev];
        }
        // Is there still a stash?
        if (total > 0) {
            // Search for new previous.
            address prev = address(0);
            while (accountValue[accountsLL[prev]] >= total) {
                prev = accountsLL[prev];
            }
            // Is it in a new position?
            if (prev != msg.sender) {
                // Remove sender from old position.
                accountsLL[oldPrev] = accountsLL[msg.sender];
                // Insert into new position.
                accountsLL[msg.sender] = accountsLL[prev];
                accountsLL[prev] = msg.sender;
            }
        }
        else {
            // Remove sender from list.
            accountsLL[oldPrev] = accountsLL[msg.sender];
        }
        // Update the value deposited.
        accountValue[msg.sender] = total;
        // Log info.
        emit StashRemove(msg.sender, assetId, value);
    }

    /**
     * @dev Stash value to be sold for a specific asset.
     * @param assetId Asset the stash is to be sold for.
     */
    function depositStash(bytes16 assetId) external payable {
        // Ensure value is nonzero.
        if (msg.value == 0) revert ZeroValue();
        // Records the deposit.
        stashAdd(assetId, msg.value);
    }

    /**
     * @dev Move value from one stash to another.
     * @param assetIdFrom Asset the source stash is to be sold for.
     * @param assetIdTo Asset the destination stash is to be sold for.
     * @param value Value to move.
     */
    function moveStash(bytes16 assetIdFrom, bytes16 assetIdTo, uint value) external {
         // Check there is enough.
         if (stashAssetIdAccountValue[assetIdFrom][msg.sender] < value) revert StashNotBigEnough(msg.sender, assetIdFrom, value);
         // Move the deposit.
         stashRemove(assetIdFrom, value);
         stashAdd(assetIdTo, value);
     }

    /**
     * @dev Withdraw value from a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param value Value to withdraw.
     */
    function withdrawStash(bytes16 assetId, uint value) external {
        // Check there is enough.
        if (stashAssetIdAccountValue[assetId][msg.sender] < value) revert StashNotBigEnough(msg.sender, assetId, value);
        // Remove the deposit.
        stashRemove(assetId, value);
        // Send the funds back.
        payable(msg.sender).transfer(value);
    }

    /**
     * @dev Withdraw all value from a stash.
     * @param assetId Asset the stash is to be sold for.
     */
    function withdrawStash(bytes16 assetId) external {
        uint value = stashAssetIdAccountValue[assetId][msg.sender];
        // Remove the deposit.
        stashRemove(assetId, value);
        // Send the funds back.
        payable(msg.sender).transfer(value);
    }

    /**
     * @dev Lock value.
     * @param recipient Account that can unlock the lock.
     * @param hashedSecret Hash of the secret.
     * @param timeout Timestamp when the lock will open.
     * @param sellAssetId assetId the value is paying for.
     * @param sellPrice Price the asset is being sold for.
     */
    function lockBuy(address recipient, bytes32 hashedSecret, uint256 timeout, bytes16 sellAssetId, uint256 sellPrice) payable external {
        // Ensure value is nonzero.
        if (msg.value == 0) revert ZeroValue();
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(msg.sender, recipient, hashedSecret, timeout));
        // Ensure lockId is not already in use.
        if (lockIdValue[lockId] != 0) revert LockAlreadyExists(lockId);
        // Move value into sell lock.
        lockIdValue[lockId] = msg.value;
        // Log info.
        emit BuyLock(msg.sender, recipient, hashedSecret, timeout, msg.value, lockId, sellAssetId, sellPrice);
    }

    /**
     * @dev Lock stashed value.
     * @param buyLockId The buy lock this lock is responding to.
     * @param recipient Account that can unlock the lock.
     * @param hashedSecret Hash of the secret.
     * @param timeout Timestamp when the lock will open.
     * @param stashAssetId Asset the stash is to be sold for.
     * @param value Value from the stash to lock.
     */
    function lockSell(address recipient, bytes32 hashedSecret, uint256 timeout, bytes16 stashAssetId, uint256 value, bytes32 buyLockId) external {
        // Ensure value is nonzero.
        if (value == 0) revert ZeroValue();
        // Check there is enough.
        if (stashAssetIdAccountValue[stashAssetId][msg.sender] < value) revert StashNotBigEnough(msg.sender, stashAssetId, value);
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(msg.sender, recipient, hashedSecret, timeout));
        // Ensure lockId is not already in use.
        if (lockIdValue[lockId] != 0) revert LockAlreadyExists(lockId);
        // Move value into sell lock.
        stashRemove(stashAssetId, value);
        lockIdValue[lockId] = value;
        // Log info.
        emit SellLock(msg.sender, recipient, hashedSecret, timeout, value, lockId, stashAssetId, buyLockId);
    }

    /**
     * @dev Transfer value from lock to receiver.
     * @param sender Sender of the value.
     * @param secret Secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function unlockValue(address sender, bytes32 secret, uint256 timeout) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(sender, msg.sender, keccak256(abi.encodePacked(secret)), timeout));
        // Check lock has not timed out.
        if (timeout <= block.timestamp) revert LockTimedOut(lockId);
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        payable(msg.sender).transfer(value);
        // Log info.
        emit Unlock(sender, msg.sender, lockId, secret);
    }

    /**
     * @dev Transfer value from lock back to sender's stash.
     * @param recipient Receiver of the value.
     * @param hashedSecret Hash of secret recipient unlock the value.
     * @param timeout Timeout of the lock.
     */
    function timeoutStash(address recipient, bytes32 hashedSecret, uint256 timeout, bytes16 stashAssetId) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(msg.sender, recipient, hashedSecret, timeout));
        // Check lock has timed out.
        if (timeout > block.timestamp) revert LockNotTimedOut(lockId);
        // Get lock value;
        uint256 value = lockIdValue[lockId];
        // Ensure lock has value
        if (lockIdValue[lockId] == 0) revert ZeroValue();
        // Delete lock.
        delete lockIdValue[lockId];
        // Return funds and delete lock.
        stashAdd(stashAssetId, value);
        // Log info.
        emit Timeout(msg.sender, recipient, lockId);
    }

    /**
     * @dev Transfer value from lock back to sender.
     * @param recipient Receiver of the value.
     * @param hashedSecret Hash of secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function timeoutValue(address recipient, bytes32 hashedSecret, uint256 timeout) external {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(msg.sender, recipient, hashedSecret, timeout));
        // Check lock has timed out.
        if (timeout > block.timestamp) revert LockNotTimedOut(lockId);
        // Get lock value;
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        payable(msg.sender).transfer(value);
        // Log info.
        emit Timeout(msg.sender, recipient, lockId);
    }

    /**
     * @dev Get a list of deposits for a specific asset.
     * @param assetId Asset the stash is to be sold for.
     * @param offset Number of deposits to skip from the start of the list.
     * @param limit Maximum number of deposits to return.
     */
    function getStashes(bytes16 assetId, uint offset, uint limit) view external returns (address[] memory accounts, uint[] memory values) {
        mapping (address => address) storage accountsLL = stashAssetIdAccountsLL[assetId];
        mapping (address => uint) storage accountValue = stashAssetIdAccountValue[assetId];
        // Find first account after offset.
        address start = address(0);
        while (offset > 0) {
          if (accountsLL[start] == address(0)) {
            break;
          }
          start = accountsLL[start];
          offset--;
        }
        // Count how many accounts to return.
        address account = start;
        uint _limit = 0;
        while (accountsLL[account] != address(0) && _limit < limit) {
            account = accountsLL[account];
            _limit++;
        }
        // Allocate the arrays.
        accounts = new address[](_limit);
        values = new uint[](_limit);
        // Populate the array.
        account = accountsLL[start];
        for (uint i = 0; i < _limit; i++) {
            accounts[i] = account;
            values[i] = accountValue[account];
            account = accountsLL[account];
        }
    }

    /**
     * @dev Get value held in a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param seller Owner of the stash.
     * @return value Value held in the stash.
     */
    function getStashValue(bytes16 assetId, address seller) view external returns (uint256 value) {
        value = stashAssetIdAccountValue[assetId][seller];
    }

    /**
     * @dev Get value locked.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param hashedSecret Hash of the secret required to unlock the value.
     * @param timeout Time after which sender can retrieve the value.
     * @return value Value held in the lock.
     */
    function getLockValue(address sender, address recipient, bytes32 hashedSecret, uint256 timeout) view external returns (uint256 value) {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(sender, recipient, hashedSecret, timeout));
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
