#!/usr/bin/env python3
"""Prepare an isolated arm64 iOS UI preview. Never use it for a release build."""
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'work' / 'live-duo'
DEST.mkdir(parents=True, exist_ok=True)
for name in ('lib', 'assets', 'packages', 'ios'):
    subprocess.run(['rsync', '-a', '--exclude=Pods', '--exclude=.symlinks',
                    '--exclude=ephemeral', '--exclude=build', '--exclude=.dart_tool',
                    str(ROOT / name), str(DEST) + '/'], check=True)
for name in ('pubspec.yaml', 'pubspec.lock'):
    shutil.copy2(ROOT / name, DEST / name)
bridge = DEST / 'packages/koofy_reader_bridge/ios'
podspec = bridge / 'koofy_reader_bridge.podspec'
podspec.write_text(podspec.read_text().replace("  s.dependency 'GoogleMLKit/Translate', '8.0.0'\n", ''))
(bridge / 'Classes/ReaderTranslation.swift').write_text('''// UI preview only: translation requires a real iOS device.
import UIKit
@MainActor final class ReaderTranslation {
 let view = UIStackView()
 let enabled = false
 var sample: ((String) async -> String?)?
 var pauseBook: (() -> Void)?
 var onClose: (() -> Void)?
 init() { view.isHidden = true }
 func palette(_ palette: ReaderPalette) {}
 func enable() {}
 func disable() {}
 func resume() {}
 func suspend() {}
 func stopVoice() {}
}
''')
config = DEST / 'ios/Flutter/Debug.xcconfig'
config.write_text(config.read_text() + '''
// Preview only. Flutter 3.35 incorrectly matches arm64e as arm64.
SUPPORTED_PLATFORMS = iphoneos iphonesimulator
EXCLUDED_ARCHS[sdk=iphonesimulator*] = i386
''')
project = DEST / 'ios/Runner.xcodeproj/project.pbxproj'
project.write_text(project.read_text().replace('SUPPORTED_PLATFORMS = iphoneos;',
                                            'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";'))
print(f'UI preview prepared: {DEST}\nTranslation is unavailable here. Never archive this copy.')
