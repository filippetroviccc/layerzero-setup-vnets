/*
Executor agent for the v2 mock endpoint.
Env:
  - RPC_URL (or WS_RPC_URL)
  - DEST_ENDPOINT (emits PacketVerified)
  - EXECUTOR_ADDR (Executor contract wired to the endpoint)
  - PRIVATE_KEY
*/
import 'dotenv/config';
import { ethers } from "ethers";

const endpointAbi = [
  "event PacketVerified((uint32 srcEid, bytes32 sender, uint64 nonce) origin, address receiver, bytes32 payloadHash)",
  "function eid() external view returns (uint32)"
];

const executorAbi = [
  "function execute(bytes32 guid) external"
];

const abiCoder = ethers.AbiCoder.defaultAbiCoder();

function addressToBytes32(addr: string): string {
  return ethers.zeroPadValue(addr, 32);
}

function computeGuid(origin: { srcEid: number; sender: string; nonce: bigint }, dstEid: number, receiver: string): string {
  return ethers.keccak256(
    ethers.solidityPacked(
      ["uint64", "uint32", "bytes32", "uint32", "bytes32"],
      [origin.nonce, origin.srcEid, origin.sender, dstEid, addressToBytes32(receiver)]
    )
  );
}

async function main() {
  const rpcHttp = process.env.RPC_URL || process.env.RPC_URL_B || "http://127.0.0.1:8545";
  const rpcWs = process.env.WS_RPC_URL || process.env.WS_RPC_URL_B;
  const pk = process.env.PRIVATE_KEY || "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
  const destEndpoint = process.env.DEST_ENDPOINT || process.env.ENDPOINT_ADDR;
  const executorAddr = process.env.EXECUTOR_ADDR;

  if (!destEndpoint || !executorAddr) {
    throw new Error("Missing DEST_ENDPOINT or EXECUTOR_ADDR environment variables");
  }

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
  const executor = new ethers.Contract(executorAddr, executorAbi, wallet);
  const endpoint = new ethers.Contract(destEndpoint, endpointAbi, provider);

  const dstEid: number = Number(await endpoint.eid());
  console.log(`Executor agent starting. endpoint=${destEndpoint} executor=${executorAddr} dstEid=${dstEid}`);
  console.log(`Using provider=${provider.constructor.name} url=${chosenUrl}`);

  const eventSig = ethers.id("PacketVerified((uint32,bytes32,uint64),address,bytes32)");
  const filter = { address: destEndpoint, topics: [eventSig] };
  const iface = new ethers.Interface(endpointAbi);
  const seen = new Set<string>();

  let lastScanned = process.env.START_BLOCK ? Number(process.env.START_BLOCK) : 0;
  const lookback = Number(process.env.LOOKBACK_BLOCKS || 5000);
  if (!process.env.START_BLOCK) {
    const latest = await provider.getBlockNumber();
    lastScanned = Math.max(0, latest - lookback);
  }

  async function handleLog(log: ethers.Log) {
    try {
      const parsed = iface.parseLog(log);
      const originTuple = parsed.args[0];
      const receiver: string = parsed.args[1];
      const origin = {
        srcEid: Number(originTuple.srcEid ?? originTuple[0]),
        sender: originTuple.sender ?? originTuple[1],
        nonce: BigInt(originTuple.nonce ?? originTuple[2])
      };
      const guid = computeGuid(origin, dstEid, receiver);
      if (seen.has(guid)) return;
      console.log(`PacketVerified guid=${guid} srcEid=${origin.srcEid} nonce=${origin.nonce} receiver=${receiver}`);
      const tx = await executor.execute(guid);
      await tx.wait();
      console.log(`execute() submitted guid=${guid} tx=${tx.hash}`);
      seen.add(guid);
    } catch (err) {
      console.error("execute handler error", err);
    }
  }

  const maxRange = Number(process.env.SCAN_RANGE || 2000);
  let tip = await provider.getBlockNumber();
  while (lastScanned <= tip) {
    const from = lastScanned;
    const to = Math.min(from + maxRange, tip);
    if (from > to) break;
    const logs = await provider.getLogs({ ...filter, fromBlock: from, toBlock: to });
    for (const log of logs) await handleLog(log);
    lastScanned = to + 1;
    tip = await provider.getBlockNumber();
  }

  if (provider instanceof ethers.WebSocketProvider) {
    provider.on(filter as any, handleLog);
    console.log("Subscribed to PacketVerified via WebSocket");
  } else {
    console.log("HTTP provider: polling new blocks for PacketVerified");
    provider.on("block", async (bn: number) => {
      try {
        const from = lastScanned;
        const to = bn;
        if (from > to) return;
        const logs = await provider.getLogs({ ...filter, fromBlock: from, toBlock: to });
        for (const log of logs) await handleLog(log);
        lastScanned = to + 1;
      } catch (err) {
        console.error("poll error", err);
      }
    });
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
