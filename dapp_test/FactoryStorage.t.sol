// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.5;

import "./test.sol";
import "../src/bonding/FactoryStorage.sol";

contract FactoryStorageTest is DSTest {
    FactoryStorage internal factoryStorage;

    function setUp() public {
        factoryStorage = new FactoryStorage();
    }

    function test_setFactoryAddress(address _factory) public {
        factoryStorage.setFactoryAddress(_factory);
        assertEq(factoryStorage.factory(), _factory);
    }
}
