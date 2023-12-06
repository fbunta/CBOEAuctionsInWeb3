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
    uint public best_bid;
    uint public best_offer;
    uint private auction_price;
    Order[] private sorted_sell_arr;
    Order[] private sorted_buy_arr;

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

    enum OrderType {Normal,
        // AuctionEligible, // this isnt useful to have without a normal orderbook running too
        AuctionOnly
    }
    
    function orderTypeEnumToInt(OrderType value) public pure returns (uint) {
        return uint(value);
    }
    
    struct Order {
        address bidder;
        OrderType order_type;
        Side side;
        uint qty;
        uint256 price;
        bool hidden;
        uint filled_qty;
    }

    function AuctionOrderFactory(address bidder, uint coin_int, uint bid_qty, uint offered_qty)
            private
            pure
            returns (Order memory) 
    {
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
        order.order_type = OrderType.AuctionOnly;
        order.side = side;
        order.qty = qty;
        order.price = price;
        order.hidden = false;
        order.filled_qty = 0;
        return order;
    }

    function OrderFactory(address bidder, OrderType order_type, uint coin_int, uint bid_qty, uint offered_qty, bool hidden)
            private
            pure
            returns (Order memory)
    {
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
        order.hidden = hidden;
        order.filled_qty = 0;
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

    function auctionPriceValid(Order memory ord) private view returns (bool) {
        return (ord.side == Side.Buy && ord.price == best_bid) || (ord.side == Side.Sell && ord.price == best_offer);
    }

    // TODO make this payable and get rid of offered qty
    function place_auction_order(address bidder, uint coin_int, uint bid_qty, uint offered_qty) public {
        Order memory ord = AuctionOrderFactory(bidder, coin_int, bid_qty, offered_qty);
        bool price_valid = auctionPriceValid(ord);
        if(!is_auction_live && price_valid) {
            if(is_auction_start(ord)){
                add_order_to_orderbook(ord);
                start_auction(ord.price);
            } else {
                add_order_to_orderbook(ord);
            }
        } // TODO add else logic for handling orders when an auction already live
        return;
    }

    // TODO make this payable and get rid of offered qty
    function place_normal_order(address bidder, uint coin_int, uint bid_qty, uint offered_qty, bool hidden) public {
        Order memory ord = OrderFactory(bidder, OrderType.Normal, coin_int, bid_qty, offered_qty, hidden);
        add_order_to_orderbook(ord);
        update_nbbo();
        return;
    }

    function add_order_to_orderbook(Order memory ord) private {
        if (ord.side == Side.Sell) {
            sell_arr.push(ord);
        } else {
            buy_arr.push(ord);
        }
    }

    function update_nbbo() private {
        uint local_best_bid = 0;
        uint local_best_offer = 9999999999999999;
        for (uint256 i = 0; i < buy_arr.length; i++) {
            if (buy_arr[i].price > local_best_bid && !buy_arr[i].hidden) {
                local_best_bid = buy_arr[i].price;
            }
        }
        for (uint256 i = 0; i < sell_arr.length; i++) {
            if (sell_arr[i].price < local_best_offer && !sell_arr[i].hidden) {
                local_best_offer = sell_arr[i].price;
            }
        }
        best_bid = local_best_bid;
        best_offer = local_best_offer;
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

    function is_auction_start(Order memory ord) private view returns (bool) {
        if (ord.side == Side.Sell) {
            for (uint256 i = 0; i < buy_arr.length; i++) {
                if (buy_arr[i].price == ord.price && buy_arr[i].order_type == OrderType.AuctionOnly) {
                    return true;
                }
            }
            return false;
        } else if (ord.side == Side.Buy) {
            for (uint256 i = 0; i < sell_arr.length; i++) {
                if (sell_arr[i].price == ord.price && sell_arr[i].order_type == OrderType.AuctionOnly) {
                    return true;
                }
            }  
            return false;
        }
        return false;
    }

    function start_auction(uint price) private {
        auction_start_time = block.timestamp;
        auction_id = auction_id += 1;
        is_auction_live = true;
        auction_price = price;
    }

    function end_auction() private {
        for (uint i = 0; i < buy_arr.length; i++) {
            if (buy_arr[i].price == auction_price){
                if (buy_arr[i].order_type == OrderType.Normal) {
                    if (!buy_arr[i].hidden) {
                        sorted_buy_arr.push(buy_arr[i]);
                    }
                }
            }
        }
        for (uint i = 0; i < buy_arr.length; i++) {
            if (buy_arr[i].price == auction_price){
                if (buy_arr[i].order_type == OrderType.AuctionOnly) {
                    sorted_buy_arr.push(buy_arr[i]);
                }
            }
        }
        for (uint i = 0; i < buy_arr.length; i++) {
            if (buy_arr[i].price == auction_price){
                if (buy_arr[i].order_type == OrderType.Normal) {
                    if (buy_arr[i].hidden) {
                        sorted_buy_arr.push(buy_arr[i]);
                    }
                }
            }
        }
        for (uint i = 0; i < sell_arr.length; i++) {
            if (sell_arr[i].price == auction_price){
                if (sell_arr[i].order_type == OrderType.Normal) {
                    if (!sell_arr[i].hidden) {
                        sorted_sell_arr.push(sell_arr[i]);
                    }
                }
            }
        }
        for (uint i = 0; i < sell_arr.length; i++) {
            if (sell_arr[i].price == auction_price){
                if (sell_arr[i].order_type == OrderType.AuctionOnly) {
                    sorted_sell_arr.push(sell_arr[i]);
                }
            }
        }
        for (uint i = 0; i < sell_arr.length; i++) {
            if (sell_arr[i].price == auction_price){
                if (sell_arr[i].order_type == OrderType.Normal) {
                    if (sell_arr[i].hidden) {
                        sorted_sell_arr.push(sell_arr[i]);
                    }
                }
            }
        }
        uint i = 0;
        uint j = 0;
        while (i < sorted_buy_arr.length && j < sorted_sell_arr.length) {
            uint min_qty;
            if (sorted_buy_arr[i].qty < sorted_sell_arr[j].qty){
                min_qty = sorted_buy_arr[i].qty;
            } else {
                min_qty = sorted_sell_arr[j].qty;
            }
            sorted_buy_arr[i].filled_qty += min_qty;
            sorted_sell_arr[i].filled_qty += min_qty;
            if (sorted_buy_arr[i].filled_qty == sorted_buy_arr[i].qty) {
                pay_out_the_order(sorted_buy_arr[i]);
                i++;
            }
            if(sorted_sell_arr[j].filled_qty == sorted_sell_arr[j].qty) {
                pay_out_the_order(sorted_sell_arr[j]);
                j++;
            }

        }
    is_auction_live = false;
    } 
    
    function pay_out_the_order(Order memory ord) private {
        //implement
    }    
}