unit ASMInline;

interface

{$IFNDEF CPUX86}
{$IFNDEF CPUX64}
{$MESSAGE ERROR 'ASMInline поддерживает только x86/x64'}
{$ENDIF}
{$ENDIF}

{$IFDEF CPUX86}
{$WARN IMPLICIT_INTEGER_CAST_LOSS OFF}
{$WARN IMPLICIT_CONVERSION_LOSS OFF}
{$ENDIF}

uses
  System.Classes,
  System.Generics.Collections,
  System.SysUtils,
  Winapi.Windows;

type
{$IFDEF CPUX86}
  TModMode = (mmNaked, mmDeref, mmDisp8, mmDisp32);
  TRegister32 = (EAX, EBX, ECX, EDX, ESP, EBP, ESI, EDI);
  TMemSize = (ms8, ms16, ms32, ms64);

  TMemoryAddress = record
    Size: TMemSize;
    UseBase: Boolean;
    Base: TRegister32;
    Index: TRegister32;
    Offset: Integer;
    Scale: Byte;
  end;

  EOperandSizeMismatch = class(Exception)
  public
    constructor Create;
  end;

  TRelocType = (rt32Bit);

  TReloc = class
  public
    Position: Cardinal;
    RelocType: TRelocType;
  end;
{$ELSE}
  TRegister64 = (RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI, R8, R9, R10, R11, R12, R13, R14, R15);
{$ENDIF}

  TASMInline = class
  private
    FBuffer: TMemoryStream;
{$IFDEF CPUX86}
    FRelocs: TObjectList<TReloc>;
    FBase: NativeUInt;
    procedure AddRelocation(const Position: Cardinal; const RelocType: TRelocType);
    function GetReloc(const Index: Integer): TReloc;
    function RelocCount: Integer;
    property Relocs[const Index: Integer]: TReloc read GetReloc;
    procedure Relocate(const Base: Pointer);
    procedure WriteRegRef(const Reg: Byte; const Base: TRegister32; const Deref: Boolean;
      const Index: TRegister32; const Offset: Integer; const Scale: Byte; const UseBase: Boolean); overload;
    procedure WriteRegRef(const Mem: TMemoryAddress; const Reg: TRegister32); overload;
    procedure WriteRegRef(const Reg: TRegister32; const Base: TRegister32; const Deref: Boolean;
      const Index: TRegister32 = EAX; const Offset: Integer = 0; const Scale: Byte = 0;
      const UseBase: Boolean = True); overload;
{$ELSE}
    function RegCode(const R: TRegister64): Byte;
    procedure WriteREX(const W, R, X, B: Boolean);
{$ENDIF}
    procedure WriteByte(const B: Byte);
    procedure WriteInteger(const I: Integer);
{$IFNDEF CPUX86}
    procedure WriteUInt64(const U: UInt64);
{$ENDIF}
  public
    constructor Create;
    destructor Destroy; override;

    function SaveAsMemory: Pointer;
    function Size: Integer;

{$IFDEF CPUX86}
    function Addr(const Base: TRegister32; const Offset: Integer; const Size: TMemSize = ms32): TMemoryAddress;

    procedure Push(const Reg: TRegister32);
    procedure Pop(const Reg: TRegister32);

    procedure Jmp(const Target: Pointer);

    procedure Mov(const Reg: TRegister32; const Value: Cardinal); overload;
    procedure Mov(const Mem: TMemoryAddress; const Reg: TRegister32); overload;
    procedure Mov(const Reg: TRegister32; const Mem: TMemoryAddress); overload;
{$ELSE}
    procedure MovRegReg(const Dest, Src: TRegister64);
    procedure MovRegImm64(const Dest: TRegister64; const Value: UInt64);
    procedure MovRegMemRSP(const Dest: TRegister64; const Disp: Integer);
    procedure MovMemRSPReg(const Disp: Integer; const Src: TRegister64);
    procedure SubRsp(const Amount: Integer);
    procedure AddRsp(const Amount: Integer);
    procedure CallReg(const Reg: TRegister64);
    procedure Ret;
{$ENDIF}
  end;

implementation

{$IFDEF CPUX86}

constructor EOperandSizeMismatch.Create;
begin
  inherited Create('Operand size mismatch');
