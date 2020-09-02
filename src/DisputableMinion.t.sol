pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./DisputableMinion.sol";

contract DisputableMinionTest is DSTest {
    DisputableMinion minion;

    function setUp() public {
        minion = new DisputableMinion();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
