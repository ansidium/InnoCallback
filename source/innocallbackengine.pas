unit InnoCallbackEngine;

interface

uses
  System.Classes;

function WrapCallback(Proc: TMethod; ParamCount: Integer): NativeInt; stdcall;

implementation

uses
  ASMInline,
  System.Generics.Collections;

var
  GInliners: TList<Pointer>;
  GInlinersLock: TObject;

procedure RegisterInliner(const InlinerPtr: Pointer);
begin
  TMonitor.Enter(GInlinersLock);
  try
    GInliners.Add(InlinerPtr);
  finally
    TMonitor.Exit(GInlinersLock);
  end;
end;

function WrapCallback(Proc: TMethod; ParamCount: Integer): NativeInt; stdcall;
var
  Inliner: TASMInline;
  SwapFirst: Integer;
  SwapLast: Integer;
  ExtraParams: Integer;
  FrameSize: Integer;
  I: Integer;
  SrcOffset: Integer;
  DestOffset: Integer;
  InlinerPtr: Pointer;
begin
  { Для совместимости внешнего ABI возвращаем 0, если входные параметры некорректны. }
  if (not Assigned(Proc.Code)) or (ParamCount < 0) then
    Exit(0);

  Inliner := TASMInline.Create;
  try
{$IFDEF CPUX86}
    { Снимаем адрес возврата, чтобы перестроить стек под вызов Delphi-метода. }
    Inliner.Pop(EAX);

    { Начиная с третьего параметра разворачиваем порядок на стеке,
      чтобы он соответствовал внутреннему ABI Delphi-метода на x86. }
    SwapFirst := 2;
    SwapLast := ParamCount - 1;
    while SwapLast > SwapFirst do
    begin
      Inliner.Mov(ECX, Inliner.Addr(ESP, SwapFirst * SizeOf(Pointer)));
      Inliner.Mov(EDX, Inliner.Addr(ESP, SwapLast * SizeOf(Pointer)));
      Inliner.Mov(Inliner.Addr(ESP, SwapFirst * SizeOf(Pointer)), EDX);
      Inliner.Mov(Inliner.Addr(ESP, SwapLast * SizeOf(Pointer)), ECX);
      Inc(SwapFirst);
      Dec(SwapLast);
    end;

    { Первые два параметра метода Delphi передаются через EDX/ECX. }
    if ParamCount >= 1 then
      Inliner.Pop(EDX);
    if ParamCount >= 2 then
      Inliner.Pop(ECX);

    Inliner.Push(EAX);
    Inliner.Mov(EAX, Cardinal(NativeUInt(Proc.Data)));
    Inliner.Jmp(Proc.Code);
{$ELSE}
    { Win64 callback получает параметры в RCX/RDX/R8/R9.
      Перекладываем их в формат, который ожидает вызов метода Delphi:
      RCX=Self, RDX/R8/R9=первые 3 параметра, остальные на стеке. }
    Inliner.MovRegReg(R11, RCX);
    Inliner.MovRegReg(R10, RDX);
    Inliner.MovRegReg(RAX, R8);
    Inliner.MovRegReg(RDX, R9);

    ExtraParams := ParamCount - 3;
    if ExtraParams < 0 then
      ExtraParams := 0;

    { Выделяем shadow space и область для «хвоста» параметров. }
    FrameSize := 32 + ExtraParams * SizeOf(Pointer);
    if (FrameSize and $F) = 0 then
      Inc(FrameSize, 8); { Сохраняем 16-байтное выравнивание стека перед call. }

    Inliner.SubRsp(FrameSize);

    if ParamCount >= 4 then
      Inliner.MovMemRSPReg(32, RDX);

    if ParamCount > 4 then
    begin
      for I := 0 to ParamCount - 5 do
      begin
        { 40 байт: адрес возврата + shadow space вызывающей стороны. }
        SrcOffset := FrameSize + 40 + I * SizeOf(Pointer);
        DestOffset := 32 + (I + 1) * SizeOf(Pointer);
        Inliner.MovRegMemRSP(RDX, SrcOffset);
        Inliner.MovMemRSPReg(DestOffset, RDX);
      end;
    end;

    Inliner.MovRegImm64(RCX, UInt64(NativeUInt(Proc.Data)));
    Inliner.MovRegReg(RDX, R11);
    if ParamCount >= 2 then
      Inliner.MovRegReg(R8, R10);
    if ParamCount >= 3 then
      Inliner.MovRegReg(R9, RAX);

    Inliner.MovRegImm64(R10, UInt64(NativeUInt(Proc.Code)));
    Inliner.CallReg(R10);
    Inliner.AddRsp(FrameSize);
    Inliner.Ret;
{$ENDIF}

    InlinerPtr := Inliner.SaveAsMemory;
    RegisterInliner(InlinerPtr);
    Result := NativeInt(InlinerPtr);
  finally
    Inliner.Free;
  end;
end;

procedure FreeInliners;
var
  I: Integer;
begin
  TMonitor.Enter(GInlinersLock);
  try
    for I := 0 to GInliners.Count - 1 do
      FreeMem(GInliners[I]);
    GInliners.Clear;
  finally
    TMonitor.Exit(GInlinersLock);
  end;
end;

exports
  WrapCallback name 'wrapcallback';

initialization
  GInliners := TList<Pointer>.Create;
  GInlinersLock := TObject.Create;

finalization
  FreeInliners;
  GInlinersLock.Free;
  GInliners.Free;

end.
