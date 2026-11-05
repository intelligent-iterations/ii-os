"""ffprobe and ffmpeg steps around the SeedVR2 upscale, run inside the container.

- `probe_source` + `check_source`: the source envelope the upscale accepts. A
  source that cannot be read or lies outside it is refused with the stable code
  `video_upscale_source_unsupported` (written to out/failure.json), so ii-os
  can say why. `probe` alone raises RuntimeError, as for the output.
- `check_output`: the upscale kept every frame, the frame rate and the aspect
  ratio, and reached the 1080-pixel short edge.
- `remux`: puts the source's first audio stream back beside the upscaled video
  (stream copy, then AAC if the codec cannot live in MP4) and always writes an
  MP4 with the index at the front for streaming.
- `extract_poster`: the opening frame as a PNG. Optional by design: a missing
  poster never fails a finished upscale.

Standard library only; `run` is injectable so tests need no ffmpeg.
"""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
from typing import Any, Callable, Mapping

import runner_io

SOURCE_UNSUPPORTED = "video_upscale_source_unsupported"
MAX_DURATION_SECONDS = 30.0
MAX_FRAMES = 1800
MAX_FPS = 60.0
MAX_EDGE = 4096
# A 1080-pixel short edge with a 1920-pixel long-edge cap: anything wider than
# 16:9 would have to be upscaled below 1080 to fit.
MAX_ASPECT = 1920 / 1080
MAX_POSTER_BYTES = 8 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
FFMPEG_TIMEOUT_SECONDS = 1800

Runner = Callable[..., subprocess.CompletedProcess]


def parse_probe(document: Mapping[str, Any]) -> dict[str, Any]:
    """Summarise `ffprobe -show_streams -show_format -count_frames -of json`."""
    streams = document.get("streams") or []
    video = next((item for item in streams if isinstance(item, dict) and item.get("codec_type") == "video"), None)
    if video is None:
        raise RuntimeError("the file has no video stream")
    audio = next((item for item in streams if isinstance(item, dict) and item.get("codec_type") == "audio"), None)
    # ffprobe writes "N/A" or "0/0" for values a container does not record
    # (WebM has no per-stream duration), so each falls back to the next source.
    fps = _rate(video.get("avg_frame_rate")) or _rate(video.get("r_frame_rate"))
    duration = _number(video.get("duration")) or _number((document.get("format") or {}).get("duration"))
    return {
        "width": int(_number(video.get("width"))),
        "height": int(_number(video.get("height"))),
        "fps": fps,
        "frames": int(_number(video.get("nb_read_frames")) or _number(video.get("nb_frames"))),
        "duration_seconds": duration,
        "has_audio": audio is not None,
        "audio_codec": None if audio is None else audio.get("codec_name"),
    }


