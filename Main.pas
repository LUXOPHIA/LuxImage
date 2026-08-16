unit Main;

interface //#################################################################### ■

uses System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
     System.Diagnostics,
     FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
     FMX.Controls.Presentation, FMX.ListBox, FMX.Layouts,
     LUX, LUX.Color, LUX.Color.Space,
     LUX.Data.Image, LUX.Data.Image.Files, LUX.Data.Image.Files.Png, LUX.Data.Image.Files.Jpg,
     LUX.Data.Image.Worker, LUX.Data.Image.Viewer;

type //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 T Y P E 】

     //%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TForm1

     TForm1 = class( TForm )
       Panel1      :TPanel;
       Viewer      :TLuxImageViewer;
       ButtonOpen  :TButton;
       ButtonSave  :TButton;
       ButtonFit   :TButton;
       Button11    :TButton;
       LabelFmt    :TLabel;
       ComboFormat :TComboBox;
       LabelGamma  :TLabel;
       TrackGamma  :TTrackBar;
       LabelGammaV :TLabel;
       CheckTone   :TCheckBox;
       LabelLevel  :TLabel;
       ComboLevel  :TComboBox;
       LabelSpace  :TLabel;
       ComboSpace  :TComboBox;
       LabelRender :TLabel;
       ComboSize   :TComboBox;
       ButtonRender :TButton;
       LabelInfo   :TLabel;
       ProgressBar1 :TProgressBar;
       OpenDialog1 :TOpenDialog;
       SaveDialog1 :TSaveDialog;
       Timer1      :TTimer;
       procedure FormCreate( Sender:TObject );
       procedure FormDestroy( Sender:TObject );
       procedure FormMouseWheel( Sender:TObject; Shift:TShiftState; WheelDelta:Integer; var Handled:Boolean );
       procedure ButtonOpenClick( Sender:TObject );
       procedure ButtonSaveClick( Sender:TObject );
       procedure ButtonFitClick( Sender:TObject );
       procedure Button11Click( Sender:TObject );
       procedure TrackGammaChange( Sender:TObject );
       procedure CheckToneChange( Sender:TObject );
       procedure ComboSpaceChange( Sender:TObject );
       procedure ButtonRenderClick( Sender:TObject );
       procedure Timer1Timer( Sender:TObject );
     private
       _Image  :TLuxImage;
       _Worker :TLuxImageWorker;   // 並列描画（マンデルブロ集合）
       _File   :String;
       _Watch  :TStopwatch;
       _Hold   :Int64;      // この時刻まで LabelInfo を上書きしない
       ///// E V E N T
       procedure ImageProgress( Sender_:TObject );
       procedure ImageLoaded( Sender_:TObject );
       procedure ImageSaved( Sender_:TObject );
       procedure WorkerProgress( Sender_:TObject );
       procedure WorkerFinished( Sender_:TObject );
       ///// M E T H O D
       procedure NewImage;
       procedure LoadImage( const FileName_:String );
       function ComboColorSpace :TLuxColorSpace;             // ComboSpace の選択を色空間に（「なし」は nil ）
       procedure ShowColorSpace( const Space_:TLuxColorSpace );  // 色空間を ComboSpace に映す
       procedure BeginBusy( const Text_:String );
       procedure EndBusy;
       procedure UpdateInfo;
       procedure Mandelbrot( const ThreadI_,X_,Y_,W_,H_:Integer );
     public
     end;

var //$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 V A R I A B L E 】

    Form1 :TForm1;

implementation //############################################################### ■

{$R *.fmx}

uses System.Math;

//$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$【 C L A S S 】

//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% TForm1

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& private

//////////////////////////////////////////////////////////////////// M E T H O D

///// 選択中の画素形式で空の画像を作り直す（描画中の処理があれば止める）

procedure TForm1.NewImage;
begin
     FreeAndNil( _Worker );  // 破棄は中止と完了待ちを兼ねる

     Viewer.Image := nil;

     FreeAndNil( _Image );

     case ComboFormat.ItemIndex of
       1: _Image := TLuxImageUInt16.Create;
       2: _Image := TLuxImageSFlo16.Create;
       3: _Image := TLuxImageSFlo32.Create;
     else _Image := TLuxImageUInt08.Create;
     end;

     _Image.OnProgress.Add( ImageProgress );
     _Image.OnLoaded  .Add( ImageLoaded   );
     _Image.OnSaved   .Add( ImageSaved    );

     Viewer.Image := _Image;

     TrackGamma.Value    := Viewer.Gamma * 10;
     CheckTone.IsChecked := Viewer.ToneMap;
end;

///// 読み込みは形式ごとの設定を持たないので、拡張子からファイラを選ぶだけでよい

