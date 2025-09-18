/*
Verifier agent for the v2 mock endpoint.
Env:
  - RPC_URL (or WS_RPC_URL)
  - SOURCE_ENDPOINT (emits PacketSent)
  - DEST_ENDPOINT (where verify is invoked)
  - PRIVATE_KEY
*/
import 'dotenv/config';
import { ethers } from "ethers";

const endpointAbi = [
  "event PacketSent(bytes encodedPayload, bytes options, address sendLibrary)"
];

const destAbi = [
  "function verify((uint32 srcEid, bytes32 sender, uint64 nonce) origin, address receiver, bytes32 payloadHash) external"
];

const abiCoder = ethers.AbiCoder.defaultAbiCoder();

function bytes32ToAddress(value: string): string {
  return ethers.getAddress(ethers.dataSlice(value, 12));
}

type Origin = { srcEid: number; sender: string; nonce: bigint; };

type DecodedPacket = {
  origin: Origin;
  dstEid: number;
  receiver: string;
  guid: string;
  message: string;
};

function decodePacket(data: string): DecodedPacket {
  const decoded = abiCoder.decode(
    [
      "tuple(uint32 srcEid, bytes32 sender, uint64 nonce)",
      "uint32",
      "bytes32",
      "bytes32",
      "bytes"
    ],
    data
  );
  const originTuple = decoded[0] as any;
  const origin: Origin = {
    srcEid: Number(originTuple[0]),
    sender: originTuple[1],
    nonce: BigInt(originTuple[2])
  };
  const dstEid = Number(decoded[1]);
  const receiver = bytes32ToAddress(decoded[2]);
  const guid = decoded[3] as string;
  const message = decoded[4] as string;
  return { origin, dstEid, receiver, guid, message };
}

async function main() {
  const rpcHttp = process.env.RPC_URL || process.env.RPC_URL_A || "http://127.0.0.1:8545";
  const rpcWs = process.env.WS_RPC_URL || process.env.WS_RPC_URL_A;
  const pk = process.env.PRIVATE_KEY || "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
  const sourceEndpoint = process.env.SOURCE_ENDPOINT || process.env.ENDPOINT_ADDR;
  const destEndpoint = process.env.DEST_ENDPOINT || process.env.DEST_ENDPOINT_ADDR;

  if (!sourceEndpoint || !destEndpoint) {
    throw new Error("Missing SOURCE_ENDPOINT or DEST_ENDPOINT environment variables");
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
  const dest = new ethers.Contract(destEndpoint, destAbi, wallet);
  const endpointIface = new ethers.Interface(endpointAbi);

  const eventSig = ethers.id("PacketSent(bytes,bytes,address)");
  const filter = { address: sourceEndpoint, topics: [eventSig] };

  const seen = new Set<string>();
  let lastScanned = process.env.START_BLOCK ? Number(process.env.START_BLOCK) : 0;
  const lookback = Number(process.env.LOOKBACK_BLOCKS || 5000);
  if (!process.env.START_BLOCK) {
    const latest = await provider.getBlockNumber();
    lastScanned = Math.max(0, latest - lookback);
  }

  console.log(`Verifier agent starting. endpoint=${sourceEndpoint} dest=${destEndpoint}`);
  console.log(`Using provider=${provider.constructor.name} url=${chosenUrl}`);

  async function handleLog(log: ethers.Log) {
    try {
      const parsed = endpointIface.parseLog(log);
      const encoded = parsed.args[0] as string;
      const packet = decodePacket(encoded);
      if (seen.has(packet.guid)) return;
      const payloadHash = ethers.keccak256(packet.message);
      console.log(`PacketSent guid=${packet.guid} srcEid=${packet.origin.srcEid} dstEid=${packet.dstEid} nonce=${packet.origin.nonce}`);
      const tx = await dest.verify(packet.origin, packet.receiver, payloadHash);
      await tx.wait();
      console.log(`verify() submitted guid=${packet.guid} tx=${tx.hash}`);
      seen.add(packet.guid);
    } catch (err) {
      console.error("verify handler error", err);
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
    console.log("Subscribed to PacketSent via WebSocket");
  } else {
    console.log("HTTP provider: polling new blocks for PacketSent");
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
