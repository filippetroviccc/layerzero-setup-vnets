# PRD: Local Setup of LayerZero OFTs with Custom Tokens

## Background & Context

LayerZero provides an interoperability protocol enabling seamless messaging between blockchains. **Omnichain Fungible Tokens (OFTs)** are LayerZero’s primitive for cross-chain fungible assets.

The goal here is to stand up a local development environment with Foundry that simulates two networks. We will:

1. Deploy two ERC20-style tokens (dummy/custom implementations).
2. Wrap them as OFTs using LayerZero contracts.
3. Set up message relaying between two local chains to test token transfers.
4. Keep the system modular so later the same setup can be deployed on custom RPC networks (testnets, Tenderly Virtual TestNets, or mainnets).

---

## Goals

* Enable developers to **deploy and test OFTs locally** with two networks simulated in Foundry.
* Provide a **repeatable framework** (scripts + deployment flow) that can extend to testnets or mainnets.
* Validate full flow: token deployment → OFT configuration → message passing → token bridging.

---

## Scope

### In-Scope

* **Environment setup**: Local Foundry chains (e.g., Anvil instances) simulating two networks.
* **Token deployment**: Deploy 2 ERC20 contracts (e.g., `TokenA` and `TokenB`).
* **OFT wrapping**: Deploy OFT contracts for each token, wired to LayerZero endpoint mocks.
* **LayerZero config**: Deploy mock LayerZero endpoint contracts for each chain. Configure them to know about each other.
* **Bridge test flow**: Write Foundry tests & scripts to:

    * Mint tokens on chain A.
    * Send tokens to chain B through OFT.
    * Validate balances before/after.
* **Scripts**: Deployment scripts + interaction scripts in Solidity/Foundry.

### Out of Scope

* No production mainnet/testnet deployments (but should be extendable).
* No UI frontend. CLI/Foundry scripts only.
* No advanced LayerZero relayer configurations (use mock endpoints).

---

## Strategic Fit

* Serves as a **foundation** for Tenderly’s Virtual TestNet integrations.
* Enables **rapid experimentation** with cross-chain token flows locally.
* Positions the project for **extending to custom RPCs** with minimal friction.

---

## Technical Specification

### Contracts

1. **ERC20 tokens**

    * `TokenA.sol`, `TokenB.sol` (basic OpenZeppelin ERC20).

2. **OFT contracts**

    * Use LayerZero’s OFT implementation (OFTV2 recommended).
    * Each token gets its OFT wrapper.

3. **LayerZero endpoint mocks**

    * `LZEndpointMock.sol` for both chains.
    * Configure them to map chain IDs (e.g., `chainA = 101`, `chainB = 102`).

---

### Deployment Flow

1. **Start 2 Foundry nodes** (simulate two local chains).

2. **Deploy contracts on Chain A**:

    * `TokenA`
    * `OFT_A` (pointing to LZ endpoint mock A)
    * `LZEndpointMockA`

3. **Deploy contracts on Chain B**:

    * `TokenB`
    * `OFT_B` (pointing to LZ endpoint mock B)
    * `LZEndpointMockB`

4. **Configure endpoints**:

    * Map Chain A ↔ Chain B in both mocks.

5. **Register OFTs**:

    * Set trusted remotes between OFT\_A and OFT\_B.

6. **Test bridging**:

    * Mint TokenA on Chain A.
    * Call OFT\_A to send to Chain B.
    * Verify TokenB minted (or reflected) on Chain B.

---

### Deliverables

* **Contracts**:

    * `TokenA.sol`, `TokenB.sol`
    * `OFT_A.sol`, `OFT_B.sol` (inherit OFTV2)
* **Scripts**:

    * `Deploy.s.sol` (Foundry deployment script for both chains)
    * `Config.s.sol` (script to wire up endpoints/trusted remotes)
    * `BridgeTest.t.sol` (unit/integration tests for bridging)
* **Docs**:

    * `README.md` with setup steps: run local nodes, deploy, config, test bridge.

---

## Success Metrics

* Deployments succeed on two local networks with mock LZ endpoints.
* A minted token on Chain A can be successfully bridged and reflected on Chain B.
* Full flow reproducible with single `make test` or Foundry script command.

---

## Future Extensions

* Swap `LZEndpointMock` with real LayerZero endpoints on testnets.
* Extend to multi-chain setups (3+ chains).
* Add Tenderly Virtual TestNet config (auto-deploy flows).
* Add support for custom relayer configuration.