procedure TForm1.LoadImage( const FileName_:String );
var
   Filer :TLuxImageFiler;
begin
     Filer := TLuxImageFiler.CreateFor( FileName_ );

     if not Assigned( Filer ) then
     begin
          ShowMessage( '対応していない形式： ' + ExtractFileExt( FileName_ ) );  Exit;
     end;

     try
        NewImage;

        _File := FileName_;

        BeginBusy( '読み込み中…' );

        Filer.LoadFromFileAsync( _Image, FileName_ );   // 設定は複製されるので、すぐ解放してよい
     finally
        Filer.Free;
     end;
end;

//------------------------------------------------------------------------------

///// ComboSpace の項目：0 = なし、1〜 = TLuxColorSpaces.Presets の順。読み込んだファイルの色空間が
///// プリセットに無いものなら、その名前を末尾に足して選ぶ。

function TForm1.ComboColorSpace :TLuxColorSpace;
var
   I :Integer;
begin
     I := ComboSpace.ItemIndex;

     if ( I >= 1 ) and ( I <= Length( TLuxColorSpaces.Presets ) ) then Result := TLuxColorSpaces.Presets[ I-1 ]
     else
     if ( I > Length( TLuxColorSpaces.Presets ) ) and Assigned( _Image ) then Result := _Image.ColorSpace  // 末尾に足した「その他」
     else Result := nil;
end;

procedure TForm1.ShowColorSpace( const Space_:TLuxColorSpace );
var
   I :Integer;
begin
     ComboSpace.OnChange := nil;
     try
        while ComboSpace.Count > 1 + Length( TLuxColorSpaces.Presets ) do ComboSpace.Items.Delete( ComboSpace.Count-1 );

        if not Assigned( Space_ ) then ComboSpace.ItemIndex := 0
        else
        begin
             I := 0;
             while ( I < Length( TLuxColorSpaces.Presets ) ) and ( TLuxColorSpaces.Presets[ I ] <> Space_ ) do Inc( I );

             if I < Length( TLuxColorSpaces.Presets ) then ComboSpace.ItemIndex := I + 1
             else
             begin
                  ComboSpace.Items.Add( Space_.Name );  ComboSpace.ItemIndex := ComboSpace.Count-1;
             end;
        end;
     finally
        ComboSpace.OnChange := ComboSpaceChange;
     end;
end;

//------------------------------------------------------------------------------

procedure TForm1.BeginBusy( const Text_:String );
begin
     _Watch := TStopwatch.StartNew;

     ProgressBar1.Value   := 0;
     ProgressBar1.Visible := True;

     LabelInfo.Text := Text_;

     ButtonOpen.Enabled   := False;
     ButtonSave.Enabled   := False;
     ComboFormat.Enabled  := False;
     ComboSize.Enabled    := False;
end;

procedure TForm1.EndBusy;
begin
     ProgressBar1.Visible := False;

     ButtonOpen.Enabled   := True;
     ButtonSave.Enabled   := True;
     ComboFormat.Enabled  := True;
     ComboSize.Enabled    := True;
end;

//------------------------------------------------------------------------------

///// マンデルブロ集合の１ブロック。集合の内側は最大反復まで回り、外側は数回で脱出するので、
///// 場所ごとの計算量が桁で違う（レイトレーシングと同じ性質）。

procedure TForm1.Mandelbrot( const ThreadI_,X_,Y_,W_,H_:Integer );
const
      ITER_MAX = 2048;
      X0 = -2.2;  X1 = +1.0;  // 実部の範囲
      Y0 = -1.6;  Y1 = +1.6;  // 虚部の範囲
var
   Row      :TArray<TSingleRGBA>;
   I, J, N  :Integer;
   CX, CY   :Double;
   ZX, ZY   :Double;
   ZX2, ZY2 :Double;
   S, T     :Double;
   IsFloat  :Boolean;
