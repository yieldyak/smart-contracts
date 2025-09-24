// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {ISimpleRouter} from "./../interfaces/ISimpleRouter.sol";
import {IYakRouter, FormattedOffer} from "./interfaces/IYakRouter.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {IERC20} from "./../interfaces/IERC20.sol";
import {Ownable} from "./../lib/Ownable.sol";

contract SimpleRouter is ISimpleRouter, Ownable {
    bool public yakSwapFallback;
    uint256 public maxStepsFallback;
    IYakRouter public yakRouter;
    address public feeCollector;
    uint256 public feeBips;
    uint256 internal constant BIPS_DIVISOR = 10000;
    uint256 public constant MAX_FEE_BIPS = 1000;

    mapping(address => mapping(address => SwapConfig)) public swapConfigurations;

    constructor(
        bool _yakSwapFallback,
        uint256 _maxStepsFallback,
        address _yakRouter,
        uint256 _feeBips,
        address _feeCollector
    ) {
        configureYakSwapDefaults(_yakSwapFallback, _maxStepsFallback, _yakRouter);
        updateFeeBips(_feeBips);
        updateFeeCollector(_feeCollector);
    }

    function updateFeeBips(uint256 _feeBips) public onlyOwner {
        if (_feeBips > MAX_FEE_BIPS) {
            revert FeeExceedsMaximum(_feeBips, MAX_FEE_BIPS);
        }
        if (_feeBips != feeBips) {
            emit UpdateFeeBips(feeBips, _feeBips);
            feeBips = _feeBips;
        }
    }

    function updateFeeCollector(address _feeCollector) public onlyOwner {
        if (_feeCollector == address(0)) {
            revert InvalidFeeCollector(_feeCollector);
        }
        if (_feeCollector != feeCollector) {
            emit UpdateFeeCollector(feeCollector, _feeCollector);
            feeCollector = _feeCollector;
        }
    }

    function updateSwapConfiguration(SwapConfig memory _swapConfig) external onlyOwner {
        swapConfigurations[_swapConfig.path.tokens[0]][_swapConfig.path.tokens[_swapConfig.path.tokens.length - 1]] =
            _swapConfig;
    }

    function updateYakSwapDefaults(bool _yakSwapFallback, uint256 _maxStepsFallback, address _yakRouter)
        external
        onlyOwner
    {
        configureYakSwapDefaults(_yakSwapFallback, _maxStepsFallback, _yakRouter);
    }

    function configureYakSwapDefaults(bool _yakSwapFallback, uint256 _maxStepsFallback, address _yakRouter) internal {
        if (_yakRouter == address(0)) {
            revert InvalidConfiguration();
        }
        maxStepsFallback = _maxStepsFallback > 0 ? _maxStepsFallback : 1;
        yakSwapFallback = _yakSwapFallback;
        yakRouter = IYakRouter(_yakRouter);
    }

    function query(uint256 _amountIn, address _tokenIn, address _tokenOut)
        external
        view
        override
        returns (FormattedOffer memory offer)
    {
        SwapConfig storage swapConfig = swapConfigurations[_tokenIn][_tokenOut];
        return query(_amountIn, _tokenIn, _tokenOut, swapConfig);
    }

    function query(uint256 _amountIn, address _tokenIn, address _tokenOut, SwapConfig memory _swapConfig)
        public
        view
        returns (FormattedOffer memory offer)
    {
        bool routeConfigured = _swapConfig.path.adapters.length > 0;

        if (!routeConfigured && !_swapConfig.useYakSwapRouter && !yakSwapFallback) {
            return zeroOffer(_tokenIn, _tokenOut);
        }

        uint256 amountIn = _amountIn;
        _amountIn = _amountIn * (BIPS_DIVISOR - feeBips) / BIPS_DIVISOR;

        if (routeConfigured) {
            offer = queryPredefinedRoute(_amountIn, _swapConfig.path.adapters, _swapConfig.path.tokens);
        } else {
            offer = queryYakSwap(
                _amountIn,
                _tokenIn,
                _tokenOut,
                _swapConfig.yakSwapMaxSteps > 0 ? _swapConfig.yakSwapMaxSteps : maxStepsFallback
            );
        }
        offer.amounts[0] = amountIn;
    }

    function queryPredefinedRoute(uint256 _amountIn, address[] memory _adapters, address[] memory _tokens)
        internal
        view
        returns (FormattedOffer memory offer)
    {
        uint256[] memory amounts = new uint256[](_tokens.length);
        amounts[0] = _amountIn;
        for (uint256 i; i < _adapters.length; i++) {
            amounts[i + 1] = IAdapter(_adapters[i]).query(amounts[i], _tokens[i], _tokens[i + 1]);
        }

        offer = FormattedOffer({amounts: amounts, path: _tokens, adapters: _adapters, gasEstimate: 0});
    }

    function queryYakSwap(uint256 _amountIn, address _tokenIn, address _tokenOut, uint256 _maxSteps)
        internal
        view
        returns (FormattedOffer memory offer)
    {
        offer = yakRouter.findBestPath(_amountIn, _tokenIn, _tokenOut, _maxSteps);
        if (offer.amounts.length == 0) {
            return zeroOffer(_tokenIn, _tokenOut);
        }
    }

    function zeroOffer(address _tokenIn, address _tokenOut) internal pure returns (FormattedOffer memory offer) {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        return FormattedOffer({amounts: new uint256[](0), path: path, adapters: new address[](0), gasEstimate: 0});
    }

    function swap(FormattedOffer memory _offer) external override returns (uint256 amountOut) {
        address tokenIn = _offer.path[0];
        address tokenOut = _offer.path[_offer.path.length - 1];

        if (_offer.adapters.length == 0) {
            revert UnsupportedSwap(tokenIn, tokenOut);
        }

        return _swap(tokenIn, _offer);
    }

    function swap(uint256 _amountIn, uint256 _amountOutMin, address _tokenIn, address _tokenOut)
        external
        returns (uint256 amountOut)
    {
        SwapConfig memory swapConfig = swapConfigurations[_tokenIn][_tokenOut];
        return swap(_amountIn, _amountOutMin, _tokenIn, _tokenOut, swapConfig);
    }

    function swap(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _tokenIn,
        address _tokenOut,
        SwapConfig memory _swapConfig
    ) public returns (uint256 amountOut) {
        uint256 fee = _amountIn * feeBips / BIPS_DIVISOR;
        IERC20(_tokenIn).transferFrom(msg.sender, feeCollector, fee);

        _amountIn -= fee;
        FormattedOffer memory offer = query(_amountIn, _tokenIn, _tokenOut, _swapConfig);

        if (offer.adapters.length == 0) {
            revert UnsupportedSwap(_tokenIn, _tokenOut);
        }

        if (offer.amounts[offer.amounts.length - 1] < _amountOutMin) {
            revert SlippageExceeded();
        }

        return _swap(_tokenIn, offer);
    }

    function _swap(address _tokenIn, FormattedOffer memory _offer) internal returns (uint256 amountOut) {
        IERC20(_tokenIn).transferFrom(msg.sender, _offer.adapters[0], _offer.amounts[0]);

        for (uint256 i; i < _offer.adapters.length; i++) {
            address targetAddress = i < _offer.adapters.length - 1 ? _offer.adapters[i + 1] : msg.sender;
            IAdapter(_offer.adapters[i]).swap(
                _offer.amounts[i], _offer.amounts[i + 1], _offer.path[i], _offer.path[i + 1], targetAddress
            );
        }

        return _offer.amounts[_offer.amounts.length - 1];
    }
}
