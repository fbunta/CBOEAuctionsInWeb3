// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED
 * VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */

/**
 * If you are reading data feeds on L2 networks, you must
 * check the latest answer from the L2 Sequencer Uptime
 * Feed to ensure that the data is accurate in the event
 * of an L2 sequencer outage. See the
 * https://docs.chain.link/data-feeds/l2-sequencer-feeds
 * page for details.
 */

//maybe a modifier in the public function place_bid would be
// the best way to limit orders that are outside the price collar you are 
//creating from subscribing to chainlink's BTC/ETH feed

contract CollarPriceDataFeed{
    // Chainlink ETH/USD price feed address (replace with the relevant price feed address)
    AggregatorV3Interface public priceFeed;

    // Collar bounds
    uint256 public upperBound;
    uint256 public lowerBound;

    // Event triggered when the collar is breached
    event CollarBreached(string direction);

    constructor(address _priceFeed, uint256 _upperBound, uint256 _lowerBound) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        upperBound = _upperBound;
        lowerBound = _lowerBound;
    }

    // Function to get the latest ETH/USD price from the Chainlink Oracle
    function getLatestPrice() public view returns (int) {
        (, int price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    // Function to check if the collar is breached
    function checkCollar() external {
        int latestPrice = getLatestPrice();

        if (uint256(latestPrice) > upperBound) {
            emit CollarBreached("Upper Bound");
            // Implement actions for breaching upper bound (e.g., initiate liquidation)
        } else if (uint256(latestPrice) < lowerBound) {
            emit CollarBreached("Lower Bound");
            // Implement actions for breaching lower bound (e.g., stop trading)
        }
    }

    // Function to update collar bounds (only callable by the contract owner)
    function updateCollarBounds(uint256 _upperBound, uint256 _lowerBound) external  {
        upperBound = _upperBound;
        lowerBound = _lowerBound;
    }
}