end;

procedure RequireSize(const TestSize, ExpectedSize: TMemSize);
begin
  if TestSize <> ExpectedSize then
    raise EOperandSizeMismatch.Create;
end;

function RegisterCode(const Reg: TRegister32): Byte;
begin
  case Reg of
    EAX: Result := 0;
    EBX: Result := 3;
    ECX: Result := 1;
    EDX: Result := 2;
    ESP: Result := 4;
    EBP: Result := 5;
    ESI: Result := 6;
    EDI: Result := 7;
  else
    raise Exception.Create('Неизвестный регистр');
  end;
end;

function ModModeCode(const Value: TModMode): Byte;
begin
  case Value of
    mmDeref: Result := 0;
    mmDisp8: Result := 1;
    mmDisp32: Result := 2;
    mmNaked: Result := 3;
  else
    raise Exception.CreateFmt('Некорректный режим адресации: %d', [Ord(Value)]);
  end;
end;

function EncodeSIB(const Scale, IndexCode, BaseCode: Byte): Byte;
begin
  Result := Byte(BaseCode or (IndexCode shl 3) or (Scale shl 6));
end;

function EncodeModRM(const AMod, AReg, ARM: Byte): Byte;
begin
  Result := Byte((AMod shl 6) or (AReg shl 3) or ARM);
end;

{$ENDIF}

{ TASMInline }

constructor TASMInline.Create;
begin
  inherited Create;
  FBuffer := TMemoryStream.Create;
{$IFDEF CPUX86}
  FRelocs := TObjectList<TReloc>.Create(True);
{$ENDIF}
end;

destructor TASMInline.Destroy;
begin
{$IFDEF CPUX86}
  FRelocs.Free;
{$ENDIF}
  FBuffer.Free;
  inherited;
end;

{$IFDEF CPUX86}

{$IFOPT R+}
{$DEFINE RESTORE_R}
{$R-}
{$ENDIF}
{$IFOPT Q+}
{$DEFINE RESTORE_Q}
{$Q-}
{$ENDIF}
procedure TASMInline.Relocate(const Base: Pointer);
var
  OldPos: Int64;
  Diff: Integer;
  Orig: Integer;
  I: Integer;
  Reloc: TReloc;
begin
  OldPos := FBuffer.Position;
  try
    Diff := -Integer(NativeUInt(Base) - FBase);

    for I := 0 to RelocCount - 1 do
    begin
      Reloc := Relocs[I];
      case Reloc.RelocType of
        rt32Bit:
          begin
            FBuffer.Seek(Reloc.Position, soBeginning);
            FBuffer.ReadBuffer(Orig, SizeOf(Orig));
            FBuffer.Seek(-SizeOf(Orig), soCurrent);
            Orig := Integer(Cardinal(Orig + Diff));
            FBuffer.WriteBuffer(Orig, SizeOf(Orig));
          end;
      end;
    end;

    FBase := NativeUInt(Base);
  finally
    FBuffer.Position := OldPos;
  end;
end;
{$IFDEF RESTORE_R}
{$R+}
{$ENDIF}
{$IFDEF RESTORE_Q}
{$Q+}
{$ENDIF}

function TASMInline.GetReloc(const Index: Integer): TReloc;
begin
  Result := FRelocs[Index];
end;

function TASMInline.RelocCount: Integer;
begin
  Result := FRelocs.Count;
end;

procedure TASMInline.AddRelocation(const Position: Cardinal; const RelocType: TRelocType);
var
  Reloc: TReloc;
begin
  Reloc := TReloc.Create;
  Reloc.Position := Position;
  Reloc.RelocType := RelocType;
  FRelocs.Add(Reloc);
end;

function TASMInline.Addr(const Base: TRegister32; const Offset: Integer; const Size: TMemSize): TMemoryAddress;
begin
  Result.Base := Base;
  Result.Scale := 0;
  Result.Offset := Offset;
  Result.Size := Size;
  Result.UseBase := True;
end;

procedure TASMInline.Pop(const Reg: TRegister32);
begin
  WriteByte($58 + RegisterCode(Reg));
end;

