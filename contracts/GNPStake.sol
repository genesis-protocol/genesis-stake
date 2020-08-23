pragma solidity ^0.4.26;

import "./Stake.sol";

contract GNPStake is Stake {
    constructor(address _owner) public {
        Stake.initialize(_owner);
    }
}