begin
     SetLength( Row, W_ );

     IsFloat := _Image.IsFloat;

     for J := 0 to H_-1 do
     begin
          CY := Y0 + ( Y1 - Y0 ) * ( Y_ + J + 0.5 ) / _Image.Height;

          for I := 0 to W_-1 do
          begin
               CX := X0 + ( X1 - X0 ) * ( X_ + I + 0.5 ) / _Image.Width;

               ZX := 0;  ZY := 0;  ZX2 := 0;  ZY2 := 0;  N := 0;

               while ( N < ITER_MAX ) and ( ZX2 + ZY2 < 256 ) do
               begin
                    ZY  := 2 * ZX * ZY + CY;
                    ZX  := ZX2 - ZY2 + CX;
                    ZX2 := ZX * ZX;
                    ZY2 := ZY * ZY;

                    Inc( N );
               end;

               if N >= ITER_MAX then Row[ I ] := TSingleRGBA.Create( 0, 0, 0, 1 )  // 集合の内側
               else
               begin
                    S := N + 1 - Log2( Log2( ZX2 + ZY2 ) / 2 );  // 滑らかな反復回数

                    T := Pi + 0.5 * Sqrt( S );

                    with Row[ I ] do
                    begin
                         R := 0.5 + 0.5 * Cos( T + 0.0 );
                         G := 0.5 + 0.5 * Cos( T + 1.0 );
                         B := 0.5 + 0.5 * Cos( T + 2.0 );
                         A := 1;

                         if IsFloat then  // 浮動小数形式はリニアとみなして表示されるので、リニアへ戻しておく
                         begin
                              R := Power( R, 2.2 );
                              G := Power( G, 2.2 );
                              B := Power( B, 2.2 );
                         end;
                    end;
               end;
          end;

          _Image.SetRow( 0, X_, Y_ + J, W_, @Row[ 0 ] );
     end;
end;

//////////////////////////////////////////////////////////////////// E V E N T

procedure TForm1.ImageProgress( Sender_:TObject );
begin
     ProgressBar1.Value := _Image.Progress * 100;
end;

procedure TForm1.ImageLoaded( Sender_:TObject );
begin
     EndBusy;

     ShowColorSpace( _Image.ColorSpace );  // ファイルから読めた色空間

     TrackGamma.Value := Viewer.Gamma * 10;

     Viewer.FitToWindow;

     LabelInfo.Text := Format( '%d × %d' + sLineBreak + '読み込み %d ms',
                               [ _Image.Width, _Image.Height, _Watch.ElapsedMilliseconds ] );

     _Hold := _Watch.ElapsedMilliseconds + 3000;
end;

procedure TForm1.ImageSaved( Sender_:TObject );
begin
     EndBusy;

     LabelInfo.Text := Format( '%s' + sLineBreak + '保存 %d ms',
                               [ ExtractFileName( SaveDialog1.FileName ), _Watch.ElapsedMilliseconds ] );

     _Hold := _Watch.ElapsedMilliseconds + 3000;
end;

procedure TForm1.WorkerProgress( Sender_:TObject );
begin
     ProgressBar1.Value := _Worker.Progress * 100;

     LabelInfo.Text := Format( '描画中… %.1f %%' + sLineBreak + '%d ms',
                               [ _Worker.Progress * 100, _Watch.ElapsedMilliseconds ] );
end;

procedure TForm1.WorkerFinished( Sender_:TObject );
begin
     EndBusy;

     ButtonRender.Text := '描画開始';

     if _Worker.Cancelled then LabelInfo.Text := Format( '%d × %d' + sLineBreak + '描画を中止 ( %.1f %% )',
                                                         [ _Image.Width, _Image.Height, _Worker.Progress * 100 ] )
                          else LabelInfo.Text := Format( '%d × %d' + sLineBreak + '描画 %d ms',
                                                         [ _Image.Width, _Image.Height, _Watch.ElapsedMilliseconds ] );

     _Hold := _Watch.ElapsedMilliseconds + 3000;
end;

procedure TForm1.UpdateInfo;
var
   L :Integer;
   S :String;
begin
     if not Assigned( _Image ) or _Image.Busy or ( _Image.Width < 1 ) then Exit;

     if Assigned( _Worker ) and _Worker.Busy then Exit;  // 描画中は進捗を表示している

     if _Watch.IsRunning and ( _Watch.ElapsedMilliseconds < _Hold ) then Exit;  // 直後の結果表示を残す

     L := Max( 0, Floor( -Log2( Viewer.Scale ) ) );
     L := Min( L, _Image.LevelsN - 1 );

     if Assigned( _Image.ColorSpace ) then S := _Image.ColorSpace.Name + ' → ' + Viewer.ActiveColorSpace.Name  // 画像 → 表示
                                      else S := '色管理なし';

     LabelInfo.Text := Format( '%d × %d'  + sLineBreak +
                               '%s'       + sLineBreak +
                               '%s'       + sLineBreak +
                               ''         + sLineBreak +
                               '倍率 %.4g' + sLineBreak +
                               '段 %d ( %d × %d )',
                               [ _Image.Width, _Image.Height,
                                 Copy( _Image.ClassName, Length( 'TLuxImage' ) + 1, 99 ),
                                 S,
                                 Viewer.Scale, L,
                                 _Image.LevelWidth( L ), _Image.LevelHeight( L ) ] );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TForm1.FormCreate( Sender:TObject );
var
   S :TLuxColorSpace;
