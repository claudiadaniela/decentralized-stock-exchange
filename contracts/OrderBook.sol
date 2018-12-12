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

    function OrderBook(string _symbol, uint _quantity, uint _marketBuyPercent) public stringLength(_symbol, 3) {
        symbol = _symbol;
        ownedStocks[msg.sender] = _quantity;
        marketBuyPercent = _marketBuyPercent;
    }

    function placeOrder(uint _quantity, uint _stockPrice, OrderSide _orderSide, OrderType _orderType, OrderAvailability _orderAvailability) external payable {
        require(_quantity > 0);
        require(_stockPrice > 0);

        if (_orderSide == OrderSide.BUY) {
            if (_orderType == OrderType.LIMIT) {
                require(msg.value == _stockPrice * _quantity);
            }

            if (_orderType == OrderType.MARKET) {
                require(msg.value >= ((100 + marketBuyPercent) * price * _quantity) / 100);
            }
        } else {
            require(ownedStocks[msg.sender] >= _quantity);
            require(msg.value == 0);
        }

        Order memory order = Order(now, msg.sender, _quantity, _stockPrice, _orderSide, _orderType, _orderAvailability);

        if (_orderAvailability == OrderAvailability.FOK) {
            if (!canExecuteEntireOrder(order)) {
                msg.sender.transfer(msg.value);
                return;
            }
        }

        executeOrder(order);
    }

    function canExecuteEntireOrder(Order _order) private returns (bool) {
        Order[] storage oppositeSideOrders = _order.orderSide == OrderSide.BUY ? asks : bids;
        uint oppositeSideOrdersLength = oppositeSideOrders.length;

        uint position = 0;
        uint totalQuantity = 0;

        while (position < oppositeSideOrdersLength) {
            Order storage currentOrder = oppositeSideOrders[position++];

            if (_order.orderType == OrderType.MARKET) {
                totalQuantity += currentOrder.quantity;
            }

            if (_order.orderType == OrderType.LIMIT) {
                if (isPriceOk(_order, currentOrder)) {
                    totalQuantity += currentOrder.quantity;
                }
            }

            if (totalQuantity >= _order.quantity) {
                return true;
            }
        }

        return false;
    }

    function isPriceOk(Order _myOrder, Order _otherOrder) private returns (bool) {
        if (_myOrder.orderSide == OrderSide.BUY) {
            if (_myOrder.price >= _otherOrder.price) {
                return true;
            }
        } else {
            if (_myOrder.price <= _otherOrder.price) {
                return true;
            }
        }

        return false;
    }

    function executeOrder(Order _order) private {
        Order[] storage oppositeOrders = _order.orderSide == OrderSide.BUY ? asks : bids;

        uint amountToReturn = msg.value;
        uint remainingStocks = _order.quantity;

        while (remainingStocks > 0) {
            if (oppositeOrders.length == 0) {
                if (_order.orderAvailability == OrderAvailability.IOC || _order.orderType == OrderType.MARKET) {
                    // do nothing. Order is canceled
                    _order.investor.transfer(amountToReturn);
                }

                if (_order.orderAvailability == OrderAvailability.OPEN) {
                    _order.quantity = remainingStocks;
                    placeOrderInCorrectPlace(_order);
                }

                break;
            }

            Order storage orderToMatch = oppositeOrders[0];

            if (_order.orderType == OrderType.MARKET) {
                if (remainingStocks >= orderToMatch.quantity) {
                    actualExecutionOfOrder(_order, orderToMatch, orderToMatch.quantity);

                    remainingStocks -= orderToMatch.quantity;
                    amountToReturn -= orderToMatch.quantity * orderToMatch.price;
                    removeFirstElement(oppositeOrders);
                } else {
                    actualExecutionOfOrder(_order, orderToMatch, remainingStocks);
                    amountToReturn -= remainingStocks * orderToMatch.price;

                    orderToMatch.quantity -= remainingStocks;
                    remainingStocks = 0;
                }
            }

            if (_order.orderType == OrderType.LIMIT) {
                if (!isPriceOk(_order, orderToMatch)) {
                    _order.quantity = remainingStocks;
                    placeOrderInCorrectPlace(_order);
                    break;
                } else {
                    if (remainingStocks >= orderToMatch.quantity) {
                        actualExecutionOfOrder(_order, orderToMatch, orderToMatch.quantity);

                        amountToReturn -= orderToMatch.quantity * orderToMatch.price;
                        remainingStocks -= orderToMatch.quantity;
                        removeFirstElement(oppositeOrders);
                    } else {
                        actualExecutionOfOrder(_order, orderToMatch, remainingStocks);

                        amountToReturn -= remainingStocks * orderToMatch.price;
                        orderToMatch.quantity -= remainingStocks;
                        remainingStocks = 0;
                    }
                }
            }
        }
    }

    function actualExecutionOfOrder(Order _myOrder, Order _orderToMatch, uint _quantityToTransfer) private {
        if (_myOrder.orderSide == OrderSide.BUY) {
            ownedStocks[_orderToMatch.investor] -= _quantityToTransfer;
            ownedStocks[_myOrder.investor] += _quantityToTransfer;

            _orderToMatch.investor.transfer(_quantityToTransfer * _orderToMatch.price);
        } else {
            ownedStocks[_orderToMatch.investor] += _quantityToTransfer;
            ownedStocks[_myOrder.investor] -= _quantityToTransfer;

            _myOrder.investor.transfer(_quantityToTransfer * _orderToMatch.price);
        }

        price = _orderToMatch.price;
    }

    function removeFirstElement(Order[] storage _orders) private {
        if (_orders.length == 0) {
            return;
        }

        delete _orders[0];

        for (uint i = 0; i < _orders.length - 1; i++) {
            _orders[i] = _orders[i + 1];
        }

        _orders.length--;
    }

    function addElementAtPosition(Order[] storage _orders, uint _position, Order _order) private {
        if (_orders.length == 0) {
            _orders.push(_order);
            return;
        }

        uint length = _orders.length;
        _orders.length++;

        for (uint i = length; i > _position; i--) {
            _orders[i] = _orders[i - 1];
        }

        _orders[_position] = _order;
    }

    function placeOrderInCorrectPlace(Order _order) private {
        bool inserted = false;
        Order[] storage sameSideOrders = _order.orderSide == OrderSide.BUY ? bids : asks;

        uint sameSideOrdersLength = sameSideOrders.length;
        for (uint i = 0; i < sameSideOrdersLength; i++) {
            if (_order.orderSide == OrderSide.SELL) {
                if (_order.price < asks[i].price) {
                    addElementAtPosition(asks, i, _order);
                    inserted = true;
                    break;
                }

                if (_order.price == asks[i].price) {
                    if (_order.quantity > asks[i].quantity) {
                        addElementAtPosition(asks, i, _order);
                        inserted = true;
                        break;
                    } else {
                        addElementAtPosition(asks, i + 1, _order);
                        inserted = true;
                        break;
                    }
                }
            } else {
                if (_order.price > bids[i].price) {
                    addElementAtPosition(bids, i, _order);
                    inserted = true;
                    break;
                }

                if (_order.price == bids[i].price) {
                    if (_order.quantity > bids[i].quantity) {
                        addElementAtPosition(bids, i, _order);
                        inserted = true;
                        break;
                    }
                }
            }
        }

        if (!inserted && _order.orderSide == OrderSide.BUY) {
            addElementAtPosition(bids, i, _order);
        }

        if (!inserted && _order.orderSide == OrderSide.SELL) {
            addElementAtPosition(asks, i, _order);
        }
    }

    modifier stringLength(string _str, uint _length) {
        require(bytes(_str).length == _length);
        _;
    }

    function getQuantityOfStocks() external view returns (uint){
        return ownedStocks[msg.sender];
    }

    function viewPrice() external view returns (uint){
        return price;
    }
}