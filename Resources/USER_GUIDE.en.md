# LosslessStudio user guide

LosslessStudio converts video, audio, images, and PDFs on your Mac. It creates separate output files and reports which properties it could verify.

## Convert files

1. Add files or a folder. You can also drop files into the window.
2. Select a conversion mode and output format for each job. Set the output location before running the batch.
3. Start the batch. Watch the progress in the job list. You can cancel an active batch and retry failed jobs from the list.
4. Review the result and any verification notes. Open the encoding monitor to compare source and output streams, or export a report to keep the results.

Keep verification reports private when they contain filenames, paths, or command diagnostics.

## Choose a mode

| Goal | Mode | What to check |
| --- | --- | --- |
| Change a video container | Stream copy | The existing codecs must be compatible with the target container. Review any compatibility conversion and which tracks were verified. |
| Preserve decoded video frames | Lossless transcode to FFV1 in MKV | Check the verification result for the source pixel format, frame comparison, and audio tracks. Output can be large. |
| Make a video for editing | ProRes 4444 XQ in MOV | ProRes is visually near-lossless and can change decoded pixel values. |
| Make a video easier to play | Compatibility transcode | Output codecs and sampling can change. Review the encoding settings and verification notes. |
| Preserve decoded audio samples | Lossless audio conversion | Review the PCM sample comparison. Output options include WAV, FLAC, ALAC, and AIFF. |
| Reduce audio size or change playback compatibility | Lossy audio conversion | Choose an output codec and bitrate. Resampling or lossy encoding can change the decoded samples. |
| Convert a still image | Image conversion | Supported image formats include PNG, TIFF, BMP, JPEG, and WebP. Check pixel and metadata warnings, especially when changing bit depth or alpha support. |
| Put an image into a PDF | Image to PDF | The conversion keeps the original pixel dimensions. EXIF metadata and the original color profile can be lost. |
| Render PDF pages as images | PDF to images | Choose a resolution in DPI and a picture format. Multipage PDFs produce one image per page. Rendering creates new pixels at the selected resolution. |

Office documents and animated or multipage image inputs are unsupported. PDF rendering supports multipage PDFs.

## Read verification results

- **Stream comparison** checks encoded stream data. Container metadata can still change.
- **Pixel or sample comparison** checks decoded data. Consult the result for the comparison scope and any limitations.
- **Visually near-lossless** and **lossy** describe conversions where decoded values can differ.
- **Unverified** means LosslessStudio could not establish equivalence. Read the accompanying reason before relying on the result.

## Troubleshoot

- **Unsupported output**. Pick an output format compatible with the source codecs or choose a compatibility conversion.
- **Output could not be written**. Make sure the output folder exists, is writable, and has enough free space.
- **PDF could not be rendered**. Check that the source opens and is unlocked. For very large pages, try a lower DPI.
- **Slow video jobs**. In advanced settings, reduce the number of simultaneous video jobs. FFV1 encoding and verification can use substantial CPU and disk space.

See [the installation guide](INSTALLATION_GUIDE.en.txt) for system requirements and language settings.
