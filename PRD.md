# PRD: Local Setup of LayerZero OFTs with Verifier & Executor Agents

## Background & Context

LayerZero Endpoint V2 emits canonical events (`PacketSent`, `PacketVerified`, `PacketDelivered`) that drive the verifier/executor
network. The goal of this repo is to mirror that flow locally by pairing a v2-compatible endpoint mock with lightweight off-chai
n agents. Developers can observe the same lifecycle as production while retaining deterministic control over who verifies and exe
cutes packets.

---

## Goals

* Provide a **full-stack simulation** of the Endpoint V2 messaging pipeline.
* Deploy OFTs on two local chains, with locking/minting semantics that follow LayerZero patterns.
* Demonstrate the full lifecycle: send → `PacketSent` → verifier submits `verify` → executor triggers delivery → balances update.

---

## Scope

### In Scope

* **Environment**: Two Foundry chains (or Tenderly RPCs) connected via the mock endpoints.
* **Tokens/OFTs**: Minimal ERC20s wrapped by custom OFTs that use the Endpoint V2 mock.
* **Endpoint Mock**: `GatedEndpointV2Mock` that stores packets, exposes view helpers, and requires authorized verifier/executor a
ctors.
* **Agents**: TypeScript services that watch on-chain events and exercise `verify` / `Executor.execute`.
* **End-to-end flow**: Mint on chain A → send → agent verifies → agent executes → recipient receives minted tokens on chain B.

### Out of Scope

* Real LayerZero Endpoint deployments (mock only).
* Decentralized verifier consensus or economic incentives.
* Advanced OFT features (fee sharing, compose options, etc.).

---

## Strategic Fit

* Gives Tenderly engineering a reproducible playground that behaves like Endpoint V2.
* Enables experimentation with intents, DVN simulations, and executor strategies before hitting real networks.
* Lays the groundwork for custom verifier/executor orchestration inside Virtual TestNets.

---

## Technical Specification

### Components

1. **ERC20 Tokens**
   * `TokenA.sol`, `TokenB.sol` (simple ownable ERC20s with configurable `minter`).

2. **OFT Contracts**
   * `BaseOFTV2` handles quote/send/receive logic against the mock endpoint.
   * `OFT_A` locks canonical liquidity; `OFT_B` mints/burns a representation.

3. **LayerZero Endpoint Mock**
   * `GatedEndpointV2Mock` implements the v2 structs/events, tracks GUIDs, and enforces verifier/executor authorization.
   * Emits the same events production infrastructure consumes.

4. **Executor Contract**
   * `Executor.sol` exposes `execute(bytes32 guid)` and forwards to `endpoint.deliver`.

5. **Off-Chain Agents**
   * **Verifier agent**: listens to `PacketSent`, decodes the packet, calls `verify` on the destination endpoint.
   * **Executor agent**: listens to `PacketVerified`, computes the GUID, calls `Executor.execute`.

### Deployment Flow

1. **Launch chains** (two Anvil instances or Tenderly RPCs).
2. **Deploy endpoints** on each chain via `GatedEndpointV2Mock`.
3. **Deploy tokens/OFTs** (TokenA + OFT_A on chain A, OFT_B on chain B).
4. **Wire configuration**:
   * `setRemoteEndpoint` between mocks.
   * `setPeer` on both OFTs.
   * `setVerifier` / `setExecutor` on each endpoint.
5. **Deploy executors** and register with endpoints.
6. **Run agents** to process packets.
7. **Test bridge**: Mint TokenA, call `OFT_A.send`, wait for agents, verify balances on chain B.

---

## Deliverables

* **Contracts**
  * `TokenA.sol`, `TokenB.sol`
  * `OFT_A.sol`, `OFT_B.sol`, `BaseOFTV2.sol`
  * `GatedEndpointV2Mock.sol`
  * `Executor.sol`
* **Agents**
  * `agents/verifier-agent.ts`
  * `agents/executor-agent.ts`
* **Scripts & Tests**
  * `script/Deploy.s.sol`
  * `helper/deploy_oft.sh`, `helper/trigger_bridge.sh`
  * `test/BridgeTest.t.sol`
* **Docs**
  * Updated `README.md` outlining workflow and agent usage.

---

## Success Metrics

* Without verifier or executor calls, packets remain queued (no balances updated).
* With agents running, tokens bridge end-to-end and `PacketDelivered` fires.
* `forge test` reproduces the entire lifecycle deterministically.

---

## Future Extensions

* Support multiple verifiers with quorum logic.
* Inject adversarial verifier/executor behaviours to test resilience.
* Expand OFT options handling (e.g., compose messages, native drops).
* Integrate with Tenderly VNets for multi-region testing.
