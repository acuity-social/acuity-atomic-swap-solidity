// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.14;

import "ds-test/test.sol";

import "./AcuityAccount.sol";

contract AcuityAccountTest is DSTest {
    AcuityAccount acuityAccount;

    function setUp() public {
        acuityAccount = new AcuityAccount();
    }

    function testSetAcuAccount() public {
        acuityAccount.setAcuAccount(hex"1234");
        assertEq(acuityAccount.getAcuAccount(address(this)), hex"1234");
    }

}