// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../lib/SafeERC20.sol";

import "./interfaces/IPlatypusVoter.sol";
import "./interfaces/IMasterPlatypus.sol";
import "./interfaces/IBaseMasterPlatypus.sol";
import "./interfaces/IPlatypusPool.sol";
import "./interfaces/IPlatypusAsset.sol";
import "./interfaces/IPlatypusNFT.sol";
import "./interfaces/IVePTP.sol";
import "./interfaces/IPlatypusStrategy.sol";
import "./interfaces/IPlatypusVoterProxy.sol";
import "./interfaces/IVotingGauge.sol";
import "./interfaces/IBribe.sol";

library SafeProxy {
    function safeExecute(
        IPlatypusVoter platypusVoter,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnValue) = platypusVoter.execute(target, value, data);
        if (!success) revert("PlatypusVoterProxy::safeExecute failed");
        return returnValue;
    }
}

/**
 * @notice PlatypusVoterProxy is an upgradable contract.
 * Strategies interact with PlatypusVoterProxy and
 * PlatypusVoterProxy interacts with PlatypusVoter.
 * @dev For accounting reasons, there is one approved
 * strategy per Masterchef PID. In case of upgrade,
 * use a new proxy.
 */
contract PlatypusVoterProxy is IPlatypusVoterProxy {
    using SafeProxy for IPlatypusVoter;
    using SafeERC20 for IERC20;

    struct FeeSettings {
        uint256 stakerFeeBips;
        uint256 boosterFeeBips;
        address stakerFeeReceiver;
        address boosterFeeReceiver;
    }

    struct Reward {
        address reward;
        uint256 amount;
    }

    uint256 internal constant BIPS_DIVISOR = 10000;
    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    uint256 public boosterFee;
    uint256 public stakerFee;
    address public stakerFeeReceiver;
    address public boosterFeeReceiver;
    address public constant PTP = 0x22d4002028f537599bE9f666d1c4Fa138522f9c8;
    address public constant PLATYPUS_NFT = 0x6A04a578247e15e3c038AcF2686CA00A624a5aa0;
    IVePTP public constant vePTP = IVePTP(0x5857019c749147EEE22b1Fe63500F237F3c1B692);

    IPlatypusVoter public immutable override platypusVoter;
    address public devAddr;
    address public gaugeVoter;
    IVotingGauge public votingGauge;
    uint256 public maxSupportedMasterPlatypusVersion;

    // strategy => masterchef
    mapping(address => address) public stakingContract;
    // staking contract => pid => strategy
    mapping(address => mapping(uint256 => address)) public approvedStrategies;

    // factory pools masterchef
    address private constant BASE_MASTER_PLATYPUS = 0x2Cd5012b5f7cc09bfE0De6C44df32a92D2431232;

    modifier onlyDev() {
        require(msg.sender == devAddr, "PlatypusVoterProxy::onlyDev");
        _;
    }

    constructor(
        address _platypusVoter,
        address _devAddr,
        address _gaugeVoter,
        address _votingGauge,
        uint256 _maxSupportedMasterPlatypusVersion,
        FeeSettings memory _feeSettings
    ) {
        devAddr = _devAddr;
        gaugeVoter = _gaugeVoter;
        votingGauge = IVotingGauge(_votingGauge);
        boosterFee = _feeSettings.boosterFeeBips;
        stakerFee = _feeSettings.stakerFeeBips;
        stakerFeeReceiver = _feeSettings.stakerFeeReceiver;
        boosterFeeReceiver = _feeSettings.boosterFeeReceiver;
        maxSupportedMasterPlatypusVersion = _maxSupportedMasterPlatypusVersion;
        platypusVoter = IPlatypusVoter(_platypusVoter);
    }

    /**
     * @notice Update devAddr
     * @param newValue address
     */
    function updateDevAddr(address newValue) external onlyDev {
        devAddr = newValue;
    }

    /**
     * @notice Update maxSupportedMasterPlatypusVersion
     * @param newValue uint
     */
    function updateMaxSupportedMasterPlatypusVersion(uint256 newValue) external onlyDev {
        maxSupportedMasterPlatypusVersion = newValue;
    }

    /**
     * @notice Update gaugeVoter
     * @param newValue address
     */
    function updateGaugeVoter(address newValue) external onlyDev {
        gaugeVoter = newValue;
    }

    /**
     * @notice Update votingGauge
     * @param newValue address
     */
    function updateVotingGauge(address newValue) external onlyDev {
        votingGauge = IVotingGauge(newValue);
    }

    /**
     * @notice Add an approved strategy
     * @dev Very sensitive, restricted to devAddr
     * @dev Can only be set once per PID and staking contract (reported by the strategy)
     * @param _stakingContract address
     * @param _strategy address
     */
    function approveStrategy(address _stakingContract, address _strategy) public override onlyDev {
        uint256 pid = IPlatypusStrategy(_strategy).PID();
        require(
            approvedStrategies[_stakingContract][pid] == address(0),
            "PlatypusVoterProxy::Strategy for PID already added"
        );

        approvedStrategies[_stakingContract][pid] = _strategy;
        stakingContract[_strategy] = _stakingContract;
    }

    function migrateStrategy(address _strategy, address _from) external onlyDev {
        uint256 pid = IPlatypusStrategy(_strategy).PID();
        require(approvedStrategies[_from][pid] == _strategy, "PlatypusVoterProxy::Unknown strategy");

        address currentMasterPlatypus = stakingContract[_strategy];
        address newMasterPlatypus = IMasterPlatypus(currentMasterPlatypus).newMasterPlatypus();
        require(
            approvedStrategies[newMasterPlatypus][pid] == address(0),
            "PlatypusVoterProxy::Strategy for PID already added"
        );
        require(
            IMasterPlatypus(newMasterPlatypus).version() <= maxSupportedMasterPlatypusVersion,
            "PlatypusVoterProxy::New Version not supported"
        );

        uint256[] memory pids = new uint256[](1);
        pids[0] = pid;

        platypusVoter.safeExecute(currentMasterPlatypus, 0, abi.encodeWithSignature("migrate(uint256[])", pids));

        approvedStrategies[_from][pid] = address(0);
        approveStrategy(newMasterPlatypus, _strategy);
    }

    /**
     * @notice Update booster fee
     * @dev Restricted to devAddr
     * @param _boosterFeeBips new fee in bips (1% = 100 bips)
     */
    function setBoosterFee(uint256 _boosterFeeBips) external onlyDev {
        boosterFee = _boosterFeeBips;
    }

    /**
     * @notice Update staker fee
     * @dev Restricted to devAddr
     * @param _stakerFeeBips new fee in bips (1% = 100 bips)
     */
    function setStakerFee(uint256 _stakerFeeBips) external onlyDev {
        stakerFee = _stakerFeeBips;
    }

    /**
     * @notice Update booster fee receiver
     * @dev Restricted to devAddr
     * @param _boosterFeeReceiver address
     */
    function setBoosterFeeReceiver(address _boosterFeeReceiver) external onlyDev {
        boosterFeeReceiver = _boosterFeeReceiver;
    }

    /**
     * @notice Update staker fee receiver
     * @dev Restricted to devAddr
     * @param _stakerFeeReceiver address
     */
    function setStakerFeeReceiver(address _stakerFeeReceiver) external onlyDev {
        stakerFeeReceiver = _stakerFeeReceiver;
    }

    /**
     * @notice Stake NFT
     * @dev Restricted to devAddr.
     * @dev The currently staked NFT will be automatically unstaked and remain on voter. Use "sweepNFT" to get it back.
     * @param id id of the NFT to be staked
     */
    function stakeNFT(uint256 id) external onlyDev {
        if (IERC721(PLATYPUS_NFT).ownerOf(id) != address(platypusVoter)) {
            IERC721(PLATYPUS_NFT).transferFrom(msg.sender, address(platypusVoter), id);
        }

        platypusVoter.safeExecute(
            PLATYPUS_NFT,
            0,
            abi.encodeWithSignature("approve(address,uint256)", address(vePTP), id)
        );
        platypusVoter.safeExecute(address(vePTP), 0, abi.encodeWithSignature("stakeNft(uint256)", id));
    }

    /**
     * @notice Unstake the currently staked NFT
     * @dev Restricted to devAddr.
     * @dev The unstaked NFT will remain on voter. Use "sweepNFT" to get it back.
     */
    function unstakeNFT() external onlyDev {
        platypusVoter.safeExecute(address(vePTP), 0, abi.encodeWithSignature("unstakeNft()"));
    }

    /**
     * @notice Sweep NFT
     * @dev Restricted to devAddr.
     * @param id id of the NFT to be swept
     */
    function sweepNFT(uint256 id) public onlyDev {
        platypusVoter.safeExecute(
            PLATYPUS_NFT,
            0,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(platypusVoter), msg.sender, id)
        );
    }

    /**
     * @notice Deposit function
     * @dev Restricted to strategy with _pid
     * @param _pid PID
     * @param
     * @param _pool Platypus pool
     * @param _token Deposit asset
     * @param _asset Platypus asset
     * @param _amount deposit amount
     * @param _depositFee deposit fee
     */
    function deposit(
        uint256 _pid,
        address, /*_stakingContract*/
        address _pool,
        address _token,
        address _asset,
        uint256 _amount,
        uint256 _depositFee
    ) external override {
        address masterchef = stakingContract[msg.sender];
        require(approvedStrategies[masterchef][_pid] == msg.sender, "PlatypusVoterProxy::onlyStrategy");

        uint256 liquidity = _depositTokenToAsset(_asset, _amount, _depositFee);
        IERC20(_token).safeApprove(_pool, _amount);
        IPlatypusPool(_pool).deposit(address(_token), _amount, address(platypusVoter), type(uint256).max);
        platypusVoter.safeExecute(
            _asset,
            0,
            abi.encodeWithSignature("approve(address,uint256)", masterchef, liquidity)
        );
        platypusVoter.safeExecute(masterchef, 0, abi.encodeWithSignature("deposit(uint256,uint256)", _pid, liquidity));
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", masterchef, 0));
    }

    /**
     * @notice Conversion for deposit token to Platypus asset
     * @return liquidity amount of LP tokens
     */
    function _depositTokenToAsset(
        address _asset,
        uint256 _amount,
        uint256 _depositFee
    ) private view returns (uint256 liquidity) {
        if (IPlatypusAsset(_asset).liability() == 0) {
            liquidity = _amount - _depositFee;
        } else {
            liquidity =
                ((_amount - _depositFee) * IPlatypusAsset(_asset).totalSupply()) /
                IPlatypusAsset(_asset).liability();
        }
    }

    /**
     * @notice Calculation of reinvest fee (boost + staking)
     * @return reinvest fee
     */
    function reinvestFeeBips() public view override returns (uint256) {
        uint256 boostFee = 0;
        if (boosterFee > 0 && boosterFeeReceiver > address(0) && platypusVoter.depositsEnabled()) {
            boostFee = boosterFee;
        }

        uint256 stakingFee = 0;
        if (stakerFee > 0 && stakerFeeReceiver > address(0)) {
            stakingFee = stakerFee;
        }
        return boostFee + stakingFee;
    }

    /**
     * @notice Calculation of withdraw fee
     * @param _pool Platypus pool
     * @param _token Withdraw token
     * @param _amount Withdraw amount, in _token
     * @return fee Withdraw fee
     */
    function _calculateWithdrawFee(
        address _pool,
        address _token,
        uint256 _amount
    ) private view returns (uint256 fee) {
        (, fee, ) = IPlatypusPool(_pool).quotePotentialWithdraw(_token, _amount);
    }

    /**
     * @notice Conversion for handling withdraw
     * @param _pid PID
     * @param _stakingContract Platypus Masterchef
     * @param _amount withdraw amount in deposit asset
     * @return liquidity LP tokens
     */
    function _depositTokenToAssetForWithdrawal(
        uint256 _pid,
        address _stakingContract,
        uint256 _amount
    ) private view returns (uint256) {
        uint256 totalDeposits = _poolBalance(_stakingContract, _pid);
        uint256 assetBalance = getAssetBalance(_stakingContract, _pid);
        return (_amount * assetBalance) / totalDeposits;
    }

    /**
     * @notice Withdraw function
     * @dev Restricted to strategy with _pid
     * @param _pid PID
     * @param
     * @param _pool Platypus pool
     * @param _token Deposit asset
     * @param _asset Platypus asset
     * @param _maxSlippage max slippage in bips
     * @param _amount withdraw amount
     * @return amount withdrawn, in _token
     */
    function withdraw(
        uint256 _pid,
        address, /*_stakingContract*/
        address _pool,
        address _token,
        address _asset,
        uint256 _maxSlippage,
        uint256 _amount
    ) external override returns (uint256) {
        address masterchef = stakingContract[msg.sender];
        require(approvedStrategies[masterchef][_pid] == msg.sender, "PlatypusVoterProxy::onlyStrategy");

        uint256 liquidity = _depositTokenToAssetForWithdrawal(_pid, masterchef, _amount);
        platypusVoter.safeExecute(masterchef, 0, abi.encodeWithSignature("withdraw(uint256,uint256)", _pid, liquidity));
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", _pool, liquidity));
        uint256 minimumReceive = liquidity - _calculateWithdrawFee(_pool, _token, liquidity);
        uint256 slippage = (minimumReceive * _maxSlippage) / BIPS_DIVISOR;
        minimumReceive = minimumReceive - slippage;
        bytes memory result = platypusVoter.safeExecute(
            _pool,
            0,
            abi.encodeWithSignature(
                "withdraw(address,uint256,uint256,address,uint256)",
                _token,
                liquidity,
                minimumReceive,
                address(this),
                type(uint256).max
            )
        );
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", _pool, 0));
        uint256 amount = toUint256(result, 0);
        IERC20(_token).safeTransfer(msg.sender, amount);

        return amount;
    }

    /**
     * @notice Emergency withdraw function
     * @dev Restricted to strategy with _pid
     * @param _pid PID
     * @param
     * @param _pool Platypus pool
     * @param _token Deposit asset
     * @param _asset Platypus asset
     */
    function emergencyWithdraw(
        uint256 _pid,
        address, /*_stakingContract*/
        address _pool,
        address _token,
        address _asset
    ) external override {
        address masterchef = stakingContract[msg.sender];
        require(approvedStrategies[masterchef][_pid] == msg.sender, "PlatypusVoterProxy::onlyStrategy");

        platypusVoter.safeExecute(masterchef, 0, abi.encodeWithSignature("emergencyWithdraw(uint256)", _pid));
        uint256 balance = IERC20(_asset).balanceOf(address(platypusVoter));
        (uint256 expectedAmount, , ) = IPlatypusPool(_pool).quotePotentialWithdraw(_token, balance);
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", _pool, balance));
        platypusVoter.safeExecute(
            _pool,
            0,
            abi.encodeWithSignature(
                "withdraw(address,uint256,uint256,address,uint256)",
                _token,
                balance,
                expectedAmount,
                msg.sender,
                type(uint256).max
            )
        );
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", masterchef, 0));
        platypusVoter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _pool, 0));
    }

    /**
     * @notice Pending rewards matching interface for PlatypusStrategy
     * @param
     * @param _pid PID
     * @return pendingPtp
     * @return pendingBonusToken
     * @return bonusTokenAddress
     */
    function pendingRewards(
        address, /*_stakingContract*/
        uint256 _pid
    )
        external
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        address masterchef = stakingContract[msg.sender];
        (
            uint256 pendingPtp,
            address[] memory bonusTokenAddresses,
            ,
            uint256[] memory pendingBonusTokens
        ) = IMasterPlatypus(masterchef).pendingTokens(_pid, address(platypusVoter));

        uint256 bonusTokens = pendingBonusTokens.length > 0 ? pendingBonusTokens[0] : 0;
        address bonusTokenAddress = bonusTokenAddresses.length > 0 ? bonusTokenAddresses[0] : address(0);

        return (pendingPtp, bonusTokens, bonusTokenAddress);
    }

    function pendingRewards(uint256 _pid) external view returns (Reward[] memory) {
        address masterchef = stakingContract[msg.sender];
        (
            uint256 pendingPtp,
            address[] memory bonusTokenAddresses,
            ,
            uint256[] memory pendingBonusTokens
        ) = IMasterPlatypus(masterchef).pendingTokens(_pid, address(platypusVoter));

        uint256 feeBips = reinvestFeeBips();
        uint256 boostFee = (pendingPtp * feeBips) / BIPS_DIVISOR;

        Reward[] memory rewards = new Reward[](bonusTokenAddresses.length + 1);
        rewards[0] = Reward({reward: address(PTP), amount: pendingPtp - boostFee});
        for (uint256 i = 0; i < bonusTokenAddresses.length; i++) {
            rewards[i + 1] = Reward({reward: bonusTokenAddresses[i], amount: pendingBonusTokens[i]});
        }
        return rewards;
    }

    /**
     * @notice Pool balance
     * @param
     * @param _pid PID
     * @return balance in depositToken
     */
    function poolBalance(
        address, /*_stakingContract*/
        uint256 _pid
    ) external view override returns (uint256 balance) {
        address masterchef = stakingContract[msg.sender];
        return _poolBalance(masterchef, _pid);
    }

    function _poolBalance(address _stakingContract, uint256 _pid) internal view returns (uint256 balance) {
        uint256 assetBalance = getAssetBalance(_stakingContract, _pid);
        if (assetBalance > 0) {
            address asset = getAsset(_stakingContract, _pid);

            IPlatypusPool pool = IPlatypusPool(IPlatypusAsset(asset).pool());
            (uint256 expectedAmount, uint256 fee, bool enoughCash) = pool.quotePotentialWithdraw(
                IPlatypusAsset(asset).underlyingToken(),
                assetBalance
            );
            require(enoughCash, "PlatypusVoterProxy::This shouldn't happen");
            return expectedAmount + fee;
        }
        return 0;
    }

    function getAssetBalance(address _stakingContract, uint256 _pid) private view returns (uint256 assetBalance) {
        if (_stakingContract == BASE_MASTER_PLATYPUS) {
            (assetBalance, ) = IBaseMasterPlatypus(_stakingContract).userInfo(_pid, address(platypusVoter));
        } else {
            (assetBalance, , ) = IMasterPlatypus(_stakingContract).userInfo(_pid, address(platypusVoter));
        }
    }

    function getAsset(address _stakingContract, uint256 _pid) private view returns (address asset) {
        if (_stakingContract == BASE_MASTER_PLATYPUS) {
            (asset, , ) = IBaseMasterPlatypus(_stakingContract).poolInfo(_pid);
        } else {
            (asset, , , , ) = IMasterPlatypus(_stakingContract).poolInfo(_pid);
        }
    }

    /**
     * @notice Claim and distribute PTP rewards
     * @dev Restricted to strategy with _pid
     * @param
     * @param _pid PID
     */
    function claimReward(
        address, /*_stakingContract*/
        uint256 _pid
    ) external override {
        address masterchef = stakingContract[msg.sender];
        require(approvedStrategies[masterchef][_pid] == msg.sender, "PlatypusVoterProxy::onlyStrategy");

        platypusVoter.safeExecute(masterchef, 0, abi.encodeWithSignature("deposit(uint256,uint256)", _pid, 0));

        uint256 pendingPtp = IERC20(PTP).balanceOf(address(platypusVoter));
        if (pendingPtp > 0) {
            uint256 boostFee = 0;
            if (boosterFee > 0 && boosterFeeReceiver > address(0) && platypusVoter.depositsEnabled()) {
                boostFee = (pendingPtp * boosterFee) / BIPS_DIVISOR;
                platypusVoter.depositFromBalance(boostFee);
                IERC20(address(platypusVoter)).safeTransfer(boosterFeeReceiver, boostFee);
            }

            uint256 stakingFee = 0;
            if (stakerFee > 0 && stakerFeeReceiver > address(0)) {
                stakingFee = (pendingPtp * stakerFee) / BIPS_DIVISOR;
                platypusVoter.safeExecute(
                    PTP,
                    0,
                    abi.encodeWithSignature("transfer(address,uint256)", stakerFeeReceiver, stakingFee)
                );
            }

            uint256 reward = pendingPtp - boostFee - stakingFee;
            platypusVoter.safeExecute(PTP, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));
        }

        (address[] memory bonusTokenAddresses, ) = IMasterPlatypus(masterchef).rewarderBonusTokenInfo(_pid);

        for (uint256 i = 0; i < bonusTokenAddresses.length; i++) {
            if (bonusTokenAddresses[i] == WAVAX) {
                platypusVoter.wrapAvaxBalance();
            }
            uint256 pendingBonusToken = IERC20(bonusTokenAddresses[i]).balanceOf(address(platypusVoter));
            platypusVoter.safeExecute(
                bonusTokenAddresses[i],
                0,
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, pendingBonusToken)
            );
        }

        if (platypusVoter.vePTPBalance() > 0) {
            platypusVoter.claimVePTP();
        }
    }

    function toUint256(bytes memory _bytes, uint256 _start) internal pure returns (uint256) {
        require(_bytes.length >= _start + 32, "toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function vote(
        address[] memory _lpVote,
        int256[] memory _deltas,
        address _bribeReceiver
    ) external returns (Reward[] memory claimedBribes) {
        address voter = gaugeVoter;
        require(msg.sender == voter, "PlatypusVoterProxy::Unauthorized");

        IVotingGauge gauge = votingGauge;
        platypusVoter.safeExecute(
            address(gauge),
            0,
            abi.encodeWithSignature("vote(address[],int256[])", _lpVote, _deltas)
        );

        _bribeReceiver = _bribeReceiver > address(0) ? _bribeReceiver : voter;
        claimedBribes = new Reward[](_lpVote.length);
        for (uint256 i = 0; i < _lpVote.length; i++) {
            IBribe bribe = IBribe(gauge.bribes(_lpVote[i]));
            address rewardToken = bribe.rewardToken();
            uint256 claimedAmount = IERC20(rewardToken).balanceOf(address(platypusVoter));
            if (claimedAmount > 0) {
                platypusVoter.safeExecute(
                    rewardToken,
                    0,
                    abi.encodeWithSignature("transfer(address,uint256)", _bribeReceiver, claimedAmount)
                );
            }
            Reward memory reward = Reward({reward: rewardToken, amount: claimedAmount});
            claimedBribes[i] = reward;
        }
    }
}
