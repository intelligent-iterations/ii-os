"""MiniMax H3 audiovisual generation through ComfyUI.

    profiles    the Quality and Turbo inference profiles, model files, canvases
                and the VRAM reserve each render needs
    references  reference manifests, staged sources, durations and prompt labels
    extension   continuing a source video by anchoring it inside the render
    graph       the ComfyUI API graph and server flags
    media       ffprobe, the 720p delivery encode and the poster frame

`profiles`, `references` and `extension` use only the Python standard library,
so a request is validated on the runner host before any image is pulled.
"""