procedure TASMInline.Jmp(const Target: Pointer);
begin
  WriteByte($E9);
  AddRelocation(Cardinal(FBuffer.Position), rt32Bit);
  WriteInteger(Integer(NativeInt(Target) - NativeInt(FBase + NativeUInt(FBuffer.Position) + 4)));
end;

procedure TASMInline.Push(const Reg: TRegister32);
begin
  WriteByte($50 + RegisterCode(Reg));
end;

procedure TASMInline.WriteRegRef(const Mem: TMemoryAddress; const Reg: TRegister32);
begin
  WriteRegRef(Reg, Mem.Base, True, Mem.Index, Mem.Offset, Mem.Scale, Mem.UseBase);
end;

procedure TASMInline.WriteRegRef(const Reg: TRegister32; const Base: TRegister32;
  const Deref: Boolean; const Index: TRegister32; const Offset: Integer;
  const Scale: Byte; const UseBase: Boolean);
begin
  WriteRegRef(RegisterCode(Reg), Base, Deref, Index, Offset, Scale, UseBase);
end;

procedure TASMInline.WriteRegRef(const Reg: Byte; const Base: TRegister32;
  const Deref: Boolean; const Index: TRegister32; const Offset: Integer;
  const Scale: Byte; const UseBase: Boolean);
type
  TOffSize = (osNone, os8, os32);
var
  Mode: TModMode;
  OffSize: TOffSize;
  UseSIB: Boolean;
  AReg: Byte;
  ARM: Byte;
  LocalBase: TRegister32;
  LocalIndex: TRegister32;
  LocalOffset: Integer;
  LocalScale: Byte;
begin
  LocalBase := Base;
  LocalIndex := Index;
  LocalOffset := Offset;
  LocalScale := Scale;

  if not Deref then
  begin
    Mode := mmNaked;
    OffSize := osNone;
  end
  else if not UseBase then
  begin
    OffSize := os32;
    Mode := mmDeref;
    LocalBase := EBP; // Специальный код x86 для адресации без базового регистра
  end
  else if LocalOffset = 0 then
  begin
    Mode := mmDeref;
    OffSize := osNone;
  end
  else if (LocalOffset >= -128) and (LocalOffset < 128) then
  begin
    Mode := mmDisp8;
    OffSize := os8;
  end
  else
  begin
    Mode := mmDisp32;
    OffSize := os32;
  end;

  if Mode <> mmNaked then
    UseSIB := (LocalScale > 0) or (LocalBase = ESP)
  else
    UseSIB := False;

  if UseSIB then
  begin
    case LocalScale of
      0:
        LocalIndex := ESP; // Индекс не используется
      1:
        LocalScale := 0;
      2:
        LocalScale := 1;
      4:
        LocalScale := 2;
      8:
        LocalScale := 3;
    else
      raise Exception.Create('Допустимые значения Scale: 1, 2, 4, 8');
    end;
  end;

  if (not UseSIB) and (Mode = mmDeref) and (LocalBase = EBP) then
  begin
    Mode := mmDisp8;
    OffSize := os8;
    LocalOffset := 0;
  end;

  ARM := RegisterCode(LocalBase);
  AReg := Reg;

  if UseSIB then
    WriteByte(EncodeModRM(ModModeCode(Mode), AReg, 4))
  else
    WriteByte(EncodeModRM(ModModeCode(Mode), AReg, ARM));

  if UseSIB then
    WriteByte(EncodeSIB(LocalScale, RegisterCode(LocalIndex), RegisterCode(LocalBase)));

  case OffSize of
    os8:
      WriteByte(Byte(LocalOffset));
    os32:
      WriteInteger(LocalOffset);
  end;
end;

procedure TASMInline.Mov(const Mem: TMemoryAddress; const Reg: TRegister32);
begin
  RequireSize(Mem.Size, ms32);
  WriteByte($89);
  WriteRegRef(Mem, Reg);
end;

procedure TASMInline.Mov(const Reg: TRegister32; const Mem: TMemoryAddress);
begin
  RequireSize(Mem.Size, ms32);
  WriteByte($8B);
  WriteRegRef(Mem, Reg);
end;

procedure TASMInline.Mov(const Reg: TRegister32; const Value: Cardinal);
begin
  WriteByte($B8 + RegisterCode(Reg));
  WriteInteger(Integer(Value));
