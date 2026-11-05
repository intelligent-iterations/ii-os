"""ComfyUI nodes for exact, memory-safe MiniMax H3 inference on a 24 GB GPU.

IiOsMiniMaxH3LowMemory patches the H3 transformer blocks so the feed-forward,
the fused QKV projection and the attention heads run in bounded chunks. The
result is numerically the same computation with shorter tensor lifetimes.
IiOsMiniMaxH3CABSampler is the CAB-2/3 low-step sampler (cab_sampler.py).

Written against the ComfyUI commit pinned in the runner's Dockerfile; the
patch reaches into comfy.ldm.minimax internals that may change upstream.
"""

from __future__ import annotations

import logging
import types

from comfy.ldm.minimax.model import _mod_gate, _mod_scale_shift
from comfy.ldm.modules.attention import optimized_attention
import comfy.model_management
import comfy.ops
import comfy.quant_ops
import torch

from .cab_sampler import IiOsMiniMaxH3CABSampler

LOG = logging.getLogger("ii_os_minimax_h3")

def _force_sage_cuda_on_sm86() -> None:
    """Send sm86 to SageAttention's CUDA kernel instead of its Triton one.

    SageAttention 2.2 dispatches by architecture, and sm86 is the only one it
    routes through Triton:

        sm80 -> sageattn_qk_int8_pv_fp16_cuda
        sm86 -> sageattn_qk_int8_pv_fp16_triton
        sm89 -> sageattn_qk_int8_pv_fp8_cuda
        sm90 -> sageattn_qk_int8_pv_fp8_cuda_sm90

    That Triton path takes an illegal memory access on a keyframe-anchored
    MiniMax H3 sequence. ComfyUI catches it and falls back to pytorch
    attention, but too late: the CUDA context is already poisoned, so the next
    allocator free throws from a destructor and the process aborts with
    'Fatal Python error: Aborted', surfacing only as exit status -6.

    Every sm86 GPU (the GeForce RTX 30 series, for example) hits it on an H3
    continuation. The fp16 CUDA kernel is what sm80 already uses, so this is
    the neighbouring supported path rather than a new one.

    Patching the name ComfyUI bound at import, not the package attribute:
    comfy.ldm.modules.attention does `from sageattention import sageattn`
    before this node loads, so rebinding the package would change nothing.
    """
    try:
        import sageattention
        from sageattention import sageattn_qk_int8_pv_fp16_cuda
    except ImportError:
        return

    try:
        major, minor = torch.cuda.get_device_capability()
    except Exception:
        return
    if (major, minor) != (8, 6):
        return

    import comfy.ldm.modules.attention as comfy_attention

    original = getattr(comfy_attention, "sageattn", None)
    if original is None or getattr(original, "_ii_os_sm86_cuda", False):
        return

    def sageattn_sm86_cuda(q, k, v, **kwargs):
        # The CUDA kernel does not take Triton's extras; drop what it cannot
        # accept rather than failing the whole render on an unexpected kwarg.
        accepted = {
            key: value
            for key, value in kwargs.items()
            if key in ("tensor_layout", "is_causal", "sm_scale", "return_lse")
        }
        return sageattn_qk_int8_pv_fp16_cuda(q, k, v, **accepted)

    sageattn_sm86_cuda._ii_os_sm86_cuda = True
    comfy_attention.sageattn = sageattn_sm86_cuda
    LOG.info(
        "[ii-os MiniMax H3 sage] sm86 routed to the CUDA kernel; "
        "SageAttention 2.2's Triton path aborts on anchored sequences"
    )


_force_sage_cuda_on_sm86()


def _chunked_feed_forward(module, tokens: torch.Tensor) -> torch.Tensor:
    """Evaluate independent packed-token rows in bounded activation chunks."""
    chunk_count = min(module.ii_os_h3_ffn_chunks, int(tokens.shape[0]))
    if chunk_count <= 1 or int(tokens.shape[0]) <= module.ii_os_h3_ffn_threshold:
        return comfy.ops.linear_input_act(
            module.fc2, module.fc1(tokens), "swiglu"
        )

    output = torch.empty_like(tokens)
    offset = 0
    for token_chunk in torch.chunk(tokens, chunk_count, dim=0):
        expanded = module.fc1(token_chunk)
        chunk_output = comfy.ops.linear_input_act(module.fc2, expanded, "swiglu")
        del expanded
        output.narrow(0, offset, token_chunk.shape[0]).copy_(chunk_output)
        offset += token_chunk.shape[0]
        del chunk_output
    return output


