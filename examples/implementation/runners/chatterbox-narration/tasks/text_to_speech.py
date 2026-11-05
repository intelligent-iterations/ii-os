"""Narration with Chatterbox Turbo (ResembleAI/chatterbox-turbo), optionally in
a reference voice.

Serves the catalog id narration-create-chatterbox-tts. Inputs, from the claim:

    text                      what to say, 1 to 6,000 characters
    voice_model               chatterbox-turbo, the only voice model (default)
    language                  a language label up to 32 characters (default
                              English); Chatterbox Turbo speaks English
    seed                      optional whole number for a repeatable take
    voice_reference_asset_id  optional ii-os audio asset whose voice to use; the
                              claim stages it at in/sources/00.<ext>
    voice_clone_consent       must be true whenever a voice reference is given

A voice reference is used only with consent, only when it is the staged asset
the request names, and only if it is 50 MB or smaller and longer than five
seconds once cut to its first 30 seconds of 24 kHz mono.

Writes out/narration.mp3 and out/narration.wav. Chatterbox embeds Resemble AI's
Perth audio watermark in everything it generates.
"""

from __future__ import annotations

from pathlib import Path
import random
import subprocess
from typing import Any, Callable

import runner_io

INPUTS = {"text", "voice_model", "language", "seed", "voice_reference_asset_id", "voice_clone_consent"}
VOICE_MODELS = ("chatterbox-turbo",)
MODEL = "ResembleAI/chatterbox-turbo"
MODEL_REVISION = "749d1c1a46eb10492095d68fbcf55691ccf137cd"
# Every file ChatterboxTurboTTS.from_local reads from the voice model folder.
MODEL_FILES = (
    "ve.safetensors",
    "t3_turbo_v1.safetensors",
    "s3gen_meanflow.safetensors",
    "conds.pt",
    "added_tokens.json",
    "merges.txt",
    "special_tokens_map.json",
    "tokenizer_config.json",
    "vocab.json",
)
MAX_TEXT = 6000
MAX_LANGUAGE = 32
MAX_SEED = 2**53 - 1
REFERENCE_MAX_BYTES = 50 * 1024 * 1024
REFERENCE_MAX_SECONDS = 30
REFERENCE_MIN_SECONDS = 5.25  # Chatterbox needs more than 5 s after resampling.
REFERENCE_SAMPLE_RATE = 24000
SAMPLING = {"temperature": 0.8, "top_p": 0.95, "top_k": 1000, "repetition_penalty": 1.2}

Runner = Callable[..., "subprocess.CompletedProcess[str]"]


def plan(request: runner_io.Request) -> dict[str, Any]:
    runner_io.only(request.inputs, INPUTS)
    voice_model = runner_io.choice(request.inputs, "voice_model", VOICE_MODELS, default=VOICE_MODELS[0])
    text = runner_io.text(request.inputs, "text", max_length=MAX_TEXT)
    language = runner_io.text(request.inputs, "language", max_length=MAX_LANGUAGE, required=False) or "English"
    seed = runner_io.integer(request.inputs, "seed", minimum=0, maximum=MAX_SEED, required=False)
    reference = _voice_reference(request)
    return {
        "profile": voice_model,
        "voice_model": voice_model,
        "text": text,
        "language": language,
        "seed": seed if seed is not None else random.randrange(1, 2**32),
        "reference": str(reference.path) if reference is not None else None,
    }


def _voice_reference(request: runner_io.Request) -> runner_io.Source | None:
    asset_id = runner_io.text(request.inputs, "voice_reference_asset_id", max_length=64, required=False)
    if asset_id is None:
        if request.sources:
            raise runner_io.RequestError("a source asset was staged but voice_reference_asset_id names none")
        return None
    if not runner_io.boolean(request.inputs, "voice_clone_consent", default=False):
        raise runner_io.RequestError("voice_clone_consent must be true to narrate in a reference voice")
    sources = runner_io.sources_of(request, "audio", minimum=0, maximum=1)
    if not sources:
        raise runner_io.RequestError("the voice reference was not staged by the claim")
    source = sources[0]
    if source.asset_id and source.asset_id != asset_id:
        raise runner_io.RequestError("the staged audio is not the asset voice_reference_asset_id names")
    if source.size_bytes > REFERENCE_MAX_BYTES:
        raise runner_io.RequestError("the voice reference must be 50 MB or smaller")
    return source


