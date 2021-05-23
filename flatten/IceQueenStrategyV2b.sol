// Sources flattened with hardhat v2.3.0 https://hardhat.org

// File contracts/lib/SafeMath.sol

// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

// From https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/Math.sol
// Subject to the MIT license.

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting with custom message on overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, errorMessage);

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on underflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot underflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction underflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on underflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot underflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, errorMessage);

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers.
     * Reverts on division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers.
     * Reverts with custom message on division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}


// File contracts/interfaces/IERC20.sol


interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


// File contracts/SnowballERC20.sol



abstract contract SnowballERC20 {
    using SafeMath for uint256;

    string public name = "Snowball";
    string public symbol = "SNOW";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
  
    mapping (address => mapping (address => uint256)) internal allowances;
    mapping (address => uint256) internal balances;

    /// keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 public constant DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    /// keccak256("1");
    bytes32 public constant VERSION_HASH = 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

    /// keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    mapping(address => uint) public nonces;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {}

    /**
     * @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
     * @param account The address of the account holding the funds
     * @param spender The address of the account spending the funds
     * @return The number of tokens approved
     */
    function allowance(address account, address spender) external view returns (uint) {
        return allowances[account][spender];
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     * and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * It is recommended to use increaseAllowance and decreaseAllowance instead
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (2^256-1 means infinite)
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external view returns (uint) {
        return balances[account];
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint256 amount) external returns (bool) {
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(address src, address dst, uint256 amount) external returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = allowances[src][spender];

        if (spender != src && spenderAllowance != uint256(-1)) {
            uint256 newAllowance = spenderAllowance.sub(amount, "transferFrom: transfer amount exceeds allowance");
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }


    /**
     * @notice Approval implementation
     * @param owner The address of the account which owns tokens
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (2^256-1 means infinite)
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "_approve::owner zero address");
        require(spender != address(0), "_approve::spender zero address");
        allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @notice Transfer implementation
     * @param from The address of the account which owns tokens
     * @param to The address of the account which is receiving tokens
     * @param value The number of tokens that are being transferred
     */
    function _transferTokens(address from, address to, uint256 value) internal {
        require(to != address(0), "_transferTokens: cannot transfer to the zero address");

        balances[from] = balances[from].sub(value, "_transferTokens: transfer exceeds from balance");
        balances[to] = balances[to].add(value);
        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply.add(value);
        balances[to] = balances[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balances[from] = balances[from].sub(value, "_burn: burn amount exceeds from balance");
        totalSupply = totalSupply.sub(value, "_burn: burn amount exceeds total supply");
        emit Transfer(from, address(0), value);
    }

    /**
     * @notice Triggers an approval from owner to spender
     * @param owner The address to approve from
     * @param spender The address to be approved
     * @param value The number of tokens that are approved (2^256-1 means infinite)
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, "permit::expired");

        bytes32 encodeData = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));
        _validateSignedData(owner, encodeData, v, r, s);

        _approve(owner, spender, value);
    }

    /**
     * @notice Recovers address from signed data and validates the signature
     * @param signer Address that signed the data
     * @param encodeData Data signed by the address
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function _validateSignedData(address signer, bytes32 encodeData, uint8 v, bytes32 r, bytes32 s) internal view {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                getDomainSeparator(),
                encodeData
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        // Explicitly disallow authorizations for address(0) as ecrecover returns address(0) on malformed messages
        require(recoveredAddress != address(0) && recoveredAddress == signer, "Arch::validateSig: invalid signature");
    }

    /**
     * @notice EIP-712 Domain separator
     * @return Separator
     */
    function getDomainSeparator() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                VERSION_HASH,
                _getChainId(),
                address(this)
            )
        );
    }

    /**
     * @notice Current id of the chain where this contract is deployed
     * @return Chain id
     */
    function _getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }
}


// File contracts/interfaces/IIceQueen.sol


interface IIceQueen {
    function poolLength() external view returns (uint256);
    function setComPerBlock(uint256 _newPerBlock) external;
    function add(uint256 _allocPoint, address _lpToken, bool _withUpdate) external;
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external;
    function setMigrator(address _migrator) external;
    function migrate(uint256 _pid) external;
    function getMultiplier(uint256 _from, uint256 _to) external view returns (uint256);
    function pendingSnowball(uint256 _pid, address _user) external view returns (uint256);
    function massUpdatePools() external;
    function updatePool(uint256 _pid) external;
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function dev(address _devaddr) external;
    event Recovered(address token, uint256 amount);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
}


