/*
Simple executor agent for local dev.
Env:
  - RPC_URL_A (or B)
  - VERIFIER_ADDR
  - EXECUTOR_ADDR (Executor contract wired to the source endpoint)
  - PRIVATE_KEY
*/
import 'dotenv/config';
import { ethers } from "ethers";

const verifierAbi = [
  "event Verified(bytes32 indexed messageId, address indexed submitter)"
];
const executorAbi = [
  "function execute(bytes32 messageId) external"
];

async function main() {
  const rpcHttp = process.env.RPC_URL_A || process.env.RPC_URL || "http://127.0.0.1:8545";
  const rpcWs = process.env.WS_RPC_URL_A || process.env.WS_RPC_URL; // optional
  const pk = process.env.PRIVATE_KEY || "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"; // anvil default[0]
  const verifierAddr = process.env.VERIFIER_ADDR!;
  const executorAddr = process.env.EXECUTOR_ADDR!;
  if (!verifierAddr || !executorAddr) throw new Error("Missing VERIFIER_ADDR or EXECUTOR_ADDR envs");

  const chosenUrl = rpcWs && rpcWs.length > 0 ? rpcWs : rpcHttp;
  const isWs = /^wss?:/i.test(chosenUrl);
  const provider = isWs
    ? new ethers.WebSocketProvider(chosenUrl)
    : new ethers.JsonRpcProvider(chosenUrl);
  const pollMs = Number(process.env.POLL_INTERVAL_MS || 2000);
  if (!isWs && typeof (provider as any).setPollInterval === 'function') {
    (provider as any).setPollInterval(pollMs);
  }
  const wallet = new ethers.Wallet(pk, provider);

  const verifier = new ethers.Contract(verifierAddr, verifierAbi, provider);
  const executor = new ethers.Contract(executorAddr, executorAbi, wallet);

  const eventSig = ethers.id("Verified(bytes32,address)");
  const filter = { address: verifierAddr, topics: [eventSig] };

  const net = await provider.getNetwork();
  const latest = await provider.getBlockNumber();
  const lookback = Number(process.env.LOOKBACK_BLOCKS || 5000);
  const startBlock = process.env.START_BLOCK ? Number(process.env.START_BLOCK) : Math.max(0, Number(latest) - lookback);
  console.log(`Executor starting. chainId=${net.chainId} verifier=${verifierAddr} executor=${executorAddr}`);
  console.log(`RPC URL=${chosenUrl}`);
  console.log(`Provider=${provider.constructor.name} startBlock=${startBlock} latest=${latest}`);

  const iface = new ethers.Interface(verifierAbi);
  const seen = new Set<string>();
  let lastScanned = startBlock;

  async function handleLog(log: ethers.Log) {
    try {
      const parsed = iface.parseLog(log);
      const messageId: string = parsed.args[0];
      if (seen.has(messageId)) return;
      console.log("Verified:", messageId, `at block ${log.blockNumber}`);
      try {
        const tx = await executor.execute(messageId);
        await tx.wait();
        console.log("Delivered:", messageId);
      } catch (err: any) {
        const msg = String(err?.message || err);
        if (msg.includes("revert") || msg.toLowerCase().includes("already")) {
          console.warn("execute skipped:", messageId, msg);
        } else {
          console.error("execute error", err);
        }
      }
      seen.add(messageId);
    } catch (e) {
      console.error("parse/execute error", e);
    }
  }

  // Backfill historical range in chunks
  const maxRange = Number(process.env.SCAN_RANGE || 2000);
  let tip = await provider.getBlockNumber();
  while (lastScanned <= tip) {
    const from = lastScanned;
    const to = Math.min(from + maxRange, tip);
    if (from > to) break;
    const logs = await provider.getLogs({ ...filter, fromBlock: from, toBlock: to });
    for (const log of logs) await handleLog(log);
    lastScanned = to + 1;
  }

  // Live tail: use WS logs if available, else poll new blocks
  if (provider instanceof ethers.WebSocketProvider) {
    provider.on(filter as any, handleLog);
    console.log("Subscribed via WebSocket to Verified events.");
  } else {
    console.log("HTTP provider: polling new blocks for events.");
    provider.on("block", async (bn: number) => {
      try {
        const from = lastScanned;
        const to = bn;
        if (from > to) return;
        const logs = await provider.getLogs({ ...filter, fromBlock: from, toBlock: to });
        for (const log of logs) await handleLog(log);
        lastScanned = to + 1;
      } catch (e) {
        console.error("block poll error", e);
      }
    });
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
