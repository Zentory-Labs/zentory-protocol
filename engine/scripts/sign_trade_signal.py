"""
CLI helper for Foundry vm.ffi parity tests.

Outputs a 0x-prefixed hex ECDSA signature for StrategyExecutor TradeSignal.
"""

from __future__ import annotations

import importlib.util
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
        # IMPORTANT: load signer module directly to avoid importing `signals/__init__.py`,
        # which pulls in optional runtime deps (e.g. httpx) not needed for signing.
        signer_path = os.path.join(src_path, "signals", "signer.py")
        spec = importlib.util.spec_from_file_location("_zentory_signal_signer", signer_path)
        if spec is None or spec.loader is None:
            raise RuntimeError("Could not create import spec for signer.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        SignalSigner = getattr(mod, "SignalSigner")
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

    # sign_hex() now returns 0x-prefixed hex directly
    print(sig)


if __name__ == "__main__":
    main()

