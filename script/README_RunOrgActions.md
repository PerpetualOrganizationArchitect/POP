# RunOrgActions Script - Comprehensive Org Actions Demo

## Overview

`RunOrgActions.s.sol` is a comprehensive demonstration script that shows how to interact with a deployed POA organization. It demonstrates the full lifecycle of organization actions including deployment, member onboarding, task management, and governance.

## What This Script Demonstrates

1. **Organization Deployment** - Deploy a complete organization from a JSON config
2. **Member Onboarding** - Use QuickJoin to onboard multiple members
3. **Token Distribution** - Request and manage participation tokens
4. **Task Management** - Create projects, tasks, assign work, and complete deliverables
5. **Governance** - Create proposals, vote, and execute through HybridVoting

## Files

- `script/RunOrgActions.s.sol` - Main demonstration script
- `script/org-config-governance-demo.json` - Configuration for governance-focused organization

## Configuration Structure

The `org-config-governance-demo.json` defines a 4-role organization:

| Role | Index | Permissions | Description |
|------|-------|-------------|-------------|
| MEMBER | 0 | QuickJoin, Tokens, Education, DD Voting | Base membership tier |
| COORDINATOR | 1 | Task Creation, Proposals, DD Creation | Project coordinators |
| CONTRIBUTOR | 2 | Education Access | Non-voting contributors |
| ADMIN | 3 | Token Approval, Task Creation, Proposals | Full administrative access |

### Voting Configuration

- **Hybrid Voting**: 60% Direct Democracy / 40% Token-Weighted
- **Quadratic Voting**: Enabled for token class
- **Quorum**: 50% for HybridVoting, 60% for DirectDemocracy

## Prerequisites

### 1. Deploy Infrastructure

First, deploy the core infrastructure contracts:

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

This creates `script/infrastructure.json` with deployed contract addresses.

### 2. Setup Private Key

You only need **ONE** private key:

```bash
# .env file
DEPLOYER_PRIVATE_KEY=0x...        # Deploys the organization and funds demo accounts
```

**How it works:**
- Script generates ephemeral test accounts automatically using `makeAddrAndKey()`
- Deployer funds each test account with 0.01 ETH for gas (~$30, enough for all demo actions)
- Test accounts are used for demo (joining, tasks, voting)
- After demo, ephemeral keys are discarded (no need to store anywhere!)

**Security Benefits:**
- No need to manage multiple private keys
- Ephemeral accounts can't accidentally receive real funds
- Clean separation between deployer and test accounts

**Security Note**: Use test accounts only! Never use real private keys with funds.

## Usage

### Basic Usage

Run the complete demonstration:

```bash
forge script script/RunOrgActions.s.sol:RunOrgActions \
  --rpc-url $RPC_URL \
  --broadcast \
  --slow
```

### Custom Configuration

Use a custom org config:

```bash
ORG_CONFIG_PATH=script/my-custom-org.json \
forge script script/RunOrgActions.s.sol:RunOrgActions \
  --rpc-url $RPC_URL \
  --broadcast
```

### Dry Run (No Broadcasting)

Test without sending transactions:

```bash
forge script script/RunOrgActions.s.sol:RunOrgActions \
  --rpc-url $RPC_URL
```

## Script Flow

### Step 1: Deploy Organization

1. Reads `infrastructure.json` for OrgDeployer address
2. Parses `org-config-governance-demo.json`
3. Builds deployment parameters
4. Calls `OrgDeployer.deployFullOrg()`
5. Stores deployed contract addresses

**Output**: All org contract addresses (Executor, HybridVoting, TaskManager, etc.)

### Step 2: Onboard Members

1. **Generate ephemeral test accounts** using `makeAddrAndKey()` (no keys stored!)
2. **Fund accounts**: Deployer sends 0.01 ETH to each for gas
3. **Join organization**: All accounts call `QuickJoin.quickJoinNoUser()` → receive MEMBER hat

**Why this works:**
- QuickJoin grants MEMBER role (index 0) to everyone
- Config grants MEMBER role full demo permissions (can create tasks, proposals, vote)
- This demonstrates self-service onboarding - no manual hat minting needed!

**Note**: In production, you'd typically have restricted permissions:
- MEMBER role: voting only
- COORDINATOR role: task creation (requires manual minting)
- ADMIN role: token approval (requires governance or manual minting)

**Output**: 3 members joined, all with MEMBER role and full demo permissions

### Step 3: Distribute Tokens

