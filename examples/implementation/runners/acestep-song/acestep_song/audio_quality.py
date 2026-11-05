"""Objective sanity checks for a generated song before it is published.

ACE-Step occasionally renders silence, hard clipping or a high-frequency
noise-like waveform. These checks read the 48 kHz 16-bit PCM WAV the API
returns and reject those outcomes, plus a length that does not match the
request. Standard library only.
"""

from __future__ import annotations

from array import array
from dataclasses import asdict, dataclass
import math
from pathlib import Path
import sys
import wave

EXPECTED_SAMPLE_RATE = 48_000
MIN_RMS = 0.003
MIN_PEAK = 0.01
MAX_CLIPPED_RATIO = 0.02
MAX_ZERO_CROSSING_RATE = 0.45
CLIPPED_MAGNITUDE = 32_760


class AudioQualityError(RuntimeError):
    """The file is a WAV, but not audio worth publishing."""


@dataclass(frozen=True)
class AudioQualityMetrics:
    sample_rate: int
    channels: int
    duration_seconds: float
    rms: float
    peak: float
    clipped_ratio: float
    zero_crossing_rate: float

    def as_json(self) -> dict[str, int | float]:
        return asdict(self)


def validate_wav_quality(path: Path, *, expected_duration_seconds: float) -> AudioQualityMetrics:
    """Reject structurally wrong, silent, clipped or noise-like PCM output."""
    channels, sample_rate, frame_count, raw = _read_pcm16(path)
    duration = frame_count / sample_rate
    if abs(duration - expected_duration_seconds) > max(1.0, expected_duration_seconds * 0.03):
        raise AudioQualityError("generated WAV duration does not match the requested song duration")

    samples = array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    if not samples:
        raise AudioQualityError("generated WAV is silent")

    peak_value = clipped = square_sum = crossings = opportunities = 0
    previous = [0] * channels
    for index, sample in enumerate(samples):
        magnitude = abs(sample)
        peak_value = max(peak_value, magnitude)
        square_sum += sample * sample
        if magnitude >= CLIPPED_MAGNITUDE:
            clipped += 1
        channel = index % channels
        sign = 1 if sample > 0 else -1 if sample < 0 else 0
        if sign and previous[channel]:
            opportunities += 1
            if sign != previous[channel]:
                crossings += 1
        if sign:
            previous[channel] = sign

    count = len(samples)
    metrics = AudioQualityMetrics(
        sample_rate=sample_rate,
        channels=channels,
        duration_seconds=round(duration, 6),
        rms=round(math.sqrt(square_sum / count) / 32_768, 6),
        peak=round(peak_value / 32_768, 6),
        clipped_ratio=round(clipped / count, 6),
        zero_crossing_rate=round(crossings / opportunities if opportunities else 0.0, 6),
    )
    if metrics.rms < MIN_RMS or metrics.peak < MIN_PEAK:
        raise AudioQualityError("generated WAV is silent or nearly silent")
    if metrics.clipped_ratio > MAX_CLIPPED_RATIO:
        raise AudioQualityError("generated WAV is hard-clipped")
    if metrics.zero_crossing_rate > MAX_ZERO_CROSSING_RATE:
        raise AudioQualityError("generated WAV is noise-like")
    return metrics


def _read_pcm16(path: Path) -> tuple[int, int, int, bytes]:
    try:
        with wave.open(str(path), "rb") as source:
            channels = source.getnchannels()
            width = source.getsampwidth()
            rate = source.getframerate()
            frames = source.getnframes()
            compression = source.getcomptype()
            if channels not in {1, 2}:
                raise AudioQualityError(f"generated WAV has unsupported channel count: {channels}")
            if width != 2 or compression != "NONE":
                raise AudioQualityError("generated WAV must contain uncompressed 16-bit PCM audio")
            if rate != EXPECTED_SAMPLE_RATE:
                raise AudioQualityError(f"generated WAV has unexpected sample rate: {rate}")
            return channels, rate, frames, source.readframes(frames)
    except (EOFError, wave.Error) as error:
        raise AudioQualityError("generated WAV cannot be decoded") from error
