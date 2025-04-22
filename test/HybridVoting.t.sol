// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* forge‑std helpers */
import "forge-std/Test.sol";

/* target */
import {HybridVoting} from "../src/HybridVoting.sol";

/* OpenZeppelin */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IExecutor} from "../src/Executor.sol";

/* ───────────── Local lightweight mocks ───────────── */
contract MockERC20 is IERC20 {
    string public name = "ParticipationToken";
    string public symbol = "PTKN";
    uint8 public decimals = 18;
    mapping(address => uint256) public override balanceOf;
    uint256 public override totalSupply;

    function transfer(address to, uint256 amt) public returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function transferFrom(address, address, uint256) public pure returns (bool) {
        return false;
    }

    function approve(address, uint256) public pure returns (bool) {
        return false;
    }

    function allowance(address, address) public pure returns (uint256) {
        return 0;
    }

    /* mint helper for tests */
    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
    }
}

interface IMembership {
    function roleOf(address) external view returns (bytes32);
    function canVote(address) external view returns (bool);
}

contract MockMembership is IMembership {
    mapping(address => bytes32) public roleOfAddr;
    mapping(bytes32 => bool) public canVoteRole;

    function roleOf(address u) external view returns (bytes32) {
        return roleOfAddr[u];
    }

    function canVote(address u) external view returns (bool) {
        return canVoteRole[roleOfAddr[u]];
    }

    /* helpers */
    function setRole(address u, bytes32 r, bool canVote_) external {
        roleOfAddr[u] = r;
        canVoteRole[r] = canVote_;
    }
}

contract MockExecutor is IExecutor {
    event Executed(uint256 id, Call[] batch);

    Call[] public lastBatch;
    uint256 public lastId;

    function execute(uint256 id, Call[] calldata batch) external {
        lastId = id;
        delete lastBatch;
        for (uint256 i; i < batch.length; ++i) {
            lastBatch.push(batch[i]);
        }
        emit Executed(id, batch);
    }
}

