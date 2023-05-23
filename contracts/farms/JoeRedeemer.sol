// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../lib/Ownable.sol";
import "../lib/SafeERC20.sol";
import "../strategies/avalanche/traderjoe/interfaces/IVeJoeStaking.sol";
import "../strategies/avalanche/traderjoe/interfaces/IJoeVoter.sol";

library SafeProxy {
    function safeExecute(IJoeVoter voter, address target, uint256 value, bytes memory data)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returnValue) = voter.execute(target, value, data);
        if (!success) revert("JoeVoterProxy::safeExecute failed");
        return returnValue;
    }
}

contract JoeRedeemer is Ownable {
    using SafeERC20 for IERC20;
    using SafeProxy for IJoeVoter;

    /// @notice Redemption token
    IERC20 public constant yyJOE = IERC20(0xe7462905B79370389e8180E300F58f63D35B725F);
    IERC20 public constant JOE = IERC20(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);
    address public constant veJoeStaking = 0x25D85E17dD9e544F6E9F8D44F99602dbF5a97341;

    bool public redeemEnabled;

    event Redeem(address indexed account, uint256 amount);
    event Recovered(IERC20 token, uint256 amount);

    /**
     * @notice Redeem yyJOE for JOE
     */
    function redeem(uint256 amount) public {
        require(redeemEnabled, "YrtRedeemer::redeem disabled");
        yyJOE.safeTransferFrom(msg.sender, address(this), amount);
        JOE.safeTransfer(msg.sender, amount);
        emit Redeem(msg.sender, amount);
    }

    function withdrawFromVeJoe() external onlyOwner {
        (uint256 balance,,,) = IVeJoeStaking(veJoeStaking).userInfos(address(yyJOE));
        IJoeVoter(address(yyJOE)).safeExecute(
            veJoeStaking, 0, abi.encodeWithSelector(IVeJoeStaking.withdraw.selector, balance)
        );
        IJoeVoter(address(yyJOE)).safeExecute(
            address(JOE), 0, abi.encodeWithSelector(IERC20.transfer.selector, address(this), balance)
        );
        require(JOE.balanceOf(address(this)) == yyJOE.totalSupply(), "YrtRedeemer::withdraw failed");
        redeemEnabled = true;
    }

    /**
     * @notice Recover ERC20 from contract
     * @param token token address
     * @param amount amount to recover
     */
    function recoverERC20(IERC20 token, uint256 amount) external onlyOwner {
        require(amount > 0, "recoverERC20::Nothing to recover");
        require(address(token) != address(yyJOE), "recoverERC20::Not allowed");
        token.safeTransfer(msg.sender, amount);
        emit Recovered(token, amount);
    }
}