// File contracts/interfaces/ISnowGlobe.sol


interface ISnowGlobe {
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);


    function token() external view returns (address);
    function min() external view returns (uint256);
    function max() external view returns (uint256);

    function governance() external view returns (address);
    function timelock() external view returns (address);
    function controller() external view returns (address);

    function depositAll() external;
    function earn() external;
    function available() external view returns (uint256);
    function setController(address _controller) external;
    function getRatio() external view returns (uint256);
    function balance() external view returns (uint256);
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _shares) external;
    function withdrawAll() external;
    function harvest(address reserve, uint256 amount) external;
}


// File contracts/interfaces/IRouter.sol


interface IRouter {
    function addLiquidity(address tokenA, address tokenB, uint amountADesired, uint amountBDesired, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityAVAX(address token, uint amountTokenDesired, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline) external payable returns (uint amountToken, uint amountAVAX, uint liquidity);
    function removeLiquidity(address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, address to, uint deadline) external returns (uint amountA, uint amountB);
    function removeLiquidityAVAX(address token, uint liquidity, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline) external returns (uint amountToken, uint amountAVAX);
    function removeLiquidityWithPermit(address tokenA, address tokenB, uint liquidity, uint amountAMin, uint amountBMin, address to, uint deadline, bool approveMax, uint8 v, bytes32 r, bytes32 s) external returns (uint amountA, uint amountB);
    function removeLiquidityAVAXWithPermit(address token, uint liquidity, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline, bool approveMax, uint8 v, bytes32 r, bytes32 s) external returns (uint amountToken, uint amountAVAX);
    function removeLiquidityAVAXSupportingFeeOnTransferTokens(address token, uint liquidity, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline) external returns (uint amountAVAX);
    function removeLiquidityAVAXWithPermitSupportingFeeOnTransferTokens(address token, uint liquidity, uint amountTokenMin, uint amountAVAXMin, address to, uint deadline, bool approveMax, uint8 v, bytes32 r, bytes32 s) external returns (uint amountAVAX);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactAVAXForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
    function swapTokensForExactAVAX(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactTokensForAVAX(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapAVAXForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline ) external;
    function swapExactAVAXForTokensSupportingFeeOnTransferTokens( uint amountOutMin, address[] calldata path, address to, uint deadline) external payable;
    function swapExactTokensForAVAXSupportingFeeOnTransferTokens( uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] memory path) external view returns (uint[] memory amounts);
}


// File contracts/interfaces/IPair.sol


interface IPair is IERC20 {
    function token0() external pure returns (address);
    function token1() external pure returns (address);
}


// File contracts/lib/Context.sol


/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


// File contracts/lib/Ownable.sol


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}


// File contracts/IceQueenStrategyV2b.sol









