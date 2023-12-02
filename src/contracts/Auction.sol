pragma solidity ^0.8.4;

contract CBOEPeriodicAuction {
    address public exchange_admin;
    // Increments every auction
    int public auction_id;
    // By default initialized to `false`.
    bool public is_auction_live;

    uint256 public auction_start_time;

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
        address bidder;
        OrderType order_type;
        Side side;
        uint qty;
        uint256 price;
    }

    function OrderFactory(address bidder, uint order_type_int, uint coin_int, uint bid_qty, uint offered_qty)
            private
            pure
            returns (Order memory) 
    {
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
        order.bidder = bidder;
        order.order_type = order_type;
        order.side = side;
        order.qty = qty;
        order.price = price;
        return order;
    }

    constructor() {
        exchange_admin = msg.sender;
        auction_id = 0;
        is_auction_live = false;
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
        Order memory ord = OrderFactory(bidder, order_type_int, coin_int, bid_qty, offered_qty);
        if(!is_auction_live) {
            if (ord.order_type == OrderType.AuctionOnly || ord.order_type == OrderType.AuctionEligible) {
                if(is_auction_start(ord)){
                    add_order_to_orderbook(ord);
                    start_auction();
                } else {
                    add_order_to_orderbook(ord);
                }
            } else {
                add_order_to_orderbook(ord);
            }
        } // TODO add else logic for handling orders when an auction already live
        return;
    }

    function add_order_to_orderbook(Order memory ord) private {
        if (ord.side == Side.Sell) {
            sell_arr.push(ord);
        } else {
            buy_arr.push(ord);
        }
    }

    // TODO figure out a way this is not manually called
    function manually_end_auction() public onlyAdmin() {
        require(block.timestamp >= auction_start_time + set_auction_time_random(), "Not enough time has passed");
        end_auction();
    }

    function set_auction_time_random() private pure returns(uint256) {
        // TODO(Neal) add randomness https://docs.chain.link/vrf/v2/best-practices
        return 65;
    }

    function is_one_order_auction_only(Order memory ord_1, Order memory ord_2) private pure returns (bool) {
        return (ord_1.order_type == OrderType.AuctionOnly || ord_2.order_type == OrderType.AuctionOnly);
    }

    function is_auction_start(Order memory ord) private view returns (bool) {
        if (ord.side == Side.Sell) {
            for (uint256 i = 0; i < buy_arr.length; i++) {
                if (buy_arr[i].price == ord.price && is_one_order_auction_only(ord, buy_arr[i])) {
                    return true;
                }
            }  
            return false;
        } else if (ord.side == Side.Buy) {
            for (uint256 i = 0; i < sell_arr.length; i++) {
                if (sell_arr[i].price == ord.price && is_one_order_auction_only(ord, sell_arr[i])) {
                    return true;
                }
            }  
            return false;
        }
        return false;
    }

    function start_auction() private {
        auction_start_time = block.timestamp;
        auction_id = auction_id += 1;
        is_auction_live = true;
    }

    function end_auction() private {
        // TODO end the auction execution logic
        is_auction_live = false;
    }
}