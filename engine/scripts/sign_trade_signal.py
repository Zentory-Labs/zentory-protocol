"""
CLI helper for Foundry vm.ffi parity tests.

Outputs a 0x-prefixed hex ECDSA signature for StrategyExecutor TradeSignal.
"""

from __future__ import annotations

import os
import sys


def _die(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(2)


def main() -> None:
    # Ensure `engine/src` is importable when called from `contracts/`
    here = os.path.dirname(os.path.abspath(__file__))
    engine_root = os.path.abspath(os.path.join(here, ".."))
    src_path = os.path.join(engine_root, "src")
    if src_path not in sys.path:
        sys.path.insert(0, src_path)

    try:
        from signals.signer import SignalSigner  # type: ignore
    except Exception as e:  # pragma: no cover
        _die(f"Failed to import engine signer: {e}")

    if len(sys.argv) != 10:
        _die(
            "Usage: sign_trade_signal.py <private_key_hex> <vault> <direction> <size> <price> <nonce> <expiry> <chain_id> <executor>"
        )

    (
        _script,
        private_key,
        vault,
        direction,
        size,
        price,
        nonce,
        expiry,
        chain_id,
        executor,
    ) = sys.argv

    signer = SignalSigner(private_key)
    sig = signer.sign_hex(
        vault=vault,
        direction=int(direction),
        size=int(size),
        price=int(price),
        nonce=int(nonce),
        expiry=int(expiry),
        chain_id=int(chain_id),
        executor_address=executor,
    )

    # SignalSigner.sign_hex returns hex without 0x prefix; Foundry expects 0x...
    if sig.startswith("0x"):
        print(sig)
    else:
        print("0x" + sig)


if __name__ == "__main__":
    main()

