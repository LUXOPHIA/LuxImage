unit Main;

interface //#################################################################### ■

uses System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
     System.Diagnostics,
     FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls,
     FMX.Controls.Presentation, FMX.ListBox, FMX.Layouts,
     LUX, LUX.Color, LUX.Data.Image, LUX.Data.Image.Files, LUX.Data.Image.Viewer;

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
       procedure Timer1Timer( Sender:TObject );
     private
       _Image  :TLuxImage;
       _File   :String;
       _Watch  :TStopwatch;
       _Hold   :Int64;      // この時刻まで LabelInfo を上書きしない
       ///// E V E N T
       procedure ImageProgress( Sender_:TObject );
       procedure ImageLoaded( Sender_:TObject );
       procedure ImageSaved( Sender_:TObject );
       ///// M E T H O D
       procedure LoadImage( const FileName_:String );
       procedure BeginBusy( const Text_:String );
       procedure EndBusy;
       procedure UpdateInfo;
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

procedure TForm1.LoadImage( const FileName_:String );
begin
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

     _File := FileName_;

     Viewer.Image := _Image;

     TrackGamma.Value    := Viewer.Gamma * 10;
     CheckTone.IsChecked := Viewer.ToneMap;

     BeginBusy( '読み込み中…' );

     _Image.LoadFromFileAsync( FileName_ );
end;

//------------------------------------------------------------------------------

procedure TForm1.BeginBusy( const Text_:String );
begin
     _Watch := TStopwatch.StartNew;

     ProgressBar1.Value   := 0;
     ProgressBar1.Visible := True;

     LabelInfo.Text := Text_;

     ButtonOpen.Enabled  := False;
     ButtonSave.Enabled  := False;
     ComboFormat.Enabled := False;
end;

procedure TForm1.EndBusy;
begin
     ProgressBar1.Visible := False;

     ButtonOpen.Enabled  := True;
     ButtonSave.Enabled  := True;
     ComboFormat.Enabled := True;
end;

//////////////////////////////////////////////////////////////////// E V E N T

procedure TForm1.ImageProgress( Sender_:TObject );
begin
     ProgressBar1.Value := _Image.Progress * 100;
end;

procedure TForm1.ImageLoaded( Sender_:TObject );
begin
     EndBusy;

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

procedure TForm1.UpdateInfo;
var
   L :Integer;
begin
     if not Assigned( _Image ) or _Image.Busy or ( _Image.Width < 1 ) then Exit;

     if _Watch.IsRunning and ( _Watch.ElapsedMilliseconds < _Hold ) then Exit;  // 直後の結果表示を残す

     L := Max( 0, Ceil( -Log2( Viewer.Scale ) ) );
     L := Min( L, _Image.LevelsN - 1 );

     LabelInfo.Text := Format( '%d × %d'  + sLineBreak +
                               '%s'       + sLineBreak +
                               ''         + sLineBreak +
                               '倍率 %.4g' + sLineBreak +
                               '段 %d ( %d × %d )',
                               [ _Image.Width, _Image.Height,
                                 Copy( _Image.ClassName, 11, 99 ),
                                 Viewer.Scale, L,
                                 _Image.LevelWidth( L ), _Image.LevelHeight( L ) ] );
end;

//&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&& public

//////////////////////////////////////////////////////////////////// M E T H O D

procedure TForm1.FormCreate( Sender:TObject );
begin
     ComboFormat.ItemIndex := 0;

     Caption := Caption + '  －  ' + TCanvasManager.DefaultCanvas.ClassName;
end;

procedure TForm1.FormDestroy( Sender:TObject );
begin
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
     OpenDialog1.Filter := '画像 (*.jpg;*.jpeg;*.png)|*.jpg;*.jpeg;*.png|すべて (*.*)|*.*';

     if OpenDialog1.Execute then LoadImage( OpenDialog1.FileName );
end;

procedure TForm1.ButtonSaveClick( Sender:TObject );
begin
     if not Assigned( _Image ) or _Image.Busy then Exit;

     SaveDialog1.Filter     := 'PNG (*.png)|*.png|JPEG (*.jpg)|*.jpg';
     SaveDialog1.DefaultExt := 'png';
     SaveDialog1.FileName   := ChangeFileExt( ExtractFileName( _File ), '.png' );

     if not SaveDialog1.Execute then Exit;

     BeginBusy( '保存中…' );

     _Image.SaveToFileAsync( SaveDialog1.FileName, 90 );
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

procedure TForm1.Timer1Timer( Sender:TObject );
begin
     UpdateInfo;
end;

end. //######################################################################### ■
