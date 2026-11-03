# MiniMax H3 generation contract

Status: version 1 implementation contract for ii-os workspace workflows.

This contract separates MiniMax H3's model capability from the capability a
particular workspace runner has actually deployed. The ii-os UI MUST enable a
mode only when the selected workflow advertises every input required by that
mode. A workflow advertises endpoint-frame and Ref2VA inputs only when the
renderer its deployment pins actually implements them.

## Model capability

The H3 family accepts text, image, video, and audio context and produces video
with synchronized stereo audio. The open H3 release documents:

- 4-15 second output, 24 FPS, and output up to 2K;
- FL2VA with zero, one, or two endpoint images;
- Ref2VA with at most 9 images, 3 videos, 3 audio files, and 12 files total;
- at most 15 seconds of video references and 15 seconds of audio references;
- subject and environment reference, motion transfer, video editing,
  character or object replacement, and audio reference or reuse.

Upstream references:

- [MiniMax H3 repository](https://github.com/MiniMax-AI/MiniMax-H3)
- [MiniMax H3 model card](https://huggingface.co/MiniMaxAI/MiniMax-H3)
- [MiniMax H3 prompting guide](https://huggingface.co/MiniMaxAI/MiniMax-H3/blob/main/docs/VIDEO_PROMPT_WRITING_GUIDE_base_en.md)

The upstream limits are maxima, not a promise that every workspace runner can
serve every resolution or mode. A workflow catalog is the source of truth for
deployed capability.

## Catalog capability discovery

The workflow ID remains `text-to-video-minimax-h3` for backward compatibility.
Text-to-video needs no new inputs. A runner declares multimodal support by
adding both `generation_mode` and `reference_manifest`. Video editing also
requires `edit_operation` and `identity_replacement_consent`. A runner exposes
the Quality/Turbo selector by publishing the optional `performance_mode`
string input; older catalogs without it remain on their workflow default.

```yaml
- id: text-to-video-minimax-h3
  name: MiniMax H3 audiovisual generation
  model: MiniMax H3
  contract_version: 1
  dispatch_workflow: .github/workflows/minimax-h3-text-to-video.yml
  inputs:
    prompt: {type: string, required: true, max_length: 7000}
    duration_seconds: {type: number, required: true, minimum: 4, maximum: 15, default: 8}
    orientation: {type: string, required: true, max_length: 20}
    fps: {type: number, required: true, minimum: 24, maximum: 24, default: 24}
    performance_mode: {type: string, required: true, max_length: 16}
    generation_mode: {type: string, required: true, max_length: 40}
    reference_manifest: {type: string, required: true, max_length: 30000}
    edit_operation: {type: string, required: false, max_length: 40}
    identity_replacement_consent: {type: boolean, required: false}
  # Illustrative values only: publish baselines measured on your own runner.
  runtime_estimates:
    - selector: {performance_mode: quality}
      duration_input: duration_seconds
      baseline_output_seconds: 15
      baseline_runtime_seconds: 1800
      hardware: example 24 GB GPU
      measured_at: 2026-01-01
    - selector: {performance_mode: turbo}
      duration_input: duration_seconds
      baseline_output_seconds: 15
      baseline_runtime_seconds: 900
      hardware: example 24 GB GPU
      measured_at: 2026-01-01
  outputs:
    - kind: video
      content_types: [video/mp4]
      max_bytes: 1073741824
```

Catalog presence is intentionally coarse-grained. The versioned manifest and
the validation rules below are the detailed capability contract. A future
catalog schema may add enumerated values for resolution and aspect ratio; until
then the UI uses the deployed workflow's existing orientation, resolution, FPS,
and duration limits.

`runtime_estimates` are optional workflow-owner observations; the numbers in
the example above are placeholders, not measurements. Each selector
must name declared string inputs, and `duration_input` must name a declared
number input. ii-os scales the matching baseline to the requested duration and
snapshots the result into `jobRuns.runtimeEstimate`. The UI labels this as GPU
generation time and separately warns that queueing, setup, and uploads can add
to total completion time. Estimates are never accepted from browser input.

## Dispatch inputs

Every request includes the existing inputs:

- `prompt`: generation or edit instructions;
- `duration_seconds`: bounded by the workflow catalog;
- `orientation`: the orientation the deployment's renderer supports, for
  example `landscape`;
- `fps`: currently fixed at 24.
- `performance_mode`: `quality` for the accepted ten-step CAB/Sage profile or
  `turbo` for the pinned LightX2V four-step acceleration profile.

Quality is the UI default. Turbo uses the same MiniMax H3 base model, prompt,
duration, 1280x736 source canvas, 1280x720 delivery, 24 FPS, and native stereo
audio. It adds the third-party Apache-2.0 LightX2V 768p LoRA at an exact pinned
revision and hash, with LoRA strength 1.0, video/audio sigma shifts 6/3, Euler
sampling, and four steps. The UI labels it as a speed/quality tradeoff rather
than presenting it as a newer official MiniMax base model.

Multimodal workflows add:

- `generation_mode`: one of `text_to_video`, `first_frame_to_video`,
  `last_frame_to_video`, `first_last_frame_to_video`, `reference_to_video`, or
  `video_edit`, or `video_continue`;
- `reference_manifest`: compact JSON containing workspace source-asset IDs and
  semantic roles, never URLs or media bytes;
- `edit_operation`: present for `video_edit`;
- `identity_replacement_consent`: present for `video_edit`, and `true` for
  character or face replacement.

The manifest has this shape:

```json
{
  "schema_version": 1,
  "mode": "video_edit",
  "references": [
    {
      "asset_id": "33449737-9e39-4d53-8040-f39d5f7bc3ce",
      "kind": "video",
      "role": "source_video",
      "ordinal": 0
    },
    {
      "asset_id": "e4a443e5-ef0d-4f23-b977-2d89959a0812",
      "kind": "image",
      "role": "subject",
      "ordinal": 1
    }
  ],
  "edit_operation": "character_replacement",
  "identity_replacement_consent": true
}
```

Allowed roles are:

| Kind | Roles |
| --- | --- |
| image | `first_frame`, `last_frame`, `subject`, `style`, `environment` |
| video | `source_video`, `motion_reference` |
| audio | `audio_reference`, `audio_reuse` |

Allowed edit operations are `general_edit`, `character_replacement`,
`object_replacement`, `motion_transfer`, and `background_replacement`.

## Mode validation

| Mode | Required references |
| --- | --- |
| `text_to_video` | none |
| `first_frame_to_video` | exactly one image with `first_frame` role |
| `last_frame_to_video` | exactly one image with `last_frame` role |
| `first_last_frame_to_video` | exactly two images, one endpoint of each role |
| `reference_to_video` | at least one valid reference |
| `video_edit` | at least one video with `source_video` role |
| `video_continue` | at least one video with `source_video` role |

All manifests enforce unique UUID source-asset IDs, contiguous zero-based
ordinals, 9-image/3-video/3-audio type ceilings, and 12 files total. Character
replacement additionally requires a `subject` image and affirmative identity
permission in the UI; the control plane independently rejects a false consent
value.

ii-os can validate file type and byte size but does not inspect media payloads.
The runner MUST validate cumulative video and audio durations after downloading
the signed references and before loading the model. A violation MUST complete
the workflow as failed with a stable, nonsecret error code.

## Asset and runner handoff

The browser uploads each source directly to the workspace-controlled GCS bucket
using an expiring write grant. Firestore stores only source metadata and opaque
asset IDs. At workflow claim time, ii-os resolves the manifest and returns:

```json
{
  "sourceAssets": [
    {
      "assetId": "33449737-9e39-4d53-8040-f39d5f7bc3ce",
      "url": "https://storage.googleapis.com/...",
      "expiresAt": "2026-08-13T16:15:00Z",
      "contentType": "video/mp4",
      "sizeBytes": 1048576,
      "kind": "video",
      "role": "source_video",
      "ordinal": 0
    }
  ]
}
```

The broker verifies that the stored MIME type matches the declared kind before
issuing the contract. The runner MUST download in ordinal order, reject expired
or mismatched contracts, and avoid logging signed URLs. It maps endpoint modes
to FL2VA and general reference or editing modes to Ref2VA. It publishes only a
workspace-GCS artifact manifest through the existing completion API.

Deployments run this workflow on compute selected by their implementation.
The public contract does not name or silently select a particular host,
scheduler, or execution provider.

## Output and UX contract

The primary output is `video/mp4` with synchronized audio when the selected
model profile produces audio. The workflow must report duration, dimensions,
FPS, content type, object generation, and object path in its artifact manifest.

From dispatch until a terminal result, the exact video output surface shows an
animated loading state. Success replaces it with direct-from-workspace-GCS
playback. Failure replaces it with an inline error and retry action. ii-os does
not proxy, cache, transform, thumbnail, or serve the media bytes.
