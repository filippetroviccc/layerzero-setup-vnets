#!/usr/bin/env bash
set -euo pipefail

# Validates deployed setup and checks for recent logs.
# - Loads env from ENV_PATH (default: ./.env)
# - Uses HTTP_RPC_URL if set; otherwise derives HTTP from RPC_URL if it is wss://
# - Verifies contract code exists and wiring is correct
# - Scans last LOOKBACK_BLOCKS (default 5000) for expected events

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_PATH=${ENV_PATH:-"$ROOT_DIR/.env"}
LOOKBACK_BLOCKS=${LOOKBACK_BLOCKS:-5000}

req() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 not found. Please install it." >&2; exit 1; }; }
req cast
req jq

if [ ! -f "$ENV_PATH" ]; then
  echo "Error: env file not found at $ENV_PATH" >&2
  exit 1
fi
echo "Loading env from $ENV_PATH"
# shellcheck disable=SC1090
source "$ENV_PATH"

: "${RPC_URL?Missing RPC_URL in env file}"

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

echo "RPC for validation: $RPC_FOR_CAST"

pass_ct=0; fail_ct=0
pass() { echo "[OK]  $1"; pass_ct=$((pass_ct+1)); }
fail() { echo "[ERR] $1"; fail_ct=$((fail_ct+1)); }

chk_code() {
  local addr=$1; local name=$2
  if [ -z "$addr" ] || [ "$addr" = "0x" ]; then fail "$name address missing"; return; fi
  local code
  code=$(cast code "$addr" --rpc-url "$RPC_FOR_CAST" 2>/dev/null || echo "0x")
  if [ "$code" = "0x" ]; then fail "$name ($addr) has no code"; else pass "$name ($addr) code present"; fi
}

# Required addresses
chk_code "$EP_A" "EP_A"
chk_code "$EP_B" "EP_B"
chk_code "$OFT_A" "OFT_A"
chk_code "$OFT_B" "OFT_B"
chk_code "$TOKEN_A" "TOKEN_A"
chk_code "$VERIFIER_A" "VERIFIER_A"
chk_code "$VERIFIER_B" "VERIFIER_B"
chk_code "$EXECUTOR_A" "EXECUTOR_A"
chk_code "$EXECUTOR_B" "EXECUTOR_B"

# Endpoint wiring checks
get() { cast call "$1" "$2" ${3:+$3} --rpc-url "$RPC_FOR_CAST" 2>/dev/null || echo "0x"; }

# Chain IDs
cid_a=$(get "$EP_A" "getChainId()(uint16)")
cid_b=$(get "$EP_B" "getChainId()(uint16)")
[[ "$cid_a" == "0x0065" || "$cid_a" == "0x65" || "$cid_a" == "101" ]] && pass "EP_A chainId is 101" || fail "EP_A chainId not 101 ($cid_a)"
[[ "$cid_b" == "0x0066" || "$cid_b" == "0x66" || "$cid_b" == "102" ]] && pass "EP_B chainId is 102" || fail "EP_B chainId not 102 ($cid_b)"

# Verifier/Executor set on endpoints
ver_a=$(get "$EP_A" "verifier()(address)")
ver_b=$(get "$EP_B" "verifier()(address)")
exe_a=$(get "$EP_A" "executor()(address)")
exe_b=$(get "$EP_B" "executor()(address)")
tolower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
if [ "$(tolower "$ver_a")" = "$(tolower "$VERIFIER_A")" ]; then pass "EP_A verifier set"; else fail "EP_A verifier mismatch: $ver_a"; fi
if [ "$(tolower "$ver_b")" = "$(tolower "$VERIFIER_B")" ]; then pass "EP_B verifier set"; else fail "EP_B verifier mismatch: $ver_b"; fi
if [ "$(tolower "$exe_a")" = "$(tolower "$EXECUTOR_A")" ]; then pass "EP_A executor set"; else fail "EP_A executor mismatch: $exe_a"; fi
if [ "$(tolower "$exe_b")" = "$(tolower "$EXECUTOR_B")" ]; then pass "EP_B executor set"; else fail "EP_B executor mismatch: $exe_b"; fi

# Endpoint lookup wiring (UA -> dest endpoint)
lookup_ab=$(get "$EP_A" "lzEndpointLookup(address)(address)" "$OFT_B")
lookup_ba=$(get "$EP_B" "lzEndpointLookup(address)(address)" "$OFT_A")
if [ "$(tolower "$lookup_ab")" = "$(tolower "$EP_B")" ]; then pass "EP_A lookup[OFT_B] == EP_B"; else fail "EP_A lookup wrong: $lookup_ab"; fi
if [ "$(tolower "$lookup_ba")" = "$(tolower "$EP_A")" ]; then pass "EP_B lookup[OFT_A] == EP_A"; else fail "EP_B lookup wrong: $lookup_ba"; fi

