# PRD: Local Setup of LayerZero OFTs with Verifier Network & Executors

## Background & Context

LayerZero enables trust-minimized cross-chain messaging. In production, its stack involves:

* **Endpoints**: contract gateways on each chain.
* **Verifiers (Oracle/Verifier Network)**: independently fetch proofs from source chain and attest.
* **Executors (Relayers)**: submit payloads to the destination chain after proofs are verified.
* **OFTs (Omnichain Fungible Tokens)**: assets that leverage LayerZero messaging to move across chains.

Earlier scope covered only endpoints + mocks. This update introduces **Verifier Network + Executors** so the dev setup mimics the full LayerZero lifecycle locally.

---

## Goals

* Provide a **local full-stack simulation** of LayerZero message flow.
* Deploy OFTs for two custom tokens, with realistic verification & execution paths.
* Demonstrate end-to-end bridging flow: send → proof → verify → execute → receive.

---

## Scope

### In-Scope

* **Environment**: Two local Foundry chains.
* **Token deployment**: Deploy two ERC20s + wrap into OFTs.
* **Endpoint deployment**: Mock endpoints on each chain.
* **Verifier Network**: Contracts + off-chain component simulating proof attestation.
* **Executor**: Off-chain service or Solidity mock that relays verified payloads.
* **End-to-end bridging flow**:

    * Mint → Send via OFT → Proof verified → Executor delivers → Balances updated.

### Out of Scope

* Decentralized verifier coordination logic (we’ll simulate with single/multi-verifier mocks).
* Economics (fees, stake, slash).
* Production endpoint contracts (use mocks).

---

## Strategic Fit

* Moves beyond simple demo to **protocol-level simulation**.
* Provides Tenderly engineering with a playground to validate **intents, bridging, and relayer flows** for Virtual TestNets.
* Foundation for building **custom Verifier/Executor layers** on top of LayerZero.

---

## Technical Specification

### Components

1. **ERC20 Tokens**

    * `TokenA.sol`, `TokenB.sol` (OpenZeppelin ERC20).

2. **OFT Contracts**

    * Wrap TokenA/TokenB with OFTV2 contracts.
    * Configurable trusted remotes.

3. **LayerZero Endpoints**

    * `LZEndpointMock.sol` for each chain.
    * Handles message passing hooks.

4. **Verifier Network**

    * **Verifier contract**: Receives source chain block hash, stores/verifies proof commitments.
    * **Verifier agent** (off-chain): Monitors Chain A, submits proof attestations to Verifier contract.
    * Minimal “multi-verifier consensus” can be simulated with quorum of N signatures.

5. **Executor**

    * **Executor contract**: Receives verified messages.
    * **Executor agent**: Listens for “message ready” events from verifier, submits payload to destination endpoint/OFT.

---

### Deployment Flow

1. **Spin up 2 Foundry chains**.

2. **Deploy on Chain A**:

    * `TokenA`
    * `OFT_A`
    * `LZEndpointMockA`

3. **Deploy on Chain B**:

    * `TokenB`
    * `OFT_B`
    * `LZEndpointMockB`

4. **Deploy Verifier Network** (shared infra, can exist per chain or centrally):

    * `Verifier.sol` (accepts proof submissions).
    * Deploy one per chain for local simulation.

5. **Deploy Executor**:

    * `Executor.sol` linked to endpoint on Chain B.
    * Configured to only execute after verifier marks proof as valid.

6. **Configure connections**:

    * Map endpoints (ChainA ↔ ChainB).
    * Register OFT\_A and OFT\_B as trusted remotes.
    * Wire verifier + executor logic into endpoint mocks.

7. **Test flow**:

    * Mint TokenA on Chain A.
    * Call OFT\_A to send tokens → emits message event.
    * Off-chain verifier agent picks event, submits proof to Verifier contract.
    * Executor agent detects verified message, calls endpoint on Chain B.
    * OFT\_B mints tokens to recipient.
    * Verify balances.

---

## Deliverables

* **Contracts**:

    * `TokenA.sol`, `TokenB.sol`
    * `OFT_A.sol`, `OFT_B.sol`
    * `LZEndpointMock.sol`
    * `Verifier.sol`, `Executor.sol`

* **Agents (off-chain)**:

    * `verifier-agent.ts` (listen, build proof, submit).
    * `executor-agent.ts` (watch verifier, deliver payload).

* **Scripts**:

    * `Deploy.s.sol` – full deployment for both chains.
    * `Config.s.sol` – set remotes, register verifier/executor.
    * `BridgeTest.t.sol` – integration test covering proof + execution flow.

* **Docs**:

    * `README.md` with step-by-step runbook.

---

## Success Metrics

* Token bridging requires both **verifier** and **executor** to succeed.
* Disabling verifier/executor should halt bridging (simulate security guarantees).
* Reproducible end-to-end test with Foundry (`forge test`) and off-chain scripts.

---

## Future Extensions

* Add **multiple verifiers** with consensus logic.
* Simulate **malicious verifier** to test fault tolerance.
* Add **economic model** (fees, slashing).
* Integrate into Tenderly VNets for multi-region cross-chain tests.
