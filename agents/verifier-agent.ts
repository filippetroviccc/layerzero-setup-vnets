/*
Simple verifier agent for local dev.
Env:
  - RPC_URL_A (or B)
  - VERIFIER_ADDR
  - ENDPOINT_ADDR (GatedLZEndpointMock on source chain)
  - PRIVATE_KEY
*/
import 'dotenv/config';
import { ethers } from "ethers";

const endpointAbi = [
  "event MessageQueued(bytes32 indexed messageId, uint16 indexed srcChainId, uint16 indexed dstChainId, address srcUa, address dstUa, uint64 nonce, bytes32 payloadHash)"
];
const verifierAbi = [
  "function submitAttestation(bytes32 messageId) external",
];

async function main() {
  const rpc = process.env.RPC_URL_A || process.env.RPC_URL || "http://127.0.0.1:8545";
  const pk = process.env.PRIVATE_KEY || "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"; // anvil default[0]
  const endpointAddr = process.env.ENDPOINT_ADDR!;
  const verifierAddr = process.env.VERIFIER_ADDR!;

  if (!endpointAddr || !verifierAddr) throw new Error("Missing ENDPOINT_ADDR or VERIFIER_ADDR envs");

  const provider = new ethers.JsonRpcProvider(rpc);
  const wallet = new ethers.Wallet(pk, provider);

  const endpoint = new ethers.Contract(endpointAddr, endpointAbi, provider);
  const verifier = new ethers.Contract(verifierAddr, verifierAbi, wallet);

  console.log("Verifier agent listening on", endpointAddr);

  endpoint.on("MessageQueued", async (messageId: string) => {
    try {
      console.log("MessageQueued:", messageId);
      const tx = await verifier.submitAttestation(messageId);
      await tx.wait();
      console.log("Verified:", messageId);
    } catch (e) {
      console.error("verify error", e);
    }
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
