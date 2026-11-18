# LosslessStudio

**English | [繁體中文](README.md)**

A native, high-performance macOS batch media processing studio strictly adhering to lossless principles.

---

## 🌟 Core Philosophy & Technical Standards

1. **Source Protection (Never Overwrite Source)**:
   - Overwriting source files is strictly forbidden at the engine level.
   - Detects hard links and symbolic links sharing identical inodes across directories.
   - Concurrency uses a thread-safe atomic filename registry (`reservedOutputPaths`) to completely eliminate file collisions.

2. **Honest Technical Disclosure (No Fake Lossless)**:
   - There is no such thing as universal lossless conversion between arbitrary formats. LosslessStudio explicitly classifies and enforces distinct levels of lossless processing, rejecting deceptive presets:
     * **Stream Copy (Remux, `-c copy`)**: Rewraps containers without decoding or re-encoding (e.g. MP4 to MKV). Preserves 100% identical bitstreams in milliseconds with zero quality loss.
     * **Broadcast Blackmagic Uncompressed Support**: Full stream copy for broadcast-grade `v210` (10-bit 4:2:2) and `2vuy` (8-bit) uncompressed video directly into MKV containers.
     * **Archival Mathematical Lossless Transcode (FFV1)**: Bit-exact mathematical preservation via `FFV1` video and `FLAC` audio. Verified frame-by-frame using `VideoLosslessVerifier` with native pixel format hashing (`framemd5`), ensuring 10-bit depth and chroma sampling are fully preserved.
     * **Multi-Track Audio & Floating-Point Protection**: Retains up to 4 discrete PCM audio channels 1:1, and automatically protects 32-bit float PCM (`pcm_f32le`) from integer quantization.
     * **DaVinci Resolve Compatibility**: Generated MKV and QuickTime archives are tested and verified for seamless import into DaVinci Resolve.
     * **Visually Near-Lossless (Apple ProRes 4444 XQ)**: High-bitrate 12-bit mastering profile designed for post-production color grading. Honestly categorized as visually lossless rather than bit-exact mathematical lossless.
     * **Lossless Image Conversion**: Native Apple ImageIO and CoreGraphics engine supporting bidirectional conversions between PNG, TIFF, Lossless WebP, and BMP while preserving EXIF, GPS, IPTC, and ICC profiles.
     * **Lossless Audio Conversion**: Bit-exact 1:1 PCM MD5 matching across broadcast WAV (16/24/32-bit PCM), FLAC, Apple Lossless (ALAC / .m4a), and AIFF.
     * **Lossy & Compatibility Transcoding**: MP3 (up to 320k), AAC, OGG (Vorbis), and Opus. Honestly designated as lossy conversions.

3. **Fully Self-Contained Distribution Bundle**:
   - The App bundle embeds Apple Silicon native `ffmpeg`, `ffprobe`, and portable `ImageMagick` binaries in `Contents/Resources/`.
   - Bundles all 17 non-system dynamic libraries in `Contents/Frameworks/` with rewritten `@rpath/` paths via `bundle_dependencies.py`.
   - Verified in isolated environments (`env -i` without Homebrew in PATH). Zero external dependencies required.

4. **Native Bilingual Localization (English & Traditional Chinese)**:
   - Pure Swift zero-dependency `L10n` system that automatically adapts to the user's macOS language preference.
   - Complete localization across main window, presets, real-time monitors, status badges, VoiceOver labels, and error diagnostics.
   - Comprehensive English user guide and installation documentation included.

---

## 🎨 Shiba Inu Pixel Companion (Argon Assisted)

Warm cream (`#FAF8F5`) and terracotta orange (`#E8823A`) visual styling featuring an animated pure-SwiftUI pixel Shiba Inu companion (`ShibaPixelView.swift`):
* **4 Operational States**: Idle tail wag (`idle`), Converting run (`converting`), Success jump (`completed`), and Error head tilt (`failed`).
* **Accessibility**: Respects macOS `accessibilityReduceMotion` settings, displaying a gentle static pixel layout when enabled.

---

## 🔍 Real-Time Encoding Monitor & Stream Comparison

A dedicated diagnostic monitor window (`EncodingMonitorView`):
1. **Side-by-Side Probe Analysis**: Inspects video, audio, and subtitle streams (codec, profile, pixel format, resolution, color space, bit depth, channel count, sample rate).
2. **Clear Operational Badging**: Explicitly distinguishes between Stream Copy and Re-encode.
3. **5-Level Verification Badges**:
   * `✓ Bitstream Matches (Stream Copy)`
   * `✓ Mathematically Lossless (FFV1 / 1:1 Bitmap)`
   * `ℹ Visually Near-Lossless (Apple ProRes 4444 XQ)`
   * `⚠ Downsampling Detected (Operation Blocked)`
   * `✗ Rejected (Lossy / Incompatible Format)`
4. **Accurate Progress Monitoring**: Parses real-time `ffmpeg -progress` metrics for progress percentage, processing speed (x-factor), and calculated ETA.

---

## 🚀 Download & Installation

* **Official Releases**:
  * **DMG Disk Image**: [LosslessStudio.dmg](https://github.com/YuTinTW/LosslessStudio/releases/latest/download/LosslessStudio.dmg) (approx. 21 MB, includes drag-to-Applications shortcut and bundled frameworks).
  * **ZIP Archive**: [LosslessStudio-macOS.zip](https://github.com/YuTinTW/LosslessStudio/releases/latest/download/LosslessStudio-macOS.zip) (approx. 20 MB).
  * **Source Archive**: [LosslessStudio-sources.zip](https://github.com/YuTinTW/LosslessStudio/releases/latest/download/LosslessStudio-sources.zip) (approx. 148 MB).
* **Release Notes**: [GitHub Releases](https://github.com/YuTinTW/LosslessStudio/releases).

### System Requirements
- **Hardware**: Apple Silicon (arm64: M1 / M2 / M3 / M4).
- **Operating System**: macOS 26 (Tahoe) or newer.

### macOS Gatekeeper Notice
LosslessStudio uses local Ad-hoc code signing. If macOS displays a warning that the developer cannot be verified upon first launch:
1. Open **System Settings** > **Privacy & Security**.
2. Scroll to the Security section and click **Open Anyway** next to LosslessStudio.
3. Alternatively, run in Terminal:
   ```bash
   xattr -d com.apple.quarantine /Applications/LosslessStudio.app
   ```

---

## 📄 Documentation

* [English User Guide](Resources/USER_GUIDE.en.md)
* [English Installation Guide](Resources/INSTALLATION_GUIDE.en.txt)
* [繁體中文使用說明](Resources/USER_GUIDE.md)

---

## ⚖️ License & Open Source Attributions

LosslessStudio is distributed under the GNU General Public License v3.0 (GPL-3.0). It bundles and utilizes FFmpeg (LGPL v2.1+ / GPL v2+) and ImageMagick under their respective open source licenses. Complete license texts and source links are provided in the `Resources/` directory.
