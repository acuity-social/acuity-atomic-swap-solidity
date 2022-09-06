// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.15;

import "./AcuityAccount.sol";

contract AcuityAtomicSwap {

    /**
     * @dev Address of AcuityAccount contract.
     */
    AcuityAccount public immutable acuityAccount;

    /**
     * @dev Mapping of assetId to linked list of accounts, starting with the largest.
     */
    mapping (bytes32 => mapping (address => address)) stashAssetIdAccountLL;

    /**
     * @dev Mapping of assetId to selling address to value.
     */
    mapping (bytes32 => mapping (address => uint)) stashAssetIdAccountValue;

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
    event StashAdd(address indexed account, bytes32 indexed assetId, uint256 value);

    /**
     * @dev Value has been removed from a stash.
     * @param account Account removing from a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param value How much value has been removed from the stash.
     */
    event StashRemove(address indexed account, bytes32 indexed assetId, uint256 value);

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
    event BuyLock(address indexed sender, address indexed recipient, bytes32 hashedSecret, uint256 timeout, uint256 value, bytes32 lockId, bytes32 sellAssetId, uint256 sellPrice);

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
    event SellLock(address indexed sender, address indexed recipient, bytes32 hashedSecret, uint256 timeout, uint256 value, bytes32 lockId, bytes32 buyAssetId, bytes32 buyLockId);

    /**
     * @dev Lock has been declined by the recipient.
     * @param sender Account that locked the value.
     * @param recipient Account to receive the value.
     * @param lockId Intrinisic lockId.
     */
    event DeclineByRecipient(address indexed sender, address indexed recipient, bytes32 lockId);

    /**
     * @dev Value has been unlocked by the sender.
     * @param sender Account that locked the value.
     * @param recipient Account that received the value.
     * @param lockId Intrinisic lockId.
     * @param secret The secret used to unlock the value.
     */
    event UnlockBySender(address indexed sender, address indexed recipient, bytes32 lockId, bytes32 secret);

    /**
     * @dev Value has been unlocked by the recipient.
     * @param sender Account that locked the value.
     * @param recipient Account that received the value.
     * @param lockId Intrinisic lockId.
     * @param secret The secret used to unlock the value.
     */
    event UnlockByRecipient(address indexed sender, address indexed recipient, bytes32 lockId, bytes32 secret);

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
    error StashNotBigEnough(address owner, bytes32 assetId, uint256 value);

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
     * @dev Invalid proxy account.
     * @param account Account being proxied.
     * @param proxyAccount Invalid proxy account.
     */
    error InvalidProxy(address account, address proxyAccount);

    /**
     * @dev Check if account is proxy for msg.sender
     * @param account Account to check.
     */
    modifier checkProxy(address account) {
        if (acuityAccount.getProxyAccount(account) != msg.sender) {
            revert InvalidProxy(account, msg.sender);
        }
        _;
    }

    /**
     * @param _acuityAccount Address of AcuityAccount contract.
     */
    constructor (AcuityAccount _acuityAccount) {
        acuityAccount = _acuityAccount;
    }

    /**
     * @dev Add value to stash be sold for a specific asset.
     * @param account Account to add stash for.
     * @param assetId Asset the stash is to be sold for.
     * @param value Size of deposit to add. Must be greater than 0.
     */
    function stashAdd(address account, bytes32 assetId, uint value)
        internal
    {
        mapping (address => address) storage accountLL = stashAssetIdAccountLL[assetId];
        mapping (address => uint) storage accountValue = stashAssetIdAccountValue[assetId];
        // Get new total.
        uint currentValue = accountValue[account];
        uint total = currentValue + value;
        // Search for new previous.
        address prev = address(0);
        address next = accountLL[prev];
        while (accountValue[next] >= total) {
            prev = next;
            next = accountLL[prev];
        }
        bool replace = false;
        // Is sender already in the list?
        if (currentValue > 0) {
            // Search for old previous.
            address oldPrev = prev;
            address oldNext = next;
            while (oldNext != account) {
                oldPrev = oldNext;
                oldNext = accountLL[oldPrev];
            }
            // Is it in the same position?
            if (prev == oldPrev) {
                replace = true;
            }
            else {
                // Remove sender from current position.
                accountLL[oldPrev] = accountLL[account];
            }
        }
        if (!replace) {
            // Insert into linked list.
            accountLL[account] = next;
            accountLL[prev] = account;
        }
        // Update the value deposited.
        accountValue[account] = total;
        // Log info.
        emit StashAdd(account, assetId, value);
    }

    /**
     * @dev Remove value from stash be sold for a specific asset.
     * @param account Account to add stash for.
     * @param assetId Asset the stash is to be sold for.
     * @param value Size of deposit to remove. Must be bigger than or equal to deposit value.
     */
    function stashRemove(address account, bytes32 assetId, uint value)
        internal
    {
        mapping (address => address) storage accountLL = stashAssetIdAccountLL[assetId];
        mapping (address => uint) storage accountValue = stashAssetIdAccountValue[assetId];
        // Get new total.
        uint total = accountValue[account] - value;
        // Search for old previous.
        address oldPrev = address(0);
        address oldNext = accountLL[oldPrev];
        while (oldNext != account) {
            oldPrev = oldNext;
            oldNext = accountLL[oldPrev];
        }
        // Is there still a stash?
        if (total > 0) {
            // Search for new previous.
            address prev = oldPrev;
            address next = oldNext;
            while (accountValue[next] >= total) {
                prev = next;
                next = accountLL[prev];
            }
            // Is it in a new position?
            if (prev != account) {
                // Remove sender from old position.
                accountLL[oldPrev] = accountLL[account];
                // Insert into new position.
                accountLL[account] = next;
                accountLL[prev] = account;
            }
        }
        else {
            // Remove sender from list.
            accountLL[oldPrev] = accountLL[account];
        }
        // Update the value deposited.
        accountValue[account] = total;
        // Log info.
        emit StashRemove(account, assetId, value);
    }

    /**
     * @dev Stash value to be sold for a specific asset.
     * @param assetId Asset the stash is to be sold for.
     */
    function depositStash(bytes32 assetId)
        external
        payable
    {
        // Ensure value is nonzero.
        if (msg.value == 0) revert ZeroValue();
        // Records the deposit.
        stashAdd(msg.sender, assetId, msg.value);
    }

    /**
     * @dev Move value from one stash to another.
     * @param assetIdFrom Asset the source stash is to be sold for.
     * @param assetIdTo Asset the destination stash is to be sold for.
     * @param value Value to move.
     */
    function moveStash(bytes32 assetIdFrom, bytes32 assetIdTo, uint value)
        external
    {
         // Check there is enough.
         if (stashAssetIdAccountValue[assetIdFrom][msg.sender] < value) revert StashNotBigEnough(msg.sender, assetIdFrom, value);
         // Move the deposit.
         stashRemove(msg.sender, assetIdFrom, value);
         stashAdd(msg.sender, assetIdTo, value);
     }

    /**
     * @dev Withdraw value from a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param value Value to withdraw.
     */
    function withdrawStash(bytes32 assetId, uint value)
        external
    {
        // Check there is enough.
        if (stashAssetIdAccountValue[assetId][msg.sender] < value) revert StashNotBigEnough(msg.sender, assetId, value);
        // Remove the deposit.
        stashRemove(msg.sender, assetId, value);
        // Send the funds back.
        payable(msg.sender).transfer(value);
    }

    /**
     * @dev Withdraw all value from a stash.
     * @param assetId Asset the stash is to be sold for.
     */
    function withdrawStash(bytes32 assetId)
        external
    {
        uint value = stashAssetIdAccountValue[assetId][msg.sender];
        // Remove the deposit.
        stashRemove(msg.sender, assetId, value);
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
    function lockBuy(address recipient, bytes32 hashedSecret, uint256 timeout, bytes32 sellAssetId, uint256 sellPrice)
        external
        payable
    {
        // Ensure value is nonzero.
        if (msg.value == 0) revert ZeroValue();
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(msg.sender, recipient, hashedSecret, timeout));
        // Ensure lockId is not already in use.
        if (lockIdValue[lockId] != 0) revert LockAlreadyExists(lockId);
        // Move value into buy lock.
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
    function lockSell(address recipient, bytes32 hashedSecret, uint256 timeout, bytes32 stashAssetId, uint256 value, bytes32 buyLockId)
        external
    {
        // Ensure value is nonzero.
        if (value == 0) revert ZeroValue();
        // Check there is enough.
        if (stashAssetIdAccountValue[stashAssetId][msg.sender] < value) revert StashNotBigEnough(msg.sender, stashAssetId, value);
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(msg.sender, recipient, hashedSecret, timeout));
        // Ensure lockId is not already in use.
        if (lockIdValue[lockId] != 0) revert LockAlreadyExists(lockId);
        // Move value into sell lock.
        stashRemove(msg.sender, stashAssetId, value);
        lockIdValue[lockId] = value;
        // Log info.
        emit SellLock(msg.sender, recipient, hashedSecret, timeout, value, lockId, stashAssetId, buyLockId);
    }

    /**
     * @dev Lock stashed value.
     * @param buyLockId The buy lock this lock is responding to.
     * @param sender Sender of the value (checked for proxy).
     * @param recipient Account that can unlock the lock.
     * @param hashedSecret Hash of the secret.
     * @param timeout Timestamp when the lock will open.
     * @param stashAssetId Asset the stash is to be sold for.
     * @param value Value from the stash to lock.
     */
    function lockSellProxy(address sender, address recipient, bytes32 hashedSecret, uint256 timeout, bytes32 stashAssetId, uint256 value, bytes32 buyLockId)
        external
        checkProxy(sender)
    {
        // Ensure value is nonzero.
        if (value == 0) revert ZeroValue();
        // Check there is enough.
        if (stashAssetIdAccountValue[stashAssetId][sender] < value) revert StashNotBigEnough(sender, stashAssetId, value);
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(sender, recipient, hashedSecret, timeout));
        // Ensure lockId is not already in use.
        if (lockIdValue[lockId] != 0) revert LockAlreadyExists(lockId);
        // Move value into sell lock.
        stashRemove(sender, stashAssetId, value);
        lockIdValue[lockId] = value;
        // Log info.
        emit SellLock(sender, recipient, hashedSecret, timeout, value, lockId, stashAssetId, buyLockId);
    }

    /**
     * @dev Transfer value back to the sender (called by recipient).
     * @param sender Sender of the value.
     * @param hashedSecret Hash of the secret.
     * @param timeout Timeout of the lock.
     */
    function declineByRecipient(address sender, bytes32 hashedSecret, uint256 timeout)
        external
    {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(sender, msg.sender, hashedSecret, timeout));
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value back to the sender.
        payable(sender).transfer(value);
        // Log info.
        emit DeclineByRecipient(sender, msg.sender, lockId);
    }

    /**
     * @dev Transfer value from lock to recipient (called by sender).
     * @param recipient Recipient of the value.
     * @param secret Secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function unlockBySender(address recipient, bytes32 secret, uint256 timeout)
        external
    {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(msg.sender, recipient, keccak256(abi.encodePacked(secret)), timeout));
        // Check lock has not timed out.
        if (timeout <= block.timestamp) revert LockTimedOut(lockId);
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        payable(recipient).transfer(value);
        // Log info.
        emit UnlockBySender(msg.sender, recipient, lockId, secret);
    }

    /**
     * @dev Transfer value from lock to recipient (called by recipient).
     * @param sender Sender of the value.
     * @param secret Secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function unlockByRecipient(address sender, bytes32 secret, uint256 timeout)
        external
    {
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
        emit UnlockByRecipient(sender, msg.sender, lockId, secret);
    }

    /**
     * @dev Transfer value from lock to recipient (called by recipient).
     * @param sender Sender of the value.
     * @param recipient Receiver of the value (checked for proxy).
     * @param secret Secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function unlockByRecipientProxy(address sender, address recipient, bytes32 secret, uint256 timeout)
        external
        checkProxy(recipient)
    {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(sender, recipient, keccak256(abi.encodePacked(secret)), timeout));
        // Check lock has not timed out.
        if (timeout <= block.timestamp) revert LockTimedOut(lockId);
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        payable(recipient).transfer(value);
        // Log info.
        emit UnlockByRecipient(sender, recipient, lockId, secret);
    }

    /**
     * @dev Transfer value from lock back to sender's stash.
     * @param recipient Recipient of the value.
     * @param hashedSecret Hash of secret recipient unlock the value.
     * @param timeout Timeout of the lock.
     */
    function timeoutStash(address recipient, bytes32 hashedSecret, uint256 timeout, bytes32 stashAssetId)
        external
    {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(msg.sender, recipient, hashedSecret, timeout));
        // Check lock has timed out.
        if (timeout > block.timestamp) revert LockNotTimedOut(lockId);
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Ensure lock has value
        if (value == 0) revert ZeroValue();
        // Delete lock.
        delete lockIdValue[lockId];
        // Return funds.
        stashAdd(msg.sender, stashAssetId, value);
        // Log info.
        emit Timeout(msg.sender, recipient, lockId);
    }

    /**
     * @dev Transfer value from lock back to sender's stash.
     * @param sender Sender of the value (checked for proxy).
     * @param recipient Recipient of the value.
     * @param hashedSecret Hash of secret recipient unlock the value.
     * @param timeout Timeout of the lock.
     */
    function timeoutStashProxy(address sender, address recipient, bytes32 hashedSecret, uint256 timeout, bytes32 stashAssetId)
        external
        checkProxy(sender)
    {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(sender, recipient, hashedSecret, timeout));
        // Check lock has timed out.
        if (timeout > block.timestamp) revert LockNotTimedOut(lockId);
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Ensure lock has value
        if (value == 0) revert ZeroValue();
        // Delete lock.
        delete lockIdValue[lockId];
        // Return funds.
        stashAdd(sender, stashAssetId, value);
        // Log info.
        emit Timeout(sender, recipient, lockId);
    }

    /**
     * @dev Transfer value from lock back to sender.
     * @param recipient Recipient of the value.
     * @param hashedSecret Hash of secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function timeoutValue(address recipient, bytes32 hashedSecret, uint256 timeout)
        external
    {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(msg.sender, recipient, hashedSecret, timeout));
        // Check lock has timed out.
        if (timeout > block.timestamp) revert LockNotTimedOut(lockId);
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        payable(msg.sender).transfer(value);
        // Log info.
        emit Timeout(msg.sender, recipient, lockId);
    }

    /**
     * @dev Transfer value from lock back to sender.
     * @param sender Sender of the value (checked for proxy).
     * @param recipient Recipient of the value.
     * @param hashedSecret Hash of secret to unlock the value.
     * @param timeout Timeout of the lock.
     */
    function timeoutValueProxy(address sender, address recipient, bytes32 hashedSecret, uint256 timeout)
        external
        checkProxy(sender)
    {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(sender, recipient, hashedSecret, timeout));
        // Check lock has timed out.
        if (timeout > block.timestamp) revert LockNotTimedOut(lockId);
        // Get lock value.
        uint256 value = lockIdValue[lockId];
        // Delete lock.
        delete lockIdValue[lockId];
        // Transfer the value.
        payable(sender).transfer(value);
        // Log info.
        emit Timeout(sender, recipient, lockId);
    }

    /**
     * @dev Get a list of deposits for a specific asset.
     * @param assetId Asset the stash is to be sold for.
     * @param offset Number of deposits to skip from the start of the list.
     * @param limit Maximum number of deposits to return.
     */
    function getStashes(bytes32 assetId, uint offset, uint limit)
        external
        view
        returns (address[] memory accounts, uint[] memory values)
    {
        mapping (address => address) storage accountLL = stashAssetIdAccountLL[assetId];
        mapping (address => uint) storage accountValue = stashAssetIdAccountValue[assetId];
        // Find first account after offset.
        address account = address(0);
        address next = accountLL[account];
        while (offset > 0) {
            if (next == address(0)) {
                break;
            }
            account = next;
            next = accountLL[account];
            --offset;
        }
        // Count how many accounts to return.
        uint _limit = 0;
        while (next != address(0) && _limit < limit) {
            next = accountLL[next];
            ++_limit;
        }
        // Allocate the arrays.
        accounts = new address[](_limit);
        values = new uint[](_limit);
        // Populate the arrays.
        for (uint i = 0; i < _limit; ++i) {
            account = accountLL[account];
            accounts[i] = account;
            values[i] = accountValue[account];
        }
    }

    /**
     * @dev Get value held in a stash.
     * @param assetId Asset the stash is to be sold for.
     * @param seller Owner of the stash.
     * @return value Value held in the stash.
     */
    function getStashValue(bytes32 assetId, address seller)
        external
        view
        returns (uint256 value)
    {
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
    function getLockValue(address sender, address recipient, bytes32 hashedSecret, uint256 timeout)
        external
        view
        returns (uint256 value)
    {
        // Calculate lockId.
        bytes32 lockId = keccak256(abi.encode(sender, recipient, hashedSecret, timeout));
        value = lockIdValue[lockId];
    }

    /**
     * @dev Get value locked.
     * @param lockId Lock to examine.
     * @return value Value held in the lock.
     */
    function getLockValue(bytes32 lockId)
        external
        view
        returns (uint256 value)
    {
        value = lockIdValue[lockId];
    }

}
