# Yield Yak

Automated yield farming strategies for Avalanche.

*  Web: https://yieldyak.com/
*  Twitter: https://twitter.com/yieldyak_
*  Telegram: https://t.me/yieldyak

## YakStrategies

YakStrategies are an autocompounding primitive. They are designed to be platform-neutral and maximize returns to users from compounding strategies.

YakStrategies are designed to bootstrap growth with fees that may be changed based on ecosystem conditions.

Developers can generate revenue by writing YakStrategies.

#### Developing New Strategies

Strategies should inherit from `YakStrategy.sol`. Most strategies will:

1. Accept deposits
2. Process withdraws
3. Handle compounding
4. Take a fee

Strategies should implement the necessary behavior to generate a return on deposits.

Strategy developers have the ultimate control over functionality. Yield Yak may choose to support the underlying strategies with platform integrations.

## YakVaults

YakVaults are designed to be flexible user interfaces for YakStrategies. YakVaults may be comprised of many YakStrategies.

#### Example Implementation

The example implementation `YakVault.sol` is a managed vault, designed to meet user preferences for risk/reward based on a manager.

Most YakVaults will:

1. Accept multiple deposit types
2. Process withdraws
3. Manage rebalances
4. Take a fee