def _number(value: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0
    return number if number == number and number not in (float("inf"), float("-inf")) else 0.0


def _rate(value: Any) -> float:
    numerator, _, denominator = str(value or "").partition("/")
    top, bottom = _number(numerator), _number(denominator or 1)
    return top / bottom if bottom else 0.0


def probe(path: Path, *, run: Runner = subprocess.run) -> dict[str, Any]:
    command = ["ffprobe", "-v", "error", "-show_streams", "-show_format", "-count_frames", "-of", "json", str(path)]
    result = run(command, capture_output=True, text=True, check=False, timeout=FFMPEG_TIMEOUT_SECONDS)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe could not read {path.name}: {(result.stderr or '')[-500:]}")
    try:
        document = json.loads(result.stdout or "{}")
    except json.JSONDecodeError:
        raise RuntimeError(f"ffprobe returned no summary for {path.name}") from None
    return parse_probe(document)


def probe_source(path: Path, *, run: Runner = subprocess.run) -> dict[str, Any]:
    try:
        return probe(path, run=run)
    except RuntimeError as error:
        message = "the source has no video stream" if "video stream" in str(error) else "the source video could not be read"
        raise runner_io.RequestError(message, code=SOURCE_UNSUPPORTED) from None


def check_source(summary: Mapping[str, Any]) -> None:
    width, height = int(summary["width"]), int(summary["height"])
    if min(width, height) <= 0 or max(width, height) > MAX_EDGE:
        raise runner_io.RequestError(f"the source video must be at most {MAX_EDGE} pixels on its long edge", code=SOURCE_UNSUPPORTED)
    if max(width, height) / min(width, height) > MAX_ASPECT + 1e-6:
        raise runner_io.RequestError(
            "the source aspect ratio is wider than 16:9, so it cannot reach a 1080-pixel short edge", code=SOURCE_UNSUPPORTED
        )
    if not 0 < float(summary["fps"]) <= MAX_FPS:
        raise runner_io.RequestError(f"the source frame rate must be above 0 and at most {MAX_FPS:g} FPS", code=SOURCE_UNSUPPORTED)
    if not 0 < float(summary["duration_seconds"]) <= MAX_DURATION_SECONDS:
        raise runner_io.RequestError(f"the source video must be at most {MAX_DURATION_SECONDS:g} seconds long", code=SOURCE_UNSUPPORTED)
    if not 0 < int(summary["frames"]) <= MAX_FRAMES:
        raise runner_io.RequestError(f"the source video must have 1 to {MAX_FRAMES} frames", code=SOURCE_UNSUPPORTED)


def check_output(source: Mapping[str, Any], output: Mapping[str, Any], *, target: int) -> None:
    width, height = int(output["width"]), int(output["height"])
    if min(width, height) <= 0:
        raise RuntimeError(f"the upscaled video has no picture: {dict(output)}")
    if abs(min(width, height) - target) > 32 or max(width, height) > round(target * MAX_ASPECT):
        raise RuntimeError(f"the upscaled video is {width}x{height}, not a {target}-pixel short edge")
    if abs(float(output["fps"]) - float(source["fps"])) > 0.01:
        raise RuntimeError(f"the upscale changed the frame rate from {source['fps']} to {output['fps']}")
    if int(output["frames"]) != int(source["frames"]):
        raise RuntimeError(f"the upscale changed the frame count from {source['frames']} to {output['frames']}")
    if abs(width / height - int(source["width"]) / int(source["height"])) > 0.01:
        raise RuntimeError("the upscale changed the aspect ratio")


def remux(rendered: Path, source: Path, destination: Path, *, keep_audio: bool, run: Runner = subprocess.run) -> str:
    """Write `destination` as an MP4. Returns copy, aac_fallback or video_only."""
    base = ["ffmpeg", "-y", "-v", "error", "-i", str(rendered)]
    if not keep_audio:
        _ffmpeg(run, [*base, "-map", "0:v:0", "-c:v", "copy", "-movflags", "+faststart", str(destination)])
        return "video_only"
    base += ["-i", str(source), "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy"]
    if _ffmpeg(run, [*base, "-c:a", "copy", "-movflags", "+faststart", str(destination)], required=False):
        return "copy"
    destination.unlink(missing_ok=True)
    _ffmpeg(run, [*base, "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(destination)])
    return "aac_fallback"


def extract_poster(video: Path, destination: Path, *, run: Runner = subprocess.run) -> bool:
    """The opening frame as a PNG; returns False (and leaves no file) on any problem."""
    destination.unlink(missing_ok=True)
    # -map 0:v:0 so attached cover art can never stand in for a frame.
    command = ["ffmpeg", "-y", "-v", "error", "-i", str(video), "-map", "0:v:0", "-frames:v", "1", "-c:v", "png", str(destination)]
    try:
        made = _ffmpeg(run, command, required=False)
    except (OSError, subprocess.SubprocessError):
        made = False
    try:
        if made and 0 < destination.stat().st_size <= MAX_POSTER_BYTES:
            with destination.open("rb") as handle:
                if handle.read(len(PNG_SIGNATURE)) == PNG_SIGNATURE:
                    return True
    except OSError:
        pass
    destination.unlink(missing_ok=True)
    print("poster: the opening frame could not be extracted; publishing the video alone")
    return False


def _ffmpeg(run: Runner, command: list[str], *, required: bool = True) -> bool:
    result = run(command, capture_output=True, text=True, check=False, timeout=FFMPEG_TIMEOUT_SECONDS)
    if result.returncode == 0:
        return True
    if required:
        detail = (getattr(result, "stderr", "") or "")[-2000:]
        raise RuntimeError(f"ffmpeg exited with {result.returncode}: {detail}")
    return False
