#!/usr/bin/env bash
set -euo pipefail

# Basic config (override via env if needed)
RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
PRIVATE_KEY=${PRIVATE_KEY:-0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}
SIGNER=$(cast wallet address --private-key "$PRIVATE_KEY")
FROM=${FROM:-$SIGNER}

TOKEN_A=${TOKEN_A:-0x581f62c0901d4dce2553cb6140dBb4CeE533d834}
OFT_A=${OFT_A:-0x2572e04Caf46ba8692Bd6B4CBDc46DAA3cA9647E}
OFT_B=${OFT_B:-0x72F375F23BCDA00078Ac12e7e9E7f6a8CA523e7D}

# Destination chain EID and amount to bridge (250 TKA)
DST_EID=${DST_EID:-102}
AMOUNT=${AMOUNT:-250000000000000000000}

LOW_FROM=$(printf '%s' "$FROM" | tr '[:upper:]' '[:lower:]')
LOW_SIGNER=$(printf '%s' "$SIGNER" | tr '[:upper:]' '[:lower:]')
if [ "$LOW_FROM" != "$LOW_SIGNER" ]; then
  echo "WARN: FROM ($FROM) differs from signer ($SIGNER). Using signer for sendFrom."
  FROM=$SIGNER
fi

echo "Minting 1000 TKA to $FROM on source chain..."
cast send "$TOKEN_A" "ownerMint(address,uint256)" "$FROM" 1000000000000000000000 \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"

echo "Approving OFT_A to spend 1000 TKA from $FROM..."
cast send "$TOKEN_A" "approve(address,uint256)" "$OFT_A" 1000000000000000000000 \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"

# Adapter params: version=1, gas=200000
ADAPTER=$(cast abi-encode --packed "f(uint16,uint256)" 1 200000)
TO=${TO:-$FROM}
TO_B32=$(cast --to-bytes32 "$TO")

echo "Ensuring trusted remote paths are correctly packed (40 bytes)..."
PATH_A_TO_B=$(cast abi-encode --packed "f(address,address)" "$OFT_B" "$OFT_A" | sed 's/^0x//')
PATH_B_TO_A=$(cast abi-encode --packed "f(address,address)" "$OFT_A" "$OFT_B" | sed 's/^0x//')
cast send "$OFT_A" "setTrustedRemote(uint16,bytes)" "$DST_EID" 0x"$PATH_A_TO_B" \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
# Also set reverse on B so inbound is accepted
SRC_EID=${SRC_EID:-101}
cast send "$OFT_B" "setTrustedRemote(uint16,bytes)" "$SRC_EID" 0x"$PATH_B_TO_A" \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"

echo "Estimating native fee..."
RET_RAW=$(cast call "$OFT_A" "estimateSendFee(uint16,bytes32,uint256,bool,bytes)" \
  "$DST_EID" "$TO_B32" "$AMOUNT" false "$ADAPTER" \
  --rpc-url "$RPC_URL")

# RET_RAW is abi-encoded (uint256 nativeFee, uint256 zroFee)
RET_NO0X=${RET_RAW#0x}
NATIVE_HEX=0x${RET_NO0X:0:64}
NATIVE_FEE=$(cast --to-dec "$NATIVE_HEX")
echo "Native fee (wei): $NATIVE_FEE"

# LZ send options tuple: (refundAddress, zroPaymentAddress, adapterParams)
SEND_OPTS="($FROM,0x0000000000000000000000000000000000000000,$ADAPTER)"

echo "Sending $AMOUNT tokens from $FROM to EID $DST_EID (to=$TO)..."
cast send "$OFT_A" "sendFrom(address,uint16,bytes32,uint256,(address,address,bytes))" \
  "$FROM" "$DST_EID" "$TO_B32" "$AMOUNT" "$SEND_OPTS" \
  --value "$NATIVE_FEE" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"

echo "Done. Post-send balances (source token and dst OFT representation):"
cast call "$TOKEN_A" "balanceOf(address)" "$FROM" --rpc-url "$RPC_URL" || true
cast call "$OFT_B" "balanceOf(address)" "$FROM" --rpc-url "$RPC_URL" || true
