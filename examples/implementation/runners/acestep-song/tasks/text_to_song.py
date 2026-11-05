"""Songs with ACE-Step 1.5: the XL Turbo DiT, optionally planned by the 5Hz LM 4B.

Serves the catalog id song-create-acestep-xl-sft. Inputs, from the claim:

    prompt              the song description, 1 to 4,000 characters
    lyrics              optional lyrics up to 30,000 characters; [Verse]-style
                        section tags turn on the planner's format mode
    instrumental        true renders with the official [Instrumental] marker
    duration_seconds    10 up to the profile's cap (default: the cap)
    generation_profile  draft-120 (default) or quality-60, below
    bpm                 optional, 30 to 300
    key_scale           optional note and mode, e.g. "F# minor"
    time_signature      blank (the model decides), 2, 3, 4 or 6
    vocal_language      an ACE-Step language code, or unknown (default)
    seed                optional, 0 to 2^31-1; the exact seed is never changed

Profiles (each is also the models.json profile):

    draft-120   up to 120 s, quicker: XL Turbo alone, 8 steps, shift 3
    quality-60  up to 60 s, slower and cleaner: XL Turbo plus the 5Hz LM 4B
                planner (vLLM, thinking on); blank lyrics let it write the song

Every render must pass an objective PCM check (length, silence, clipping,
noise) before it is published; a random-seed request gets one retry with a new
seed. Writes out/song.mp3 (320 kbps) and out/song.wav (48 kHz 16-bit PCM). The
prompt and lyrics are never logged, put in errors or written to result.json.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import secrets
import subprocess
from typing import Any, Callable

import runner_io


@dataclass(frozen=True)
class SongProfile:
    id: str
    dit: str
    lm: str | None
    thinking: bool
    max_duration_seconds: int
    plan_without_lyrics: bool


PROFILES = {
    "draft-120": SongProfile("draft-120", "acestep-v15-xl-turbo", None, False, 120, False),
    "quality-60": SongProfile("quality-60", "acestep-v15-xl-turbo", "acestep-5Hz-lm-4B", True, 60, True),
}
DEFAULT_PROFILE = "draft-120"
INPUTS = {
    "prompt", "lyrics", "instrumental", "duration_seconds", "generation_profile",
    "bpm", "key_scale", "time_signature", "vocal_language", "seed",
}
MIN_DURATION_SECONDS = 10
MAX_SEED = 2**31 - 1
INFERENCE_STEPS = 8
GUIDANCE_SCALE = 1.0
SHIFT = 3.0
STARTUP_TIMEOUT_SECONDS = 1200
ATTEMPT_TIMEOUT_SECONDS = 1800
# The vocal languages ACE-Step 1.5 accepts (its VALID_LANGUAGES), plus unknown.
VOCAL_LANGUAGES = frozenset(
    "ar az bg bn ca cs da de el en es fa fi fr he hi hr ht hu id is it ja ko la lt ms ne nl no pa pl pt "
    "ro ru sa sk sr sv sw ta te th tl tr uk unknown ur vi yue zh".split()
)
TIME_SIGNATURES = ("2", "3", "4", "6")
KEY_SCALE = re.compile(r"^([A-G](?:#|b|♯|♭)?)\s+(major|minor)$", re.IGNORECASE)
LYRIC_SECTION = re.compile(r"(?m)^\s*\[[A-Za-z][^\]\n]{0,48}\]\s*$")


def plan(request: runner_io.Request) -> dict[str, Any]:
    inputs = request.inputs
    runner_io.only(inputs, INPUTS)
    if request.sources:
        raise runner_io.RequestError("song generation reads no source assets")
    profile = PROFILES[runner_io.choice(inputs, "generation_profile", tuple(PROFILES), default=DEFAULT_PROFILE)]
    return {
        "profile": profile.id,
        "prompt": runner_io.text(inputs, "prompt", max_length=4000),
        "lyrics": runner_io.text(inputs, "lyrics", max_length=30000, required=False) or "",
        "instrumental": runner_io.boolean(inputs, "instrumental", default=False),
        "duration_seconds": runner_io.integer(
            inputs, "duration_seconds", minimum=MIN_DURATION_SECONDS, maximum=profile.max_duration_seconds,
            required=False, default=profile.max_duration_seconds,
        ),
        "bpm": runner_io.integer(inputs, "bpm", minimum=30, maximum=300, required=False),
        "key_scale": _key_scale(inputs.get("key_scale", "")),
        "time_signature": _time_signature(inputs.get("time_signature", "")),
        "vocal_language": _vocal_language(inputs.get("vocal_language", "")),
        "seed": runner_io.integer(inputs, "seed", minimum=0, maximum=MAX_SEED, required=False),
    }


def _key_scale(raw: str) -> str:
    value = raw.strip()
    if not value:
        return ""
    match = KEY_SCALE.fullmatch(value) if len(value) <= 32 else None
    if match is None:
        raise runner_io.RequestError("key_scale must be a note followed by major or minor, such as F# minor")
    return f"{match.group(1)} {match.group(2).lower()}"


def _time_signature(raw: str) -> str:
    value = raw.strip()
    if value and value not in TIME_SIGNATURES:
        raise runner_io.RequestError(f"time_signature must be blank or one of {', '.join(TIME_SIGNATURES)}")
    return value


def _vocal_language(raw: str) -> str:
    value = raw.strip().lower() or "unknown"
    if value not in VOCAL_LANGUAGES:
        raise runner_io.RequestError("vocal_language must be an ACE-Step language code or unknown")
    return value


def redaction_values(plan: dict[str, Any]) -> tuple[str, ...]:
    """Request text that must never reach a log: the prompt, the lyrics, and each line of them."""
    values = {plan["prompt"], plan["lyrics"]}
    for text in (plan["prompt"], plan["lyrics"]):
        values.update(line.strip() for line in text.splitlines() if len(line.strip()) >= 4)
    return tuple(sorted(value for value in values if value))


def release_payload(plan: dict[str, Any], *, token: str, seed: int) -> dict[str, Any]:
    """The ACE-Step /release_task body for one attempt."""
    profile = PROFILES[plan["profile"]]
    instrumental = bool(plan["instrumental"])
    lyrics = "[Instrumental]" if instrumental else plan["lyrics"]
    sample_mode = profile.plan_without_lyrics and not instrumental and not lyrics
    use_format = bool(profile.lm and lyrics and not instrumental and LYRIC_SECTION.search(lyrics))
    planner = profile.lm is not None
    payload: dict[str, Any] = {
        "ai_token": token,
        "prompt": "" if sample_mode else plan["prompt"],
        "lyrics": lyrics,
        "thinking": profile.thinking,
        "sample_mode": sample_mode,
        "sample_query": plan["prompt"] if sample_mode else "",
        "use_format": use_format,
        "model": profile.dit,
        "bpm": plan["bpm"],
        "key_scale": plan["key_scale"],
        "time_signature": plan["time_signature"],
        "vocal_language": plan["vocal_language"],
        "audio_duration": plan["duration_seconds"],
        "audio_format": "wav",
        "batch_size": 1,
        "inference_steps": INFERENCE_STEPS,
        "guidance_scale": GUIDANCE_SCALE,
        "shift": SHIFT,
        "use_random_seed": False,
        "seed": seed,
        "constrained_decoding": planner,
        "use_cot_caption": planner,
        "use_cot_language": planner,
    }
    if planner:
        payload["lm_model_path"] = profile.lm
        payload["lm_backend"] = "vllm"
    return payload


def generate_publishable_wav(
    client: Any,
    plan: dict[str, Any],
    wav: Path,
    *,
    token: str,
    validate: Callable[..., Any],
    rejected: type[Exception],
    random_seed: Callable[[], int] = lambda: secrets.randbelow(MAX_SEED + 1),
) -> tuple[int, Any]:
    """Render until a waveform passes `validate`: once for a fixed seed, twice for a random one."""
    attempts = 1 if plan["seed"] is not None else 2
    failure: Exception | None = None
    for attempt in range(1, attempts + 1):
        seed = plan["seed"] if plan["seed"] is not None else random_seed()
        task_id = client.release(release_payload(plan, token=token, seed=seed))
        client.download(client.wait_for_result(task_id, timeout=ATTEMPT_TIMEOUT_SECONDS), wav)
        try:
            return seed, validate(wav, expected_duration_seconds=plan["duration_seconds"])
        except rejected as error:
            failure = error
            print(f"ACE-Step render {attempt}/{attempts} rejected: {error}", flush=True)
    assert failure is not None
    raise failure


def mp3_command(wav: Path, mp3: Path) -> list[str]:
    return ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", str(wav), "-codec:a", "libmp3lame", "-b:a", "320k", str(mp3)]


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    from acestep_song import audio_quality, server

    profile = PROFILES[plan["profile"]]
    scratch = context.scratch_dir / "acestep"
    scratch.mkdir(parents=True, exist_ok=True)
    wav = context.output_dir / "song.wav"
    mp3 = context.output_dir / "song.mp3"
    redact = redaction_values(plan)
    with server.running(models_dir=context.models_dir, scratch=scratch, dit=profile.dit, lm=profile.lm, redact=redact) as (client, alive):
        client.wait_until_ready(dit=profile.dit, lm=profile.lm, timeout=STARTUP_TIMEOUT_SECONDS, alive=alive)
        seed, metrics = generate_publishable_wav(
            client, plan, wav, token=client.token,
            validate=audio_quality.validate_wav_quality, rejected=audio_quality.AudioQualityError,
        )
    subprocess.run(mp3_command(wav, mp3), check=True, capture_output=True, text=True)
    metadata = {
        "generator": "ACE-Step 1.5",
        "generation_profile": profile.id,
        "model": profile.dit,
        "lm_model": profile.lm or "",
        "inference_steps": INFERENCE_STEPS,
        "guidance_scale": GUIDANCE_SCALE,
        "shift": SHIFT,
        "duration_seconds": plan["duration_seconds"],
        "bpm": plan["bpm"],
        "key_scale": plan["key_scale"],
        "time_signature": plan["time_signature"],
        "vocal_language": plan["vocal_language"],
        "instrumental": plan["instrumental"],
        "seed": seed,
        "audio_quality": metrics.as_json(),
    }
    return [runner_io.Artifact("song.mp3", "audio/mpeg"), runner_io.Artifact("song.wav", "audio/wav")], metadata
