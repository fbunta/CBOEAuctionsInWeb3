pragma solidity ^0.8.4;

contract CBOEPeriodicAuction {
    address public exchange_admin;
    // Increments every auction
    int public auction_id;
    // By default initialized to `false`.
    bool public is_auction_live;

    Order[] private buy_arr;
    Order[] private sell_arr;

    enum Side {Buy, Sell}
    enum Coin {BTC, ETH}

    function coinEnumToInt(Coin value) public pure returns (uint) {
        return uint(value);
    }

    function coinEnumToString(Coin value) public pure returns (string memory) {
        if (value == Coin.BTC) {
            return "BTC";
        } else if (value == Coin.ETH) {
            return "ETH";
        } else {
            revert("Unknown enum value");
        }
    }

    enum OrderType {Normal, AuctionEligible, AuctionOnly}
    
    function orderTypeEnumToInt(OrderType value) public pure returns (uint) {
        return uint(value);
    }
    
    struct Order {
        OrderType order_type;
        Side side;
        uint qty;
        uint256 price;
    }

    function OrderFactory(uint order_type_int, uint coin_int, uint bid_qty, uint offered_qty) private pure returns (Order memory) {
        OrderType order_type;
        if (order_type_int == orderTypeEnumToInt(OrderType.Normal)) {
            order_type = OrderType.Normal;
        } else if (order_type_int == orderTypeEnumToInt(OrderType.AuctionEligible)) {
            order_type = OrderType.AuctionEligible;
        } else if (order_type_int == orderTypeEnumToInt(OrderType.AuctionOnly)) {
            order_type = OrderType.AuctionOnly;
        } else {
            revert("Coin integers 1 and 2 are only allowed");
        }
        Coin coin;
        if (coin_int == coinEnumToInt(Coin.BTC)) {
            coin = Coin.BTC;
        } else if (coin_int == coinEnumToInt(Coin.ETH)) {
            coin = Coin.ETH;
        } else {
            revert("Coin integers 1 and 2 are only allowed");
        }
        (uint price, uint qty, Side side) = get_order_attr(coin, bid_qty, offered_qty);
        Order memory order;
        order.order_type = order_type;
        order.side = side;
        order.qty = qty;
        order.price = price;
        return order;
    }

    constructor() {
        exchange_admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == exchange_admin, "Not the exchange admin");
        _;
    }

    // coin is what the bidder wants and the offered qty is how much of their own coin they offered for it
    // here we put everything in BTC qty and ETH price terms (i.e. buy 4 BTC @ 100 ETH)
    function get_order_attr(Coin coin, uint bid_qty, uint offered_qty) private pure returns(uint price, uint qty, Side side){
        if (coin == Coin.BTC){
            price = offered_qty / bid_qty; // ETH/BTC
            qty = bid_qty;
            side = Side.Buy;
        } else {
            price = bid_qty / offered_qty;
            qty = offered_qty;
            side = Side.Sell;
        }
    }

    // TODO make this payable and get rid of offered qty
    function place_bid(address bidder, uint order_type_int, uint coin_int, uint bid_qty, uint offered_qty) public {
        Order memory ord = OrderFactory(order_type_int, coin_int, bid_qty, offered_qty);
        if (ord.side == Side.Sell) {
            sell_arr.push(ord);
        } else {
            buy_arr.push(ord);
        }
        if(!is_auction_live){
            check_for_auction_start();
        }
        return;
    }

    function set_auction_time_random() private pure {
        // randomness https://docs.chain.link/vrf/v2/best-practices
        return;
    }

    function check_for_auction_start() private view {
        for (uint256 i = 0; i < sell_arr.length; i++) {
            for (uint256 j = 0; j < buy_arr.length; j++) {
                if (buy_arr[j].price == sell_arr[i].price) {
                    start_auction();
                    break;
                }
            }   
        }
    }

    function start_auction() private pure {
        return;
    }
}