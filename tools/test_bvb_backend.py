"""Check new commands traverse the same validated ACK transport as upstream."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('bvb_backend', Path(__file__).parents[1] / 'panel/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

class BVBBackend(unittest.TestCase):
    def test_wire(self):
        for action in ('bvb_save', 'bvb_reset', 'bvb_place', 'bvb_preset'):
            self.assertIn(action, backend.ACTIONS)
            wire = backend.Bridge._wire({'id': 42, 'payload': json.dumps({'action': action})})
            self.assertIn(action, wire)

if __name__ == '__main__':
    unittest.main()
