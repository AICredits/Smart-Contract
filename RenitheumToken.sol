pragma solidity ^0.4.18;

import './token/TransferLimitedToken.sol';


contract RenitheumToken is TransferLimitedToken {
    uint256 public constant SALE_END_TIME = 1522540800; // 01.04.2018

    function RenitheumToken(address _listener, address[] _owners, address manager) public
        TransferLimitedToken(SALE_END_TIME, _listener, _owners, manager)
    {
        name = "Renitheum";
        symbol = "RTH";
        decimals = 8;
    }
}