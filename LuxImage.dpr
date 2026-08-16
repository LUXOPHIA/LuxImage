program LuxImage;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  FMX.Skia.Canvas.Vulkan,
  Main in 'Main.pas' {Form1},
  LUX in '_LIBRARY\LUXOPHIA\LUX\LUX.pas',
  LUX.D1.Half in '_LIBRARY\LUXOPHIA\LUX\D1\Half\LUX.D1.Half.pas',
  LUX.D1.Half.Diff in '_LIBRARY\LUXOPHIA\LUX\D1\Half\LUX.D1.Half.DIff.pas',
  LUX.D1 in '_LIBRARY\LUXOPHIA\LUX\LUX.D1.pas',
  LUX.D2 in '_LIBRARY\LUXOPHIA\LUX\LUX.D2.pas',
  LUX.D2x2 in '_LIBRARY\LUXOPHIA\LUX\LUX.D2x2.pas',
  LUX.D3 in '_LIBRARY\LUXOPHIA\LUX\LUX.D3.pas',
  LUX.D3x3 in '_LIBRARY\LUXOPHIA\LUX\LUX.D3x3.pas',
  LUX.Color in '_LIBRARY\LUXOPHIA\LUX\Color\LUX.Color.pas',
  LUX.Color.Half in '_LIBRARY\LUXOPHIA\LUX\Color\LUX.Color.Half.pas',
  LUX.Color.Space in '_LIBRARY\LUXOPHIA\LUX\Color\LUX.Color.Space.pas',
  LUX.Data.Image in '_LIBRARY\LUXOPHIA\LUX\Data\Image\LUX.Data.Image.pas',
  LUX.Data.Image.Files in '_LIBRARY\LUXOPHIA\LUX\Data\Image\LUX.Data.Image.Files.pas',
  LUX.Data.Image.Worker in '_LIBRARY\LUXOPHIA\LUX\Data\Image\LUX.Data.Image.Worker.pas',
  LUX.Data.Image.Viewer in '_LIBRARY\LUXOPHIA\LUX\Data\Image\LUX.Data.Image.Viewer.pas' {LuxImageViewer: TFrame};

{$R *.res}

begin
  ///// FMX キャンバスを Skia に置き換える。
  ///// FMX.Skia.Canvas.Vulkan を uses しておくと、そのユニットが Vulkan キャンバスを
  ///// 登録するので、対応環境では GPU（Vulkan）で描画される。

  GlobalUseSkia                    := True;
  GlobalUseSkiaRasterWhenAvailable := False;  // ラスタ（CPU）へ落とさない

  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