1. Member1 requests 10 tokens via `ParticipationToken.requestTokens()`
2. Member2 requests 10 tokens
3. Coordinator requests 20 tokens

**Note**: Requests require approval from an ADMIN hat holder before tokens are minted.

### Step 4: Demonstrate TaskManager

1. Coordinator creates project: "Governance Infrastructure"
2. Creates Task 1: "Deploy Voting System" (1000 token bounty)
3. Creates Task 2: "Documentation" (500 token bounty)
4. Member1 claims Task 1
5. Member2 applies for Task 2, gets approved
6. Both members submit task work
7. Coordinator completes both tasks

**Output**: 2 tasks completed, bounties distributed

### Step 5: Demonstrate Governance

1. Coordinator creates proposal to update TaskManager config
2. Proposal: Increase task approval timeout to 7 days
3. Member1 votes YES (60/40 weight split)
4. Member2 votes YES
5. Coordinator votes YES

**Note**: Full execution requires:
- Waiting for voting deadline
- Calling `voting.announce(proposalId)`
- Calling `executor.execute(...)` with proposal data

## Technical Details

### Configuration Parsing

The script uses Foundry's JSON parsing capabilities:

```solidity
vm.parseJsonString(configJson, ".orgId")
vm.parseJsonUint(configJson, ".quorum.hybrid")
vm.parseJson(configJson, ".roleAssignments.quickJoinRoles")
```

### Role Bitmap Encoding

Role arrays are converted to bitmaps for efficient storage:

```solidity
[0, 1, 3] → bitmap: 0b1011 = 11
```

This allows contracts to check role membership with bitwise operations.

### Voting Weight Distribution

For hybrid voting with 2 classes (60% Direct, 40% Token):

```solidity
uint8[] memory votes = [60, 40];       // How to split vote across classes
uint8[] memory weights = [100, 100];   // 100% YES for each class
```

## Troubleshooting

### "OrgDeployer not found"

**Cause**: Infrastructure not deployed or `infrastructure.json` missing

**Fix**:
```bash
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast
```

### "Private key not found"

**Cause**: Environment variables not set

**Fix**: Create `.env` file with all required private keys

### "QuickJoin: already joined"

**Cause**: Member already has a role in this org

**Fix**: Use different addresses or deploy new org with different `orgId`

### "Insufficient balance"

**Cause**: Deployer account has no ETH

**Fix**: Fund deployer account with testnet ETH

## Best Practices

### For Development

1. **Use Test Networks**: Always test on Sepolia, Base Sepolia, etc.
2. **Separate Keys**: Never reuse production keys
3. **Check Gas**: Monitor gas usage with `--gas-report`
4. **Verify Contracts**: Use `--verify` flag when deploying

### For Production

1. **Multi-sig Deployment**: Use multi-sig for deployer account
2. **Gradual Rollout**: Test each step separately before full automation
3. **Monitor Events**: Watch for `OrgDeployed`, `TaskCreated`, `ProposalCreated` events
4. **Backup Configs**: Store org configs in version control

## Extending the Script

### Add More Members

Add more private keys and replicate the onboarding pattern:

```solidity
uint256 member3Key = vm.envUint("MEMBER3_PRIVATE_KEY");
members.member3 = vm.addr(member3Key);

vm.broadcast(member3Key);
quickJoin.join();
```

### Add Education Hub Demo

Create and complete education modules:

```solidity
EducationHub hub = EducationHub(org.educationHub);

vm.broadcast(coordinatorKey);
hub.createModule("Governance 101", ...);

vm.broadcast(member1Key);
hub.completeModule(moduleId, correctAnswers);
```

### Add Payment Distribution

Demonstrate PaymentManager merkle distributions:

```solidity
PaymentManager pm = PaymentManager(org.paymentManager);

vm.broadcast(coordinatorKey);
pm.createDistribution(merkleRoot, totalAmount, ...);

vm.broadcast(member1Key);
pm.claimDistribution(proof, amount);
```

## Related Documentation

- [OrgDeployer Contract](../src/OrgDeployer.sol)
- [DeployOrg Script](./DeployOrg.s.sol)
- [TaskManager Documentation](../docs/TASK_MANAGER.md)
- [HybridVoting Documentation](../docs/HYBRID_VOTING.md)

## Support

For issues or questions:
- GitHub Issues: https://github.com/PerpetualOrganizationArchitect/POP/issues
- Documentation: https://docs.poa.coop

## License

MIT License - See LICENSE file for details
