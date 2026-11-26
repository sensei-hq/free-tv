"""CLI resilience: one bad stream never kills the run."""
import unittest

from curator.cli import safe_result


class FakeFuture:
    def __init__(self, value=None, error=None):
        self.value = value
        self.error = error

    def result(self):
        if self.error is not None:
            raise self.error
        return self.value


class SafeResultTest(unittest.TestCase):
    def test_passthrough(self):
        self.assertEqual(safe_result(FakeFuture(value=42)), 42)

    def test_exception_becomes_error_probe(self):
        probe = safe_result(FakeFuture(error=RuntimeError("boom")))
        self.assertEqual(probe.status, "error")
        self.assertIn("boom", probe.reason)


if __name__ == "__main__":
    unittest.main()
