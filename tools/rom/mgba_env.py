"""Bootstrap module: adds the locally-built mGBA Python bindings to
sys.path and provides a couple of small helpers used by the dynamic-
analysis scripts under tools/rom/. See docs/reverse-engineering/tooling.md
for how/why this was built (BUILD_LTO off pitfalls, USE_FFMPEG needed for
the DEFINE_VECTOR symbol issue, etc.) -- not committed to the repo, lives
in the sibling tools-external/ workspace folder like gen1recomp-reference.
"""

import os
import sys

MGBA_PYLIB = os.path.join(
    os.path.dirname(__file__), "..", "..", "..",
    "tools-external", "mgba", "build", "python",
    "lib.macosx-14.0-arm64-cpython-314",
)
sys.path.insert(0, os.path.abspath(MGBA_PYLIB))

DEFAULT_ROM = os.path.join(
    os.path.dirname(__file__), "..", "..", "..",
    "roms", "extracted_mq", "Mystic Quest (G) [!].gb",
)


def load_core(rom_path=None):
    import mgba.core
    core = mgba.core.load_path(rom_path or DEFAULT_ROM)
    core.autoload_save()
    return core


def save_frame_png(core, img, path):
    """mgba.image.Image.save_png expects a writable file-like object with
    Python's cffi VFS shim, not a bare path string (that's a bug/gap in
    the version of the bindings we built) -- open it ourselves instead."""
    with open(path, "wb") as f:
        img.save_png(f)
