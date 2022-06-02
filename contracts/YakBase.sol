// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./lib/Ownable.sol";
import "./lib/ERC20.sol";
import "./lib/SafeERC20.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC4626.sol";

/**
 * @notice YakStrategy should be inherited by new strategies
 */
abstract contract YakBase is IERC4626, ERC20, Ownable {
    using SafeERC20 for IERC20;

    struct BaseSettings {
        string name;
        string symbol;
        address asset;
        bool depositsEnabled;
        address devAddr;
    }

    address public immutable asset;
    address public devAddr;

    bool public DEPOSITS_ENABLED;

    event UpdateDevAddr(address oldValue, address newValue);
    event DepositsEnabled(bool newValue);

    /**
     * @notice Only called by dev
     */
    modifier onlyDev() {
        require(msg.sender == devAddr, "YakStrategy::onlyDev");
        _;
    }

    constructor(BaseSettings memory _settings) ERC20(_settings.name, _settings.symbol, 18) {
        asset = _settings.asset;
        devAddr = _settings.devAddr;
        updateDepositsEnabled(_settings.depositsEnabled);
    }

    /*//////////////////////////////////////////////////////////////
                            ABSTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Total amount of the underlying asset that is “managed” by Vault.
     * @dev MUST be inclusive of any fees that are charged against assets in the Vault.
     */
    function totalAssets() public view virtual returns (uint256);

    /*//////////////////////////////////////////////////////////////
                              INTERNAL HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys assets to underlying farm.
     * @dev Do not issue shares
     */
    function deposit(uint256 _assets, uint256 _shares) internal virtual;

    /**
     * @notice Withdraw assets from underlying farm
     * @dev Do not burn shares
     * @return withdraw amount after fees and actual slippage
     */
    function withdraw(uint256 _assets, uint256 _shares) internal virtual returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit using Permit
     * @param _assets Amount of tokens to deposit
     * @param _deadline The time at which to expire the signature
     * @param _v The recovery byte of the signature
     * @param _r Half of the ECDSA signature pair
     * @param _s Half of the ECDSA signature pair
     */
    function depositWithPermit(
        uint256 _assets,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        IERC20(asset).permit(msg.sender, address(this), _assets, _deadline, _v, _r, _s);
        deposit(_assets, msg.sender);
    }

    /**
     * @notice Mints "shares" Vault shares to receiver by depositing exactly amount "_assets" of asset.
     */
    function deposit(uint256 _assets, address _receiver) public override returns (uint256 shares) {
        require(_assets <= maxDeposit(_receiver), "YakBase::Deposit more than max");

        shares = previewDeposit(_assets);
        IERC20(asset).safeTransferFrom(msg.sender, address(this), _assets);

        _mint(_receiver, shares);

        deposit(_assets, shares);

        emit Deposit(msg.sender, _receiver, _assets, shares);
    }

    /**
     * @notice Mints exactly "shares" Vault shares to receiver by depositing amount of underlying tokens.
     */
    function mint(uint256 _shares, address _receiver) public override returns (uint256 assets) {
        require(_shares <= maxMint(_receiver), "YakBase::Mint more than max");

        assets = previewMint(_shares);
        IERC20(asset).safeTransferFrom(msg.sender, address(this), assets);

        _mint(_receiver, _shares);

        deposit(assets, _receiver);

        emit Deposit(msg.sender, _receiver, assets, _shares);
    }

    /**
     * @notice Burns shares from owner and sends exactly assets of underlying tokens to receiver.
     * @dev Must burn receipt tokens from owner
     */
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public override returns (uint256 shares) {
        require(_assets > 0, "YakBase::Withdraw amount too low");
        require(_assets <= maxWithdraw(_owner), "YakBase::Withdraw more than max");

        shares = convertToShares(_assets);
        if (msg.sender != _owner) {
            uint256 allowed = allowance[_owner][msg.sender];

            if (allowed != type(uint256).max) {
                allowance[_owner][msg.sender] = allowed - shares;
            }
        }

        uint256 minReceive = previewWithdraw(_assets);
        uint256 received = withdraw(_assets, shares);
        require(received >= minReceive, "YakBase::Slippage too high");

        _burn(_owner, shares);
        IERC20(asset).safeTransfer(_receiver, received);

        emit Withdraw(msg.sender, _receiver, _owner, received, shares);
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public override returns (uint256 assets) {
        require(_shares > 0, "YakBase::Redeem amount too low");
        require(_shares <= maxRedeem(_owner), "YakBase::Redeem more than max");

        if (msg.sender != _owner) {
            uint256 allowed = allowance[_owner][msg.sender];

            if (allowed != type(uint256).max) {
                allowance[_owner][msg.sender] = allowed - _shares;
            }
        }

        uint256 minReceive = previewRedeem(_shares);
        assets = convertToAssets(_shares);
        uint256 received = withdraw(assets, _shares);
        require(received >= minReceive, "YakBase::Slippage too high");

        _burn(_owner, _shares);
        IERC20(asset).safeTransfer(_receiver, received);

        emit Withdraw(msg.sender, _receiver, _owner, received, _shares);
    }

    /*//////////////////////////////////////////////////////////////
                                ACCOUNTING 
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the amount of shares that the Strategy would exchange for the amount of assets provided
     * @dev If contract is empty, use 1:1 ratio
     * @dev Could return zero shares for very low amounts of deposit tokens
     * @param _assets deposit tokens
     * @return shares receipt tokens
     */
    function convertToShares(uint256 _assets) public view returns (uint256 shares) {
        uint256 tSupply = totalSupply;
        uint256 tAssets = totalAssets();
        if (tSupply == 0 || tAssets == 0) {
            return _assets;
        }
        return (_assets * tSupply) / tAssets;
    }

    /**
     * @notice Calculate the amount of assets that the Vault would exchange for the amount of shares provided
     * @param _shares receipt tokens
     * @return assets deposit tokens
     */
    function convertToAssets(uint256 _shares) public view returns (uint256 assets) {
        uint256 tSupply = totalSupply;
        uint256 tAssets = totalAssets();
        if (tSupply == 0 || tAssets == 0) {
            return 0;
        }
        return (_shares * tAssets) / tSupply;
    }

    function previewDeposit(uint256 _assets) public view virtual override returns (uint256) {
        return convertToShares(_assets);
    }

    function previewMint(uint256 _shares) public view virtual override returns (uint256) {
        return convertToAssets(_shares);
    }

    function previewWithdraw(uint256 _assets) public view virtual override returns (uint256) {
        return convertToShares(_assets);
    }

    function previewRedeem(uint256 _shares) public view virtual override returns (uint256) {
        return convertToAssets(_shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Maximum amount of the underlying asset that can be deposited into the Vault for the receiver, through a deposit call.
     * @dev MUST factor in both global and user-specific limits, like if deposits are entirely disabled (even temporarily) it MUST return 0.
     */
    function maxDeposit(address) public view virtual override returns (uint256) {
        if (DEPOSITS_ENABLED) {
            return type(uint256).max;
        }
        return 0;
    }

    /**
     * @notice Maximum amount of shares that can be minted from the Vault, through a mint call.
     * @dev MUST factor in both global and user-specific limits, like if mints are entirely disabled (even temporarily) it MUST return 0.
     */
    function maxMint(address _receiver) public view virtual override returns (uint256 maxShares) {
        return previewDeposit(maxDeposit(_receiver));
    }

    /**
     * @notice Maximum amount of the underlying asset that can be withdrawn from the owner balance in the Vault, through a withdraw call.
     * @dev MUST factor in both global and user-specific limits, like if withdrawals are entirely disabled (even temporarily) it MUST return 0.
     */
    function maxWithdraw(address _owner) public view virtual override returns (uint256) {
        return previewRedeem(balanceOf[_owner]);
    }

    /**
     * @notice Maximum amount of Vault shares that can be redeemed from the owner balance in the Vault, through a redeem call.
     * @dev MUST factor in both global and user-specific limits, like if redemption is entirely disabled (even temporarily) it MUST return 0.
     */
    function maxRedeem(address _owner) public view virtual override returns (uint256) {
        return balanceOf[_owner];
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enable/disable deposits
     * @param _newValue bool
     */
    function updateDepositsEnabled(bool _newValue) public onlyOwner {
        require(DEPOSITS_ENABLED != _newValue);
        DEPOSITS_ENABLED = _newValue;
        emit DepositsEnabled(_newValue);
    }
}