contract IceQueenStrategyV2b is SnowballERC20, Ownable {
  using SafeMath for uint;

  uint public totalDeposits;

  IRouter public router;
  ISnowGlobe public depositToken;
  IPair public lpToken;
  IERC20 private token0;
  IERC20 private token1;
  IERC20 public rewardToken;
  IIceQueen public stakingContract;

  uint public PID;
  uint public MIN_TOKENS_TO_REINVEST = 20000;
  uint public REINVEST_REWARD_BIPS = 500;
  uint public ADMIN_FEE_BIPS = 500;
  uint constant private BIPS_DIVISOR = 10000;
  bool public REQUIRE_REINVEST_BEFORE_DEPOSIT;
  uint public MIN_TOKENS_TO_REINVEST_BEFORE_DEPOSIT = 20;

  event Deposit(address account, uint amount);
  event Withdraw(address account, uint amount);
  event Reinvest(uint newTotalDeposits, uint newTotalSupply);
  event Recovered(address token, uint amount);
  event UpdateAdminFee(uint oldValue, uint newValue);
  event UpdateReinvestReward(uint oldValue, uint newValue);
  event UpdateMinTokensToReinvest(uint oldValue, uint newValue);
  event UpdateRequireReinvestBeforeDeposit(bool newValue);
  event UpdateMinTokensToReinvestBeforeDeposit(uint oldValue, uint newValue);

  constructor(
    address _depositToken,
    address _rewardToken, 
    address _stakingContract,
    address _router,
    uint _pid
  ) {
    depositToken = ISnowGlobe(_depositToken);
    rewardToken = IERC20(_rewardToken);
    stakingContract = IIceQueen(_stakingContract);
    router = IRouter(_router);

    address _lpToken = ISnowGlobe(_depositToken).token();
    lpToken = IPair(_lpToken);

    PID = _pid;

    address _token0 = IPair(_lpToken).token0();
    address _token1 = IPair(_lpToken).token1();
    token0 = IERC20(_token0);
    token1 = IERC20(_token1);

    name = string(
      abi.encodePacked(
        "Snowball: ",
        ISnowGlobe(_depositToken).symbol(), " (",
        lpToken.symbol(), " ",
        IERC20(_token0).symbol(), "-",
        IERC20(_token1).symbol(), ")"
      )
    );

    emit Reinvest(0, 0);
  }

  /**
    * @dev Throws if called by smart contract
    */
  modifier onlyEOA() {
      require(tx.origin == msg.sender, "onlyEOA");
      _;
  }

  /**
   * @notice Set approvals for tokens
   * @param tokensToApprove tokens to approve
   * @param approvalAmounts approval amounts
   * @param spenders address allowed to spend tokens
   */
  function tokenAllow(
      address[] memory tokensToApprove, 
      uint256[] memory approvalAmounts, 
      address[] memory spenders
  ) external onlyOwner {
    require(
      tokensToApprove.length == approvalAmounts.length
      && tokensToApprove.length == spenders.length
    , "not same length");
    for(uint i = 0; i < tokensToApprove.length; i++) {
      IERC20 token = IERC20(tokensToApprove[i]);
      uint allowance = token.allowance(address(this), spenders[i]);
      if (
        allowance != approvalAmounts[i] &&
        (allowance != uint256(-1) || approvalAmounts[i] == 0)
      ) {
        require(token.approve(spenders[i], approvalAmounts[i]), "approve failed");
      }
    }
  }

  /**
   * @notice Deposit LP tokens to receive Snowball tokens
   * @param amount Amount of LP tokens to deposit
   */
  function deposit(uint amount) external {
    require(totalDeposits >= totalSupply, "deposit failed");
    if (REQUIRE_REINVEST_BEFORE_DEPOSIT) {
      uint unclaimedRewards = checkReward();
      if (unclaimedRewards >= MIN_TOKENS_TO_REINVEST_BEFORE_DEPOSIT) {
        _reinvest(unclaimedRewards);
      }
    }
    require(depositToken.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
    _stakeDepositTokens(amount);
    _mint(msg.sender, getSharesForLPTokens(amount));
    totalDeposits = totalDeposits.add(amount);
    emit Deposit(msg.sender, amount);
  }

  /**
   * @notice Withdraw deposit tokens by redeeming receipt tokens
   * @param amount Amount of receipt tokens to redeem
   */
  function withdraw(uint amount) external {
    uint depositTokenAmount = getLPTokensForShares(amount);
    if (depositTokenAmount > 0) {
      _withdrawDepositTokens(depositTokenAmount);
      require(depositToken.transfer(msg.sender, depositTokenAmount), "transfer failed");
      _burn(msg.sender, amount);
      totalDeposits = totalDeposits.sub(depositTokenAmount);
      emit Withdraw(msg.sender, depositTokenAmount);
    }
  }

  /**
   * @notice Calculate receipt tokens for a given amount of deposit tokens
   * @dev If contract is empty, use 1:1 ratio
   * @dev Could return zero shares for very low amounts of deposit tokens
   * @dev Note: misleading name (consider rename to "getReceiptTokensForDepositTokens")
   * @param amount deposit tokens
   * @return receipt tokens
   */
  function getSharesForLPTokens(uint amount) public view returns (uint) {
    if (totalSupply.mul(totalDeposits) == 0) {
      return amount;
    }
    return amount.mul(totalSupply).div(totalDeposits);
  }

  /**
   * @notice Calculate deposit tokens for a given amount of receipt tokens
   * @dev Note: misleading name (consider rename to "getDepositTokensForReceiptTokens")
   * @param amount receipt tokens
   * @return deposit tokens
   */
  function getLPTokensForShares(uint amount) public view returns (uint) {
    if (totalSupply.mul(totalDeposits) == 0) {
      return 0;
    }
    return amount.mul(totalDeposits).div(totalSupply);
  }

  /**
   * @notice Reward token balance that can be reinvested
   * @dev Staking rewards accurue to contract on each deposit/withdrawal
   * @return Unclaimed rewards, plus contract balance
   */
  function checkReward() public view returns (uint) {
    uint pendingReward = stakingContract.pendingSnowball(PID, address(this));
    uint contractBalance = rewardToken.balanceOf(address(this));
    return pendingReward.add(contractBalance);
  }

  /**
   * @notice Estimate reinvest reward
   * @return Estimated reward tokens earned for calling `reinvest()`
   */
  function estimateReinvestReward() external view returns (uint) {
    uint unclaimedRewards = checkReward();
    if (unclaimedRewards >= MIN_TOKENS_TO_REINVEST) {
      return unclaimedRewards.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
    }
    return 0;
  }

  /**
   * @notice Reinvest rewards from staking contract to LP tokens
   * @dev This external function requires minimum tokens to be met
   */
  function reinvest() external onlyEOA {
    uint unclaimedRewards = checkReward();
    require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "MIN_TOKENS_TO_REINVEST");
    _reinvest(unclaimedRewards);
  }

  /**
   * @notice Reinvest rewards from staking contract to deposit tokens
   */
  function _reinvest(uint amount) internal {
    stakingContract.deposit(PID, 0);

    uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
    if (adminFee > 0) {
      require(rewardToken.transfer(owner(), adminFee), "admin fee transfer failed");
    }

    uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
    if (reinvestFee > 0) {
      require(rewardToken.transfer(msg.sender, reinvestFee), "reinvest fee transfer failed");
    }

    uint lpTokenAmount = _convertRewardTokensToLpTokens(amount.sub(adminFee).sub(reinvestFee));
    uint depositTokenAmount = _convertLpTokensToDepositTokens(lpTokenAmount);
    _stakeDepositTokens(depositTokenAmount);
    totalDeposits = totalDeposits.add(depositTokenAmount);

    emit Reinvest(totalDeposits, totalSupply);
  }

  /**
   * @notice Converts intermediary LP tokens to deposit tokens
   * @dev Function `deposit(uint)` does not return an amount and is calculated
   * @dev Do NOT rely on output amount for non-standard token supply mechanisms (e.g. fee on transfer)
   * @return deposit tokens received
   */
  function _convertLpTokensToDepositTokens(uint amount) internal returns (uint) {
    require(amount > 0, "amount too low");
    uint256 _pool = depositToken.balance();
    uint256 _totalSupply = depositToken.totalSupply();
    uint256 shares = 0;
    if (_totalSupply == 0) {
        shares = amount;
    } else {
        shares = (amount.mul(_totalSupply)).div(_pool);
    }
    depositToken.deposit(amount);
    return shares;
  }

  /**
   * @notice Converts entire reward token balance to intermediary LP tokens
   * @dev Always converts through router; there are no price checks enabled
   * @return LP tokens received
   */
  function _convertRewardTokensToLpTokens(uint amount) internal returns (uint) {
    uint amountIn = amount.div(2);
    require(amountIn > 0, "amount too low");

    // swap to token0
    address[] memory path0 = new address[](2);
    path0[0] = address(rewardToken);
    path0[1] = address(token0);

    uint amountOutToken0 = amountIn;
    if (path0[0] != path0[path0.length - 1]) {
      uint[] memory amountsOutToken0 = router.getAmountsOut(amountIn, path0);
      amountOutToken0 = amountsOutToken0[amountsOutToken0.length - 1];
      router.swapExactTokensForTokens(amountIn, amountOutToken0, path0, address(this), block.timestamp);
    }

    // swap to token1
    address[] memory path1 = new address[](3);
    path1[0] = path0[0];
    path1[1] = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    path1[2] = address(token1);

    uint amountOutToken1 = amountIn;
    if (path1[0] != path1[path1.length - 1]) {
      uint[] memory amountsOutToken1 = router.getAmountsOut(amountIn, path1);
      amountOutToken1 = amountsOutToken1[amountsOutToken1.length - 1];
      router.swapExactTokensForTokens(amountIn, amountOutToken1, path1, address(this), block.timestamp);
    }

    (,,uint liquidity) = router.addLiquidity(
      path0[path0.length - 1], path1[path1.length - 1],
      amountOutToken0, amountOutToken1,
      0, 0,
      address(this),
      block.timestamp
    );

    return liquidity;
  }

  /**
   * @notice Stakes deposit tokens in Staking Contract
   * @param amount deposit tokens to stake
   */
  function _stakeDepositTokens(uint amount) internal {
    require(amount > 0, "amount too low");
    stakingContract.deposit(PID, amount);
  }

  /**
   * @notice Withdraws deposit tokens from Staking Contract
   * @dev Reward tokens are automatically collected
   * @dev Reward tokens are not automatically reinvested
   * @param amount deposit tokens to remove
   */
  function _withdrawDepositTokens(uint amount) internal {
    require(amount > 0, "amount too low");
    stakingContract.withdraw(PID, amount);
  }

  /**
   * @notice Allows exit from Staking Contract without additional logic
   * @dev Reward tokens are not automatically collected
   * @dev New deposits will be effectively disabled
   */
  function emergencyWithdraw() external onlyOwner {
    stakingContract.emergencyWithdraw(PID);
    totalDeposits = 0;
  }

  /**
   * @notice Update reinvest minimum threshold for external callers
   * @param newValue min threshold in wei
   */
  function updateMinTokensToReinvest(uint newValue) external onlyOwner {
    emit UpdateMinTokensToReinvest(MIN_TOKENS_TO_REINVEST, newValue);
    MIN_TOKENS_TO_REINVEST = newValue;
  }

  /**
   * @notice Update admin fee
   * @dev Total fees cannot be greater than BIPS_DIVISOR (100%)
   * @param newValue specified in BIPS
   */
  function updateAdminFee(uint newValue) external onlyOwner {
    require(newValue.add(REINVEST_REWARD_BIPS) <= BIPS_DIVISOR, "admin fee too high");
    emit UpdateAdminFee(ADMIN_FEE_BIPS, newValue);
    ADMIN_FEE_BIPS = newValue;
  }

  /**
   * @notice Update reinvest reward
   * @dev Total fees cannot be greater than BIPS_DIVISOR (100%)
   * @param newValue specified in BIPS
   */
  function updateReinvestReward(uint newValue) external onlyOwner {
    require(newValue.add(ADMIN_FEE_BIPS) <= BIPS_DIVISOR, "reinvest reward too high");
    emit UpdateReinvestReward(REINVEST_REWARD_BIPS, newValue);
    REINVEST_REWARD_BIPS = newValue;
  }

  /**
   * @notice Toggle requirement to reinvest before deposit
   */
  function updateRequireReinvestBeforeDeposit() external onlyOwner {
    REQUIRE_REINVEST_BEFORE_DEPOSIT = !REQUIRE_REINVEST_BEFORE_DEPOSIT;
    emit UpdateRequireReinvestBeforeDeposit(REQUIRE_REINVEST_BEFORE_DEPOSIT);
  }

  /**
   * @notice Update reinvest minimum threshold before a deposit
   * @param newValue min threshold in wei
   */
  function updateMinTokensToReinvestBeforeDeposit(uint newValue) external onlyOwner {
    emit UpdateMinTokensToReinvestBeforeDeposit(MIN_TOKENS_TO_REINVEST_BEFORE_DEPOSIT, newValue);
    MIN_TOKENS_TO_REINVEST_BEFORE_DEPOSIT = newValue;
  }

  /**
   * @notice Recover ERC20 from contract
   * @param tokenAddress token address
   * @param tokenAmount amount to recover
   */
  function recoverERC20(address tokenAddress, uint tokenAmount) external onlyOwner {
    require(tokenAmount > 0, 'amount too low');
    IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
    emit Recovered(tokenAddress, tokenAmount);
  }

  /**
   * @notice Recover AVAX from contract
   * @param amount amount
   */
  function recoverAVAX(uint amount) external onlyOwner {
    require(amount > 0, 'amount too low');
    msg.sender.transfer(amount);
    emit Recovered(address(0), amount);
  }
}
