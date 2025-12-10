// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice 테스트용 Mock ERC20 토큰 (USDC 모킹, 6 decimals)
 * @dev 누구나 원하는 주소에 원하는 수량 민팅 가능
 */
contract MockERC20 is ERC20 {
    uint8 private constant DECIMALS = 6;
    uint256 public constant MINT_AMOUNT = 100 * 10 ** DECIMALS; // 100 tokens (6 decimals)

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        // Deployer에게 초기 발행
        _mint(msg.sender, 1000 * 10 ** DECIMALS);
    }

    /**
     * @notice USDC는 6 decimals
     */
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice 누구나 특정 주소에 100개 민팅 가능 (여러 번 실행 가능)
     */
    function mintTo(address to) external {
        _mint(to, MINT_AMOUNT);
    }
}

