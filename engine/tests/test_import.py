from zentory_engine import __version__


def test_engine_package_imports() -> None:
    assert __version__ == "0.1.0"
