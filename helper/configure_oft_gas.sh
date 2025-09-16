#!/usr/bin/env bash
set -euo pipefail

# Sets minDstGas for OFT_A (dst=102) and OFT_B (dst=101) for packet types 0 and 1.
# Reads ENV_PATH (default ./.env). Uses HTTP_RPC_URL if set; else derives HTTPS from RPC_URL when it's WSS.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_PATH=${ENV_PATH:-"$ROOT_DIR/.env"}
PT_SEND=0
PT_SEND_AND_CALL=1
MIN_GAS=${MIN_GAS:-200000}

req() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found." >&2; exit 1; }; }
req cast

if [ ! -f "$ENV_PATH" ]; then
  echo "Error: env file not found at $ENV_PATH" >&2
  exit 1
fi
echo "Loading env from $ENV_PATH"
# shellcheck disable=SC1090
source "$ENV_PATH"

: "${RPC_URL?Missing RPC_URL in env file}"
: "${PRIVATE_KEY?Missing PRIVATE_KEY in env file}"
: "${OFT_A?Missing OFT_A in env file}"
: "${OFT_B?Missing OFT_B in env file}"

RPC_FOR_CAST="${HTTP_RPC_URL:-}"
if [ -z "$RPC_FOR_CAST" ]; then
  if [[ "$RPC_URL" =~ ^wss:// ]]; then
    RPC_FOR_CAST="${RPC_URL/wss:\/\//https://}"
  elif [[ "$RPC_URL" =~ ^ws:// ]]; then
    RPC_FOR_CAST="${RPC_URL/ws:\/\//http://}"
  else
    RPC_FOR_CAST="$RPC_URL"
  fi
fi

echo "Using RPC: $RPC_FOR_CAST"
echo "Setting minDstGas to $MIN_GAS for PT_SEND($PT_SEND) and PT_SEND_AND_CALL($PT_SEND_AND_CALL)"

# Derive sender from PRIVATE_KEY
SENDER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")
echo "Signer: $SENDER_ADDR"

owner_a=$(cast call "$OFT_A" "owner()(address)" --rpc-url "$RPC_FOR_CAST")
owner_b=$(cast call "$OFT_B" "owner()(address)" --rpc-url "$RPC_FOR_CAST")
echo "OFT_A owner: $owner_a"
echo "OFT_B owner: $owner_b"

lc() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
if [ "$(lc "$SENDER_ADDR")" != "$(lc "$owner_a")" ] || [ "$(lc "$SENDER_ADDR")" != "$(lc "$owner_b")" ]; then
  echo "Error: current signer is not the owner of both OFTs." >&2
  echo "- Use the PRIVATE_KEY of the deployer (owner), or" >&2
  echo "- From the owner address, transfer ownership to your signer:" >&2
  echo "    cast send $OFT_A 'transferOwnership(address)' $SENDER_ADDR --rpc-url $RPC_FOR_CAST --private-key <OWNER_PK>" >&2
  echo "    cast send $OFT_B 'transferOwnership(address)' $SENDER_ADDR --rpc-url $RPC_FOR_CAST --private-key <OWNER_PK>" >&2
  exit 1
fi

echo "Configuring OFT_A for dstChainId=102 ..."
cast send "$OFT_A" "setMinDstGas(uint16,uint16,uint256)" 102 "$PT_SEND" "$MIN_GAS" \
  --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY"
cast send "$OFT_A" "setMinDstGas(uint16,uint16,uint256)" 102 "$PT_SEND_AND_CALL" "$MIN_GAS" \
  --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY"

echo "Configuring OFT_B for dstChainId=101 ..."
cast send "$OFT_B" "setMinDstGas(uint16,uint16,uint256)" 101 "$PT_SEND" "$MIN_GAS" \
  --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY"
cast send "$OFT_B" "setMinDstGas(uint16,uint16,uint256)" 101 "$PT_SEND_AND_CALL" "$MIN_GAS" \
  --rpc-url "$RPC_FOR_CAST" --private-key "$PRIVATE_KEY"

echo "Reading back values ..."
cast call "$OFT_A" "minDstGasLookup(uint16,uint16)(uint256)" 102 "$PT_SEND" --rpc-url "$RPC_FOR_CAST"
cast call "$OFT_A" "minDstGasLookup(uint16,uint16)(uint256)" 102 "$PT_SEND_AND_CALL" --rpc-url "$RPC_FOR_CAST"
cast call "$OFT_B" "minDstGasLookup(uint16,uint16)(uint256)" 101 "$PT_SEND" --rpc-url "$RPC_FOR_CAST"
cast call "$OFT_B" "minDstGasLookup(uint16,uint16)(uint256)" 101 "$PT_SEND_AND_CALL" --rpc-url "$RPC_FOR_CAST"

echo "Done."
