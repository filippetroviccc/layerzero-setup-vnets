# LayerZero OFT Local Setup (Initial Scaffold)

This repository sets up a minimal local environment to experiment with Omnichain Fungible Tokens (OFTs) using official LayerZero OFTV2 contracts and the official `LZEndpointMock`.

## Layout

- `src/tokens/` — Minimal ERC20s (`TokenA`, `TokenB`) with owner minting and an assignable `minter` (the OFT).
- `src/oft/` — Thin wrappers around official OFTV2:
  - `OFT_A` (ProxyOFTV2) locks the canonical ERC20 on Chain A
  - `OFT_B` (OFTV2) mints/burns the representation on Chain B
- Official mocks from LayerZero are pulled via `solidity-examples` dependency.
- `script/` — Placeholder deploy/config scripts (no forge-std deps yet).
- `test/` — A Foundry test that validates the basic bridge flow.

## Prerequisites

- Foundry installed: `curl -L https://foundry.paradigm.xyz | bash` then `foundryup`

## Build & Test

Install dependencies (already vendored via `forge install`) and run:

```
forge build
forge test -vvv
```

`test/BridgeTest.t.sol` deploys LayerZero `LZEndpointMock` for two chain IDs, deploys `TokenA` + `OFT_A` (ProxyOFTV2) on Chain A and `OFT_B` (OFTV2) on Chain B, wires trusted remotes/min gas, then bridges tokens from Chain A to Chain B.

## How It Works (Simplified)

- `LZEndpointMock` keeps a mapping of remote endpoints by chain ID and forwards payloads to the remote OFT.
- `SimpleOFT` stores a `trustedRemoteOFT` per chain. `sendToChain` burns local tokens then asks the mock endpoint to deliver a mint request to the remote OFT, which mints on receipt.
- `SimpleERC20` supports `ownerMint` (bootstrap supply) and a `minter` (the OFT) that can `mint`/`burnFrom` for bridging.

## Next Steps (per PRD)

- Optionally replace the mocks with real LayerZero endpoints on testnets.
- Convert `script/*.s.sol` to use `forge-std/Script.sol` and point at two Anvil nodes via `--rpc-url` flags.
- Expand tests to cover allowances, reentrancy and failure scenarios.

## Two-Node Local Run (future wiring)

When ready to split across two local chains, run two Anvil instances and use forge scripts:

```
# Terminal 1
anvil --port 8545 --chain-id 101

# Terminal 2
anvil --port 9545 --chain-id 102

# Then replace placeholder scripts with forge-std variants to deploy to each RPC and configure remotes/trusted peers.
```
