"""ffprobe and ffmpeg for MiniMax H3: reference lengths, the delivery encode, the poster.

The raw render is 1280x736 (or 736x1280). The delivery is that render scaled
and centre-cropped to 1280x720 (or 720x1280), 24 fps, H.264 yuv420p with
faststart, and the model's native audio as 48 kHz AAC stereo, trimmed or padded
to exactly the requested length. Container metadata from the render is
dropped. A delivery that is not exactly that fails the run.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
import subprocess
from typing import Any

PROBE_TIMEOUT_SECONDS = 120
ENCODE_TIMEOUT_SECONDS = 30 * 60
POSTER_TIMEOUT_SECONDS = 120
POSTER_MAX_BYTES = 8 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
DURATION_TOLERANCE_SECONDS = 0.02


def probe(path: Path) -> dict[str, Any]:
    finished = subprocess.run(
        ["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)],
        check=True, capture_output=True, text=True, timeout=PROBE_TIMEOUT_SECONDS,
    )
    value = json.loads(finished.stdout)
    return value if isinstance(value, dict) else {}


def media_facts(value: dict[str, Any]) -> tuple[float, bool]:
    """(duration in seconds, whether it has an audio stream)."""
    try:
        duration = float((value.get("format") or {}).get("duration"))
    except (TypeError, ValueError):
        raise ValueError("the file has no readable duration") from None
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("the file has no readable duration")
    streams = value.get("streams") or []
    has_audio = any(isinstance(item, dict) and item.get("codec_type") == "audio" for item in streams)
    return duration, has_audio


def finish_command(raw: Path, final: Path, *, width: int, height: int, fps: int, duration: int) -> list[str]:
    video = (
        f"scale={width}:{height}:force_original_aspect_ratio=increase:flags=lanczos,"
        f"crop={width}:{height},fps={fps},trim=duration={duration},setpts=PTS-STARTPTS"
    )
    audio = f"apad=pad_dur={duration},atrim=duration={duration},asetpts=PTS-STARTPTS"
    return [
        "ffmpeg", "-hide_banner", "-loglevel", "warning", "-nostdin", "-y", "-i", str(raw),
        "-filter_complex", f"[0:v]{video}[v];[0:a]{audio}[a]",
        "-map", "[v]", "-map", "[a]", "-map_metadata", "-1",
        "-c:v", "libx264", "-preset", "slow", "-crf", "15", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
        "-t", f"{duration:.3f}", str(final),
    ]


def check_final(value: dict[str, Any], *, width: int, height: int, fps: int, duration: int) -> None:
    streams = [item for item in value.get("streams") or [] if isinstance(item, dict)]
    video = next((item for item in streams if item.get("codec_type") == "video"), None)
    audio = next((item for item in streams if item.get("codec_type") == "audio"), None)
    if video is None or (video.get("width"), video.get("height")) != (width, height):
        raise RuntimeError(f"the delivered video is not {width}x{height}")
    if video.get("codec_name") != "h264" or video.get("pix_fmt") != "yuv420p":
        raise RuntimeError("the delivered video is not H.264 yuv420p")
    if str(video.get("avg_frame_rate")) != f"{fps}/1":
        raise RuntimeError(f"the delivered video is not {fps} fps")
    if audio is None or audio.get("codec_name") != "aac" or int(audio.get("channels") or 0) != 2:
        raise RuntimeError("the delivered video has no AAC stereo audio")
    try:
        delivered = float((value.get("format") or {}).get("duration"))
    except (TypeError, ValueError):
        delivered = math.nan
    if not abs(delivered - duration) <= DURATION_TOLERANCE_SECONDS:
        raise RuntimeError(f"the delivered video is not {duration} seconds long")


def finish_video(raw: Path, final: Path, *, width: int, height: int, fps: int, duration: int) -> dict[str, Any]:
    subprocess.run(
        finish_command(raw, final, width=width, height=height, fps=fps, duration=duration),
        check=True, timeout=ENCODE_TIMEOUT_SECONDS,
    )
    value = probe(final)
    check_final(value, width=width, height=height, fps=fps, duration=duration)
    return value


def write_poster(video: Path, poster: Path) -> bool:
    """Save the opening frame as a PNG. Any failure means no poster, never a failed run."""
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-i", str(video), "-map", "0:v:0", "-frames:v", "1", "-c:v", "png", str(poster),
    ]
    try:
        finished = subprocess.run(command, check=False, timeout=POSTER_TIMEOUT_SECONDS)
        made = finished.returncode == 0 and _is_png(poster) and poster.stat().st_size <= POSTER_MAX_BYTES
    except (OSError, subprocess.SubprocessError):
        made = False
    if not made:
        poster.unlink(missing_ok=True)
        print("minimax-h3: no poster frame could be extracted; publishing the video alone")
    return made


def _is_png(path: Path) -> bool:
    if not path.is_file():
        return False
    with path.open("rb") as handle:
        return handle.read(len(PNG_SIGNATURE)) == PNG_SIGNATURE
