#!/usr/bin/env node
/**
 * cashout-e2e.mjs — End-to-end USDC → Venmo cashout test
 *
 * Uses Bungee depositRoute (simple transfer, no Permit2) + manual trigger.
 *
 * Prerequisites:
 *   1. Deploy CashOutRelay on Base:
 *      forge script script/DeployCashOutRelay.s.sol:Step1_DeployRelayOnBase \
 *        --rpc-url base --broadcast --slow --private-key $DEPLOYER_PRIVATE_KEY
 *
 *   2. source .env && export DEPLOYER_PRIVATE_KEY
 *
 *   3. CASHOUT_RELAY_ADDRESS=0x... VENMO_USERNAME=hudsonhrh CASHOUT_AMOUNT=10 node script/cashout-e2e.mjs
 */

import { createWalletClient, createPublicClient, http, encodeFunctionData, encodeAbiParameters, parseAbiParameters, keccak256, toBytes, parseUnits, formatUnits } from 'viem';
import { arbitrum, base } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';

// ── Config ──
const PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY;
const RELAY_ADDRESS = process.env.CASHOUT_RELAY_ADDRESS;
const VENMO_USERNAME = process.env.VENMO_USERNAME || 'hudsonhrh';
const CASHOUT_AMOUNT = process.env.CASHOUT_AMOUNT || '10';
const ARB_RPC = process.env.ARB_RPC || 'https://arb-mainnet.g.alchemy.com/v2/REDACTED_ALCHEMY_KEY';
const BASE_RPC = process.env.BASE_RPC || 'https://base.drpc.org';

// ── Addresses ──
const ARB_USDC = '0xaf88d065e77c8cC2239327C5EDb3A432268e5831';
const BASE_USDC = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const BUNGEE_API = 'https://public-backend.bungee.exchange/api';

