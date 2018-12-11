pragma solidity ^0.4.21;

contract OrderBook {

    string private symbol;
    uint private price;

    Order[] private bids;
    Order[] private asks;

    mapping(address => uint) ownedStocks;

    uint private marketBuyPercent = 5;

    enum OrderSide {BUY, SELL}
    enum OrderType {LIMIT, MARKET}
    enum OrderAvailability {OPEN, FOK, IOC}

    struct Order {
        uint timestamp;
        address investor;

        uint quantity;
        uint price;

        OrderSide orderSide;
        OrderType orderType;
        OrderAvailability orderAvailability;
    }
	
	
}