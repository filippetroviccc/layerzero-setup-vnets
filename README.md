# LayerZero OFT Local Setup (Endpoint V2 Mock)

This repository sets up a local development environment to experiment with Omnichain Fungible Tokens (OFTs) on top of a LayerZero
Endpoint V2–style mock. Messages emit the real `PacketSent`, `PacketVerified`, and `PacketDelivered` events, and delivery is gate
ed by an explicit verifier/executor pair so the flow mirrors the production pipeline.

## Layout

- `src/tokens/` — Minimal ERC20s (`TokenA`, `TokenB`) with owner minting and an assignable `minter`.
- `src/oft/` — Lightweight OFT adapters built for the mock endpoint:
  - `OFT_A` locks the canonical ERC20 on chain A.
  - `OFT_B` mints/burns a representation on chain B.
- `src/layerzero/GatedEndpointV2Mock.sol` — Endpoint V2 mock that queues packets, emits canonical events, and requires an autho
rized verifier/executor to progress messages.
- `src/infra/Executor.sol` — Minimal executor contract the off-chain agent calls to trigger delivery.
- `script/` — Convenience deploy helper that wires peers, executors, and verifiers.
- `test/` — A Foundry test covering the full bridge flow using the new endpoint.
- `agents/` — TypeScript verifier/executor agents that react to `PacketSent` / `PacketVerified`.

## Prerequisites

- Foundry installed: `curl -L https://foundry.paradigm.xyz | bash` then `foundryup`.
- Node.js 18+ for the TypeScript agents.

## Build & Test

Run the standard Foundry commands:

```
forge build
forge test -vvv
```

`test/BridgeTest.t.sol` deploys two `GatedEndpointV2Mock` instances for endpoint IDs 101 and 102, sets up `TokenA` + `OFT_A` on
chain A and `OFT_B` on chain B, wires peers, and demonstrates that bridging requires:

1. `PacketSent` on the source endpoint → verifier agent calls `verify(origin, receiver, payloadHash)` on the destination endpoin
t.
2. `PacketVerified` on the destination endpoint → executor agent calls the on-chain `Executor`, which in turn calls `deliver(gui
d, extraData)` on the endpoint.
3. `PacketDelivered` fires once `lzReceive` succeeds on the destination OFT.

## How It Works

- `GatedEndpointV2Mock` stores outbound packets by GUID, exposes view helpers, and enforces the same origin/nonce bookkeeping as
 the production endpoint. Verifier/executor addresses are configurable via `setVerifier`/`setExecutor`.
- `BaseOFTV2` abstracts the OFT send/receive logic. Derived contracts implement `_debit` / `_credit` to lock or mint tokens and
 configure peers with `setPeer(eid, peer)`.
- `Executor` is a thin proxy contract so the off-chain agent can call `execute(guid)`; the endpoint checks that the caller is the
 registered executor before delivering the packet.

## Off-Chain Agents

- `agents/verifier-agent.ts` listens for `PacketSent` on the source endpoint, decodes the packet, and calls `verify` on the desti
nation endpoint using the configured signer.
- `agents/executor-agent.ts` listens for `PacketVerified` on the destination endpoint, computes the GUID, and calls `Executor.exe
cute(guid)`.

Environment variables (shared by both agents):

- `RPC_URL` or `RPC_URL_A/B` (HTTP)
- `WS_RPC_URL` or `WS_RPC_URL_A/B` (optional WebSocket; enables live subscriptions)
- `SOURCE_ENDPOINT` / `DEST_ENDPOINT` (endpoints emitting the events)
- `EXECUTOR_ADDR` (executor contract to call)
- `PRIVATE_KEY` (controls both the verifier and executor transactions)
- Scanning controls: `START_BLOCK`, `LOOKBACK_BLOCKS` (default 5000), `POLL_INTERVAL_MS` (default 2000), `SCAN_RANGE` (default 200
0)

Run the agents via npm scripts:

- Development (tsx):
  - `npm run agent:verifier`
  - `npm run agent:executor`
- Compiled JS:
  - `npm run agent:verifier:dist`
  - `npm run agent:executor:dist`

## Quick Start with Tenderly RPC

- Deploy contracts and auto-write `.env` using the helper script:

  - `npm run deploy:oft` (defaults to `https://virtual.mainnet.eu.rpc.tenderly.co/f09a8ab7-aa41-4acb-811c-88161d25a778`)

- Run agents (two terminals):

  - `npm run agent:verifier`
  - `npm run agent:executor`

- Trigger a bridge (mints, approves, quotes, sends):

  - `npm run bridge`
  - Override env path with `ENV_PATH=./.env npm run bridge`

The deploy helper writes endpoint/OFT/executor addresses, default options, and RPC URLs to `.env` so the agents and helper share
 configuration.

Bridge helper envs:

- Reads addresses and RPC from `.env` by default; override path with `ENV_PATH=/path/to/.env`.
- If `.env` contains a WebSocket-only RPC, set `HTTP_RPC_URL` or rely on the helper’s automatic replacement of `wss://` → `https:
//`.

## Two-Node Local Run (future wiring)

When ready to split across two local chains, run two Anvil instances and point the deploy/agent scripts at each RPC:

```
# Terminal 1
anvil --port 8545 --chain-id 101

# Terminal 2
anvil --port 9545 --chain-id 102
```

Then deploy endpoints/OFTs to the respective RPCs, configure `setRemoteEndpoint`, `setPeer`, `setVerifier`, and `setExecutor`, a
nd run the agents against the appropriate endpoints.
