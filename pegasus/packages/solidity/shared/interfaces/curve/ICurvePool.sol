// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ICurvePool is IERC20Metadata {
    event TokenExchange(
        address indexed buyer,
        int128 sold_id,
        uint256 tokens_sold,
        int128 bought_id,
        uint256 tokens_bought
    );
    event AddLiquidity(
        address indexed provider,
        uint256[] token_amounts,
        uint256[] fees,
        uint256 invariant,
        uint256 token_supply
    );
    event RemoveLiquidity(
        address indexed provider, uint256[] token_amounts, uint256[] fees, uint256 token_supply
    );
    event RemoveLiquidityOne(
        address indexed provider,
        int128 token_id,
        uint256 token_amount,
        uint256 coin_amount,
        uint256 token_supply
    );
    event RemoveLiquidityImbalance(
        address indexed provider,
        uint256[] token_amounts,
        uint256[] fees,
        uint256 invariant,
        uint256 token_supply
    );

    function version() external view returns (string memory);
    function salt() external view returns (bytes32);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy, address _receiver)
        external
        returns (uint256);
    function exchange_received(int128 i, int128 j, uint256 _dx, uint256 _min_dy, address _receiver)
        external
        returns (uint256);

    function add_liquidity(uint256[] memory _amounts, uint256 _min_mint_amount)
        external
        returns (uint256);
    function remove_liquidity(uint256 _burn_amount, uint256[] memory _min_amounts)
        external
        returns (uint256[] memory);
    function remove_liquidity_one_coin(uint256 _burn_amount, int128 _i, uint256 _min_received)
        external
        returns (uint256);
    function remove_liquidity_imbalance(uint256[] memory _amounts, uint256 _max_burn_amount)
        external
        returns (uint256);
    function calc_token_amount(uint256[] memory _amounts, bool _is_deposit)
        external
        view
        returns (uint256);

    function last_price(uint256 i) external view returns (uint256);
    function ema_price(uint256 i) external view returns (uint256);
    function price_oracle(uint256 i) external view returns (uint256);
    function stored_rates() external view returns (uint256[] memory);
    function get_virtual_price() external view returns (uint256);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);

    function balances(uint256 i) external view returns (uint256);

    function coins(uint256 i) external view returns (address);
}
