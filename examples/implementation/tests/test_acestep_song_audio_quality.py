"""acestep-song audio sanity check: a generated WAV must be 48 kHz 16-bit PCM of
the requested length, and neither silent, hard-clipped nor noise-like."""

from __future__ import annotations

import math
from pathlib import Path
import struct
import unittest
import wave

from tests.support import TempDir, load

quality = load("runners/acestep-song/acestep_song/audio_quality.py", "kit_acestep_song_audio_quality")

SAMPLE_RATE = 48_000


def write_wav(path: Path, samples: list[int], *, channels: int = 2, rate: int = SAMPLE_RATE, width: int = 2) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(width)
        output.setframerate(rate)
        frames = [sample for sample in samples for _ in range(channels)]
        if width == 2:
            output.writeframes(struct.pack(f"<{len(frames)}h", *frames))
        else:
            output.writeframes(bytes(len(frames) * width))


class AudioQualityTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TempDir()
        self.addCleanup(self.temp.cleanup)

    def path(self, name: str) -> Path:
        return self.temp.path / name

    def test_accepts_a_tonal_song(self) -> None:
        samples = [
            round(12_000 * math.sin(2 * math.pi * 220 * frame / SAMPLE_RATE) * (0.65 + 0.35 * math.sin(2 * math.pi * 2 * frame / SAMPLE_RATE)))
            for frame in range(SAMPLE_RATE * 2)
        ]
        write_wav(self.path("tonal.wav"), samples)
        metrics = quality.validate_wav_quality(self.path("tonal.wav"), expected_duration_seconds=2)
        self.assertEqual((metrics.sample_rate, metrics.channels), (SAMPLE_RATE, 2))
        self.assertGreater(metrics.rms, 0.1)
        self.assertEqual(set(metrics.as_json()), {"sample_rate", "channels", "duration_seconds", "rms", "peak", "clipped_ratio", "zero_crossing_rate"})

    def test_rejects_silence(self) -> None:
        write_wav(self.path("silence.wav"), [0] * SAMPLE_RATE)
        with self.assertRaisesRegex(quality.AudioQualityError, "silent"):
            quality.validate_wav_quality(self.path("silence.wav"), expected_duration_seconds=1)

    def test_rejects_hard_clipping(self) -> None:
        write_wav(self.path("clipped.wav"), [32_767] * SAMPLE_RATE)
        with self.assertRaisesRegex(quality.AudioQualityError, "clipped"):
            quality.validate_wav_quality(self.path("clipped.wav"), expected_duration_seconds=1)

    def test_rejects_a_noise_like_pattern(self) -> None:
        write_wav(self.path("noise.wav"), [24_000 if frame % 2 == 0 else -24_000 for frame in range(SAMPLE_RATE)])
        with self.assertRaisesRegex(quality.AudioQualityError, "noise-like"):
            quality.validate_wav_quality(self.path("noise.wav"), expected_duration_seconds=1)

    def test_rejects_the_wrong_duration(self) -> None:
        write_wav(self.path("short.wav"), [1_000] * SAMPLE_RATE)
        with self.assertRaisesRegex(quality.AudioQualityError, "duration"):
            quality.validate_wav_quality(self.path("short.wav"), expected_duration_seconds=10)

    def test_rejects_the_wrong_format(self) -> None:
        write_wav(self.path("rate.wav"), [1_000] * 44_100, rate=44_100)
        with self.assertRaisesRegex(quality.AudioQualityError, "sample rate"):
            quality.validate_wav_quality(self.path("rate.wav"), expected_duration_seconds=1)
        write_wav(self.path("wide.wav"), [0] * SAMPLE_RATE, width=3)
        with self.assertRaisesRegex(quality.AudioQualityError, "16-bit"):
            quality.validate_wav_quality(self.path("wide.wav"), expected_duration_seconds=1)
        self.path("junk.wav").write_bytes(b"not a wav file")
        with self.assertRaisesRegex(quality.AudioQualityError, "decoded"):
            quality.validate_wav_quality(self.path("junk.wav"), expected_duration_seconds=1)


if __name__ == "__main__":
    unittest.main()
