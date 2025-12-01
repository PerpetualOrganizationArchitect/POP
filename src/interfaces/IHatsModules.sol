// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEligibilityModule {
    function setToggleModule(address) external;
    function setWearerEligibility(address wearer, uint256 hatId, bool eligible, bool standing) external;
    function setDefaultEligibility(uint256 hatId, bool eligible, bool standing) external;
    function setEligibilityModuleAdminHat(uint256) external;
    function mintHatToAddress(uint256 hatId, address wearer) external;
    function transferSuperAdmin(address) external;
    function registerHatCreation(uint256 hatId, uint256 parentHatId, bool defaultEligible, bool defaultStanding)
        external;
}

interface IToggleModule {
    function setEligibilityModule(address) external;
    function setHatStatus(uint256 hatId, bool active) external;
    function transferAdmin(address) external;
}
