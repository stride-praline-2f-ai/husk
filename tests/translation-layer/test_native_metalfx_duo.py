#!/usr/bin/env python3
"""Portable native MetalFX Duo profile contracts, no Apple GPU claims."""
from pathlib import Path
import ctypes
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
C = ROOT / "src/translation-layer-next/husk-tl-spatial.c"
H = ROOT / "src/translation-layer-next/husk-tl-spatial.h"
SETTINGS = ROOT / "src/app/Husk/TLAppSettings.swift"
LAUNCH = ROOT / "src/app/Husk/TLUnityView.swift"
VULKAN = ROOT / "src/translation-layer-next/husk-tl-vulkan.m"
SPATIAL = ROOT / "patches/metalfx/HuskSpatial.inc"

class Config(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint32) for name in
                ("version", "size", "input_width", "input_height",
                 "output_width", "output_height", "enabled", "reserved")]

class NativeMetalFXDuo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cc = shutil.which("cc") or shutil.which("clang")
        if not cc:
            raise unittest.SkipTest("C compiler not available")
        output = str(Path(cls.temp.name) / "libspatial.so")
        subprocess.run([cc, "-std=c11", "-shared", "-fPIC", "-I", str(H.parent),
                        str(C), "-o", output], check=True)
        lib = ctypes.CDLL(output)
        cls.dimensions = lib.tl_spatial_dimensions
        cls.dimensions.argtypes = [ctypes.c_int, ctypes.c_int,
                                   ctypes.c_int, ctypes.POINTER(Config)]
        cls.dimensions.restype = ctypes.c_bool

    def test_real_duo_output_presets_keep_aspect_and_alignment(self):
        for p, (w, h) in {50: (912, 640), 60: (1088, 768),
                          67: (1216, 856), 80: (1456, 1024)}.items():
            with self.subTest(percent=p):
                config = Config()
                self.assertTrue(self.dimensions(1816, 1280, p, ctypes.byref(config)))
                self.assertEqual((config.input_width, config.input_height), (w, h))
                self.assertEqual((config.output_width, config.output_height), (1816, 1280))
                self.assertEqual(config.enabled, 1)
                self.assertLess(abs(w / h / (1816 / 1280) - 1), 0.01)
                self.assertEqual((w % 8, h % 8), (0, 0))
                self.assertLess(w * h, 1816 * 1280)

    def test_small_outer_screen_and_invalid_sizes_do_not_force_duo_pixels(self):
        config = Config()
        self.assertTrue(self.dimensions(1400, 960, 60, ctypes.byref(config)))
        self.assertEqual((config.output_width, config.output_height), (1400, 960))
        for (w, h, p) in [(0, 1280, 60), (1816, 0, 60), (1816,1280,49),
                          (1816,1280,100), (9000,1280,60)]:
            self.assertFalse(self.dimensions(w, h, p, ctypes.byref(config)))

    def test_60_real_fps_no_legacy_framegen_selection_and_apple_scaler(self):
        settings, launch, vulkan, spatial = (
            x.read_text() for x in (SETTINGS, LAUNCH, VULKAN, SPATIAL))
        self.assertIn("var duoSpatialPreset = DuoDisplayPolicy.inputPercent", settings)
        self.assertIn("spatialUpscaling = true", launch)
        self.assertIn("efficientFrameLimit = DuoDisplayPolicy.fps", launch)
        self.assertIn("husk_ue4_set_frame_generation(false)", launch)
        self.assertIn("spatial_input_percent=(percent==50||percent==60||percent==67", vulkan)
        self.assertIn("id<MTLFXSpatialScaler>", spatial)
        self.assertIn("[scaler encodeToCommandBuffer:command]", spatial)
        self.assertIn("scaler.inputContentWidth=c.input_width", spatial)
        self.assertIn("scaler.inputContentHeight=c.input_height", spatial)
        self.assertNotIn("let metal4 = fw +", launch)

if __name__ == "__main__":
    unittest.main()
