"""The headless runner's result cache persists JSON, never Python objects."""
from concurrent.futures import ThreadPoolExecutor
import sqlite3
import unittest

from tests.support import TempDir, load

cache_module = load('runners/acestep-song/acestep_song/json_cache.py', 'kit_acestep_json_cache')


class JsonCacheTest(unittest.TestCase):
    def setUp(self):
        self.temp = TempDir()
        self.addCleanup(self.temp.cleanup)
        self.directory = self.temp.path / 'cache'
        self.now = 100.0
        self.cache = cache_module.JsonCache(self.directory, clock=lambda: self.now)
        self.addCleanup(self.cache.close)

    def test_round_trip_reopen_and_ttl(self):
        payload = {'status': 1, 'result': '[{"file":"audio.wav"}]', 'text': 'Example café'}
        self.assertTrue(self.cache.set('job', payload, expire=10))
        self.cache.set('nullable', None)
        self.cache.set('permanent', 'result')
        second = cache_module.JsonCache(self.directory, clock=lambda: self.now)
        self.addCleanup(second.close)
        self.assertEqual(second.get('job'), payload)
        self.assertIn('nullable', second)
        self.now = 110
        self.assertIsNone(second.get('job'))
        self.assertNotIn('job', second)
        self.assertEqual(set(second.iterkeys()), {'nullable', 'permanent'})
        self.assertTrue(second.delete('permanent'))
        self.assertFalse(second.delete('permanent'))

    def test_concurrent_connections_preserve_distinct_results(self):
        second = cache_module.JsonCache(self.directory)
        self.addCleanup(second.close)
        def write(index):
            (self.cache if index % 2 else second).set(str(index), {'result': index})
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(write, range(40)))
        self.assertEqual(len(list(second.iterkeys())), 40)
        for index in range(40):
            self.assertEqual(second.get(str(index)), {'result': index})

    def test_python_objects_and_pickle_bytes_are_rejected(self):
        with self.assertRaises(TypeError):
            self.cache.set('object', object())
        with self.assertRaises(TypeError):
            self.cache.set('bytes', b'not-json')
        self.cache.set('corrupt', 'safe')
        with sqlite3.connect(self.directory / 'results.sqlite3') as db:
            db.execute('UPDATE entries SET value=? WHERE key=?', (b'\x80\x04pickle-data', 'corrupt'))
        with self.assertRaises(ValueError):
            self.cache.get('corrupt')

    def test_keys_are_parameters_and_expiration_can_be_replaced(self):
        self.cache.set("' OR 1=1; --", 'literal', expire=1)
        self.cache.set('other', 'kept')
        self.cache.set("' OR 1=1; --", 'renewed', expire=20)
        self.now += 2
        self.assertEqual(self.cache.get("' OR 1=1; --"), 'renewed')
        self.cache.delete("' OR 1=1; --")
        self.assertEqual(self.cache.get('other'), 'kept')


if __name__ == '__main__':
    unittest.main()
