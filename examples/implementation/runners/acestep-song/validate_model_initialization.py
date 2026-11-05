"""Build regression: FSQ constants survive Transformers' meta-device loading."""

import importlib
import tempfile

import torch


def main():
    for variant, filename in (
        ("base", "base"),
        ("sft", "base"),
        ("turbo", "turbo"),
        ("xl_base", "xl_base"),
        ("xl_sft", "xl_base"),
        ("xl_turbo", "xl_turbo"),
    ):
        module = importlib.import_module(
            f"acestep.models.{variant}.modeling_acestep_v15_{filename}"
        )
        with torch.device("meta"):
            tokenizer = module.AceStepAudioTokenizer(module.AceStepConfig())
        assert tokenizer.audio_acoustic_proj.weight.is_meta, variant
        buffers = list(tokenizer.quantizer.buffers())
        assert buffers and all(not buffer.is_meta for buffer in buffers), variant
        assert all(torch.isfinite(buffer).all() for buffer in buffers), variant
        print(f"{variant}: meta loading preserves materialized FSQ constants")

        config = module.AceStepConfig(
            hidden_size=32, intermediate_size=64, num_attention_heads=4,
            num_key_value_heads=2, head_dim=8, fsq_dim=32,
            num_attention_pooler_hidden_layers=1,
        )
        original = module.AceStepAudioTokenizer(config).eval()
        with tempfile.TemporaryDirectory() as directory:
            original.save_pretrained(directory)
            loaded = module.AceStepAudioTokenizer.from_pretrained(directory).eval()
        for name, expected in original.named_buffers():
            torch.testing.assert_close(loaded.get_buffer(name), expected)
        indices = torch.tensor([[[0], [123], [63999]]])
        with torch.no_grad():
            expected = original.quantizer.get_output_from_indices(indices)
            actual = loaded.quantizer.get_output_from_indices(indices)
        assert torch.isfinite(actual).all(), variant
        torch.testing.assert_close(actual, expected)
        print(f"{variant}: checkpoint round trip preserves buffers and decoded codes")

    from transformers import Qwen3Config
    from nanovllm.models.qwen3 import Qwen3DecoderLayer

    config = Qwen3Config(
        hidden_size=32, intermediate_size=64, num_attention_heads=4,
        num_key_value_heads=2, head_dim=8, max_position_embeddings=32,
        rope_parameters={"rope_type": "default", "rope_theta": 500000.0},
    )
    layer = Qwen3DecoderLayer(config)
    frequencies = torch.arange(32).float()[:, None] / (
        500000.0 ** (torch.arange(0, 8, 2).float() / 8)
    )
    expected = torch.cat((frequencies.cos(), frequencies.sin()), dim=-1)[:, None]
    torch.testing.assert_close(layer.self_attn.rotary_emb.cos_sin_cache, expected)
    config.rope_parameters = {"rope_type": "linear", "factor": 2.0}
    try:
        Qwen3DecoderLayer(config)
    except ValueError as error:
        assert "only default" in str(error)
    else:
        raise AssertionError("unsupported RoPE scaling was silently accepted")
    print("planner: default RoPE parameters preserved; unsupported scaling rejected")


if __name__ == "__main__":
    main()
