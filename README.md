# LuxImage

[English](README.md) | [日本語](ja/README.md)

LuxImage is a demo application of `LUX.Data.Image`, an ultra-high-resolution image library for Delphi / FireMonkey. Because `TLuxImage` keeps every pixel in CPU memory as 256 × 256 tiles with a built-in mip pyramid, image size is not bounded by the GPU texture limit: it is unlimited as far as RAM allows.

![](--------/_SCREENSHOT/LuxImage.png)

## 利用ライブラリ

* [**LUX**](https://github.com/LUXOPHIA/LUX) ：The LUXOPHIA standard library, whose `LUX.Data.Image` units provide the tiled ultra-high-resolution image classes, viewer, and asynchronous file I/O used by this application.

## 1. Overview

FireMonkey's `TBitmap` shares its storage with the GPU and therefore inherits the GPU's texture size limit, which in practice caps it at about 8,192 × 8,192 pixels. `TLuxImage` stores pixels purely in CPU memory instead, and its viewer `TLuxImageViewer` hands only the *visible* tiles to Skia — so the per-frame cost depends on the size of the window, not the size of the image.

Main features demonstrated by this application:

- **No GPU size limit.** Pixels live in CPU memory, in 256 × 256 tiles (`LUXIMAGE_TILE = 256`), each tile a separate heap block.
- **Four pixel formats**, each mapping one-to-one onto a native Skia color type, so tiles reach the GPU without any pixel-format conversion:

  | Class | Pixel record | Bytes / pixel | Skia color type | Default display gamma |
  |---|---|---|---|---|
  | `TLuxImageUInt08` | `TByteRGBA` | 4 | `BGRA8888` | 1.0 |
  | `TLuxImageUInt16` | `TWordRGBA` | 8 | `RGBA16161616` | 1.0 |
  | `TLuxImageSFlo16` | `THalfRGBA` | 8 | `RGBAF16` | 2.2 |
  | `TLuxImageSFlo32` | `TSingleRGBA` | 16 | `RGBAF32` | 2.2 |

  Integer formats are taken to hold display-encoded (sRGB) values, so their default gamma is 1.0; floating-point formats are taken to hold linear values, so their default gamma is 2.2 and tone mapping is enabled by default. Alpha is stored straight (not premultiplied).
- **Built-in mip pyramid** [2][3], built on demand and in parallel on load, so a fully zoomed-out view costs no more than a zoomed-in one, however large the image.
- **Asynchronous file I/O** — loading and saving run on a worker thread (`TTask`) with per-row progress reporting and completion events delivered to the main thread through `TThread.Queue`, so the window stays responsive however large the file. PNG (implemented directly on `System.ZLib`, all bit depths / color types / `tRNS` / Adam7) and JPEG (via the Skia codec) are supported both ways.
- **GPU tone mapping and gamma correction** as an SkSL runtime color filter [1][4], so changing the display settings costs nothing and does not invalidate the tile cache.

## 2. Technical Background

### 2.1 Mip level selection

The viewer draws from the pyramid level $l$ chosen from the zoom scale $s$ (screen pixels per image pixel) as

```math
l \;=\; \operatorname{clamp}\!\left( \left\lceil \log_2 \frac{1}{s} \right\rceil,\; 0,\; N-1 \right)
\tag{1}
```

where $N$ is the number of levels. Within the chosen level the effective magnification is $s \cdot 2^{l} \in [1, 2)$: minification never occurs inside a level, so minification aliasing cannot arise by construction [2]. At $s \geq 1$ sampling is nearest neighbour (pixels show as squares past 1:1), below it linear.

### 2.2 Memory cost of the pyramid

Level 0 is the original $W \times H$ image; each subsequent level halves both dimensions down to 1 × 1. The total pixel count is

```math
\sum_{l \ge 0} \frac{W}{2^{l}} \cdot \frac{H}{2^{l}} \;=\; WH \sum_{l \ge 0} \frac{1}{4^{l}} \;\approx\; \frac{4}{3}\,WH
\tag{2}
```

i.e. the pyramid adds roughly 33 % to the memory of the base image [3].

### 2.3 Display gamma

Gamma correction is applied per channel on the GPU:

```math
out \;=\; in^{\,1/\gamma}
\tag{3}
```

with $\gamma$ set by the `ガンマ` slider (default 1.0 for integer formats, 2.2 for floating-point ones).

### 2.4 Tone mapping

Tone mapping is the extended Reinhard operator [1], applied per RGB channel to the un-premultiplied color $L$ with white point $W$ (property `White`, default 1):

```math
L_{out} \;=\; \operatorname{clamp}\!\left( \frac{L \left( 1 + L / W^{2} \right)}{1 + L},\; 0,\; 1 \right)
\tag{4}
```

For $W \to \infty$ this reduces to the simple Reinhard curve $L_{out} = L / (1 + L)$. The SkSL filter un-premultiplies the incoming color, applies (4) and then (3), and re-premultiplies. Since both run as a single runtime color filter on the GPU, toggling `トーンマップ` or dragging `ガンマ` never touches the CPU-side tile cache.

## 3. Architecture

```
■ Ownership

・TForm1 (Main.pas)                       ･･･ UI: format combo, gamma, progress
  ┣・TLuxImage (abstract)                ･･･ owns
  ┗・TLuxImageViewer :TFrame             ･･･ Image (LUX.Data.Image.Viewer.pas)

■ Class hierarchy — pixel formats    (storage: 256×256 tiles + mip pyramid)

・TLuxImage (abstract)
  ┣・TLuxImageUInt08
  ┣・TLuxImageUInt16
  ┣・TLuxImageSFlo16
  ┗・TLuxImageSFlo32

■ Change notification

・TLuxImage
  ┗・OnChange
     ┗・TLuxImageViewer

■ Per-frame draw pipeline

・TLuxImageViewer
  ┗・per frame
     ┗・1. pick level l with eq. (1), NeedLevel( l )
        ┗・2. enumerate visible tiles (≈ 54 for a 1920×1080 window)
           ┗・3. TileImage(): gather 1-px apron, wrap as ISkImage
              ┣・cache in TDictionary<TTileKey,TTileImg> (CACHE_MAX 512, LRU)
              ┗・4. ACanvas.DrawImageRect per tile
                 ┣・ISkRuntimeEffect color filter (tone map + gamma, SkSL)
                 ┗・ISkCanvas: FMX Skia canvas
                    ┣・Vulkan GPU backend when available
                    ┗・falls back to an intermediate raster TBitmap otherwise

■ Asynchronous file I/O

・TLuxImage
  ┗・LoadFromFileAsync / SaveToFileAsync ･･･ (LUX.Data.Image.Files.pas)
     ┗・TTask worker
        ┣・decode/encode PNG (System.ZLib) or JPEG (Skia codec)
        ┣・build the whole mip pyramid in parallel
        ┗・OnProgress / OnLoaded / OnSaved queued to the main thread
```

The viewer draws nothing while `Busy` is set, which is what allows the worker to write pixels without any locking. Cached tile images carry a one-pixel apron gathered from the neighbouring tiles, so linear filtering at a tile boundary reads real neighbouring pixels and no seams appear.

```
・LuxImage/
  ┣・LuxImage.dpr                        ･･･ GlobalUseSkia := True (Vulkan)
  ┣・LuxImage.dproj                      ･･･ RAD Studio project (Win64)
  ┣・Main.pas / Main.fmx                 ･･･ TForm1: panel, progress, info
  ┣・_LIBRARY/
  ┃  ┗・LUXOPHIA/LUX/                   ･･･ git subtree of LUXOPHIA/LUX
  ┃     ┣・LUX.pas                      ･･･ base declarations
  ┃     ┣・Color/                       ･･･ pixel types (TByteRGBA, …)
  ┃     ┣・D1/Half/                     ･･･ THalf, the half-precision scalar
  ┃     ┗・Data/Image/
  ┃        ┣・LUX.Data.Image.pas        ･･･ TLuxImage: tiles & pyramid
  ┃        ┣・LUX.Data.Image.Files.pas  ･･･ PNG / JPEG read/write, async I/O
  ┃        ┣・LUX.Data.Image.Viewer.pas ･･･ TLuxImageViewer
  ┃        ┗・README.md                 ･･･ full library documentation
  ┗・--------/_SCREENSHOT/LuxImage.png
```

`LUX.Data.Image.pas` uses neither FireMonkey nor Skia; those dependencies are confined to the file and viewer units. Full library documentation: [`_LIBRARY/LUXOPHIA/LUX/Data/Image`](_LIBRARY/LUXOPHIA/LUX/Data/Image/README.md).

## 4. Usage

The application opens with nothing loaded — pick an image with `開く…`. No image is bundled; anything sized up to tens of thousands of pixels square will show what the library is for.

| Control | Action |
|---|---|
| Mouse wheel (towards you) | Zoom in around the cursor; four notches double the scale |
| Left drag | Scroll |
| `開く…` (Open) | Open a PNG / JPEG asynchronously into the selected pixel format |
| `保存…` (Save) | Save as PNG / JPEG (quality 90) asynchronously |
| `画素形式` (Pixel format) | Format the next-opened file is loaded into: `UInt08` / `UInt16` / `SFlo16` / `SFlo32` |
| `全体表示` (Fit) | Fit the whole image to the window |
| `等倍 ( 1 : 1 )` (1:1) | One image pixel per screen pixel |
| `ガンマ` (Gamma) | Display gamma $\gamma$ of eq. (3); defaults per format |
| `トーンマップ` (Tone map) | Reinhard tone mapping, eq. (4); on by default for floating-point formats |

The label at the bottom of the panel reports the image size, the pixel format, the current zoom, and which pyramid level is being drawn; load/save times are shown for a few seconds after each operation.

## 5. Building

- RAD Studio (Delphi) with FireMonkey + Skia [5], both of which ship with RAD Studio.
- The project source enables the Skia canvas and its Vulkan backend:

  ```pascal
  uses ..., FMX.Skia, FMX.Skia.Canvas.Vulkan, ...;

  GlobalUseSkia                    := True;
  GlobalUseSkiaRasterWhenAvailable := False;  // do not fall back to the CPU raster canvas
  ```

  With this in place the viewer draws straight into the window surface. Without it the viewer still works, through an intermediate raster bitmap, at the cost of a full-window blit every frame.
- Open `LuxImage.dproj` and build for **Win64**.
- `sk4d.dll` must sit next to the executable; RAD Studio deploys it automatically when the project is built from the IDE.

## 6. References

1. E. Reinhard, M. Stark, P. Shirley, J. Ferwerda, ["Photographic Tone Reproduction for Digital Images"](https://doi.org/10.1145/566654.566575), *ACM Transactions on Graphics (Proc. SIGGRAPH)*, 21(3), 2002.
2. L. Williams, ["Pyramidal Parametrics"](https://doi.org/10.1145/964967.801126), *Computer Graphics (Proc. SIGGRAPH)*, 17(3), 1983.
3. [Mipmap](https://en.wikipedia.org/wiki/Mipmap) — Wikipedia.
4. [SkSL — Skia Shading Language](https://skia.org/docs/user/sksl/).
5. [Skia4Delphi](https://github.com/skia4delphi/skia4delphi).

## 💖 [Embarcadero](https://www.embarcadero.com/) [**Delphi**](https://www.embarcadero.com/products/delphi)
Integrated Development Environment (IDE) for Creating Native Cross-Platform Apps.
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/products/delphi/starter)
