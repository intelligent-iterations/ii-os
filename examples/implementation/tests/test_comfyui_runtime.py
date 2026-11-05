"""The shared ComfyUI runtime's pure parts: model paths, output discovery, and
error text that never carries the request's own values into job logs."""

from __future__ import annotations

import json
import unittest

from tests.support import TempDir, load

runtime = load("runners/common/comfyui_runtime.py", "comfyui_runtime")

SECRET = "a lighthouse at dusk, private prompt"


class ModelPathsTest(unittest.TestCase):
    def test_every_model_folder_is_mapped_from_the_read_only_mount(self) -> None:
        temp = TempDir()
        try:
            for folder in ("diffusion_models", "vae", ".cache"):
                (temp.path / folder).mkdir()
            text = runtime.extra_model_paths(temp.path)
            self.assertIn(f'base_path: "{temp.path}"', text)
            self.assertIn('diffusion_models: "diffusion_models/"', text)
            self.assertIn('vae: "vae/"', text)
            self.assertNotIn(".cache", text)
        finally:
            temp.cleanup()


class ErrorTextTest(unittest.TestCase):
    def test_an_execution_error_keeps_the_node_and_message_but_not_its_inputs(self) -> None:
        status = {
            "status_str": "error",
            "completed": False,
            "messages": [
                ["execution_start", {"prompt_id": "p1"}],
                [
                    "execution_error",
                    {
                        "node_id": "27",
                        "node_type": "CLIPTextEncode",
                        "exception_message": "CUDA out of memory",
                        "exception_type": "torch.OutOfMemoryError",
                        "current_inputs": {"text": [SECRET]},
                        "current_outputs": {"27": [SECRET]},
                        "traceback": ["frame"],
                    },
                ],
            ],
        }
        text = runtime.describe_failure(status)
        self.assertIn("CLIPTextEncode", text)
        self.assertIn("CUDA out of memory", text)
        self.assertNotIn(SECRET, text)
        self.assertNotIn("current_inputs", text)

    def test_a_refused_graph_names_the_node_errors_without_received_values(self) -> None:
        refused = {
            "error": {"type": "prompt_outputs_failed_validation", "message": "Prompt outputs failed validation"},
            "node_errors": {
                "27": {
                    "class_type": "CLIPTextEncode",
                    "errors": [
                        {
                            "type": "value_not_valid",
                            "message": "Value not in list",
                            "details": f"text: '{SECRET}' not in []",
                            "extra_info": {"input_name": "text", "received_value": SECRET},
                        }
                    ],
                }
            },
        }
        text = runtime.describe_failure(refused)
        self.assertIn("prompt_outputs_failed_validation", text)
        self.assertIn("value_not_valid", text)
        self.assertIn("text", text)
        self.assertNotIn(SECRET, text)
        json.loads(text)


if __name__ == "__main__":
    unittest.main()
