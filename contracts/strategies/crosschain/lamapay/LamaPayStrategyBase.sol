// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../BaseStrategy.sol";

import "./../../../interfaces/ILamaPay.sol";

abstract contract LamaPayStrategyBase is BaseStrategy {
    using SafeERC20 for IERC20;

    struct Stream {
        address lamaPayInstance;
        address payer;
        uint216 amountPerSec;
        address token;
    }

    Stream[] public streams;

    event AddStream(address lamaPayInstance, address payer, uint216 amountPerSec, address token);
    event RemoveStream(address lamaPayInstance, address payer, uint216 amountPerSec, address token);
    event BorkedStream(address lamaPayInstance, address payer, uint216 amountPerSec, address token);

    constructor(BaseStrategySettings memory _baseStrategySettings, StrategySettings memory _strategySettings)
        BaseStrategy(_baseStrategySettings, _strategySettings)
    {}

    function addStream(address _lamaPayInstance, address _payer, uint216 _amountPerSec) external onlyDev {
        if (_lamaPayInstance > address(0) && _payer > address(0) && _amountPerSec > 0) {
            (, bool found) = findStream(_lamaPayInstance, _payer, _amountPerSec);
            require(!found, "MemeRushStrategy::Stream already configured!");
            address token = ILamaPay(_lamaPayInstance).token();
            streams.push(
                Stream({lamaPayInstance: _lamaPayInstance, payer: _payer, amountPerSec: _amountPerSec, token: token})
            );
            emit AddStream(_lamaPayInstance, _payer, _amountPerSec, token);
        }
    }

    function removeStream(address _lamaPayInstance, address _payer, uint216 _amountPerSec) external onlyDev {
        (uint256 index, bool found) = findStream(_lamaPayInstance, _payer, _amountPerSec);
        require(found, "MemeRushStrategy::Stream not configured!");
        streams[index] = streams[streams.length - 1];
        streams.pop();
        emit RemoveStream(_lamaPayInstance, _payer, _amountPerSec, ILamaPay(_lamaPayInstance).token());
    }

    function findStream(address _lamaPayInstance, address _payer, uint216 _amountPerSec)
        internal
        view
        returns (uint256 index, bool found)
    {
        for (uint256 i = 0; i < streams.length; i++) {
            if (
                _lamaPayInstance == streams[i].lamaPayInstance && _payer == streams[i].payer
                    && _amountPerSec == streams[i].amountPerSec
            ) {
                found = true;
                index = i;
            }
        }
    }

    function _readStream(Stream memory _stream) internal view returns (Reward memory) {
        try ILamaPay(_stream.lamaPayInstance).withdrawable(_stream.payer, address(this), _stream.amountPerSec) returns (
            uint256 withdrawableAmount, uint256, uint256
        ) {
            return Reward({reward: _stream.token, amount: withdrawableAmount});
        } catch {
            return Reward({reward: _stream.token, amount: 0});
        }
    }

    function _pendingRewards() internal view virtual override returns (Reward[] memory) {
        Reward[] memory rewards = new Reward[](streams.length);
        for (uint256 i = 0; i < streams.length; i++) {
            rewards[i] = _readStream(streams[i]);
        }
        return rewards;
    }

    function _getRewards() internal virtual override {
        for (uint256 i = 0; i < streams.length; i++) {
            try ILamaPay(streams[i].lamaPayInstance).withdraw(streams[i].payer, address(this), streams[i].amountPerSec)
            {} catch {
                emit BorkedStream(
                    streams[i].lamaPayInstance, streams[i].payer, streams[i].amountPerSec, streams[i].token
                );
            }
        }
    }
}
