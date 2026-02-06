#define MyAppName "InnoCallback Experiment"
#define MyAppVersion "1.0"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
CreateAppDir=no
OutputBaseFilename=innocallback-experiment
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
  CountFromDll: Integer;
  CountFromBuiltIn: Integer;

function EnumCallbackDll(hWnd: NativeUInt; lParam: NativeInt): Boolean;
begin
  if IsWindowVisible(hWnd) then
    Inc(CountFromDll);
  Result := True;
end;

function EnumCallbackBuiltIn(hWnd: NativeUInt; lParam: NativeInt): Boolean;
begin
  if IsWindowVisible(hWnd) then
    Inc(CountFromBuiltIn);
  Result := True;
end;

function InitializeSetup: Boolean;
var
  DllCallback: NativeInt;
  BuiltInCallback: NativeInt;
begin
  CountFromDll := 0;
  CountFromBuiltIn := 0;

  { Текущий проект: внешний callback-обёртчик через DLL. }
  DllCallback := WrapEnumWindowsProc(@EnumCallbackDll, 2);

  { Нативный путь Inno Setup 6.7+: встроенный CreateCallback. }
  BuiltInCallback := CreateCallback(@EnumCallbackBuiltIn);

  EnumWindows(DllCallback, 0);
  EnumWindows(BuiltInCallback, 0);

  MsgBox(
    Format('DLL callback: %d; built-in callback: %d', [CountFromDll, CountFromBuiltIn]),
    mbInformation,
    MB_OK);

  Result := True;
end;
