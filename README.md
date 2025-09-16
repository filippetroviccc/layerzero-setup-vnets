# LayerZero OFT Local Setup (Initial Scaffold)

This repository sets up a local environment to experiment with Omnichain Fungible Tokens (OFTs) using OFTV2 and a gated LayerZero endpoint mock that requires a Verifier + Executor, per the PRD.

## Layout

- `src/tokens/` — Minimal ERC20s (`TokenA`, `TokenB`) with owner minting and an assignable `minter` (the OFT).
- `src/oft/` — Thin wrappers around official OFTV2:
  - `OFT_A` (ProxyOFTV2) locks the canonical ERC20 on Chain A
  - `OFT_B` (OFTV2) mints/burns the representation on Chain B
- `src/layerzero/GatedLZEndpointMock.sol` — Endpoint mock that enqueues messages and requires verification + execution
- `src/infra/Verifier.sol` — Off-chain agent submits `messageId` attestations
- `src/infra/Executor.sol` — Called by off-chain agent to trigger delivery on the endpoint
- Official examples from LayerZero are pulled via `solidity-examples` dependency.
- `script/` — Placeholder deploy/config scripts (no forge-std deps yet).
- `test/` — A Foundry test that validates the basic bridge flow.
 - `agents/` — Minimal TypeScript agents to simulate verifier/executor off-chain

## Prerequisites

- Foundry installed: `curl -L https://foundry.paradigm.xyz | bash` then `foundryup`

## Build & Test

Install dependencies (already vendored via `forge install`) and run:

```
forge build
forge test -vvv
```

`test/BridgeTest.t.sol` deploys gated endpoints for two chain IDs, deploys `TokenA` + `OFT_A` (ProxyOFTV2) on Chain A and `OFT_B` (OFTV2) on Chain B, wires trusted remotes/min gas, then demonstrates that bridging requires:

- Verifier to attest the queued message id
- Executor to call the endpoint to deliver

## How It Works (Simplified)

- `GatedLZEndpointMock` keeps a mapping of remote endpoints by chain ID and enqueues payloads.
- Verifier must mark the `messageId` as verified before delivery.
- Executor triggers delivery which calls `lzReceive` on the destination OFT.
- `SimpleOFT` stores a `trustedRemoteOFT` per chain. `sendToChain` burns local tokens then asks the mock endpoint to deliver a mint request to the remote OFT, which mints on receipt.
- `SimpleERC20` supports `ownerMint` (bootstrap supply) and a `minter` (the OFT) that can `mint`/`burnFrom` for bridging.

## Off-Chain Agents (local)

- `agents/verifier-agent.ts`: listens for `MessageQueued` on the source endpoint and calls `Verifier.submitAttestation(messageId)`.
- `agents/executor-agent.ts`: listens for `Verified` and calls `Executor.execute(messageId)`.

Setup:
- Copy `.env.example` to `.env` and fill addresses.
- Install deps: `npm install`

Env variables:
- `RPC_URL` or `RPC_URL_A` (HTTP)
- `WS_RPC_URL` or `WS_RPC_URL_A` (optional WebSocket; enables live subscriptions)
- `ENDPOINT_ADDR` (verifier agent)
- `VERIFIER_ADDR`
- `EXECUTOR_ADDR` (executor agent)
- `PRIVATE_KEY` (Anvil’s default works for local)
- Scanning controls (to avoid missing events): `START_BLOCK`, `LOOKBACK_BLOCKS` (default 5000), `POLL_INTERVAL_MS` (default 2000), `SCAN_RANGE` (default 2000)

Run agents with npm scripts:
- Preferred (TypeScript via tsx):
  - `npm run agent:verifier`
  - `npm run agent:executor`
- If your environment struggles with ESM loaders, run compiled JS:
  - `npm run agent:verifier:dist`
  - `npm run agent:executor:dist`

See RUNBOOK.md for a full step-by-step deployment and run guide.

## Quick Start with Tenderly RPC

- Deploy contracts and auto-write `.env` using your Tenderly endpoint:

  - `npm run deploy:oft` (uses `https://virtual.mainnet.eu.rpc.tenderly.co/f09a8ab7-aa41-4acb-811c-88161d25a778` by default)

- Run agents (two terminals):

  - `npm run agent:verifier`
  - `npm run agent:executor`

- Trigger a bridge (mints, approves, estimates, and sends):

  - `npm run bridge`
  - Optional: `ENV_PATH=./.env npm run bridge` to specify a different env file

The deploy script writes all addresses to `.env` and sets `RPC_URL` so the agents and bridge helper use the same network.

Bridge helper envs:
- Reads addresses and RPC from `.env` by default; override path with `ENV_PATH=/path/to/.env`.
- If `.env` contains a WebSocket-only `RPC_URL`, set `HTTP_RPC_URL` to the HTTPS Tenderly endpoint for `cast` commands; otherwise it will auto-derive HTTP by replacing `wss://` with `https://`.

## Two-Node Local Run (future wiring)

When ready to split across two local chains, run two Anvil instances and use forge scripts:

```
# Terminal 1
anvil --port 8545 --chain-id 101

# Terminal 2
anvil --port 9545 --chain-id 102

# Then replace placeholder scripts with forge-std variants to deploy to each RPC, configure remotes/trusted peers, and set endpoint verifier/executor addresses.
```