def reference_command(source: Path, destination: Path) -> list[str]:
    return [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-i", str(source),
        "-t", str(REFERENCE_MAX_SECONDS), "-ar", str(REFERENCE_SAMPLE_RATE), "-ac", "1",
        "-map_metadata", "-1",
        str(destination),
    ]


def duration_command(path: Path) -> list[str]:
    return ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nokey=1:noprint_wrappers=1", str(path)]


def mp3_command(wav: Path, mp3: Path) -> list[str]:
    return ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", str(wav), "-codec:a", "libmp3lame", "-q:a", "2", str(mp3)]


def decode_check_command(path: Path) -> list[str]:
    return ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-i", str(path), "-f", "null", "-"]


def prepare_reference(source: Path, scratch: Path, *, run: Runner = subprocess.run) -> Path:
    """Cut the staged reference to the mono 24 kHz WAV Chatterbox conditions on."""
    scratch.mkdir(parents=True, exist_ok=True)
    wav = scratch / "voice-reference.wav"
    run(reference_command(source, wav), check=True, capture_output=True, text=True)
    probed = run(duration_command(wav), check=True, capture_output=True, text=True)
    try:
        seconds = float(str(probed.stdout).strip())
    except ValueError:
        raise runner_io.RequestError("the voice reference could not be read as audio") from None
    if seconds <= REFERENCE_MIN_SECONDS:
        raise runner_io.RequestError("the voice reference must be longer than 5 seconds")
    return wav


def run(plan: dict[str, Any], request: runner_io.Request, context: Any) -> tuple[list[runner_io.Artifact], dict[str, Any]]:
    import numpy as np
    import soundfile
    import torch
    from chatterbox.tts_turbo import ChatterboxTurboTTS

    if not torch.cuda.is_available():
        raise RuntimeError("Chatterbox narration needs an NVIDIA GPU; the container sees none")
    reference = None
    if plan["reference"]:
        reference = prepare_reference(Path(plan["reference"]), context.scratch_dir / "narration")

    seed = int(plan["seed"])
    random.seed(seed)
    np.random.seed(seed % 2**32)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)

    model = ChatterboxTurboTTS.from_local(context.models_dir / plan["voice_model"], device="cuda")
    options: dict[str, Any] = dict(SAMPLING)
    if reference is not None:
        options["audio_prompt_path"] = str(reference)
    waveform = model.generate(plan["text"], **options)
    samples = waveform.squeeze().detach().cpu().numpy().astype(np.float32)
    if samples.size == 0:
        raise RuntimeError("Chatterbox produced no audio")

    sample_rate = int(model.sr)
    wav = context.output_dir / "narration.wav"
    mp3 = context.output_dir / "narration.mp3"
    soundfile.write(str(wav), samples, sample_rate, subtype="PCM_16")
    subprocess.run(mp3_command(wav, mp3), check=True, capture_output=True, text=True)
    subprocess.run(decode_check_command(mp3), check=True, capture_output=True, text=True)
    metadata = {
        "model": MODEL,
        "model_revision": MODEL_REVISION,
        "voice_model": plan["voice_model"],
        "seed": seed,
        "sample_rate": sample_rate,
        "duration_seconds": round(samples.size / sample_rate, 3),
        "voice_reference": reference is not None,
    }
    return [runner_io.Artifact("narration.mp3", "audio/mpeg"), runner_io.Artifact("narration.wav", "audio/wav")], metadata
