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
  const rpc = process.env.RPC_URL_A || process.env.RPC_URL || "http://127.0.0.1:8545";
  const pk = process.env.PRIVATE_KEY || "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"; // anvil default[0]
  const verifierAddr = process.env.VERIFIER_ADDR!;
  const executorAddr = process.env.EXECUTOR_ADDR!;
  if (!verifierAddr || !executorAddr) throw new Error("Missing VERIFIER_ADDR or EXECUTOR_ADDR envs");

  const provider = new ethers.JsonRpcProvider(rpc);
  const wallet = new ethers.Wallet(pk, provider);

  const verifier = new ethers.Contract(verifierAddr, verifierAbi, provider);
  const executor = new ethers.Contract(executorAddr, executorAbi, wallet);

  console.log("Executor agent listening for Verified on", verifierAddr);

  verifier.on("Verified", async (messageId: string) => {
    try {
      console.log("Verified:", messageId, "-> executing");
      const tx = await executor.execute(messageId);
      await tx.wait();
      console.log("Delivered:", messageId);
    } catch (e) {
      console.error("execute error", e);
    }
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
