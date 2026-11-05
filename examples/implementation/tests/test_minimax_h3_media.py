"""minimax-h3 media: reading reference clips with ffprobe, finishing the raw
render to the 720p H.264/AAC stereo delivery, checking it, and the poster."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

from tests.support import RUNNERS, TempDir

RUNNER = RUNNERS / "minimax-h3"
if str(RUNNER) not in sys.path:
    sys.path.insert(0, str(RUNNER))

from minimax_h3 import media  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24


def final_probe(**video: object) -> dict:
    stream = {"codec_type": "video", "codec_name": "h264", "pix_fmt": "yuv420p", "width": 1280, "height": 720, "avg_frame_rate": "24/1"}
    stream.update(video)
    return {"format": {"duration": "15.000000"}, "streams": [stream, {"codec_type": "audio", "codec_name": "aac", "channels": 2}]}


FINAL = {"width": 1280, "height": 720, "fps": 24, "duration": 15}


class FactsTest(unittest.TestCase):
    def test_duration_and_soundtrack_come_from_the_probe(self) -> None:
        probe = {"format": {"duration": "5.004"}, "streams": [{"codec_type": "video"}, {"codec_type": "audio"}]}
        self.assertEqual(media.media_facts(probe), (5.004, True))
        self.assertEqual(media.media_facts({"format": {"duration": "3"}, "streams": [{"codec_type": "audio"}]}), (3.0, True))
        self.assertEqual(media.media_facts({"format": {"duration": "3"}, "streams": [{"codec_type": "video"}]}), (3.0, False))

    def test_an_unreadable_duration_is_refused(self) -> None:
        for probe in ({}, {"format": {"duration": "N/A"}}, {"format": {"duration": "-1"}}, {"format": {"duration": "nan"}}):
            with self.subTest(probe=probe), self.assertRaises(ValueError):
                media.media_facts(probe)

    def test_probe_reads_ffprobe_json(self) -> None:
        payload = {"format": {"duration": "2.5"}, "streams": []}
        done = subprocess.CompletedProcess(["ffprobe"], 0, stdout=json.dumps(payload), stderr="")
        with mock.patch.object(media.subprocess, "run", return_value=done) as run:
            self.assertEqual(media.probe(Path("/work/in/sources/00.mp4")), payload)
        command = run.call_args.args[0]
        self.assertEqual(command[0], "ffprobe")
        self.assertEqual(command[-1], "/work/in/sources/00.mp4")


class FinishTest(unittest.TestCase):
    def test_the_command_crops_to_the_delivery_canvas_and_drops_render_metadata(self) -> None:
        command = media.finish_command(Path("raw.mp4"), Path("video.mp4"), **FINAL)
        graph = command[command.index("-filter_complex") + 1]
        self.assertIn("scale=1280:720:force_original_aspect_ratio=increase:flags=lanczos,crop=1280:720,fps=24,trim=duration=15", graph)
        self.assertIn("apad=pad_dur=15,atrim=duration=15", graph)
        self.assertEqual(command[command.index("-map_metadata") + 1], "-1")
        for pair in (("-c:v", "libx264"), ("-pix_fmt", "yuv420p"), ("-c:a", "aac"), ("-ac", "2"), ("-ar", "48000"), ("-movflags", "+faststart")):
            with self.subTest(option=pair[0]):
                self.assertEqual(command[command.index(pair[0]) + 1], pair[1])
        self.assertEqual(command[-1], "video.mp4")

    def test_the_delivery_must_be_720p_h264_24fps_with_aac_stereo(self) -> None:
        media.check_final(final_probe(), **FINAL)
        cases = {
            "size": final_probe(width=1280, height=736),
            "codec": final_probe(codec_name="hevc"),
            "fps": final_probe(avg_frame_rate="25/1"),
        }
        mono = final_probe()
        mono["streams"][1]["channels"] = 1
        cases["mono"] = mono
        short = final_probe()
        short["format"]["duration"] = "14.9"
        cases["duration"] = short
        for label, probe in cases.items():
            with self.subTest(case=label), self.assertRaises(RuntimeError):
                media.check_final(probe, **FINAL)

    def test_finish_runs_ffmpeg_then_checks_its_output(self) -> None:
        temp = TempDir()
        try:
            raw, final = temp.path / "raw.mp4", temp.path / "video.mp4"
            raw.write_bytes(b"raw")
            done = subprocess.CompletedProcess([], 0)
            with mock.patch.object(media.subprocess, "run", return_value=done) as run, \
                    mock.patch.object(media, "probe", return_value=final_probe()):
                self.assertEqual(media.finish_video(raw, final, **FINAL), final_probe())
            self.assertEqual(run.call_args.args[0][0], "ffmpeg")
            with mock.patch.object(media.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "ffmpeg")):
                with self.assertRaises(subprocess.CalledProcessError):
                    media.finish_video(raw, final, **FINAL)
        finally:
            temp.cleanup()


def ffmpeg_writing(content: bytes, returncode: int = 0):
    def fake(command: list[str], **_: object) -> subprocess.CompletedProcess:
        Path(command[-1]).write_bytes(content)
        return subprocess.CompletedProcess(command, returncode)
    return fake


class PosterTest(unittest.TestCase):
    def test_the_opening_frame_becomes_a_png_poster_or_nothing(self) -> None:
        temp = TempDir()
        try:
            video, poster = temp.path / "video.mp4", temp.path / "poster.png"
            with mock.patch.object(media.subprocess, "run", side_effect=ffmpeg_writing(PNG)):
                self.assertTrue(media.write_poster(video, poster))
            self.assertEqual(poster.read_bytes(), PNG)
            for label, effect in {"exit": ffmpeg_writing(PNG, 1), "gif": ffmpeg_writing(b"GIF89a"), "missing": FileNotFoundError("ffmpeg")}.items():
                with self.subTest(case=label), mock.patch.object(media.subprocess, "run", side_effect=effect):
                    self.assertFalse(media.write_poster(video, poster))
                    self.assertFalse(poster.exists())
        finally:
            temp.cleanup()


if __name__ == "__main__":
    unittest.main()
