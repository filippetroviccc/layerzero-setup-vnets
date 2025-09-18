#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
ENV_PATH=${ENV_PATH:-"$ROOT_DIR/.env"}
if [ -f "$ENV_PATH" ]; then
  echo "Loading env from $ENV_PATH"
  # shellcheck disable=SC1090
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
DST_EID=${DST_EID:-102}
OPTIONS=${OPTIONS:-${DEFAULT_OPTIONS:-$(cast abi-encode "f(uint256,uint256)" 200000 0)}}

SENDER=$FROM
if command -v cast >/dev/null 2>&1; then
  if ADDR=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null); then
    if [ -n "$ADDR" ]; then SENDER=$ADDR; fi
  fi
fi
RECIPIENT=${RECIPIENT:-$SENDER}

RPC_FOR_CAST="$RPC_URL"
if [[ "$RPC_URL" =~ ^wss?:// ]]; then
  RPC_FOR_CAST="${RPC_URL/wss:\/\//https://}"
  RPC_FOR_CAST="${RPC_FOR_CAST/ws:\/\//http://}"
fi

echo "Using RPC=$RPC_FOR_CAST"
echo "Sending amount=$AMOUNT wei to eid=$DST_EID recipient=$RECIPIENT (sender=$SENDER)"

echo "Minting TokenA to $SENDER ..."
cast send "$TOKEN_A" "ownerMint(address,uint256)" "$SENDER" "$AMOUNT" \
  --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY" >/dev/null

echo "Approving OFT_A to spend TokenA from $SENDER ..."
cast send "$TOKEN_A" "approve(address,uint256)" "$OFT_A" "$AMOUNT" \
  --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY" >/dev/null

echo "Quoting send ..."
QUOTE=$(cast call "$OFT_A" "quoteSend(uint32,address,uint256,bytes)" \
  "$DST_EID" "$RECIPIENT" "$AMOUNT" "$OPTIONS" \
  --rpc-url "$RPC_FOR_CAST")
NATIVE_FEE=$(cast --to-dec "0x$(echo "$QUOTE" | cut -c3-66)")

echo "Estimated nativeFee=$NATIVE_FEE"

echo "Sending via OFT_A ..."
SEND_TX=$(cast send "$OFT_A" "send(uint32,address,uint256,bytes)" \
  "$DST_EID" "$RECIPIENT" "$AMOUNT" "$OPTIONS" \
  --value "$NATIVE_FEE" --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY")

echo "Send transaction hash: $SEND_TX"

echo "Bridge submitted. Watch for PacketSent/PacketVerified/PacketDelivered events."
