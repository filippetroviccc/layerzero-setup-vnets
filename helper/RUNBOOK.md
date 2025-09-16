# LayerZero Runbook (Tenderly VNet + Local Scripts)

This runbook reflects the current scripted setup: deploy to a single RPC (e.g., Tenderly VNet), wire OFTs and gated endpoints, run Verifier/Executor agents, trigger a bridge, and validate.

Note: The gated endpoint mock simulates two chains (chain IDs 101 and 102) on one EVM RPC. Both endpoints (EP_A, EP_B) are deployed to the same RPC and internally route by chain ID.

## Prerequisites

- Foundry (forge, cast)
- jq (for parsing JSON)
- Node.js 18+ and npm

## 1) Deploy with helper (writes .env)

```
npm install
npm run deploy:oft
```

The deploy script uses a Tenderly VNet HTTP RPC by default and writes addresses + RPC_URL to `.env` in the repo root.

Optional: If you prefer different endpoints, edit `.env` after deployment. You may also add:

```
# Optional WSS for agents
WS_RPC_URL=wss://virtual.mainnet.eu.rpc.tenderly.co/<your-wss-id>

# Optional explicit HTTP RPC for cast
HTTP_RPC_URL=https://virtual.mainnet.eu.rpc.tenderly.co/<your-http-id>
```

## 2) Configure OFT min-destination gas

Set the required minDstGas on both OFTs with the provided helper:

```
bash ./configure_oft_gas.sh
```

Notes:
- The signer must be the owner of both OFT_A and OFT_B (as returned by `owner()`). If not, the script will exit with instructions to transfer ownership or switch to the deployer’s key.
- Override gas via `MIN_GAS=200000`.
- The script uses `HTTP_RPC_URL` if set; otherwise it derives HTTPS from `RPC_URL` when it is WSS.

## 3) Run agents (Verifier + Executor)

Agents read `.env`:

- `RPC_URL` or `WS_RPC_URL` (WebSocket preferred for live subscriptions)
- `ENDPOINT_ADDR`, `VERIFIER_ADDR`, `EXECUTOR_ADDR`
- Scanning controls (optional): `START_BLOCK`, `LOOKBACK_BLOCKS` (default 5000), `POLL_INTERVAL_MS` (HTTP only), `SCAN_RANGE`

Run in two terminals:

```
npm run agent:verifier
npm run agent:executor
```

Tips:
- Ensure WSS hostname contains `rpc` (e.g., `wss://virtual.mainnet.eu.rpc.tenderly.co/...`). The `...eu.ws...` hostname is invalid.
- If you only have HTTPS, agents will backfill and then poll new blocks.

## 4) Trigger a bridge

Use the helper script, which mints TokenA to the signer, approves OFT_A, estimates fee, and calls `sendFrom`:

```
npm run bridge
# or with a custom env file
ENV_PATH=/absolute/path/to/.env npm run bridge
```

Notes:
- The script derives the sender from `PRIVATE_KEY` and uses it consistently for mint/approve/send.
- It prefers `HTTP_RPC_URL` for Foundry calls; otherwise it will derive HTTPS from a WSS `RPC_URL`.

## 5) Validate setup and logs

Run the validator to check wiring and see recent event counts:

```
bash ./validate_setup.sh
```

It checks:
- Code present at EP_A/B, OFT_A/B, TOKEN_A, VERIFIER_A/B, EXECUTOR_A/B
- Endpoint chain IDs: EP_A=101, EP_B=102
- Endpoint verifier/executor set correctly
- Endpoint lookups: EP_A[OFT_B]=EP_B and EP_B[OFT_A]=EP_A
- OFT trusted remotes and minDstGas set
- Scans last `LOOKBACK_BLOCKS` (default 5000) for: SendToChain, MessageQueued, Verified, Delivered events

## Troubleshooting

- Min gas not set:
  - Run `bash ./configure_oft_gas.sh`. If the script says you are not the owner, switch to the deployer’s `PRIVATE_KEY` or transfer ownership to your signer.

- Agents see no events:
  - Prefer a WSS endpoint in `.env`: `WS_RPC_URL=wss://virtual.mainnet.eu.rpc.tenderly.co/<id>`
  - Add `LOOKBACK_BLOCKS=10000` to catch past events.
  - Ensure `ENDPOINT_ADDR`, `VERIFIER_ADDR`, `EXECUTOR_ADDR` match what `npm run deploy:oft` wrote.

- Wrong WSS host:
  - Use `...eu.rpc.tenderly.co/...` for both HTTPS and WSS. Do not use `...eu.ws...`.

- Re-validate anytime:
  - `bash ./validate_setup.sh`