begin
     ComboFormat.ItemIndex := 0;
     ComboSize  .ItemIndex := 2;
     ComboLevel .ItemIndex := 2;   // plDefault

     ComboSpace.Items.Add( 'なし' );
     for S in TLuxColorSpaces.Presets do ComboSpace.Items.Add( S.Name );
     ComboSpace.ItemIndex := 0;

     Caption := Caption + '  －  ' + TCanvasManager.DefaultCanvas.ClassName;
end;

procedure TForm1.FormDestroy( Sender:TObject );
begin
     _Worker.Free;  // 描画中なら止めて待つ

     Viewer.Image := nil;

     _Image.Free;
end;

procedure TForm1.FormMouseWheel( Sender:TObject; Shift:TShiftState; WheelDelta:Integer; var Handled:Boolean );
begin
     Viewer.ZoomWheel( WheelDelta );  Handled := True;
end;

//------------------------------------------------------------------------------

procedure TForm1.ButtonOpenClick( Sender:TObject );
begin
     OpenDialog1.Filter := TLuxImageFiler.DialogFilter + '|すべて (*.*)|*.*';

     if OpenDialog1.Execute then LoadImage( OpenDialog1.FileName );
end;

///// 保存は形式ごとに設定が違うので、ファイラのインスタンスを作って設定してから渡す

procedure TForm1.ButtonSaveClick( Sender:TObject );
var
   Filer :TLuxImageFiler;
begin
     if not Assigned( _Image ) or _Image.Busy then Exit;

     SaveDialog1.Filter     := TLuxImageFiler.DialogFilter( False );
     SaveDialog1.DefaultExt := 'png';
     SaveDialog1.FileName   := ChangeFileExt( ExtractFileName( _File ), '.png' );

     if not SaveDialog1.Execute then Exit;

     Filer := TLuxImageFiler.CreateFor( SaveDialog1.FileName );

     if not Assigned( Filer ) then
     begin
          ShowMessage( '対応していない形式： ' + ExtractFileExt( SaveDialog1.FileName ) );  Exit;
     end;

     try
        if Filer is TLuxImageFilerPng then TLuxImageFilerPng( Filer ).Level := TLuxPngLevel( ComboLevel.ItemIndex );

        BeginBusy( '保存中…' );

        Filer.SaveToFileAsync( _Image, SaveDialog1.FileName );
     finally
        Filer.Free;
     end;
end;

procedure TForm1.ButtonFitClick( Sender:TObject );
begin
     Viewer.FitToWindow;
end;

procedure TForm1.Button11Click( Sender:TObject );
begin
     Viewer.Scale := 1;
end;

procedure TForm1.TrackGammaChange( Sender:TObject );
begin
     Viewer.Gamma := TrackGamma.Value / 10;

     LabelGammaV.Text := Format( '%.1f', [ Viewer.Gamma ] );
end;

procedure TForm1.CheckToneChange( Sender:TObject );
begin
     Viewer.ToneMap := CheckTone.IsChecked;
end;

///// 画像に色空間を割り当てる（ Photoshop の「プロファイルの指定」に相当。画素値は変えない ）

procedure TForm1.ComboSpaceChange( Sender:TObject );
begin
     if not Assigned( _Image ) then Exit;

     _Image.ColorSpace := ComboColorSpace;

     TrackGamma.Value := Viewer.Gamma * 10;  // 色管理の有無で表示ガンマの既定値が変わる
end;

///// 描画開始／中止。選択中の画素形式・大きさで空の画像を確保し、マンデルブロ集合を並列に描く。
///// 描画中もビューアは動く（完了したブロックから順に表示へ反映される）。

procedure TForm1.ButtonRenderClick( Sender:TObject );
var
   N :Integer;
begin
     if Assigned( _Worker ) and _Worker.Busy then
     begin
          _Worker.Cancel;  Exit;
     end;

     N := StrToIntDef( ComboSize.Selected.Text, 4096 );

     NewImage;

     try
          _Image.SetSize( N, N );  // 全段をここで確保する。足りなければ EOutOfMemory
     except
          on E:EOutOfMemory do
          begin
               ShowMessage( E.Message );  Exit;
          end;
     end;

     _File := Format( 'Mandelbrot %d.png', [ N ] );

     _Image.ColorSpace := ComboColorSpace;  // 選択中の色空間で描く（保存時に埋め込まれる）

     TrackGamma.Value := Viewer.Gamma * 10;

     Viewer.FitToWindow;

     _Worker := TLuxImageWorker.Create( _Image );

     _Worker.OnProgress.Add( WorkerProgress );
     _Worker.OnFinished.Add( WorkerFinished );

     BeginBusy( '描画中…' );

     ButtonRender.Text := '中止';

     _Worker.Start( Mandelbrot );
end;

procedure TForm1.Timer1Timer( Sender:TObject );
begin
     UpdateInfo;
end;

end. //######################################################################### ■
