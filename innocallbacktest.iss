#define MyAppName "InnoCallback Test"
#define MyAppVersion "1.0"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
CreateAppDir=no
OutputBaseFilename=innocallback-test
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "InnoCallback.dll"; DestDir: "{tmp}"; Flags: dontcopy

[Code]
type
  TEnumWindowsProc = function(hWnd: NativeUInt; lParam: NativeInt): Boolean;

function WrapEnumWindowsProc(const Callback: TEnumWindowsProc; const ParamCount: Integer): NativeInt;
  external 'wrapcallback@files:InnoCallback.dll stdcall setuponly';

function EnumWindows(lpEnumFunc: NativeInt; lParam: NativeInt): Boolean;
  external 'EnumWindows@user32.dll stdcall';

function IsWindowVisible(hWnd: NativeUInt): Boolean;
  external 'IsWindowVisible@user32.dll stdcall';

var
  VisibleWindowsCount: Integer;

function EnumWindowsCallback(hWnd: NativeUInt; lParam: NativeInt): Boolean;
begin
  if IsWindowVisible(hWnd) then
    Inc(VisibleWindowsCount);

  { Останавливаем перечисление на разумном лимите для теста. }
  Result := VisibleWindowsCount < 1000;
end;

function InitializeSetup: Boolean;
var
  EnumProc: NativeInt;
begin
  VisibleWindowsCount := 0;

  { 2 параметра: hWnd и lParam. }
  EnumProc := WrapEnumWindowsProc(@EnumWindowsCallback, 2);

  if not EnumWindows(EnumProc, 0) then
    MsgBox('EnumWindows завершился с ошибкой.', mbError, MB_OK)
  else
    MsgBox(Format('Видимых окон найдено: %d', [VisibleWindowsCount]), mbInformation, MB_OK);

  Result := True;
end;
