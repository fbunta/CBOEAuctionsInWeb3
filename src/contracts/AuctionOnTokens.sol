// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "https://github.com/fbunta/CBOEAuctionsInWeb3/blob/c4857c85dfccdef6cf8a7cdd09bb86131d1934d0/src/contracts/IssueCoin.sol";
//import "https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol"

contract CBOEPeriodicAuction is VRFConsumerBase{
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

    //Chainlink VRF
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public randomResult;
    //

    LW3Token[] public tokens;

    struct Deposit {
        address customer;
        uint256[] token_qtys;
    }
    mapping(address => Deposit) private deposits; // Deposits stored by user address

    function accessTokens() internal {
        LW3Token BTC = LW3Token(0xCA613F4296b283e8d03844Ac17114a7A8018ce19);  // BTC is coin_int=0
        LW3Token ETH = LW3Token(0x8FF44EC192457aD1a148b3ED6a0f408fFe6B32fd);  // ETH is coin_int=1
        tokens.push(BTC);
        tokens.push(ETH);
    }

    function checkBalance(uint coin_int) public view returns(uint256) {
        Deposit storage dep = deposits[msg.sender];
        if (dep.customer == address(0)) {
            revert("Account does not exist");
        } else {
            return dep.token_qtys[coin_int];
        }
    }

    function topUp(uint coin_int, uint qty) public {
        tokens[coin_int].transfer(msg.sender, address(this), qty);
        Deposit storage dep = deposits[msg.sender];
        if (dep.customer == address(0)) {
            dep.customer = msg.sender;
            dep.token_qtys = new uint[](2);
        }
        dep.token_qtys[coin_int] += qty;
    }

    function withdraw(uint coin_int, uint qty) public {
        Deposit storage dep = deposits[msg.sender];
        if (dep.customer == address(0)) {
            revert("Account does not exist");
        } else if (dep.token_qtys[coin_int] < qty) {
            revert("Insufficient balance");
        } else {
            dep.token_qtys[coin_int] -= qty;
            tokens[coin_int].transfer(address(this), msg.sender, qty);
        }
    }

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

    enum OrderStatus { Filled, Active};

    struct Order {
        address bidder;
        OrderType order_type;
        Side side;
        uint qty;
        uint256 price;
        bool hidden;
        uint filled_qty;
        OrderStatus status;
    }

    function auctionOrderFactory(address bidder, uint coin_int, uint bid_qty, uint offered_qty)
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
            revert("Coin integers 0 and 1 are only allowed");
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
        order.status = OrderStatus.Active;
        return order;
    }

    function orderFactory(address bidder, OrderType order_type, uint coin_int, uint bid_qty, uint offered_qty, bool hidden)
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
        order.status = OrderStatus.Active;
        return order;
    }

    constructor(address vrfCoordinator, address linkToken, bytes32 _keyHash, uint256 _fee) {
        accessTokens();
        exchange_admin = msg.sender;
        auction_id = 0;
        is_auction_live = false;

        VRFConsumerBase(vrfCoordinator, linkToken) {
          keyHash = _keyHash;
          fee = _fee;
          
        }
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

    // TODO get rid of offered qty (optional)
    function placeAuctionOrder(address bidder, uint coin_int, uint bid_qty, uint offered_qty) public {
        Deposit storage dep = deposits[bidder];
        if (dep.customer == address(0) || dep.token_qtys[coin_int] < offered_qty) {
            revert("Insufficient fund")
        }
        Order memory ord = auctionOrderFactory(bidder, coin_int, bid_qty, offered_qty);
        bool price_valid = auctionPriceValid(ord);
        if (!is_auction_live && price_valid) {
            if (isAuctionStart(ord)) {
                addOrderToOrderbook(ord);
                startAuction(ord.price);
            } else {
                addOrderToOrderbook(ord);
            }
        } // TODO add else logic for handling orders when an auction already live
        return;
    }

    // TODO get rid of offered qty (optional)
    function placeNormalOrder(address bidder, uint coin_int, uint bid_qty, uint offered_qty, bool hidden) public {
        Deposit storage dep = deposits[bidder];
        if (dep.customer == address(0) || dep.token_qtys[coin_int] < offered_qty) {
            revert("Insufficient fund")
        }
        Order memory ord = orderFactory(bidder, OrderType.Normal, coin_int, bid_qty, offered_qty, hidden);
        addOrderToOrderbook(ord);
        updateNBBO();
        return;
    }

    function addOrderToOrderbook(Order memory ord) private {
        if (ord.side == Side.Sell) {
            sell_arr.push(ord);
        } else {
            buy_arr.push(ord);
        }
    }

    function updateNBBO() private {
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
    function manuallyEndAuction() public onlyAdmin() {
        require(block.timestamp >= auction_start_time + setAuctionTimeRandom(), "Not enough time has passed");
        endAuction();
    }

    // Function to request a random number
    function setAuctionTimeRandom() private returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK - fill contract with faucet");
        return requestRandomness(keyHash, fee);
    }

    // Callback function called by Chainlink VRF service
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomResult = randomness.mod(100); // Modify the range if needed
    }

    function isAuctionStart(Order memory ord) private view returns (bool) {
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

    function startAuction(uint price) private {
        auction_start_time = block.timestamp;
        auction_id = auction_id += 1;
        is_auction_live = true;
        auction_price = price;
    }

    function endAuction() private {
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
                sorted_buy_arr[i].status = OrderStatus.Filled;
                i++;
            }
            if(sorted_sell_arr[j].filled_qty == sorted_sell_arr[j].qty) {
                pay_out_the_order(sorted_sell_arr[j]);
                sorted_sell_arr[j].status = OrderStatus.Filled;
                j++;
            }
        }
        delete sorted_buy_arr;
        delete sorted_sell_arr;
        delete buy_arr;
        delete sell_arr;
        is_auction_live = false;
    }

    function pay_out_the_order(Order memory ord) private {
        Deposit storage dep = deposits[ord.bidder];
        if (ord.Side == Side.Buy) {
            deposits[ord.bidder].token_qtys[0] += ord.filled_qty; // BTC
            deposits[ord.bidder].token_qtys[1] -= (ord.filled_qty * ord.price); // ETH
        } else {
            deposits[ord.bidder].token_qtys[0] -= ord.filled_qty; // BTC
            deposits[ord.bidder].token_qtys[1] += (ord.filled_qty * ord.price); // ETH
        }
    }
}
