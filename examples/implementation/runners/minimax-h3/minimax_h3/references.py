"""MiniMax H3 reference manifests: modes, roles, staged sources and durations.

ii-os sends `generation_mode` and a `reference_manifest` (asset ids, kinds,
roles and ordinals, never URLs or bytes) and stages the matching sources
through the claim. The runner re-checks everything the model depends on
instead of trusting the dispatch: the mode rules, the per-kind ceilings, that
the claim staged exactly the manifest, and (inside the container, after
ffprobe) each clip's length.

Endpoint modes (FL2VA) run on the FL2VA transformer; reference, edit and
continuation modes (Ref2VA) run on the Ref2VA transformer. Standard library
only.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import re
from typing import Any, Iterable, Mapping, Sequence

FL2VA_MODES = ("text_to_video", "first_frame_to_video", "last_frame_to_video", "first_last_frame_to_video")
REF2VA_MODES = ("reference_to_video", "video_edit", "video_continue")
GENERATION_MODES = FL2VA_MODES + REF2VA_MODES
ROLE_KINDS = {
    "first_frame": "image",
    "last_frame": "image",
    "subject": "image",
    "style": "image",
    "environment": "image",
    "pose_reference": "image",
    "effect_reference": "image",
    "source_video": "video",
    "motion_reference": "video",
    "video_subject": "video",
    "video_style": "video",
    "video_environment": "video",
    "video_action": "video",
    "video_effect": "video",
    "audio_reference": "audio",
    "audio_reuse": "audio",
}
COUNT_LIMITS = {"image": 9, "video": 3, "audio": 3}
MAX_REFERENCES = 12
EDIT_OPERATIONS = ("general_edit", "character_replacement", "object_replacement", "motion_transfer", "background_replacement")
MAX_MANIFEST_LENGTH = 30000
# Each video or audio reference is 2 to 15 seconds, and each kind totals at
# most 15 seconds; the 0.05 s allows for container rounding.
MIN_MEDIA_SECONDS = 2.0
MAX_MEDIA_SECONDS = 15.05
ASSET_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,199}$")
FL2VA_LABEL = "integrated_multimodal_description:"
SUBJECT_HEADING = "subject_definitions:"


class ManifestError(ValueError):
    """The references cannot be used as sent. The message names no media or text."""


@dataclass(frozen=True)
class Reference:
    asset_id: str
    kind: str
    role: str
    ordinal: int


@dataclass(frozen=True)
class Manifest:
    mode: str
    references: tuple[Reference, ...]
    edit_operation: str | None = None
    identity_replacement_consent: bool | None = None


def parse_manifest(raw: str | None, mode: str) -> Manifest:
    if mode not in GENERATION_MODES:
        raise ManifestError(f"generation_mode must be one of {', '.join(GENERATION_MODES)}")
    if raw is None or not raw.strip():
        if mode != "text_to_video":
            raise ManifestError(f"{mode} needs a reference_manifest")
        return Manifest(mode, ())
    if len(raw) > MAX_MANIFEST_LENGTH:
        raise ManifestError("the reference manifest is too long")
    try:
        value = json.loads(raw)
    except ValueError:
        raise ManifestError("the reference manifest is not JSON") from None
    if not isinstance(value, dict):
        raise ManifestError("the reference manifest must be an object")
    _only(value, {"schema_version", "mode", "references", "edit_operation", "identity_replacement_consent"})
    if value.get("schema_version") != 1:
        raise ManifestError("the reference manifest version is unsupported")
    if value.get("mode") != mode:
        raise ManifestError("the reference manifest mode does not match generation_mode")
    entries = value.get("references")
    if not isinstance(entries, list) or len(entries) > MAX_REFERENCES:
        raise ManifestError(f"the reference manifest lists at most {MAX_REFERENCES} references")
    found = tuple(_reference(entry, ordinal) for ordinal, entry in enumerate(entries))
    if len({item.asset_id for item in found}) != len(found):
        raise ManifestError("a reference is listed twice")
    for kind, limit in COUNT_LIMITS.items():
        if sum(item.kind == kind for item in found) > limit:
            raise ManifestError(f"MiniMax H3 reads at most {limit} {kind} references")
    manifest = Manifest(mode, found, value.get("edit_operation"), value.get("identity_replacement_consent"))
    _check_mode(manifest, value)
    return manifest


def _only(value: Mapping[str, Any], allowed: set[str]) -> None:
    if set(value) - allowed:
        raise ManifestError("the reference manifest has an unknown field")


def _reference(entry: Any, ordinal: int) -> Reference:
    if not isinstance(entry, dict):
        raise ManifestError(f"reference {ordinal} is not an object")
    _only(entry, {"asset_id", "kind", "role", "ordinal"})
    asset_id, kind, role = entry.get("asset_id"), entry.get("kind"), entry.get("role")
    if not isinstance(asset_id, str) or not ASSET_ID.fullmatch(asset_id):
        raise ManifestError(f"reference {ordinal} has no asset id")
    if entry.get("ordinal") != ordinal:
        raise ManifestError(f"reference {ordinal} is out of order")
    if not isinstance(role, str) or ROLE_KINDS.get(role) is None or ROLE_KINDS[role] != kind:
        raise ManifestError(f"reference {ordinal} has a role that does not fit its kind")
    return Reference(asset_id, kind, role, ordinal)


def _check_mode(manifest: Manifest, value: Mapping[str, Any]) -> None:
    mode, roles = manifest.mode, [item.role for item in manifest.references]
    if mode != "video_edit" and ("edit_operation" in value or "identity_replacement_consent" in value):
        raise ManifestError("only video_edit takes edit_operation and identity_replacement_consent")
    rules = {
        "text_to_video": (not roles, "text_to_video takes no references"),
        "first_frame_to_video": (roles == ["first_frame"], "first_frame_to_video takes one first_frame image"),
        "last_frame_to_video": (roles == ["last_frame"], "last_frame_to_video takes one last_frame image"),
        "first_last_frame_to_video": (
            sorted(roles) == ["first_frame", "last_frame"], "first_last_frame_to_video takes one first_frame and one last_frame image"
        ),
        "reference_to_video": (bool(roles), "reference_to_video needs at least one reference"),
        "video_edit": (roles.count("source_video") == 1, "video_edit needs exactly one source_video"),
        "video_continue": (roles.count("source_video") == 1, "video_continue needs exactly one source_video"),
    }
    accepted, message = rules[mode]
    if not accepted:
        raise ManifestError(message)
    if mode != "video_edit":
        return
    if manifest.edit_operation not in EDIT_OPERATIONS:
        raise ManifestError(f"edit_operation must be one of {', '.join(EDIT_OPERATIONS)}")
    if not isinstance(manifest.identity_replacement_consent, bool):
        raise ManifestError("identity_replacement_consent must be true or false")
    if manifest.edit_operation == "character_replacement":
        if not manifest.identity_replacement_consent:
            raise ManifestError("character replacement needs confirmed permission to use the identity")
        if not {"subject", "video_subject"} & set(roles):
            raise ManifestError("character replacement needs a subject reference")


def check_declared(manifest: Manifest, *, edit_operation: str | None, consent: str | None) -> None:
    """The plain edit inputs, when sent, must say what the manifest says."""
    if manifest.mode != "video_edit":
        if edit_operation or consent:
            raise ManifestError("only video_edit takes edit_operation and identity_replacement_consent")
        return
    if edit_operation and edit_operation != manifest.edit_operation:
        raise ManifestError("edit_operation does not match the reference manifest")
    if consent and consent != str(manifest.identity_replacement_consent).lower():
        raise ManifestError("identity_replacement_consent does not match the reference manifest")


def match_sources(manifest: Manifest, sources: Sequence[Any]) -> None:
    """The claim must have staged exactly the manifest, in order."""
    if len(sources) != len(manifest.references):
        raise ManifestError("the staged sources do not match the reference manifest")
    for reference, source in zip(manifest.references, sources):
        staged = (source.asset_id, source.kind, source.role, source.ordinal)
        if staged != (reference.asset_id, reference.kind, reference.role, reference.ordinal):
            raise ManifestError(f"staged source {reference.ordinal} does not match the reference manifest")


def check_durations(durations: Iterable[tuple[Reference, float]]) -> None:
    totals = {"video": 0.0, "audio": 0.0}
    for reference, seconds in durations:
        if not MIN_MEDIA_SECONDS <= seconds <= MAX_MEDIA_SECONDS:
            raise ManifestError(f"{reference.kind} reference {reference.ordinal} must be 2 to 15 seconds long")
        totals[reference.kind] += seconds
    for kind, total in totals.items():
        if total > MAX_MEDIA_SECONDS:
            raise ManifestError(f"{kind} references must total at most 15 seconds")


_ROLE_DIRECTIONS = {
    "first_frame": "is the concrete opening-frame anchor",
    "last_frame": "is the concrete final-frame anchor",
    "subject": "defines the subject identity and visible appearance",
    "style": "defines the target visual style",
    "environment": "defines the target environment",
    "pose_reference": "defines the target action and body pose",
    "effect_reference": "defines the target visible effect",
    "motion_reference": "defines the motion, camera path, cuts, and rhythm",
    "video_subject": "defines the subject or object identity over time",
    "video_style": "defines the target visual style over time",
    "video_environment": "defines the target environment over time",
    "video_action": "defines the target action and body pose over time",
    "video_effect": "defines the target visible effect over time",
    "audio_reference": "guides timbre, rhythm, and audible continuity",
    "audio_reuse": "is copied or retained as the requested target audio",
}
_EDIT_SOURCE = "is the source timeline to edit"
_CONTINUE_SOURCE = "is the source whose final moment begins the continuation"


def prepare_prompt(prompt: str, mode: str, references: Sequence[Reference]) -> str:
    """Add the structure H3 reads; the person's own words are kept verbatim.

    Endpoint modes read the prompt from an `integrated_multimodal_description:`
    field. Reference modes name each reference by its tag (<Picture 1>,
    <Video 1>, <Audio 1>, numbered per kind in manifest order) and role under
    `subject_definitions:`.
    """
    if mode in FL2VA_MODES:
        return prompt if FL2VA_LABEL in prompt else f"{FL2VA_LABEL} {prompt}"
    counters = {"image": 0, "video": 0, "audio": 0}
    tags = {"image": "Picture", "video": "Video", "audio": "Audio"}
    lines = []
    for item in references:
        counters[item.kind] += 1
        if item.role == "source_video":
            direction = _EDIT_SOURCE if mode == "video_edit" else _CONTINUE_SOURCE
        else:
            direction = _ROLE_DIRECTIONS[item.role]
        lines.append(f"<{tags[item.kind]} {counters[item.kind]}> {direction}.")
    assignments = "\n".join(lines)
    if SUBJECT_HEADING in prompt:
        return prompt.replace(SUBJECT_HEADING, f"{SUBJECT_HEADING}\n{assignments}", 1)
    return f"{SUBJECT_HEADING}\n{assignments}\n\n{prompt}"


def add_conditioning(graph: dict[str, Any], mode: str, staged: Sequence[tuple[Reference, str]]) -> None:
    """Load each staged reference and wire it into node 5 (from node 20 on)."""
    node = 20
    image_to_video = graph["5"]["inputs"]
    if mode in FL2VA_MODES:
        for reference, name in staged:
            graph[str(node)] = {"class_type": "LoadImage", "inputs": {"image": name}}
            image_to_video[reference.role] = [str(node), 0]
            node += 1
        return
    graph["5"]["class_type"] = "MiniMaxH3ReferenceToVideo"
    image_to_video.update(audio_vae=["4", 0], ref_image_size="match")
    index = {"image": 0, "video": 0, "audio": 0}
    for reference, name in staged:
        slot = index[reference.kind]
        index[reference.kind] += 1
        if reference.kind == "image":
            graph[str(node)] = {"class_type": "LoadImage", "inputs": {"image": name}}
            image_to_video[f"ref_images.ref_image_{slot}"] = [str(node), 0]
            node += 1
        elif reference.kind == "video":
            graph[str(node)] = {"class_type": "LoadVideo", "inputs": {"file": name}}
            graph[str(node + 1)] = {"class_type": "GetVideoComponents", "inputs": {"video": [str(node), 0]}}
            image_to_video[f"ref_videos.ref_video_{slot}"] = [str(node + 1), 0]
            node += 2
        else:
            graph[str(node)] = {"class_type": "LoadAudio", "inputs": {"audio": name}}
            image_to_video[f"ref_audios.ref_audio_{slot}"] = [str(node), 0]
            node += 1