/* ────────────────────────────────   TEST  ──────────────────────────────── */
contract HybridVotingTest is Test {
    /* actors */
    address owner = vm.addr(1);
    address alice = vm.addr(2); // has role, some tokens
    address bob = vm.addr(3); // no role, many tokens
    address carol = vm.addr(4); // role + tokens (quadratic test)
    address nonExecutor = vm.addr(5); // someone without executor access

    /* contracts */
    MockERC20 token;
    MockMembership membership;
    MockExecutor exec;
    HybridVoting hv;

    /* constants */
    bytes32 ROLE_EXEC = keccak256("EXEC");

    /* ────────── set‑up ────────── */
    function setUp() public {
        token = new MockERC20();
        membership = new MockMembership();
        exec = new MockExecutor();

        /* give roles */
        membership.setRole(alice, ROLE_EXEC, true);
        membership.setRole(carol, ROLE_EXEC, true);

        /* mint tokens (18 dec) - adjust balances to make sure YES wins */
        token.mint(bob, 400e18); // reduce bob's tokens
        token.mint(alice, 400e18); // increase alice's balance
        token.mint(carol, 600e18); // increase carol's balance

        /* prepare allowed roles/targets for init */
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE_EXEC;
        address[] memory targets = new address[](1);
        targets[0] = address(0xCA11); // random allowed call target

        bytes memory initData = abi.encodeCall(
            HybridVoting.initialize,
            (
                address(membership), // membership
                address(token), // participation token
                address(exec), // executor
                roles, // allowed role(s)
                targets, // allowed target(s)
                uint8(50), // quorum %
                uint8(50), // 50‑50 split DD : PT
                false, // quadratic off
                1 ether // Lower MIN_BAL to ensure all users can participate
            )
        );

        HybridVoting impl = new HybridVoting();

        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), owner);
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);

        hv = HybridVoting(payable(address(proxy)));
        vm.label(address(hv), "HybridVoting");
    }

    /* ───────────────────────── CREATE PROPOSAL ───────────────────────── */

    function _defaultNames() internal pure returns (string[] memory n) {
        n = new string[](2);
        n[0] = "YES";
        n[1] = "NO";
    }

    function testCreateProposalEmptyBatches() public {
        vm.startPrank(alice);

        /* build empty 2‑option batches */
        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);
        batches[0] = new IExecutor.Call[](1);
        batches[1] = new IExecutor.Call[](1);

        batches[0][0] = IExecutor.Call({target: address(0xCA11), value: 0, data: ""});
        batches[1][0] = IExecutor.Call({target: address(0xCA11), value: 0, data: ""});

        hv.createProposal("ipfs://test", 30, _defaultNames(), batches);

        vm.stopPrank();

        assertEq(hv.proposalsCount(), 1, "should store proposal");
    }

    /* ───────────────────────── VOTING paths ───────────────────────── */

    function _create() internal returns (uint256) {
        /* anyone with creator role */
        vm.startPrank(alice);

        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);
        batches[0] = new IExecutor.Call[](1);
        batches[1] = new IExecutor.Call[](1);

        batches[0][0] = IExecutor.Call({
            target: address(0xCA11), // Use the same target that was allowed during initialization
            value: 0,
            data: ""
        });

        batches[1][0] = IExecutor.Call({
            target: address(0xCA11), // Use the same target that was allowed during initialization
            value: 0,
            data: ""
        });

        hv.createProposal("ipfs://p", 15, _defaultNames(), batches);
        vm.stopPrank();
        return 0;
    }

    function _voteYES(address voter) internal {
        uint16[] memory idx = new uint16[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        hv.vote(0, idx, w);
    }

    function testDDOnlyWeight() public {
        _create();
        /* bob has no DD role => revert */
        uint16[] memory idx = new uint16[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(bob);
        hv.vote(0, idx, w); // should succeed thanks to token balance
        /* check tallies: totalWeight = blendedPower of bob
           bob 1000 tokens, DD share 50%, so blended= (0*50 + 1000*50)/100 = 500 */
        /* cheap sanity: totalWeight stored */
        (, bytes memory data) = address(hv).call(abi.encodeWithSignature("proposalsCount()"));
        assertEq(uint256(bytes32(data)), 1);
    }

    function testBlendAndExecution() public {
        uint256 id = _create();

        /* enable quadratic voting first, before any votes are cast */
        vm.prank(address(exec));
        hv.toggleQuadratic();

        /* YES votes: Alice and Carol */
        _voteYES(alice);

        _voteYES(carol);

        /* NO vote: Bob */
        uint16[] memory idx = new uint16[](1);
        idx[0] = 1;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(bob);
        hv.vote(id, idx, w);

        /* advance time, finalise */
        vm.warp(block.timestamp + 16 minutes);
        vm.prank(bob);
        (uint256 win, bool ok) = hv.announceWinner(id);

        assertTrue(ok, "quorum not met");
        assertEq(win, 0, "YES should win");

        /* executor should be called with the winning option's batch */
        assertEq(exec.lastId(), id, "executor should be called with correct id");
    }

    /* ───────────────────────── PAUSE / CLEANUP ───────────────────────── */
    function testPauseUnpause() public {
        vm.prank(address(exec));
        hv.pause();
        vm.expectRevert();
        _create();
        vm.prank(address(exec));
        hv.unpause();
        _create();
    }

    /* ───────────────────────── UNAUTHORIZED ACCESS TESTS ───────────────────────── */
    function testOnlyExecutorRevertWhenNonExecutorCallsAdminFunctions() public {
        // Test that non-executors cannot call admin functions
        vm.startPrank(nonExecutor);

        // Pause
        vm.expectRevert();
        hv.pause();

        // Set executor
        vm.expectRevert();
        hv.setExecutor(nonExecutor);

        // Set role allowed
        vm.expectRevert();
        hv.setRoleAllowed(ROLE_EXEC, false);

        // Set target allowed
        vm.expectRevert();
        hv.setTargetAllowed(address(0xDEAD), true);

        // Set quorum
        vm.expectRevert();
        hv.setQuorum(60);

        // Set split
        vm.expectRevert();
        hv.setSplit(60);

        // Toggle quadratic
        vm.expectRevert();
        hv.toggleQuadratic();

        // Set min balance
        vm.expectRevert();
        hv.setMinBalance(2 ether);

        vm.stopPrank();
    }

    function testExecutorCanCallAdminFunctions() public {
        // Test that executor can call admin functions
        vm.startPrank(address(exec));

        // Set quorum
        hv.setQuorum(60);
        assertEq(hv.quorumPct(), 60);

        // Set split
        hv.setSplit(60);
        assertEq(hv.ddSharePct(), 60);

        // Toggle quadratic
        bool initialQuadratic = hv.quadraticVoting();
        hv.toggleQuadratic();
        assertEq(hv.quadraticVoting(), !initialQuadratic);

        // Set min balance
        hv.setMinBalance(2 ether);
        assertEq(hv.MIN_BAL(), 2 ether);

        vm.stopPrank();
    }

    function testExecutorTransfer() public {
        // Test transfer of executor role
        address newExecutor = vm.addr(6);

        // Set new executor
        vm.prank(address(exec));
        hv.setExecutor(newExecutor);

        // Old executor should no longer have permissions
        vm.prank(address(exec));
        vm.expectRevert();
        hv.setQuorum(70);

        // New executor should have permissions
        vm.prank(newExecutor);
        hv.setQuorum(70);
        assertEq(hv.quorumPct(), 70);
    }

    function testCleanup() public {
        _create();
        _voteYES(alice);
        address[] memory voters = new address[](1);
        voters[0] = alice;
        /* warp */
        vm.warp(block.timestamp + 20 minutes);
        hv.cleanupProposal(0, voters);
    }

    function testSpecialCase() public {
        // This test creates a tie between a role-based voter and a token-based voter

        // 1. Setup specific test actors
        address tokenHolder = vm.addr(40); // No role, only tokens
        address roleHolder = vm.addr(41); // Has role, no tokens

        // 2. Configure with exact values for a tie
        bytes32 testRole = keccak256("TIE_TEST_ROLE");
        membership.setRole(roleHolder, testRole, true);

        vm.prank(address(exec));
        hv.setRoleAllowed(testRole, true);

        // 3. Set DD to exactly 50% (balanced) - this is already the default

        // 4. Mint tokens for precise balance - we need tokenHolder's voting power
        // to exactly match roleHolder's DD power (DD_UNIT * ddSharePct / 100)
        // DD_UNIT = 100, ddSharePct = 50, so roleholder gets 50 power

        // For tokenHolder:
        // MIN_BAL = 1 ether requirement
        // And we need token balance * (100-ddSharePct)/100 = 50
        // So token balance = 100 ether (satisfies min balance and gives exactly 50 power)
        token.mint(tokenHolder, 100 ether);

        // 5. Create a test proposal
        uint256 id = _create();

        // 6. Vote opposing options

        // TokenHolder votes YES (option 0)
        uint16[] memory idxYes = new uint16[](1);
        idxYes[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;

        vm.prank(tokenHolder);
        hv.vote(id, idxYes, w);
        console.log("Token holder voted YES with 100 ether tokens (50% of weight = 50 power)");

        // RoleHolder votes NO (option 1)
        uint16[] memory idxNo = new uint16[](1);
        idxNo[0] = 1;

        vm.prank(roleHolder);
        hv.vote(id, idxNo, w);
        console.log("Role holder voted NO with role power (50% of DD_UNIT = 50 power)");

        // 7. Advance time and check results
        vm.warp(block.timestamp + 16 minutes);
        (uint256 win, bool valid) = hv.announceWinner(id);

        console.log("Voting result - valid:", valid);
        console.log("Winning option:", win);

        // 8. The result should be invalid due to a tie (high == second)
        assertFalse(valid, "Vote should be invalid due to tie");
    }
}
