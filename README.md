# LuxImage

[English](README.md) | [日本語](ja/README.md)

LuxImage is a demo application of `LUX.Data.Image`, an ultra-high-resolution image library for Delphi / FireMonkey. Because `TLuxImage` keeps every pixel in CPU memory as 256 × 256 tiles with a built-in mip pyramid, image size is not bounded by the GPU texture limit: it is unlimited as far as RAM allows. The application opens PNG / JPEG files, and renders a Mandelbrot set of up to 65,536² pixels on all cores while showing the blocks as they finish.

![](--------/_SCREENSHOT/LuxImage.png)

## 利用ライブラリ

* [**LUX**](https://github.com/LUXOPHIA/LUX) ：The LUXOPHIA standard library, whose `LUX.Data.Image` units provide the tiled ultra-high-resolution image classes, viewer, and asynchronous file I/O used by this application.

## 1. Overview

FireMonkey's `TBitmap` shares its storage with the GPU and therefore inherits the GPU's texture size limit, which in practice caps it at about 8,192 × 8,192 pixels. `TLuxImage` stores pixels purely in CPU memory instead, and its viewer `TLuxImageViewer` hands only the *visible* tiles to Skia — so the per-frame cost depends on the size of the window, not the size of the image.

Main features demonstrated by this application:

- **No GPU size limit.** Pixels live in CPU memory, in 256 × 256 tiles (`LUXIMAGE_TILE = 256`), each tile a separate heap block. Every tile of every level is allocated by `SetSize`; an image that does not fit in free physical memory is refused there and then with `EOutOfMemory`.
- **Parallel rendering with live display.** `TLuxImageWorker` cuts the image into 64 × 64 blocks and hands them one at a time to a thread per logical processor; each finished block is reported with `TileChanged`, and the viewer — which validates its tile cache against per-tile stamps and updates only the footprints of changed tiles in the pyramid — shows it within a frame. The Mandelbrot set is the demo's stand-in for ray tracing: pixels inside the set run to the iteration limit while pixels outside escape in a few steps, so per-block cost varies by orders of magnitude and only dynamic block assignment keeps the threads balanced.
- **Four pixel formats**, each mapping one-to-one onto a native Skia color type, so tiles reach the GPU without any pixel-format conversion:

  | Class | Pixel record | Bytes / pixel | Skia color type | Default display gamma |
  |---|---|---|---|---|
  | `TLuxImageUInt08` | `TByteRGBA` | 4 | `BGRA8888` | 1.0 |
  | `TLuxImageUInt16` | `TWordRGBA` | 8 | `RGBA16161616` | 1.0 |
  | `TLuxImageSFlo16` | `THalfRGBA` | 8 | `RGBAF16` | 2.2 |
  | `TLuxImageSFlo32` | `TSingleRGBA` | 16 | `RGBAF32` | 2.2 |

  Integer formats are taken to hold display-encoded (sRGB) values, so their default gamma is 1.0; floating-point formats are taken to hold linear values, so their default gamma is 2.2 and tone mapping is enabled by default. Alpha is stored straight (not premultiplied).
- **Built-in mip pyramid** [2][3], allocated with the image and rebuilt incrementally — a changed tile costs a third of a tile to propagate, a loaded file a third of the image, both in parallel — so a fully zoomed-out view costs no more than a zoomed-in one, however large the image.
- **Asynchronous file I/O** — loading and saving run on a worker thread (`TTask`) with per-row progress reporting and completion events delivered to the main thread through `TThread.Queue`, so the window stays responsive however large the file. PNG (implemented directly on `System.ZLib`, all bit depths / color types / `tRNS` / Adam7) and JPEG (via the Skia codec) are supported both ways.
- **GPU tone mapping and gamma correction** as an SkSL runtime color filter [1][4], so changing the display settings costs nothing and does not invalidate the tile cache.
- **Colour management** through `LUX.Color.Space`: an image may carry a colour space (sRGB, Display P3, Adobe RGB, Rec.2020, ProPhoto RGB, ACEScg and their linear forms, or a custom one), which is embedded in PNG (`sRGB` / `iCCP`) and JPEG (APP2 ICC) on save and recovered on load. The viewer converts on the GPU — image transfer function → primaries matrix → display transfer function — to the ICC profile Windows assigns to the monitor the window is on, or to a space you set. Pixel values are never modified.

## 2. Technical Background

### 2.1 Mip level selection

The viewer draws from the pyramid level $l$ chosen from the zoom scale $s$ (screen pixels per image pixel) as

```math
l \;=\; \operatorname{clamp}\!\left( \left\lfloor \log_2 \frac{1}{s} \right\rfloor,\; 0,\; N-1 \right)
\tag{1}
```

where $N$ is the number of levels. Within the chosen level the effective scale is $s \cdot 2^{l} \in (\tfrac{1}{2}, 1]$: a level is never magnified, and the remaining minification of at most 2 is left to the GPU, which draws every tile as a mip-mapped texture with trilinear sampling and so blends the level continuously with the next coarser one [2] — sharp at every zoom, with neither magnification blur nor minification aliasing. At $s \geq 1$ sampling is nearest neighbour (pixels show as squares past 1:1).

### 2.2 Memory cost of the pyramid

Level 0 is the original $W \times H$ image; each subsequent level halves both dimensions down to 1 × 1. The total pixel count is

```math
\sum_{l \ge 0} \frac{W}{2^{l}} \cdot \frac{H}{2^{l}} \;=\; WH \sum_{l \ge 0} \frac{1}{4^{l}} \;\approx\; \frac{4}{3}\,WH
\tag{2}
```

i.e. the pyramid adds roughly 33 % to the memory of the base image [3], and `SetSize` allocates all of it up front.

### 2.3 Incremental pyramid update

Every level-0 tile carries a dirty flag, and every tile of every level a stamp that advances when its content changes. A thread that finishes writing a tile calls `TileChanged`, two atomic operations and no lock. Before each frame the viewer calls `UpdateLevels`, which rebuilds only the *footprint* of each dirty tile in the levels above — a square of side $256 / 2^{l}$ in level $l$, computed solely from the same tile's footprint one level down — so the chains of different tiles are independent up to level 8 and run in parallel. The work per changed tile is

```math
\sum_{l=1}^{8} \frac{1}{4^{l}} \;\approx\; \frac{1}{3}
\tag{2'}
```

of a tile, however large the image; a full load marks every tile dirty and goes through the same path.

### 2.4 Dynamic block assignment

`TLuxImageWorker` numbers the 64 × 64 blocks in raster order and hands them to $N$ threads through one shared atomic counter, one block per fetch. With no static partition, the imbalance at the end of a run is at most one block regardless of how per-pixel cost is distributed — the property a ray tracer needs. Blocks never cross a tile and are disjoint, so no lock is taken on the pixel store; the worker throttles `Notify` and `OnProgress` to about 30 Hz.

### 2.5 Display gamma

Gamma correction is applied per channel on the GPU:

```math
out \;=\; in^{\,1/\gamma}
\tag{3}
```

with $\gamma$ set by the `ガンマ` slider (default 1.0 for integer formats, 2.2 for floating-point ones).

### 2.6 Tone mapping

Tone mapping is the extended Reinhard operator [1], applied per RGB channel to the un-premultiplied color $L$ with white point $W$ (property `White`, default 1):

```math
L_{out} \;=\; \operatorname{clamp}\!\left( \frac{L \left( 1 + L / W^{2} \right)}{1 + L},\; 0,\; 1 \right)
\tag{4}
```

For $W \to \infty$ this reduces to the simple Reinhard curve $L_{out} = L / (1 + L)$. The SkSL filter un-premultiplies the incoming color, applies (4) and then (3), and re-premultiplies. Since both run as a single runtime color filter on the GPU, toggling `トーンマップ` or dragging `ガンマ` never touches the CPU-side tile cache.

## 3. Architecture

```
■ Ownership

・TForm1 (Main.pas)                       ･･･ UI: format combo, gamma, render size, progress
  ┣・TLuxImage (abstract)                ･･･ owns
  ┣・TLuxImageWorker                     ･･･ owns; renders the Mandelbrot set into the image
  ┗・TLuxImageViewer :TFrame             ･･･ Image (LUX.Data.Image.Viewer.pas)

■ Class hierarchy — pixel formats    (storage: 256×256 tiles + mip pyramid, all allocated by SetSize)

・TLuxImage (abstract)
  ┣・TLuxImageUInt08
  ┣・TLuxImageUInt16
  ┣・TLuxImageSFlo16
  ┗・TLuxImageSFlo32

■ Parallel rendering and change tracking

・TLuxImageWorker
  ┗・N threads, one 64×64 block per atomic fetch
     ┗・TForm1.Mandelbrot( ThreadI, X,Y,W,H )   ･･･ SetRow per row of the block
        ┗・TLuxImage.TileChanged( TX,TY )        ･･･ Dirty := 1, Stamp++  (atomic, no lock)
           ┗・TLuxImage.Notify  ( ≤ 30 Hz )      ･･･ OnChange → TLuxImageViewer.Redraw
              ┗・OnProgress ( ≤ 30 Hz ), OnFinished

■ Per-frame draw pipeline

・TLuxImageViewer
  ┗・per frame
     ┗・1. UpdateLevels: footprints of dirty tiles into levels 1…, in parallel
        ┗・2. pick level l with eq. (1)
           ┗・3. enumerate visible tiles (≈ 54 for a 1920×1080 window)
              ┗・4. TileImage(): validate by stamps of tile + 8 neighbours, else gather 1-px apron, wrap as ISkImage
                 ┣・cache in TDictionary<TTileKey,TTileImg> (CACHE_MAX 512, LRU)
                 ┗・5. ACanvas.DrawImageRect per tile
                    ┣・ISkRuntimeEffect color filter (tone map + gamma, SkSL)
                    ┗・ISkCanvas: FMX Skia canvas
                       ┣・Vulkan GPU backend when available
                       ┗・falls back to an intermediate raster TBitmap otherwise

■ Asynchronous file I/O

・TLuxImage
  ┗・LoadFromFileAsync / SaveToFileAsync ･･･ (LUX.Data.Image.Files.pas)
     ┗・TTask worker
        ┣・decode/encode PNG (System.ZLib) or JPEG (Skia codec)
        ┣・build the whole mip pyramid in parallel ( UpdateLevels with every tile dirty )
        ┗・OnProgress / OnLoaded / OnSaved queued to the main thread
```

The viewer draws nothing while `Busy` is set, because a load begins with `SetSize`, which replaces the tile structure; a render, by contrast, writes into tiles that already exist, so the viewer keeps drawing throughout and only ever reads a tile after its dirty flag has been taken down. Cached tile images carry a one-pixel apron gathered from the neighbouring tiles, so linear filtering at a tile boundary reads real neighbouring pixels and no seams appear.

```
・LuxImage/
  ┣・LuxImage.dpr                        ･･･ GlobalUseSkia := True (Vulkan)
  ┣・LuxImage.dproj                      ･･･ RAD Studio project (Win64)
  ┣・Main.pas / Main.fmx                 ･･･ TForm1: panel, progress, info
  ┣・_LIBRARY/
  ┃  ┗・LUXOPHIA/LUX/                   ･･･ git subtree of LUXOPHIA/LUX
  ┃     ┣・LUX.pas                      ･･･ base declarations
  ┃     ┣・Color/                       ･･･ pixel types (TByteRGBA, …), colour spaces (LUX.Color.Space)
  ┃     ┣・D1/Half/                     ･･･ THalf, the half-precision scalar
  ┃     ┗・Data/Image/
  ┃        ┣・LUX.Data.Image.pas        ･･･ TLuxImage: tiles & pyramid, change tracking
  ┃        ┣・LUX.Data.Image.Files.pas  ･･･ PNG / JPEG read/write, async I/O
  ┃        ┣・LUX.Data.Image.Worker.pas ･･･ TLuxImageWorker: parallel block scheduler
  ┃        ┣・LUX.Data.Image.Viewer.pas ･･･ TLuxImageViewer
  ┃        ┗・README.md                 ･･･ full library documentation
  ┗・--------/_SCREENSHOT/LuxImage.png
```

`LUX.Data.Image.pas` and `LUX.Data.Image.Worker.pas` use neither FireMonkey nor Skia; those dependencies are confined to the file and viewer units. Full library documentation: [`_LIBRARY/LUXOPHIA/LUX/Data/Image`](_LIBRARY/LUXOPHIA/LUX/Data/Image/README.md).

## 4. Usage

The application opens with nothing loaded — pick an image with `開く…`, or render one with `描画開始`. No image is bundled; anything sized up to tens of thousands of pixels square will show what the library is for.

| Control | Action |
|---|---|
| Mouse wheel (towards you) | Zoom in around the cursor; four notches double the scale |
| Left drag | Scroll |
| `開く…` (Open) | Open a PNG / JPEG asynchronously into the selected pixel format |
| `保存…` (Save) | Save as PNG / JPEG (quality 90) asynchronously |
| `画素形式` (Pixel format) | Format the next-opened or next-rendered image: `UInt08` / `UInt16` / `SFlo16` / `SFlo32` |
| `全体表示` (Fit) | Fit the whole image to the window |
| `等倍 ( 1 : 1 )` (1:1) | One image pixel per screen pixel |
| `ガンマ` (Gamma) | Display gamma $\gamma$ of eq. (3); defaults per format |
| `トーンマップ` (Tone map) | Reinhard tone mapping, eq. (4); on by default for floating-point formats |
| `色空間` (Colour space) | The image's colour space — `なし` (none) or one of the ten presets, sRGB to ACEScg. A loaded file's embedded profile selects the matching entry (or adds its own); the choice is embedded when saving and used for a render. With a colour space the viewer converts to the monitor's profile on the GPU; the info label shows *image → display* |
| `並列描画（マンデルブロ集合）` (Parallel render) | Side of the square image to render: 4,096 … 65,536 pixels |
| `描画開始` / `中止` (Render / Cancel) | Allocate an image of that size in the selected format and render the Mandelbrot set on all cores; the view fills in block by block and can be zoomed and scrolled meanwhile. Pressing again cancels after the blocks in flight |

The label at the bottom of the panel reports the image size, the pixel format, the current zoom, and which pyramid level is being drawn; load/save/render times are shown for a few seconds after each operation, and the percentage and elapsed time during a render.

If the selected size does not fit in free physical memory the render is refused with a message before anything is allocated: 65,536² pixels take 16 GB in `UInt08` and 64 GB in `SFlo32`, plus a third for the pyramid.

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
