{\rtf1\ansi\ansicpg1252\cocoartf2758
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fnil\fcharset0 Menlo-Regular;}
{\colortbl;\red255\green255\blue255;\red172\green172\blue193;}
{\*\expandedcolortbl;;\cssrgb\c72941\c73333\c80000;}
\paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\deftab720
\pard\pardeftab720\partightenfactor0

\f0\fs24 \cf2 \expnd0\expndtw0\kerning0
\outl0\strokewidth0 \strokec2 // SPDX-License-Identifier: MIT\
pragma solidity ^0.8.19;\
\
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";\
\
contract LW3Token is ERC20 \{\
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) \{\
        _mint(msg.sender, 10 * 10**decimals()); // 10 full tokens to be minted to developer's address upon deployment\
    \}\
\
    function get(uint256 value) external \{\
      _update(address(0), msg.sender, value * 10**decimals());\
    \}\
\
    function transfer_to(address to, uint256 value) external \{\
      _transfer(msg.sender, to, value * 10**decimals());\
    \}\
\}}