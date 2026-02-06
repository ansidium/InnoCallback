#define MyAppName "InnoCallback Example"
#define MyAppVersion "1.0"
#define MyAppPublisher "Inno Tools"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
CreateAppDir=no
OutputBaseFilename=innocallback-example
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "InnoCallback.dll"; DestDir: "{tmp}"; Flags: dontcopy

[Code]
type
  TTimerProc = procedure(hWnd: Cardinal; Msg: Cardinal; idEvent: NativeUInt; dwTime: Cardinal);

function WrapTimerProc(const Callback: TTimerProc; const ParamCount: Integer): NativeInt;
  external 'wrapcallback@files:InnoCallback.dll stdcall setuponly';

function SetTimer(hWnd, nIDEvent, uElapse: Cardinal; lpTimerFunc: NativeInt): Cardinal;
  external 'SetTimer@user32.dll stdcall';

function KillTimer(hWnd, uIDEvent: Cardinal): Boolean;
  external 'KillTimer@user32.dll stdcall';

var
  TimerId: Cardinal;
  TimerCallback: NativeInt;

procedure MyTimerProc(hWnd: Cardinal; Msg: Cardinal; idEvent: NativeUInt; dwTime: Cardinal);
begin
  { Показываем, что callback реально вызывается из WinAPI. }
  WizardForm.WelcomePage.SurfaceColor := Random($FFFFFF);
end;

function InitializeSetup: Boolean;
begin
  Randomize;

  { Упаковываем script-метод в stdcall callback. }
  TimerCallback := WrapTimerProc(@MyTimerProc, 4);
  TimerId := SetTimer(0, 0, 1000, TimerCallback);

  if TimerId = 0 then
    MsgBox('Не удалось создать таймер Windows API.', mbError, MB_OK);

  Result := True;
end;

procedure DeinitializeSetup;
begin
  if TimerId <> 0 then
    KillTimer(0, TimerId);
end;
