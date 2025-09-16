#!/usr/bin/env bash
set -euo pipefail

# Trigger a cross-chain send using the deployed OFT_A on Chain A -> OFT_B on Chain B
# Reads variables from repo root .env (written by helper/deploy_oft.sh)
#
# Optional overrides via env or args:
#   AMOUNT (wei) default 250e18
#   DST_CHAIN_ID default 102
#   RECIPIENT default $FROM
#
# Usage:
#   bash helper/trigger_bridge.sh

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
ENV_PATH=${ENV_PATH:-"$ROOT_DIR/.env"}
if [ -f "$ENV_PATH" ]; then
  # shellcheck disable=SC1090
  echo "Loading env from $ENV_PATH"
  source "$ENV_PATH"
else
  echo "Error: env file not found at $ENV_PATH. Set ENV_PATH or run helper/deploy_oft.sh first." >&2
  exit 1
fi

: "${RPC_URL?Missing RPC_URL in env file}"
: "${PRIVATE_KEY?Missing PRIVATE_KEY in .env}"
: "${FROM?Missing FROM in .env}"
: "${TOKEN_A?Missing TOKEN_A in .env}"
: "${OFT_A?Missing OFT_A in .env}"
: "${OFT_B?Missing OFT_B in .env}"

AMOUNT=${AMOUNT:-250000000000000000000}     # 250e18
DST_CHAIN_ID=${DST_CHAIN_ID:-102}

# Derive sender from private key if possible
SENDER=${FROM}
if command -v cast >/dev/null 2>&1; then
  if ADDR=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null); then
    if [ -n "$ADDR" ]; then SENDER=$ADDR; fi
  fi
fi
RECIPIENT=${RECIPIENT:-$SENDER}

RPC_FOR_CAST="${HTTP_RPC_URL:-}"
if [ -z "$RPC_FOR_CAST" ]; then
  # Derive HTTP RPC if only WS is provided
  if [[ "$RPC_URL" =~ ^wss:// ]]; then
    RPC_FOR_CAST="${RPC_URL/wss:\/\//https://}"
  elif [[ "$RPC_URL" =~ ^ws:// ]]; then
    RPC_FOR_CAST="${RPC_URL/ws:\/\//http://}"
  else
    RPC_FOR_CAST="$RPC_URL"
  fi
fi

echo "Using RPC (cast)=$RPC_FOR_CAST"
echo "Sending amount=$AMOUNT wei to chainId=$DST_CHAIN_ID recipient=$RECIPIENT (sender=$SENDER)"

# 1) Mint on TokenA to FROM (owner-only)
echo "Minting TokenA to $SENDER ..."
cast send "$TOKEN_A" "ownerMint(address,uint256)" "$SENDER" "$AMOUNT" \
  --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY" >/dev/null

# 2) Approve OFT_A to spend TOKEN_A
echo "Approving OFT_A to spend TokenA from $SENDER ..."
cast send "$TOKEN_A" "approve(address,uint256)" "$OFT_A" "$AMOUNT" \
  --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY" >/dev/null

# 3) Build adapter and estimate fee
ADAPTER=$(cast abi-encode --packed "f(uint16,uint256)" 1 200000)
echo "Estimating native fee ..."
EST_OUT=$(cast call "$OFT_A" "estimateSendFee(uint16,bytes32,uint256,bool,bytes)" \
  "$DST_CHAIN_ID" "$(cast --to-bytes32 "$RECIPIENT")" "$AMOUNT" false "$ADAPTER" \
  --rpc-url "$RPC_FOR_CAST")
# ABI-encoded (uint256 nativeFee, uint256 zroFee); take the first 32 bytes
FEE_HEX="0x$(echo "$EST_OUT" | cut -c3-66)"
NATIVE_FEE=$(cast --to-dec "$FEE_HEX")
echo "Estimated nativeFee=$NATIVE_FEE wei (hex=$FEE_HEX)"

# 4) Send the tokens from A -> B
echo "Sending via OFT_A (sendFrom) -> chain $DST_CHAIN_ID ..."
cast send "$OFT_A" "sendFrom(address,uint16,bytes32,uint256,(address,address,bytes))" \
  "$SENDER" "$DST_CHAIN_ID" "$(cast --to-bytes32 "$RECIPIENT")" "$AMOUNT" \
  "($SENDER,0x0000000000000000000000000000000000000000,$ADAPTER)" \
  --value "$NATIVE_FEE" --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY"

echo "Bridge transaction submitted. Verifier/Executor agents should process delivery."
