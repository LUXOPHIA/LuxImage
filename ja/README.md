# LuxImage

[English](../README.md) | [日本語](README.md)

LuxImage は、Delphi / FireMonkey 向け超高解像度画像ライブラリ `LUX.Data.Image` のデモアプリケーションである。`TLuxImage` は全画素を 256 × 256 のタイルとして CPU メモリに保持し、縮小ピラミッド（ミップマップ）を内蔵するため、画像サイズは GPU のテクスチャ制限に縛られず、RAM の許す限り無制限である。本アプリケーションは PNG / JPEG を開くほか、最大 65,536² 画素のマンデルブロ集合を全コアで描画し、終わったブロックから順に表示する。

![](../--------/_SCREENSHOT/LuxImage.png)

## 利用ライブラリ

* [**LUX**](https://github.com/LUXOPHIA/LUX) ：LUXOPHIA の標準ライブラリ。本アプリケーションが用いるタイル式超高解像度画像クラス・ビューア・非同期ファイル入出力は、その `LUX.Data.Image` ユニット群が提供する。

## 1. 概要

FireMonkey の `TBitmap` は GPU とデータを共有するため GPU のテクスチャサイズ制限をそのまま受け、実際には 8,192 × 8,192 画素程度が上限となる。これに対し `TLuxImage` は画素を純粋に CPU メモリへ格納し、ビューア `TLuxImageViewer` は*可視*タイルだけを Skia に渡す ―― そのため 1 フレームあたりのコストは画像の大きさではなく窓の大きさで決まる。

本アプリケーションが示す主な機能：

- **GPU によるサイズ制限なし。** 画素は 256 × 256 のタイル（`LUXIMAGE_TILE = 256`）として CPU メモリに置かれ、各タイルは独立したヒープブロックである。全段の全タイルは `SetSize` が確保し、物理メモリの空きに載らない画像はその場で `EOutOfMemory` として拒否される。
- **並列描画とライブ表示。** `TLuxImageWorker` が画像を 64 × 64 のブロックに刻み、論理 CPU 1 個につき 1 本のスレッドへ 1 個ずつ配る。終わったブロックは `TileChanged` で報告され、ビューア ── タイルごとの Stamp でキャッシュを検証し、ピラミッドは変わったタイルの足跡だけを更新する ── が次のフレームで映し出す。マンデルブロ集合はレイトレーシングの代役である。集合の内側の画素は反復上限まで回り、外側は数回で脱出するので、ブロックごとの計算量が桁で違い、動的なブロック割り当てでなければスレッドの負荷が釣り合わない。
- **4 種類の画素形式。** それぞれが Skia のネイティブカラータイプと 1 対 1 に対応するため、タイルは画素形式の変換なしに GPU へ渡る：

  | クラス | 画素レコード | バイト／画素 | Skia カラータイプ | 既定の表示ガンマ |
  |---|---|---|---|---|
  | `TLuxImageUInt08` | `TByteRGBA` | 4 | `BGRA8888` | 1.0 |
  | `TLuxImageUInt16` | `TWordRGBA` | 8 | `RGBA16161616` | 1.0 |
  | `TLuxImageSFlo16` | `THalfRGBA` | 8 | `RGBAF16` | 2.2 |
  | `TLuxImageSFlo32` | `TSingleRGBA` | 16 | `RGBAF32` | 2.2 |

  整数形式は表示エンコード済み（sRGB）の値を保持するものとして既定ガンマ 1.0、浮動小数形式はリニアな値を保持するものとして既定ガンマ 2.2 とし、トーンマッピングを既定で有効にする。アルファはストレート（非プリマルチプライ）で保持する。
- **縮小ピラミッド内蔵** [2][3]。画像と共に確保され、差分で作り直される ── 変わったタイル 1 枚の反映はタイルの 3 分の 1、ファイルの読み込みは画像の 3 分の 1 の費用で、いずれも並列 ── ので、どれほど大きな画像でも全景表示は拡大表示と同じコストで描ける。
- **非同期ファイル入出力** ―― 読み込みも保存もワーカースレッド（`TTask`）で走り、行単位の進捗通知と完了イベントは `TThread.Queue` でメインスレッドへ届く。そのためファイルがどれだけ大きくてもウィンドウは応答し続ける。PNG（`System.ZLib` 上に直接実装。全ビット深度・全カラータイプ・`tRNS`・Adam7 に対応）と JPEG（Skia コーデック経由）に両方向で対応。
- **GPU 上のトーンマッピングとガンマ補正**。SkSL のランタイムカラーフィルタとして実行される [1][4] ため、表示設定の変更はコストゼロで、タイルキャッシュも無効化しない。

## 2. 技術的背景

### 2.1 縮小段（ミップレベル）の選択

ビューアが描画に使うピラミッドの段 $l$ は、ズーム倍率 $s$（画像 1 画素あたりの画面画素数）から

```math
l \;=\; \operatorname{clamp}\!\left( \left\lceil \log_2 \frac{1}{s} \right\rceil,\; 0,\; N-1 \right)
\tag{1}
```

と選ぶ。ここで $N$ は段数である。選ばれた段の内部では実効倍率が $s \cdot 2^{l} \in [1, 2)$ となり、段内で縮小が起こらないため、縮小によるエイリアシングが原理的に発生しない [2]。$s \geq 1$ では最近傍サンプリング（等倍を超えると画素が四角に見える）、それ未満では線形補間となる。

### 2.2 ピラミッドのメモリコスト

段 0 は元の $W \times H$ 画像であり、以降の段は縦横を半分ずつ 1 × 1 まで縮める。総画素数は

```math
\sum_{l \ge 0} \frac{W}{2^{l}} \cdot \frac{H}{2^{l}} \;=\; WH \sum_{l \ge 0} \frac{1}{4^{l}} \;\approx\; \frac{4}{3}\,WH
\tag{2}
```

すなわちピラミッドは元画像のメモリに対しおよそ 33 % の追加となり [3]、`SetSize` はその全てを前もって確保する。

### 2.3 ピラミッドの差分更新

段 0 の各タイルは Dirty フラグを、全段の各タイルは内容が変わると進む Stamp を持つ。タイルを書き終えたスレッドは `TileChanged` を呼ぶ。不可分操作 2 回で、ロックは要らない。ビューアは毎フレームの前に `UpdateLevels` を呼び、Dirty なタイルの*足跡*だけを上の段に作り直す ── 段 $l$ では一辺 $256 / 2^{l}$ の正方形で、同じタイルの 1 段下の足跡だけから計算できる ── ので、タイルごとの連鎖は段 8 まで互いに独立で、並列に走る。変わったタイル 1 枚あたりの仕事量は

```math
\sum_{l=1}^{8} \frac{1}{4^{l}} \;\approx\; \frac{1}{3}
\tag{2'}
```

タイルぶんであり、画像の大きさによらない。ファイルの読み込みは全タイルを Dirty にして同じ経路を通る。

### 2.4 動的なブロック割り当て

`TLuxImageWorker` は 64 × 64 のブロックにラスタ順の番号を振り、共有の不可分カウンタ 1 つで $N$ 本のスレッドへ 1 回に 1 個ずつ配る。静的な分割をしないので、画素ごとの計算量がどう分布していても最後の待ちは高々ブロック 1 個ぶんに収まる ── レイトレーサに要る性質である。ブロックはタイルをまたがず互いに素なので、画素の格納領域にロックはかからない。ワーカーは `Notify` と `OnProgress` を約 30 Hz に間引く。

### 2.5 表示ガンマ

ガンマ補正は GPU 上でチャンネルごとに

```math
out \;=\; in^{\,1/\gamma}
\tag{3}
```

と適用される。$\gamma$ は `ガンマ` スライダで設定する（既定値は整数形式が 1.0、浮動小数形式が 2.2）。

### 2.6 トーンマッピング

トーンマッピングは拡張 Reinhard 演算子 [1] であり、非プリマルチプライの色 $L$ に対し、白色点 $W$（プロパティ `White`、既定値 1）を用いて RGB チャンネルごとに

```math
L_{out} \;=\; \operatorname{clamp}\!\left( \frac{L \left( 1 + L / W^{2} \right)}{1 + L},\; 0,\; 1 \right)
\tag{4}
```

と適用される。$W \to \infty$ の極限で単純な Reinhard 曲線 $L_{out} = L / (1 + L)$ に帰着する。SkSL フィルタは入力色のプリマルチプライを解き、式 (4)、続いて式 (3) を適用してから再びプリマルチプライする。両者は単一のランタイムカラーフィルタとして GPU 上で走るため、`トーンマップ` の切り替えや `ガンマ` のドラッグは CPU 側のタイルキャッシュに一切触れない。

## 3. アーキテクチャ

```
■ 所有

・TForm1 (Main.pas)                       ･･･ UI：形式コンボ・ガンマ・描画サイズ・進捗
  ┣・TLuxImage（抽象）                   ･･･ 所有
  ┣・TLuxImageWorker                     ･･･ 所有。マンデルブロ集合を画像へ描く
  ┗・TLuxImageViewer :TFrame             ･･･ Image (LUX.Data.Image.Viewer.pas)

■ クラス階層 — 画素形式        （記憶形式：256×256 タイル＋縮小ピラミッド。全て SetSize が確保）

・TLuxImage（抽象）
  ┣・TLuxImageUInt08
  ┣・TLuxImageUInt16
  ┣・TLuxImageSFlo16
  ┗・TLuxImageSFlo32

■ 並列描画と変更の追跡

・TLuxImageWorker
  ┗・N スレッド。不可分の取得 1 回につき 64×64 ブロック 1 個
     ┗・TForm1.Mandelbrot( ThreadI, X,Y,W,H )   ･･･ ブロックの行ごとに SetRow
        ┗・TLuxImage.TileChanged( TX,TY )        ･･･ Dirty := 1、Stamp++（不可分・ロック無し）
           ┗・TLuxImage.Notify（≦ 30 Hz）        ･･･ OnChange → TLuxImageViewer.Redraw
              ┗・OnProgress（≦ 30 Hz）、OnFinished

■ 毎フレームの描画パイプライン

・TLuxImageViewer
  ┗・毎フレーム
     ┗・1. UpdateLevels           ･･･ Dirty なタイルの足跡を段 1 以上へ並列に反映
        ┗・2. 式 (1) で段 l を選ぶ
           ┗・3. 可視タイルを列挙（1920×1080 の窓で高々約 54 枚）
              ┗・4. TileImage()          ･･･ タイル＋周囲 8 枚の Stamp で検証。古ければ、のりしろを集めて ISkImage 化
                 ┣・TDictionary<TTileKey,TTileImg>（CACHE_MAX 512、LRU）
                 ┗・5. タイルごとに ACanvas.DrawImageRect
                    ┣・ISkRuntimeEffect カラーフィルタ（トーンマップ＋ガンマ）
                    ┗・ISkCanvas            ･･･ FMX Skia キャンバス
                       ┣・対応環境では Vulkan GPU バックエンド
                       ┗・非対応環境では中間ラスタ TBitmap 経由

■ 非同期ファイル入出力

・TLuxImage
  ┗・LoadFromFileAsync / SaveToFileAsync ･･･ (LUX.Data.Image.Files.pas)
     ┗・TTask ワーカー
        ┣・PNG（System.ZLib）／JPEG（Skia コーデック）の復号・符号化
        ┣・縮小ピラミッド全体の並列構築（全タイルを Dirty にした UpdateLevels）
        ┗・OnProgress / OnLoaded / OnSaved をメインスレッドへキュー
```

`Busy` の間、ビューアは何も描かない。読み込みは `SetSize` から始まり、タイルの構造そのものが入れ替わるためである。対して描画は既にあるタイルへ書き込むだけなので、ビューアはその間も描き続け、タイルは Dirty を降ろした後にしか読まない。キャッシュされるタイル画像は隣接タイルから集めた 1 画素ののりしろ（エプロン）を持つため、タイル境界での線形補間は実際の隣接画素を読み、継ぎ目が現れない。

```
・LuxImage/
  ┣・LuxImage.dpr                        ･･･ GlobalUseSkia := True（Vulkan）
  ┣・LuxImage.dproj                      ･･･ RAD Studio プロジェクト（Win64）
  ┣・Main.pas / Main.fmx                 ･･･ TForm1：操作パネル・進捗・情報
  ┣・_LIBRARY/
  ┃  ┗・LUXOPHIA/LUX/                   ･･･ LUXOPHIA/LUX の git subtree
  ┃     ┣・LUX.pas                      ･･･ 基本宣言
  ┃     ┣・Color/                       ･･･ 画素型（TByteRGBA など）
  ┃     ┣・D1/Half/                     ･･･ THalf（半精度スカラー）
  ┃     ┗・Data/Image/
  ┃        ┣・LUX.Data.Image.pas        ･･･ TLuxImage：タイルと縮小段、変更の追跡
  ┃        ┣・LUX.Data.Image.Files.pas  ･･･ PNG/JPEG の読み書き・非同期入出力
  ┃        ┣・LUX.Data.Image.Worker.pas ･･･ TLuxImageWorker：並列ブロックスケジューラ
  ┃        ┣・LUX.Data.Image.Viewer.pas ･･･ TLuxImageViewer
  ┃        ┗・README.md                 ･･･ ライブラリの詳細ドキュメント
  ┗・--------/_SCREENSHOT/LuxImage.png
```

`LUX.Data.Image.pas` と `LUX.Data.Image.Worker.pas` は FireMonkey も Skia も使用しない。これらへの依存はファイルユニットとビューアユニットに限られる。ライブラリの詳細ドキュメント：[`_LIBRARY/LUXOPHIA/LUX/Data/Image`](../_LIBRARY/LUXOPHIA/LUX/Data/Image/ja/README.md)。

## 4. 使い方

起動時は何も読み込まれていない ―― `開く…` で画像を選ぶか、`描画開始` で描く。画像は同梱していない。数万画素四方までの画像であれば、このライブラリの用途が分かるはずである。

| 操作 | 動作 |
|---|---|
| マウスホイール（手前へ） | カーソル位置を中心に拡大。ノッチ 4 段で倍率 2 倍 |
| 左ドラッグ | スクロール |
| `開く…` | PNG / JPEG を選択中の画素形式へ非同期に読み込む |
| `保存…` | PNG / JPEG として非同期に保存（品質 90） |
| `画素形式` | 次に開く、または次に描く画像の形式：`UInt08` / `UInt16` / `SFlo16` / `SFlo32` |
| `全体表示` | 画像全体を窓に合わせる |
| `等倍 ( 1 : 1 )` | 画像の 1 画素を画面の 1 画素で表示する |
| `ガンマ` | 式 (3) の表示ガンマ $\gamma$。既定値は形式ごと |
| `トーンマップ` | 式 (4) の Reinhard トーンマッピング。浮動小数形式では既定で有効 |
| `並列描画（マンデルブロ集合）` | 描く正方形画像の一辺：4,096 〜 65,536 画素 |
| `描画開始` / `中止` | その大きさの画像を選択中の形式で確保し、マンデルブロ集合を全コアで描く。表示はブロック単位で埋まっていき、その間もズームとスクロールができる。もう一度押すと、実行中のブロックを終えた時点で中止する |

パネル下部のラベルには、画像の大きさ・画素形式・現在の倍率・描画中のピラミッド段が表示され、読み込み・保存・描画の所要時間は操作後数秒間、描画中は進捗率と経過時間が表示される。

選択した大きさが物理メモリの空きに載らない場合は、何も確保せずにメッセージで拒否される。65,536² 画素は `UInt08` で 16 GB、`SFlo32` で 64 GB を占め、ピラミッドがその 3 分の 1 を加える。

## 5. ビルド

- RAD Studio（Delphi）＋ FireMonkey ＋ Skia [5]。いずれも RAD Studio に同梱。
- プロジェクトソースで Skia キャンバスと Vulkan バックエンドを有効にする：

  ```pascal
  uses ..., FMX.Skia, FMX.Skia.Canvas.Vulkan, ...;

  GlobalUseSkia                    := True;
  GlobalUseSkiaRasterWhenAvailable := False;  // CPU ラスタキャンバスへ落とさない
  ```

  この設定によりビューアはウィンドウサーフェスへ直接描画する。設定なしでも中間ラスタビットマップ経由で動作するが、毎フレーム全面転写のコストがかかる。
- `LuxImage.dproj` を開き **Win64** でビルドする。
- `sk4d.dll` を実行ファイルと同じ場所に置くこと。IDE からビルドすれば RAD Studio が自動で配置する。

## 6. 参考文献

1. E. Reinhard, M. Stark, P. Shirley, J. Ferwerda, ["Photographic Tone Reproduction for Digital Images"](https://doi.org/10.1145/566654.566575), *ACM Transactions on Graphics (Proc. SIGGRAPH)*, 21(3), 2002.
2. L. Williams, ["Pyramidal Parametrics"](https://doi.org/10.1145/964967.801126), *Computer Graphics (Proc. SIGGRAPH)*, 17(3), 1983.
3. [Mipmap](https://en.wikipedia.org/wiki/Mipmap) — Wikipedia.
4. [SkSL — Skia Shading Language](https://skia.org/docs/user/sksl/).
5. [Skia4Delphi](https://github.com/skia4delphi/skia4delphi).

## 💖 [Embarcadero](https://www.embarcadero.com/jp/) [**Delphi**](https://www.embarcadero.com/jp/products/delphi)
ネイティブなクロスプラットフォームアプリを開発するための統合開発環境（ＩＤＥ）。
### Free Download: [**Delphi** Community Edition](https://www.embarcadero.com/jp/products/delphi/starter)