def _bound_chunked_forward(module, chunks: int, threshold: int):
    def forward(self, tokens: torch.Tensor) -> torch.Tensor:
        self.ii_os_h3_ffn_chunks = chunks
        self.ii_os_h3_ffn_threshold = threshold
        return _chunked_feed_forward(self, tokens)

    return types.MethodType(forward, module)


def _chunked_qkv_projection(module, tokens: torch.Tensor, chunks: int):
    """Project token chunks while keeping one Comfy-managed weight resident."""
    if not hasattr(module, "_forward"):
        raise RuntimeError("expected Comfy mixed-precision QKV linear")

    comfy.ops.run_every_op()
    pre_quant_scale = getattr(module, "pre_quant_scale", None)
    token_chunks = torch.chunk(tokens, min(max(1, chunks), int(tokens.shape[0])), dim=0)
    compute_dtype = tokens.dtype
    use_quantized = (
        getattr(module, "layout_type", None) is not None
        and not module._full_precision_mm
        and not getattr(module, "comfy_force_cast_weights", False)
        and len(module.weight_function) == 0
        and len(module.bias_function) == 0
    )
    quantize_input = comfy.ops.QUANT_ALGOS.get(
        getattr(module, "quant_format", None), {}
    ).get("quantize_input", True)
    scale = getattr(module, "input_scale", None)
    if scale is not None:
        scale = comfy.model_management.cast_to_device(
            scale, tokens.device, None
        )

    def prepare(token_chunk):
        if pre_quant_scale is not None:
            token_chunk = token_chunk * comfy.model_management.cast_to_device(
                pre_quant_scale, token_chunk.device, token_chunk.dtype
            )
        if use_quantized and quantize_input:
            return comfy.ops.QuantizedTensor.from_float(
                token_chunk, module.layout_type, scale=scale
            )
        return token_chunk

    first_input = prepare(token_chunks[0])
    weight_only_quant = (
        use_quantized
        and not quantize_input
        and isinstance(module.weight, comfy.ops.QuantizedTensor)
    )
    if weight_only_quant:
        weight, bias, offload_stream = comfy.ops.cast_bias_weight(
            module,
            input=None,
            dtype=module.weight.dtype,
            device=first_input.device,
            bias_dtype=first_input.dtype,
            offloadable=True,
            compute_dtype=compute_dtype,
            want_requant=True,
        )
        weight = weight.to(dtype=first_input.dtype)
    else:
        weight, bias, offload_stream = comfy.ops.cast_bias_weight(
            module,
            first_input,
            offloadable=True,
            compute_dtype=compute_dtype,
            want_requant=isinstance(first_input, comfy.ops.QuantizedTensor),
        )

    try:
        first_projection = module._forward(first_input, weight, bias)
        qkv = torch.empty(
            (tokens.shape[0], *first_projection.shape[1:]),
            dtype=first_projection.dtype,
            device=first_projection.device,
        )
        offset = 0
        qkv.narrow(0, offset, first_projection.shape[0]).copy_(first_projection)
        offset += first_projection.shape[0]
        del first_projection, first_input
        for token_chunk in token_chunks[1:]:
            projection = module._forward(prepare(token_chunk), weight, bias)
            qkv.narrow(0, offset, projection.shape[0]).copy_(projection)
            offset += projection.shape[0]
            del projection
    finally:
        comfy.ops.uncast_bias_weight(module, weight, bias, offload_stream)
    return qkv