# OFT config: trusted remotes and min gas
path_ab=$(cast abi-encode --packed "f(address,address)" "$OFT_B" "$OFT_A" | sed 's/^0x//')
path_ba=$(cast abi-encode --packed "f(address,address)" "$OFT_A" "$OFT_B" | sed 's/^0x//')

tr_a=$(get "$OFT_A" "trustedRemoteLookup(uint16)(bytes)" 102 | sed 's/^0x//')
tr_b=$(get "$OFT_B" "trustedRemoteLookup(uint16)(bytes)" 101 | sed 's/^0x//')
[[ "$tr_a" = "$path_ab" ]] && pass "OFT_A trustedRemote[102] set" || fail "OFT_A trustedRemote mismatch"
[[ "$tr_b" = "$path_ba" ]] && pass "OFT_B trustedRemote[101] set" || fail "OFT_B trustedRemote mismatch"

min_a0=$(get "$OFT_A" "minDstGasLookup(uint16,uint16)(uint256)" 102 0)
min_a1=$(get "$OFT_A" "minDstGasLookup(uint16,uint16)(uint256)" 102 1)
min_b0=$(get "$OFT_B" "minDstGasLookup(uint16,uint16)(uint256)" 101 0)
min_b1=$(get "$OFT_B" "minDstGasLookup(uint16,uint16)(uint256)" 101 1)

chk_min() { local v=$1; local label=$2; if [ "$v" = "0x" ] || [ "$v" = "0x0" ] || [ "$v" = "0" ]; then fail "$label not set"; else pass "$label set ($v)"; fi; }
chk_min "$min_a0" "OFT_A minDstGas[102,PT_SEND]"
chk_min "$min_a1" "OFT_A minDstGas[102,PT_SEND_AND_CALL]"
chk_min "$min_b0" "OFT_B minDstGas[101,PT_SEND]"
chk_min "$min_b1" "OFT_B minDstGas[101,PT_SEND_AND_CALL]"

echo "--- Log scan (last $LOOKBACK_BLOCKS blocks) ---"
latest_bn=$(cast block-number --rpc-url "$RPC_FOR_CAST")
from_bn=$(( latest_bn > LOOKBACK_BLOCKS ? latest_bn - LOOKBACK_BLOCKS : 0 ))

to_hex() { printf "0x%x" "$1"; }
from_hex=$(to_hex "$from_bn")

topic_msgq=$(cast keccak "MessageQueued(bytes32,uint16,uint16,address,address,uint64,bytes32)")
topic_deliv=$(cast keccak "MessageDelivered(bytes32,address)")
topic_verified=$(cast keccak "Verified(bytes32,address)")
topic_exec=$(cast keccak "Delivered(bytes32)")
topic_send=$(cast keccak "SendToChain(uint16,address,bytes32,uint256)")

eth_getLogs() {
  local addr=$1; local topic0=$2
  cast rpc eth_getLogs "{\"fromBlock\":\"$from_hex\",\"toBlock\":\"latest\",\"address\":\"$addr\",\"topics\":[\"$topic0\"]}" --rpc-url "$RPC_FOR_CAST"
}

cnt() { echo "$1" | jq 'length'; }

logs_msgq=$(eth_getLogs "$EP_A" "$topic_msgq" || echo '[]')
logs_deliv=$(eth_getLogs "$EP_A" "$topic_deliv" || echo '[]')
logs_verified=$(eth_getLogs "$VERIFIER_A" "$topic_verified" || echo '[]')
logs_exec=$(eth_getLogs "$EXECUTOR_A" "$topic_exec" || echo '[]')
logs_send=$(eth_getLogs "$OFT_A" "$topic_send" || echo '[]')

echo "MessageQueued (EP_A): $(cnt "$logs_msgq")"
echo "MessageDelivered (EP_A): $(cnt "$logs_deliv")"
echo "Verified (Verifier_A): $(cnt "$logs_verified")"
echo "Executor Delivered (Executor_A): $(cnt "$logs_exec")"
echo "SendToChain (OFT_A): $(cnt "$logs_send")"

echo "--- Summary ---"
echo "Passed: $pass_ct"
echo "Failed: $fail_ct"
if [ "$fail_ct" -gt 0 ]; then
  exit 1
fi
echo "All checks passed."
