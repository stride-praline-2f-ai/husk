#!/usr/bin/env python3
"""Run the actual Foundation/CoreGraphics chrome-clearance policy in macOS build CI."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]

@unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler unavailable; macOS IPA CI runs this check')
class GameChromeTests(unittest.TestCase):
    def test_safe_status_hosted_and_already_inset_geometry(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'main.swift'
            path.write_text('''import Foundation
import CoreGraphics
func check(_ value: Bool) { precondition(value) }
let full = CGRect(x: 0, y: 0, width: 1376, height: 1032)
let safe = CGRect(x: 0, y: 24, width: 1376, height: 1008)
let status = CGRect(x: 0, y: 0, width: 1376, height: 24)
let hosted = GameChromeLayout.clearance(view: full, safe: full, status: nil, hostedTopBoundary: 24)
check(hosted.top == 24) // LC claims zero safe/status inset
check(GameChromeLayout.clearance(view: full, safe: safe, status: status, hostedTopBoundary: 24).top == 24) // not 48 or 72
check(GameChromeLayout.clearance(view: safe, safe: safe, status: status, hostedTopBoundary: 24).top == 0) // already clear
check(GameChromeLayout.clearance(view: full, safe: full, status: status, hostedTopBoundary: nil).top == 24)
check(GameChromeLayout.clearance(view: full, safe: full, status: nil, hostedTopBoundary: nil).top == 0) // standalone hidden
let notch = CGRect(x: 44, y: 0, width: 1288, height: 1032)
let inset = GameChromeLayout.clearance(view: full, safe: notch, status: nil, hostedTopBoundary: nil)
check(inset.leading == 44 && inset.trailing == 44 && inset.top == 0)
check(GameChromeLayout.clearance(view: notch, safe: notch, status: nil, hostedTopBoundary: nil) == GameChromeClearance())
let floating = CGRect(x: 150, y: 100, width: 700, height: 500)
check(GameChromeLayout.clearance(view: floating, safe: safe, status: status, hostedTopBoundary: 24).top == 0)
check(GameChromeLayout.clearance(view: .zero, safe: safe, status: status, hostedTopBoundary: 24) == GameChromeClearance())
// Hosted iPad status row plus the window/ellipsis control row.
let hostedControls = GameChromeLayout.clearance(view: full, safe: safe, status: status, hostedTopBoundary: 52)
check(hostedControls.top == 52)
let alreadyBelowControls = CGRect(x: 0, y: 52, width: 1376, height: 980)
check(GameChromeLayout.clearance(view: alreadyBelowControls, safe: safe, status: status, hostedTopBoundary: 52).top == 0)
// Geometry already converted into a scaled guest's local points by UIKit.
check(GameChromeLayout.clearance(view: full, safe: full, status: nil, hostedTopBoundary: 32).top == 32)
// Java-only native toolbar: reserve max(system, host clearance) once, then toolbar height.
check(JavaAppChromeLayout.pixelInsets(system: [0, 0, 0, 0], chromeClearance: 0, keyboard: 0, scale: 3) == [0, 156, 0, 0, 0])
check(JavaAppChromeLayout.pixelInsets(system: [0, 24, 0, 20], chromeClearance: 24, keyboard: 200, scale: 2) == [0, 152, 0, 40, 400])
check(JavaAppChromeLayout.pixelInsets(system: [0, 24, 0, 20], chromeClearance: 0, keyboard: 0, scale: 2) == [0, 152, 0, 40, 0])
check(JavaAppChromeLayout.pixelInsets(system: [0, 0, 0, 0], chromeClearance: 52, keyboard: 0, scale: 3) == [0, 312, 0, 0, 0])
check(JavaAppChromeLayout.pixelInsets(system: [44, 0, 44, 20], chromeClearance: nil, keyboard: 0, scale: 3) == [132, 0, 132, 60, 0]) // hidden restores guest safe area
check(JavaAppChromeLayout.pixelInsets(system: [0, 0, 0, 0], chromeClearance: nil, keyboard: 100, scale: 2) == [0, 0, 0, 0, 200]) // floating window keeps keyboard
let returned = GameChromeLayout.clearance(view: full, safe: safe, status: status, hostedTopBoundary: 24)
check(returned == hosted) // returning from system UI restores the same layout
''')
            executable=Path(d)/'check'
            subprocess.run(['swiftc',str(ROOT/'src/app/Husk/GameChromeInsets.swift'),str(path),'-o',str(executable)],check=True)
            subprocess.run([str(executable)],check=True)

if __name__=='__main__':unittest.main()
