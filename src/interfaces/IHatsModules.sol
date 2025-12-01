// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEligibilityModule {
    function setToggleModule(address) external;
    function setWearerEligibility(address wearer, uint256 hatId, bool eligible, bool standing) external;
    function setDefaultEligibility(uint256 hatId, bool eligible, bool standing) external;
    function setEligibilityModuleAdminHat(uint256) external;
    function mintHatToAddress(uint256 hatId, address wearer) external;
    function transferSuperAdmin(address) external;
    function getWearerStatus(address wearer, uint256 hatId) external view returns (bool eligible, bool standing);
    function vouchFor(address wearer, uint256 hatId) external;
    function revokeVouch(address wearer, uint256 hatId) external;
    function currentVouchCount(uint256 hatId, address wearer) external view returns (uint32);
    function claimVouchedHat(uint256 hatId) external;
    function registerHatCreation(uint256 hatId, uint256 parentHatId, bool defaultEligible, bool defaultStanding)
        external;
    // Batch operations for gas optimization
    function batchSetWearerEligibilityMultiHat(
        address[] calldata wearers,
        uint256[] calldata hatIds,
        bool eligible,
        bool standing
    ) external;
    function batchSetDefaultEligibility(
        uint256[] calldata hatIds,
        bool[] calldata eligibles,
        bool[] calldata standings
    ) external;
    function batchMintHats(uint256[] calldata hatIds, address[] calldata wearers) external;
    function batchRegisterHatCreation(
        uint256[] calldata hatIds,
        uint256[] calldata parentHatIds,
        bool[] calldata defaultEligibles,
        bool[] calldata defaultStandings
    ) external;
    function batchConfigureVouching(
        uint256[] calldata hatIds,
        uint32[] calldata quorums,
        uint256[] calldata membershipHatIds,
        bool[] calldata combineWithHierarchyFlags
    ) external;
}

interface IToggleModule {
    function setEligibilityModule(address) external;
    function setHatStatus(uint256 hatId, bool active) external;
    function batchSetHatStatus(uint256[] calldata hatIds, bool[] calldata actives) external;
    function transferAdmin(address) external;
}