def _low_memory_attention_forward(
    module,
    tokens,
    rope_freqs=None,
    transformer_options=None,
) -> torch.Tensor:
    """Shorten H3 attention lifetimes and evaluate independent head groups."""
    if isinstance(tokens, list):
        tokens = tokens.pop()
    transformer_options = transformer_options or {}
    sequence = int(tokens.shape[0])
    device = tokens.device
    dtype = tokens.dtype

    # The preceding block can leave multi-GiB cached segments that are too
    # small for H3's fused QKV result. Releasing only unused allocator cache
    # prevents that fragmentation without moving or changing live tensors.
    torch.cuda.empty_cache()
    requested_qkv_chunks = int(
        transformer_options.get("ii_os_h3_attention_qkv_chunks", 1)
    )
    qkv_chunk_count = min(max(1, requested_qkv_chunks), sequence)
    if qkv_chunk_count == 1:
        qkv = module.qkv_proj(tokens)
    else:
        qkv = _chunked_qkv_projection(module.qkv_proj, tokens, qkv_chunk_count)
    del tokens
    q, k, v = qkv.split(module.heads * module.head_dim, dim=-1)
    v = v.view(sequence, module.heads, module.head_dim)
    if rope_freqs is not None:
        q = q.view(1, sequence, module.heads, module.head_dim)
        k = k.view(1, sequence, module.heads, module.head_dim)
        q_weight = comfy.model_management.cast_to(
            module.q_norm.weight, device=device
        )
        k_weight = comfy.model_management.cast_to(
            module.k_norm.weight, device=device
        )
        rotation_dimensions = rope_freqs.shape[-3] * 2
        # Always the out-of-place variant, never the in-place one.
        #
        # A keyframe-anchored sequence is the only case that changes this
        # tensor's length, and it is the only case that faults: the render
        # aborts with an illegal memory access that surfaces at the next
        # kernel to touch q and k, which is why it reads as a SageAttention
        # error. Routing sm86 to sage's CUDA kernel and removing head slicing
        # both left it untouched, because neither is where it starts.
        #
        # rms_rope_split_half_ mutates q and k in place. The non-mutating twin
        # is already what this node uses under training, so it is an exercised
        # path rather than a new one, and it costs one extra allocation.
        q, k = comfy.quant_ops.ck.rms_rope_split_half(
            q,
            k,
            rope_freqs,
            q_weight,
            k_weight,
            epsilon=module.q_norm.eps,
            rot_dim=rotation_dimensions,
        )
        q = q[0]
        k = k[0]
    else:
        q = module.q_norm(q.view(sequence, module.heads, module.head_dim))
        k = module.k_norm(k.view(sequence, module.heads, module.head_dim))

    q = q.transpose(0, 1).unsqueeze(0)
    k = k.transpose(0, 1).unsqueeze(0)
    v = v.transpose(0, 1).unsqueeze(0)
    requested_groups = int(transformer_options.get("ii_os_h3_attention_head_chunks", 1))
    group_count = min(max(1, requested_groups), module.heads)
    if group_count == 1:
        output = optimized_attention(
            q,
            k,
            v,
            module.heads,
            mask=None,
            skip_reshape=True,
            transformer_options=transformer_options,
        ).squeeze(0)
    else:
        output = torch.empty(
            (sequence, module.heads * module.head_dim),
            dtype=dtype,
            device=device,
        )
        head_start = 0
        base_size, remainder = divmod(module.heads, group_count)
        for group in range(group_count):
            group_size = base_size + (1 if group < remainder else 0)
            head_stop = head_start + group_size
            group_output = optimized_attention(
                q[:, head_start:head_stop],
                k[:, head_start:head_stop],
                v[:, head_start:head_stop],
                group_size,
                mask=None,
                skip_reshape=True,
                transformer_options=transformer_options,
            ).squeeze(0)
            output.narrow(
                1,
                head_start * module.head_dim,
                group_size * module.head_dim,
            ).copy_(group_output)
            head_start = head_stop
            del group_output

    del q, k, v, qkv
    torch.cuda.empty_cache()
    return module.out_proj(output)


_low_memory_attention_forward._uses_optimized_attention = True


def _bound_attention_forward(module):
    def forward(self, tokens, rope_freqs=None, transformer_options=None):
        return _low_memory_attention_forward(
            self,
            tokens,
            rope_freqs=rope_freqs,
            transformer_options=transformer_options,
        )

    return types.MethodType(forward, module)


