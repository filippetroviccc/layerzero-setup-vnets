# LayerZero Local Runbook (Verifier + Executor)

This runbook shows how to build, deploy, and run the full local flow using the gated LayerZero endpoint mock plus off-chain Verifier/Executor agents.

Note: The gated endpoint mock simulates two chains on a single EVM node. Both endpoints live on the same Anvil instance and internally use chain IDs 101 and 102 to route messages.

## Prerequisites

- Foundry (forge, cast) installed
- Node.js 18+ and npm

## 1) Build and test

```
forge build
forge test -vvv
```

You should see the integration test pass.

## 2) Start Anvil

```
anvil --port 8545 --chain-id 31337
```

Keep it running. The default private key at index 0 will be used in examples below.

## 3) Deploy contracts (single-node, simulating 2 chains)

Open a new terminal. Export a sender (Anvil account[0]) and RPC URL:

```
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
export FROM=0x5FbDB2315678afecb367f032d93F642f64180aa3 # replace with your account if different
```

- Deploy endpoints (chain A = 101, chain B = 102):

```
forge create src/layerzero/GatedLZEndpointMock.sol:GatedLZEndpointMock \
  --rpc-url $RPC_URL --constructor-args 101 --private-key $PRIVATE_KEY --json | tee /tmp/epA.json
export EP_A=$(jq -r '.deployedTo' /tmp/epA.json)

forge create src/layerzero/GatedLZEndpointMock.sol:GatedLZEndpointMock \
  --rpc-url $RPC_URL --constructor-args 102 --private-key $PRIVATE_KEY --json | tee /tmp/epB.json
export EP_B=$(jq -r '.deployedTo' /tmp/epB.json)
```

- Deploy TokenA and OFTs:

```
forge create src/tokens/TokenA.sol:TokenA \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --json | tee /tmp/tA.json
export TOKEN_A=$(jq -r '.deployedTo' /tmp/tA.json)

forge create src/oft/OFT_A.sol:OFT_A \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --constructor-args $TOKEN_A 18 $EP_A --json | tee /tmp/oA.json
export OFT_A=$(jq -r '.deployedTo' /tmp/oA.json)

forge create src/oft/OFT_B.sol:OFT_B \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --constructor-args TokenA TKA 18 $EP_B --json | tee /tmp/oB.json
export OFT_B=$(jq -r '.deployedTo' /tmp/oB.json)
```

- Wire endpoints (point each UA to the other endpoint):

```
cast send $EP_A "setDestLzEndpoint(address,address)" $OFT_B $EP_B --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $EP_B "setDestLzEndpoint(address,address)" $OFT_A $EP_A --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

- Set trusted remotes and gas on OFTs:

```
# Build paths: bytes.concat(dstUA, srcUA)
export PATH_A_TO_B=$(cast abi-encode "f(address,address)" $OFT_B $OFT_A | sed 's/^0x//')
export PATH_B_TO_A=$(cast abi-encode "f(address,address)" $OFT_A $OFT_B | sed 's/^0x//')

# Min gas
cast send $OFT_A "setMinDstGas(uint16,uint16,uint256)" 102 0 200000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $OFT_A "setMinDstGas(uint16,uint16,uint256)" 102 1 200000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $OFT_B "setMinDstGas(uint16,uint16,uint256)" 101 0 200000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $OFT_B "setMinDstGas(uint16,uint16,uint256)" 101 1 200000 --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Trusted remotes
cast send $OFT_A "setTrustedRemote(uint16,bytes)" 102 0x$PATH_A_TO_B --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $OFT_B "setTrustedRemote(uint16,bytes)" 101 0x$PATH_B_TO_A --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

- Deploy Verifier + Executor and set on endpoints:

```
forge create src/infra/Verifier.sol:Verifier \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --json | tee /tmp/vA.json
export VERIFIER_A=$(jq -r '.deployedTo' /tmp/vA.json)

forge create src/infra/Verifier.sol:Verifier \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY --json | tee /tmp/vB.json
export VERIFIER_B=$(jq -r '.deployedTo' /tmp/vB.json)

forge create src/infra/Executor.sol:Executor \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --constructor-args $EP_A --json | tee /tmp/exA.json
export EXECUTOR_A=$(jq -r '.deployedTo' /tmp/exA.json)

forge create src/infra/Executor.sol:Executor \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --constructor-args $EP_B --json | tee /tmp/exB.json
export EXECUTOR_B=$(jq -r '.deployedTo' /tmp/exB.json)

# Register on endpoints
cast send $EP_A "setVerifier(address)" $VERIFIER_A --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $EP_A "setExecutor(address)" $EXECUTOR_A --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $EP_B "setVerifier(address)" $VERIFIER_B --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast send $EP_B "setExecutor(address)" $EXECUTOR_B --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## 4) Configure agents and run

Install Node dependencies and configure .env:

```
npm install
cp .env.example .env
```

Edit `.env` and set at minimum (source side):

```
RPC_URL=http://127.0.0.1:8545
ENDPOINT_ADDR=$EP_A
VERIFIER_ADDR=$VERIFIER_A
EXECUTOR_ADDR=$EXECUTOR_A
PRIVATE_KEY=<your anvil key>
```

Run agents (two terminals):

```
npm run agent:verifier
npm run agent:executor
```

## 5) Trigger a bridge

- Mint TokenA to your account and approve OFT_A:

```
# Mint 1000 TKA to sender
cast send $TOKEN_A "ownerMint(address,uint256)" $FROM 1000000000000000000000 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Approve OFT_A to spend
cast send $TOKEN_A "approve(address,uint256)" $OFT_A 1000000000000000000000 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

- Build adapter params and estimate fee:

```
export ADAPTER=$(cast abi-encode "f(uint16,uint256)" 1 200000)
cast call $OFT_A "estimateSendFee(uint16,bytes32,uint256,bool,bytes)" \
  102 $(cast --to-bytes32 $FROM) 250000000000000000000 false $ADAPTER \
  --rpc-url $RPC_URL
```

Take the first returned value as `nativeFee`. Use it as `--value` in the next call.

- Send tokens to Chain B (OFT_B):

```
cast send $OFT_A "sendFrom(address,uint16,bytes32,uint256,(address,address,bytes))" \
  $FROM 102 $(cast --to-bytes32 $FROM) 250000000000000000000 \
  "($FROM,0x$($(printf %s "$ADAPTER" | sed 's/^0x//')),0x)" \
  --value <nativeFee> --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

The verifier agent should log `MessageQueued` and submit an attestation, and the executor agent will execute delivery. Check balances:

```
# Balance on A decreases by 250 TKA
cast call $TOKEN_A "balanceOf(address)" $FROM --rpc-url $RPC_URL

# Representation on B increases by 250 TKA
cast call $OFT_B "balanceOf(address)" $FROM --rpc-url $RPC_URL
```

## Notes

- This simulation runs both endpoints on a single Anvil node. Cross-endpoint delivery is an internal call in the mock; running endpoints on separate RPC nodes is not supported by this mock.
- For automation, consider adding forge-std-based deploy scripts to emit JSON artifacts and write a .env.

