// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @dev CurveGauge interface documentation https://docs.curve.fi/curve_dao/liquidity-gauge-and-minting-crv/gauges/PermissionlessRewards/
interface IGauge is IERC20Metadata {
    struct Reward {
        address token;
        address distributor;
        uint256 period_finish;
        uint256 rate;
        uint256 last_update;
        uint256 integral;
    }

    function deposit(uint256 _value) external;

    function deposit(uint256 _value, address _user) external;

    function deposit(uint256 _value, address _user, bool _claim_rewards) external;

    function withdraw(uint256 _value) external;

    function withdraw(uint256 _value, address _user) external;

    function withdraw(uint256 _value, address _user, bool _claim_rewards) external;

    function user_checkpoint(address _addr) external returns (bool);

    function claimable_tokens(address _addr) external returns (uint256);

    function claimed_reward(address _addr, address _token) external view returns (uint256);

    function claimable_reward(address _user, address _reward_token)
        external
        view
        returns (uint256);

    function set_rewards_receiver(address _receiver) external;

    function claim_rewards() external;

    function claim_rewards(address _addr) external;

    function claim_rewards(address _addr, address _receiver) external;

    function add_reward(address _reward_token, address _distributor) external;

    function set_reward_distributor(address _reward_token, address _distributor) external;

    function deposit_reward_token(address _reward_token, uint256 _amount) external;

    function manager() external view returns (address);

    function reward_count() external view returns (uint256);

    function reward_tokens(uint256 _index) external view returns (address);

    function reward_data(address _token) external view returns (Reward memory);

    function lp_token() external view returns (address);
}
