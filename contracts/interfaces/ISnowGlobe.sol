// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ISnowGlobe {
    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

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