end;

{$ELSE}

function TASMInline.RegCode(const R: TRegister64): Byte;
begin
  Result := Byte(R);
end;

procedure TASMInline.WriteREX(const W, R, X, B: Boolean);
var
  Prefix: Byte;
begin
  Prefix := $40;
  if W then
    Inc(Prefix, $08);
  if R then
    Inc(Prefix, $04);
  if X then
    Inc(Prefix, $02);
  if B then
    Inc(Prefix, $01);
  WriteByte(Prefix);
end;

procedure TASMInline.MovRegReg(const Dest, Src: TRegister64);
var
  DestCode: Byte;
  SrcCode: Byte;
begin
  DestCode := RegCode(Dest);
  SrcCode := RegCode(Src);
  WriteREX(True, SrcCode >= 8, False, DestCode >= 8);
  WriteByte($89);
  WriteByte(Byte($C0 or ((SrcCode and 7) shl 3) or (DestCode and 7)));
end;

procedure TASMInline.MovRegImm64(const Dest: TRegister64; const Value: UInt64);
var
  DestCode: Byte;
begin
  DestCode := RegCode(Dest);
  WriteREX(True, False, False, DestCode >= 8);
  WriteByte(Byte($B8 + (DestCode and 7)));
  WriteUInt64(Value);
end;

procedure TASMInline.MovRegMemRSP(const Dest: TRegister64; const Disp: Integer);
var
  DestCode: Byte;
begin
  DestCode := RegCode(Dest);
  WriteREX(True, DestCode >= 8, False, False);
  WriteByte($8B);
  WriteByte(Byte($84 or ((DestCode and 7) shl 3)));
  WriteByte($24);
  WriteInteger(Disp);
end;

procedure TASMInline.MovMemRSPReg(const Disp: Integer; const Src: TRegister64);
var
  SrcCode: Byte;
begin
  SrcCode := RegCode(Src);
  WriteREX(True, SrcCode >= 8, False, False);
  WriteByte($89);
  WriteByte(Byte($84 or ((SrcCode and 7) shl 3)));
  WriteByte($24);
  WriteInteger(Disp);
end;

procedure TASMInline.SubRsp(const Amount: Integer);
begin
  WriteByte($48);
  WriteByte($81);
  WriteByte($EC);
  WriteInteger(Amount);
end;

procedure TASMInline.AddRsp(const Amount: Integer);
begin
  WriteByte($48);
  WriteByte($81);
  WriteByte($C4);
  WriteInteger(Amount);
end;

procedure TASMInline.CallReg(const Reg: TRegister64);
var
  RegValue: Byte;
begin
  RegValue := RegCode(Reg);
  WriteREX(False, False, False, RegValue >= 8);
  WriteByte($FF);
  WriteByte(Byte($D0 + (RegValue and 7)));
end;

procedure TASMInline.Ret;
begin
  WriteByte($C3);
end;

{$ENDIF}

function TASMInline.SaveAsMemory: Pointer;
var
  Buf: Pointer;
  OldProtect: Cardinal;
begin
  GetMem(Buf, Size);
  if not VirtualProtect(Buf, SIZE_T(Size), PAGE_EXECUTE_READWRITE, OldProtect) then
  begin
    FreeMem(Buf);
    RaiseLastOSError;
  end;
{$IFDEF CPUX86}
  Relocate(Buf);
{$ENDIF}
  Move(FBuffer.Memory^, Buf^, Size);
  Result := Buf;
end;

function TASMInline.Size: Integer;
begin
  if FBuffer.Size > High(Integer) then
    raise Exception.Create('Слишком большой блок машинного кода');
  Result := Integer(FBuffer.Size);
end;

procedure TASMInline.WriteByte(const B: Byte);
begin
  FBuffer.WriteBuffer(B, SizeOf(B));
end;

procedure TASMInline.WriteInteger(const I: Integer);
begin
  FBuffer.WriteBuffer(I, SizeOf(I));
end;

{$IFNDEF CPUX86}
procedure TASMInline.WriteUInt64(const U: UInt64);
begin
  FBuffer.WriteBuffer(U, SizeOf(U));
end;
{$ENDIF}

end.