def _bound_block_forward(module):
    def forward(
        self,
        tokens,
        timestep_embedding,
        modulation_segments,
        rope_freqs,
        transformer_options=None,
    ):
        transformer_options = transformer_options or {}
        shift_msa, scale_msa, gate_msa, shift_mlp, scale_mlp, gate_mlp = (
            self.adaln_proj(timestep_embedding)
        )
        normalized = [
            _mod_scale_shift(
                self.norm1(tokens),
                shift_msa,
                scale_msa,
                modulation_segments,
            )
        ]
        attended = self.attn(
            normalized,
            rope_freqs=rope_freqs,
            transformer_options=transformer_options,
        )
        tokens = _mod_gate(tokens, gate_msa, attended, modulation_segments)
        del attended
        normalized = _mod_scale_shift(
            self.norm2(tokens),
            shift_mlp,
            scale_mlp,
            modulation_segments,
        )
        return _mod_gate(
            tokens,
            gate_mlp,
            self.mlp(normalized),
            modulation_segments,
        )

    return types.MethodType(forward, module)


class IiOsMiniMaxH3LowMemory:
    """Patch H3's independent token and attention dimensions exactly."""

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "model": ("MODEL",),
                "chunks": ("INT", {"default": 4, "min": 1, "max": 64}),
                "qkv_chunks": ("INT", {"default": 8, "min": 1, "max": 64}),
                "attention_head_chunks": (
                    "INT",
                    {"default": 4, "min": 1, "max": 56},
                ),
                "sequence_threshold": (
                    "INT",
                    {"default": 4096, "min": 256, "max": 262144},
                ),
            }
        }

    RETURN_TYPES = ("MODEL",)
    FUNCTION = "patch"
    CATEGORY = "ii-os/MiniMax H3"

    def patch(
        self,
        model,
        chunks: int,
        qkv_chunks: int,
        attention_head_chunks: int,
        sequence_threshold: int,
    ):
        patched_model = model.clone()
        diffusion_model = patched_model.get_model_object("diffusion_model")
        blocks = getattr(diffusion_model, "blocks", None)
        if not blocks:
            raise RuntimeError("expected MiniMax H3 transformer blocks")

        for index, block in enumerate(blocks):
            mlp = getattr(block, "mlp", None)
            attention = getattr(block, "attn", None)
            if mlp is None or not hasattr(mlp, "fc1") or not hasattr(mlp, "fc2"):
                raise RuntimeError(
                    f"MiniMax H3 block {index} does not expose the expected SwiGLU MLP"
                )
            if attention is None or not hasattr(attention, "qkv_proj"):
                raise RuntimeError(
                    f"MiniMax H3 block {index} does not expose the expected attention"
                )
            patched_model.add_object_patch(
                f"diffusion_model.blocks.{index}.mlp.forward",
                _bound_chunked_forward(mlp, chunks, sequence_threshold),
            )
            patched_model.add_object_patch(
                f"diffusion_model.blocks.{index}.attn.forward",
                _bound_attention_forward(attention),
            )
            patched_model.add_object_patch(
                f"diffusion_model.blocks.{index}.forward",
                _bound_block_forward(block),
            )

        transformer_options = patched_model.model_options.get("transformer_options")
        if not isinstance(transformer_options, dict):
            transformer_options = {}
            patched_model.model_options["transformer_options"] = transformer_options
        transformer_options["ii_os_h3_attention_head_chunks"] = attention_head_chunks
        transformer_options["ii_os_h3_attention_qkv_chunks"] = qkv_chunks

        logging.info(
            "[ii-os MiniMax H3 memory] patched %d blocks "
            "(ffn_chunks=%d, qkv_chunks=%d, attention_head_chunks=%d, "
            "threshold=%d)",
            len(blocks),
            chunks,
            qkv_chunks,
            attention_head_chunks,
            sequence_threshold,
        )
        return (patched_model,)


NODE_CLASS_MAPPINGS = {
    "IiOsMiniMaxH3LowMemory": IiOsMiniMaxH3LowMemory,
    "IiOsMiniMaxH3CABSampler": IiOsMiniMaxH3CABSampler,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "IiOsMiniMaxH3LowMemory": "ii-os MiniMax H3 Exact Low Memory",
    "IiOsMiniMaxH3CABSampler": "ii-os MiniMax H3 CAB Low-Step Sampler",
}
