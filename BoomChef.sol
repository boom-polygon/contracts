// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BoomBar.sol";
import "./Boom.sol";

// boom.trading
// An updated version of PancakeSwap's MasterChef V1
contract BoomChef is Ownable {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastWithdrawBlock;
        uint256 lastDepositBlock;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. BOOMs to distribute per block.
        uint256 lastRewardTimestamp; // Last block number that BOOMs distribution occurs.
        uint256 accBoomPerShare; // Accumulated BOOMs per share, times 1e12. See below.
    }

    // The BOOM TOKEN!
    Boom public boom;
    // Dev address.
    address public devaddr;
    uint256 public boomPerSec;
    // Bonus muliplier for early cake makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when CAKE mining starts.
    uint256 public startTimestamp = block.timestamp;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(Boom _boom, address _devaddr) public Ownable(msg.sender) {
        boom = _boom;
        devaddr = _devaddr;
    }

    function setBoomPerSec(uint256 _boomPerSec) public onlyOwner {
        boomPerSec = _boomPerSec;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp
            ? block.timestamp
            : startTimestamp;
        totalAllocPoint = totalAllocPoint + (_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accBoomPerShare: 0
            })
        );
        updateStakingPool();
    }

    // Update the given pool's BOOM allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint =
                totalAllocPoint -
                (prevAllocPoint) +
                (_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points + (poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points / (3);
            totalAllocPoint =
                totalAllocPoint -
                (poolInfo[0].allocPoint) +
                (points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        return _to - (_from) * (BONUS_MULTIPLIER);
    }

    // View function to see pending BOOMs on frontend.
    function pendingBoom(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBoomPerShare = pool.accBoomPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTimestamp,
                block.timestamp
            );

            uint256 boomReward = ((multiplier * boomPerSec) *
                (pool.allocPoint)) / (totalAllocPoint);

            accBoomPerShare =
                accBoomPerShare +
                ((boomReward * (1e12)) / (lpSupply));
        }
        return ((user.amount * (accBoomPerShare)) / (1e12)) - (user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(
            pool.lastRewardTimestamp,
            block.timestamp
        );
        uint256 boomReward = ((multiplier * boomPerSec) * (pool.allocPoint)) /
            totalAllocPoint;

        pool.accBoomPerShare =
            pool.accBoomPerShare +
            ((boomReward * (1e12)) / (lpSupply));
        pool.lastRewardTimestamp = block.timestamp;
    }

    // Deposit LP tokens to BoomChef for BOOM allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        require(_amount > 0, "deposit: Must deposit some LP");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        if (user.lastDepositBlock > 0) {
            require(
                user.lastDepositBlock < block.number,
                "deposit: you're depositing too fast"
            );
        }
        user.lastDepositBlock = block.number;
        if (user.amount > 0) {
            uint256 pending = (user.amount * (pool.accBoomPerShare)) /
                (1e12) -
                (user.rewardDebt);
            if (pending > 0) {
                safeBoomTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount + (_amount);
        }
        user.rewardDebt = (user.amount * (pool.accBoomPerShare)) / (1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from BoomChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        require(_amount > 0, "withdraw: must withdraw some LP");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);

        if (user.lastWithdrawBlock > 0) {
            require(
                user.lastWithdrawBlock < block.number,
                "withdraw: you're withdrawing too fast"
            );
        }
        user.lastDepositBlock = block.number;
        uint256 pending = (user.amount * (pool.accBoomPerShare)) /
            (1e12) -
            (user.rewardDebt);
        if (pending > 0 ether) {
            safeBoomTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount - (_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = (user.amount * (pool.accBoomPerShare)) / (1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function safeBoomTransfer(address _to, uint256 _amount) internal {
        uint256 contractBalance = boom.balanceOf(address(this));
        if (_amount > contractBalance) {
            boom.transfer(_to, contractBalance);
        } else {
            boom.transfer(_to, _amount);
        }
    }

    // Admin emergency use only.
    function adminWithdrawRewards() public {
        require(msg.sender == devaddr, "adminWithdrawRewards: no");
        boom.transfer(devaddr, boom.balanceOf(address(this)));
    }
}
