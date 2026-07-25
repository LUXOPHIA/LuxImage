# LuxImage

[日本語](ja/README.md)

A demo application of `LUX.Data.Image` — an ultra-high-resolution image library for Delphi / FireMonkey.

FireMonkey's `TBitmap` shares its storage with the GPU and therefore inherits the GPU's texture size limit, which in practice caps it at about 8,192 × 8,192 pixels. `TLuxImage` keeps every pixel in CPU memory instead, so the usable size is bounded by RAM rather than by the GPU — 100,000 × 100,000 pixels and beyond.

![](https://github.com/LUXOPHIA/LuxImage/raw/main/--------/_SCREENSHOT/LuxImage.png)

## What it shows

The application opens with nothing loaded — pick an image with `開く…` to try it. No image is bundled with the demo; anything sized up to tens of thousands of pixels square will show what the library is for. Loading and saving both run on a worker thread, so the window stays responsive while the progress bar fills, however large the file.

- Mouse: rolling the wheel towards you zooms in around the cursor; dragging with the left button scrolls. Past 1:1 the pixels are drawn as squares (nearest neighbour), below it the image is filtered linearly.
- Panel:
  - `開く…` / `保存…` — open and save. PNG and JPEG are supported both ways.
  - `画素形式` — the pixel format the next-opened file is loaded into: `UInt08`, `UInt16`, `SFlo16`, `SFlo32`.
  - `全体表示` — fit the whole image to the window.
  - `等倍 ( 1 : 1 )` — one image pixel per screen pixel.
  - `ガンマ` — display gamma, `out = in^(1/Gamma)`. Defaults to 1.0 for the integer formats and 2.2 for the floating-point ones.
  - `トーンマップ` — Reinhard tone mapping, enabled by default for the floating-point formats.
- The label at the bottom of the panel reports the image size, the pixel format, the current zoom, and which level of the mip pyramid is being drawn.

## The library

`LUX.Data.Image` stores pixels in 256 × 256 tiles and owns a mip pyramid, so a fully zoomed-out view of a 100,000² image costs no more than a zoomed-in one. Only the visible tiles are handed to Skia, which means the per-frame cost depends on the size of the window rather than the size of the image. Tone mapping and gamma correction run on the GPU as an SkSL runtime colour filter.

Full documentation:
[`_LIBRARY/LUXOPHIA/LUX/Data/Image`](_LIBRARY/LUXOPHIA/LUX/Data/Image/README.md).

## Build

- Delphi (RAD Studio) / FireMonkey + Skia (`GlobalUseSkia = True`, and `FMX.Skia.Canvas.Vulkan` in the uses clause so that the Vulkan backend registers itself).
- Open `LuxImage.dproj` and build for Win64.
- `sk4d.dll` must sit next to the executable; RAD Studio deploys it automatically when the project is built from the IDE.

## Libraries (git subtree)

- `_LIBRARY/LUXOPHIA/LUX`