// ── ABIs ──
const ERC20_ABI = [
  { type: 'function', name: 'approve', inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
  { type: 'function', name: 'balanceOf', inputs: [{ name: 'account', type: 'address' }], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'transfer', inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [{ type: 'bool' }] },
];

const RELAY_ABI = [
  {
    type: 'function', name: 'createDepositFromBalance',
    inputs: [{
      name: 'params', type: 'tuple',
      components: [
        { name: 'depositor', type: 'address' },
        { name: 'paymentMethod', type: 'bytes32' },
        { name: 'payeeDetailsHash', type: 'bytes32' },
        { name: 'fiatCurrency', type: 'bytes32' },
        { name: 'conversionRate', type: 'uint256' },
        { name: 'minIntentAmount', type: 'uint256' },
        { name: 'maxIntentAmount', type: 'uint256' },
      ],
    }],
    outputs: [],
  },
  { type: 'function', name: 'totalFailedAmount', inputs: [], outputs: [{ type: 'uint256' }] },
];

function log(msg) { console.log(`[${new Date().toISOString().slice(11, 19)}] ${msg}`); }
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function main() {
  if (!PRIVATE_KEY) throw new Error('Set DEPLOYER_PRIVATE_KEY');
  if (!RELAY_ADDRESS) throw new Error('Set CASHOUT_RELAY_ADDRESS');

  const account = privateKeyToAccount(PRIVATE_KEY.startsWith('0x') ? PRIVATE_KEY : `0x${PRIVATE_KEY}`);
  const amountWei = parseUnits(CASHOUT_AMOUNT, 6);

  log(`Wallet: ${account.address}`);
  log(`Relay: ${RELAY_ADDRESS}`);
  log(`Venmo: @${VENMO_USERNAME}`);
  log(`Amount: ${CASHOUT_AMOUNT} USDC`);
  console.log();

  const arbPublic = createPublicClient({ chain: arbitrum, transport: http(ARB_RPC) });
  const arbWallet = createWalletClient({ account, chain: arbitrum, transport: http(ARB_RPC) });
  const basePublic = createPublicClient({ chain: base, transport: http(BASE_RPC) });
  const baseWallet = createWalletClient({ account, chain: base, transport: http(BASE_RPC) });

  // Check balance
  const balance = await arbPublic.readContract({ address: ARB_USDC, abi: ERC20_ABI, functionName: 'balanceOf', args: [account.address] });
  log(`USDC balance on Arb: ${formatUnits(balance, 6)}`);
  if (balance < amountWei) throw new Error(`Insufficient USDC`);

  // ══════════════════════════════════════════
  // Step 1: Register Venmo with ZKP2P
  // ══════════════════════════════════════════
  log('Step 1: Registering Venmo...');
  const curatorRes = await fetch('https://api.peer.xyz/v1/makers/create', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ processorName: 'venmo', depositData: { venmoUsername: VENMO_USERNAME } }),
  });
  const curatorData = await curatorRes.json();
  if (!curatorData.success) throw new Error(`Curator: ${curatorData.message}`);
  const payeeDetailsHash = curatorData.responseObject.hashedOnchainId;
  log(`Payee hash: ${payeeDetailsHash}`);

  // ══════════════════════════════════════════
  // Step 2: Get Bungee depositRoute quote
  // ══════════════════════════════════════════
  log('Step 2: Getting Bungee quote (depositRoute)...');
  const quoteParams = new URLSearchParams({
    originChainId: '42161',
    destinationChainId: '8453',
    inputToken: ARB_USDC,
    outputToken: BASE_USDC,
    inputAmount: amountWei.toString(),
    userAddress: account.address,
    receiverAddress: RELAY_ADDRESS,
  });

  const quoteRes = await fetch(`${BUNGEE_API}/v1/bungee/quote?${quoteParams}`, {
    headers: { 'User-Agent': 'POA-CashOut/1.0' },
  });
  const quoteData = await quoteRes.json();
  if (!quoteData.success) throw new Error(`Bungee: ${quoteData.message}`);

  const depositRoute = quoteData.result.depositRoute;
  if (!depositRoute) throw new Error('No depositRoute available');

  const txData = depositRoute.txData;
  const output = depositRoute.output;
  log(`Output: ${formatUnits(BigInt(output.amount), 6)} USDC on Base`);
  log(`Estimated time: ${depositRoute.estimatedTime}s`);
  log(`Deposit address: ${depositRoute.depositAddress}`);

  // ══════════════════════════════════════════
  // Step 3: Send USDC to Bungee deposit address
  // ══════════════════════════════════════════
  log('Step 3: Transferring USDC to Bungee...');

  // The txData.data is already the encoded transfer call
  const bridgeTx = await arbWallet.sendTransaction({
    to: txData.to,
    data: txData.data,
    value: BigInt(txData.value || 0),
  });
  log(`Bridge tx: ${bridgeTx}`);
  log(`Arbiscan: https://arbiscan.io/tx/${bridgeTx}`);

  const receipt = await arbPublic.waitForTransactionReceipt({ hash: bridgeTx });
  if (receipt.status !== 'success') throw new Error('Bridge tx failed!');
  log('Transfer confirmed on Arbitrum!');

  // ══════════════════════════════════════════
  // Step 4: Poll until USDC arrives at relay on Base
  // ══════════════════════════════════════════
  log('Step 4: Waiting for bridge (~2-20 min)...');
  let relayBalance = 0n;
  for (let i = 0; i < 240; i++) {
    await sleep(5000);
    relayBalance = await basePublic.readContract({
      address: BASE_USDC, abi: ERC20_ABI, functionName: 'balanceOf', args: [RELAY_ADDRESS],
    });
    const failedAmount = await basePublic.readContract({
      address: RELAY_ADDRESS, abi: RELAY_ABI, functionName: 'totalFailedAmount',
    });
    const available = relayBalance - failedAmount;
    if (i % 6 === 0) log(`  Relay balance: ${formatUnits(relayBalance, 6)} USDC (available: ${formatUnits(available, 6)}) — ${i * 5}s`);
    if (available > 0n) {
      log(`USDC arrived at relay! ${formatUnits(available, 6)} USDC available`);
      break;
    }
  }

  if (relayBalance === 0n) throw new Error('Bridge timed out — USDC never arrived at relay');

  // ══════════════════════════════════════════
  // Step 5: Trigger ZKP2P deposit on Base
  // ══════════════════════════════════════════
  log('Step 5: Creating ZKP2P deposit on Base...');

  const cashOutParams = {
    depositor: account.address,
    paymentMethod: keccak256(toBytes('venmo')),
    payeeDetailsHash,
    fiatCurrency: keccak256(toBytes('USD')),
    conversionRate: parseUnits('1', 18), // 1:1
    minIntentAmount: parseUnits('1', 6), // $1 min
    maxIntentAmount: relayBalance, // full amount
  };

  const triggerTx = await baseWallet.writeContract({
    address: RELAY_ADDRESS,
    abi: RELAY_ABI,
    functionName: 'createDepositFromBalance',
    args: [cashOutParams],
  });
  log(`Trigger tx: ${triggerTx}`);
  log(`Basescan: https://basescan.org/tx/${triggerTx}`);

  const triggerReceipt = await basePublic.waitForTransactionReceipt({ hash: triggerTx });
  if (triggerReceipt.status !== 'success') throw new Error('Trigger tx failed!');

  // Check if deposit was created or failed
  const finalBalance = await basePublic.readContract({
    address: BASE_USDC, abi: ERC20_ABI, functionName: 'balanceOf', args: [RELAY_ADDRESS],
  });
  const finalFailed = await basePublic.readContract({
    address: RELAY_ADDRESS, abi: RELAY_ABI, functionName: 'totalFailedAmount',
  });

  if (finalFailed > 0n) {
    log(`WARNING: Deposit creation failed. ${formatUnits(finalFailed, 6)} USDC held for recovery.`);
    log('Call recoverFailed() to get your USDC back.');
  } else {
    log('');
    log('=== SUCCESS! ===');
    log(`ZKP2P deposit created! ${formatUnits(relayBalance, 6)} USDC listed for sale.`);
    log(`Venmo: @${VENMO_USERNAME}`);
    log('A P2P buyer will send USD to your Venmo. Check peer.xyz to monitor.');
    log(`Relay balance: ${formatUnits(finalBalance, 6)} USDC (should be 0)`);
  }
}

main().catch(e => {
  console.error('\nFATAL:', e.message);
  process.exit(1);
});
