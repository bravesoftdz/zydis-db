{***************************************************************************************************

  ZydisEditor

  Original Author : Florian Bernd

 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.

***************************************************************************************************}

unit Zydis.Generator.Tables;

interface

uses
  System.Classes, System.Generics.Collections, Zydis.InstructionEditor, Zydis.Enums,
  Zydis.Generator.Base, Zydis.Generator.Types;

{$SCOPEDENUMS ON}

type
  TZYTableItemWriter = class sealed(TObject)
  strict private
    FWriter: TStreamWriter;
    FIsFirst: Boolean;
    FDoNewLine: Boolean;
  strict private
    procedure WriteDelimiter; inline;
  private
    procedure Reset; inline;
  protected
    constructor Create(Writer: TStreamWriter);
  public
    function WriteLine: TZYTableItemWriter; inline;
    function WriteStr(const Value: String;
      const ExplicitName: String = ''): TZYTableItemWriter; inline;
    function WriteDec(const Value: Integer;
      const ExplicitName: String = ''): TZYTableItemWriter; inline;
    function WriteHex(const Value: Integer;
      const ExplicitName: String = ''): TZYTableItemWriter; inline;
    function StructBegin(const ExplicitName: String = ''):TZYTableItemWriter; inline;
    function StructEnd: TZYTableItemWriter; inline;
  end;

  TZYTableItemWriteProc<T> =
    reference to procedure(Writer: TZYTableItemWriter; Index: Integer; const Item: T);

  TZYTableTemplate<T> = record
  public
    Name: String;
    ItemType: String;
    Items: ^TArray<T>;
  end;

  TZYTableGenerator<T> = class sealed(TZYGeneratorTask)
  strict private
    class procedure Generate(Generator: TZYBaseGenerator; Writer: TStreamWriter;
      const TableName, TableItemType: String; const Items: TArray<T>;
      const WriteProc: TZYTableItemWriteProc<T>; const StorageClass: String); overload; static;
  public
    class procedure Generate(Generator: TZYBaseGenerator; const Filename: String;
      const TableName, TableItemType: String; const Items: TArray<T>;
      const WriteProc: TZYTableItemWriteProc<T>; const StorageClass: String = ''); overload; static;
    class procedure Generate(Generator: TZYBaseGenerator; const Filename: String;
      const Tables: TArray<TZYTableTemplate<T>>;
      const WriteProc: TZYTableItemWriteProc<T>; const StorageClass: String = ''); overload; static;
  end;

  TZYDefinitionTableGenerator = record
  strict private
    class function NumberOfUsedOperands(Operands: TZYInstructionOperands): Integer; static; inline;
    class function AcceptsASZOverride(
      Definition: TZYInstructionDefinition): Boolean; static; inline;
    class function AcceptsSegment(Definition: TZYInstructionDefinition): Boolean; static; inline;
    class function GetRegisterConstraint(Operands: TZYInstructionOperands;
      Encoding: TZYOperandEncoding): TZYRegisterConstraint; inline; static;
    class function HasVSIB(Definition: TZYInstructionDefinition): Boolean; static; inline;
  public
    class procedure Generate(Generator: TZYBaseGenerator; const Filename: String;
      Definitions: TZYDefinitionList; Operands: TZYUniqueOperandList;
      Category, ISASet, ISAExtension: TZYGeneratorEnum;
      AccessedFlags: TZYUniqueDefinitionPropertyList<TZYInstructionFlagsInfo>); static;
  end;

  TZYOperandTableGenerator = record
  public
    class procedure Generate(Generator: TZYBaseGenerator; const Filename: String;
      Operands: TZYUniqueOperandList); static;
  end;

  TZYEncodingTableGenerator = record
  public
    class procedure Generate(Generator: TZYBaseGenerator; const Filename: String;
      Encodings: TZYUniqueDefinitionPropertyList<TZYInstructionPartInfo>); static;
  end;

  TZYAccessedFlagsTableGenerator = record
  public
    class procedure Generate(Generator: TZYBaseGenerator; const Filename: String;
      AccessedFlags: TZYUniqueDefinitionPropertyList<TZYInstructionFlagsInfo>); static;
  end;

  TZYDecoderTableGenerator = record
  public
    class procedure Generate(Generator: TZYBaseGenerator; const Filename: String;
      TreeSnapshot: TZYTreeSnapshot;
      Encodings: TZYUniqueDefinitionPropertyList<TZYInstructionPartInfo>); static;
  end;

  TZYEncoderTableGenerator = record
  public
    class procedure Generate(Generator: TZYBaseGenerator; const Filename: String;
      Definitions: TZYDefinitionList; Mnemonics: TZYGeneratorEnum); static;
  end;

implementation

uses
  System.SysUtils, Zydis.InstructionFilters, Zydis.Enums.Filters;

const
  ZydisBool: array[Boolean] of String = ('ZYDIS_FALSE', 'ZYDIS_TRUE');

{$REGION 'Class: TZYTableItemWriter'}
constructor TZYTableItemWriter.Create(Writer: TStreamWriter);
begin
  inherited Create;
  FWriter := Writer;
  FIsFirst := true;
end;

procedure TZYTableItemWriter.Reset;
begin
  FIsFirst := true;
end;

function TZYTableItemWriter.StructBegin(const ExplicitName: String): TZYTableItemWriter;
begin
  Result := Self;
  WriteDelimiter;
  FIsFirst := true;
  if (ExplicitName <> '') then
  begin
    FWriter.Write('.%s = { ', [ExplicitName]);
  end else
  begin
    FWriter.Write('{ ');
  end;
end;

function TZYTableItemWriter.StructEnd: TZYTableItemWriter;
begin
  Result := Self;
  FIsFirst := false;
  FWriter.Write(' }');
end;

function TZYTableItemWriter.WriteDec(const Value: Integer;
  const ExplicitName: String): TZYTableItemWriter;
begin
  Result := Self;
  WriteDelimiter;
  if (ExplicitName <> '') then
  begin
    FWriter.Write('.%s = %d', [ExplicitName, Value]);
  end else
  begin
    FWriter.Write(Value);
  end;
end;

procedure TZYTableItemWriter.WriteDelimiter;
begin
  if (not FIsFirst) then
  begin
    FWriter.Write(', ');
  end;
  FIsFirst := false;
  if (FDoNewLine) then
  begin
    FDoNewLine := false;
    FWriter.WriteLine;
  end;
end;

function TZYTableItemWriter.WriteHex(const Value: Integer;
  const ExplicitName: String): TZYTableItemWriter;
begin
  Result := Self;
  WriteDelimiter;
  if (ExplicitName <> '') then
  begin
    FWriter.Write('.%s = 0x%X', [ExplicitName, Value]);
  end else
  begin
    FWriter.Write('0x%X', [Value]);
  end;
end;

function TZYTableItemWriter.WriteLine: TZYTableItemWriter;
begin
  Result := Self;
  //FDoNewLine := true;
end;

function TZYTableItemWriter.WriteStr(const Value: String;
  const ExplicitName: String): TZYTableItemWriter;
begin
  Result := Self;
  WriteDelimiter;
  if (ExplicitName <> '') then
  begin
    FWriter.Write('.%s = %s', [ExplicitName, Value]);
  end else
  begin
    FWriter.Write(Value);
  end;
end;
{$ENDREGION}

{$REGION 'Class: TZYTableGenerator<T>'}
class procedure TZYTableGenerator<T>.Generate(Generator: TZYBaseGenerator; Writer: TStreamWriter;
  const TableName, TableItemType: String; const Items: TArray<T>;
  const WriteProc: TZYTableItemWriteProc<T>; const StorageClass: String);
var
  S, R, U: String;
  A: TArray<String>;
  W: TZYTableItemWriter;
  I: Integer;
begin
  Assert(Length(Items) > 0);
  S := '';
  if (StorageClass <> '') then
  begin
    S := StorageClass + ' ';
  end;
  R := TableItemType;
  U := '';
  if (R.Contains('[')) then
  begin
    A := R.Split(['[']);
    Assert(Length(A) = 2);
    R := A[0];
    U := '[' + A[1];
    SetLength(A, 0);
  end;
  A := TableName.Split(['.']);
  Assert((Length(A) = 1) or (Length(A) = 2));
  if (Length(A) = 2) then
  begin
    Writer.Write('#' + A[1]);
    Writer.WriteLine;
  end;
  Writer.Write('%sconst %s %s[]%s =', [S, R, A[0], U]);
  Writer.WriteLine;
  Writer.Write('{');
  Writer.WriteLine;
  W := TZYTableItemWriter.Create(Writer);
  try
    for I := Low(Items) to High(Items) do
    begin
      Writer.Write('    { ');
      W.Reset;
      WriteProc(W, I, Items[I]);
      Writer.Write(' }');
      if (I <> High(Items)) then
      begin
        Writer.Write(', ');
      end;
      Writer.WriteLine;
      WorkStep(Generator);
    end;
  finally
    W.Free;
  end;
  Writer.Write('};');
  Writer.WriteLine;
  if (Length(A) = 2) then
  begin
    Writer.Write('#endif');
    Writer.WriteLine;
  end;
end;

class procedure TZYTableGenerator<T>.Generate(Generator: TZYBaseGenerator; const Filename,
  TableName, TableItemType: String; const Items: TArray<T>;
  const WriteProc: TZYTableItemWriteProc<T>; const StorageClass: String);
var
  Writer: TStreamWriter;
begin
  Writer := TStreamWriter.Create(Filename);
  try
    Writer.AutoFlush := true;
    Writer.NewLine := sLineBreak;
    WorkStart(Generator, Length(Items));
    Generate(Generator, Writer, TableName, TableItemType, Items, WriteProc, StorageClass);
    WorkEnd(Generator);
  finally
    Writer.Free;
  end;
end;

class procedure TZYTableGenerator<T>.Generate(Generator: TZYBaseGenerator; const Filename: String;
  const Tables: TArray<TZYTableTemplate<T>>; const WriteProc: TZYTableItemWriteProc<T>;
  const StorageClass: String);
var
  I, N: Integer;
  Writer: TStreamWriter;
begin
  N := 0;
  for I := Low(Tables) to High(Tables) do
  begin
    Inc(N, Length(Tables[I].Items^));
  end;
  WorkStart(Generator, N);
  Writer := TStreamWriter.Create(Filename);
  try
    Writer.AutoFlush := true;
    Writer.NewLine := sLineBreak;
    for I := Low(Tables) to High(Tables) do
    begin
      Generate(Generator, Writer, Tables[I].Name, Tables[I].ItemType, Tables[I].Items^, WriteProc,
        StorageClass);
      if (I <> High(Tables)) then
      begin
        Writer.WriteLine;
      end;
    end;
  finally
    Writer.Free;
  end;
  WorkEnd(Generator);
end;
{$ENDREGION}

{$REGION 'Class: TZYDefinitionTableGenerator'}
class function TZYDefinitionTableGenerator.AcceptsASZOverride(
  Definition: TZYInstructionDefinition): Boolean;
begin
  Result := not (pfIgnoreASZOverride in Definition.PrefixFlags);
end;

class function TZYDefinitionTableGenerator.AcceptsSegment(
  Definition: TZYInstructionDefinition): Boolean;
var
  I: Integer;
begin
  Result := false;
  if (pfRemoveSegment in Definition.PrefixFlags) then
  begin
    Exit;
  end;
  for I := 0 to Definition.Operands.NumberOfUsedOperands - 1 do
  begin
    if (Definition.Operands.Items[I].OperandType in
      [optImplicitMem, optMEM, optMEMVSIBX, optMEMVSIBY, optMEMVSIBZ, optPTR, optAGEN,
       optMOFFS, optMIB]) then
    begin
      Result := true;
      Break;
    end;
  end;
end;

class procedure TZYDefinitionTableGenerator.Generate(Generator: TZYBaseGenerator;
  const Filename: String; Definitions: TZYDefinitionList; Operands: TZYUniqueOperandList;
  Category, ISASet, ISAExtension: TZYGeneratorEnum;
  AccessedFlags: TZYUniqueDefinitionPropertyList<TZYInstructionFlagsInfo>);
const
  TABLE_NAMES: array[TZYInstructionEncoding] of String = (
    'DEFAULT',
    '3DNOW',
    'XOP',
    'VEX',
    'EVEX',
    'MVEX'
  );
var
  Tables: TArray<TZYTableTemplate<TZYInstructionDefinition>>;
  E: TZYInstructionEncoding;
begin
  SetLength(Tables, Ord(High(TZYInstructionEncoding)) + 1);
  for E := Low(TZYInstructionEncoding) to High(TZYInstructionEncoding) do
  begin
    Tables[Ord(E)].Name     := 'instructionDefinitions'     + TABLE_NAMES[E];
    Tables[Ord(E)].ItemType := 'ZydisInstructionDefinition' + TABLE_NAMES[E];
    Tables[Ord(E)].Items    := @Definitions.UniqueItems[E];
    case E of
      iencEVEX: Tables[Ord(E)].Name := Tables[Ord(E)].Name + '.ifndef ZYDIS_DISABLE_EVEX';
      iencMVEX: Tables[Ord(E)].Name := Tables[Ord(E)].Name + '.ifndef ZYDIS_DISABLE_MVEX';
    end;
  end;
  TZYTableGenerator<TZYInstructionDefinition>.Generate(Generator, Filename, Tables,
    procedure(Writer: TZYTableItemWriter; Index: Integer; const Item: TZYInstructionDefinition)
    begin
      // ZYDIS_INSTRUCTION_DEFINITION_BASE
      { mnemonic                    } Writer.WriteStr(
                                        'ZYDIS_MNEMONIC_' + AnsiUpperCase(Item.Mnemonic));
      { operandCount                } Writer.WriteDec(NumberOfUsedOperands(Item.Operands));
      { operandReference            } Writer.WriteHex(Operands.Mapping[Item.Encoding][Index]);
      { operandSizeMapping          } Writer.WriteDec(Ord(Item.OperandSizeMap));
      { flagsReference              } Writer.WriteHex(AccessedFlags.Mapping[Item.Encoding][Index]);
      { requiresProtectedMode       } Writer.WriteStr(ZydisBool[dfProtectedMode in Item.Flags]);
      { acceptsAddressSizeOverride  } Writer.WriteStr(ZydisBool[AcceptsASZOverride(Item)]);
      { category                    } Writer.WriteStr(
                                        'ZYDIS_CATEGORY_' +
                                        Category.Items[
                                        Category.Mapping[Item.Encoding][Index]].ToUpper);
      { isaSet                      } Writer.WriteStr(
                                        'ZYDIS_ISA_SET_' +
                                        ISASet.Items[
                                        ISASet.Mapping[Item.Encoding][Index]].ToUpper);
      { isaExt                      } Writer.WriteStr(
                                        'ZYDIS_ISA_EXT_' + ISAExtension.Items[
                                        ISAExtension.Mapping[Item.Encoding][Index]].ToUpper);
      { exceptionClass              } Writer.WriteStr(
                                        'ZYDIS_EXCEPTION_CLASS_' +
                                        TZYExceptionClass.ZydisStrings[Item.ExceptionClass]);
      { constrREG                   } Writer.WriteStr(
                                        'ZYDIS_REG_CONSTRAINTS_' +
                                        TZYRegisterConstraint.ZydisStrings[
                                        GetRegisterConstraint(Item.Operands, opeModrmReg)]);
      { constrRM                    } Writer.WriteStr(
                                        'ZYDIS_REG_CONSTRAINTS_' +
                                        TZYRegisterConstraint.ZydisStrings[
                                        GetRegisterConstraint(Item.Operands, opeModrmRm)]);

      // ZYDIS_INSTRUCTION_DEFINITION_BASE_VECTOR
      if (Item.Encoding in [iencXOP, iencVEX, iencEVEX, iencMVEX]) then
      begin
        { constrNDSNDD }  Writer.WriteStr('ZYDIS_REG_CONSTRAINTS_' +
                            TZYRegisterConstraint.ZydisStrings[
                            GetRegisterConstraint(Item.Operands, opeNDSNDD)]);
      end;

      // ZYDIS_INSTRUCTION_DEFINITION_BASE_VECTOR_INTEL
      if (Item.Encoding in [iencVEX, iencEVEX, iencMVEX]) then
      begin
        { isGather     } Writer.WriteStr(ZydisBool[Item.Meta.Category.ToUpper.Contains('GATHER')]);
      end;

      case Item.Encoding of
        iencDEFAULT:
          begin
            // ZydisInstructionDefinitionDEFAULT
            { isPrivileged          } Writer.WriteStr(ZydisBool[Item.PrivilegeLevel = 0]);
            { isFarBranch           } Writer.WriteStr(ZydisBool[dfIsFarBranch in Item.Flags]);
            { acceptsLock           } Writer.WriteStr(
                                        ZydisBool[pfAcceptsLOCK in Item.PrefixFlags]);
            { acceptsREP            } Writer.WriteStr(
                                        ZydisBool[pfAcceptsREP in Item.PrefixFlags]);
            { acceptsREPEREPZ       } Writer.WriteStr(
                                        ZydisBool[pfAcceptsREPEREPZ in Item.PrefixFlags]);
            { acceptsREPNEREPNZ     } Writer.WriteStr(
                                        ZydisBool[pfAcceptsREPNEREPNZ in Item.PrefixFlags]);
            { acceptsBOUND          } Writer.WriteStr(
                                        ZydisBool[pfAcceptsBOUND in Item.PrefixFlags]);
            { acceptsXACQUIRE       } Writer.WriteStr(
                                        ZydisBool[pfAcceptsXACQUIRE in Item.PrefixFlags]);
            { acceptsXRELEASE       } Writer.WriteStr(
                                        ZydisBool[pfAcceptsXRELEASE in Item.PrefixFlags]);
            { acceptsHLEWithoutLock } Writer.WriteStr(
                                        ZydisBool[pfAcceptsLocklessHLE in Item.PrefixFlags]);
            { acceptsBranchHints    } Writer.WriteStr(
                                        ZydisBool[pfAcceptsBranchHints in Item.PrefixFlags]);
            { acceptsSegment        } Writer.WriteStr(
                                        ZydisBool[AcceptsSegment(Item)]);
          end;
        iencVEX:
          begin
            // ZydisInstructionDefinitionVEX
            { broadcast             } Writer.WriteStr('ZYDIS_VEX_STATIC_BROADCAST_' +
                                        TZYStaticBroadcast.ZydisStrings[Item.VEX.StaticBroadcast]);
          end;
        iencEVEX:
          begin
            // ZydisInstructionDefinitionEVEX
            { vectorLength          } Writer.WriteStr('ZYDIS_IVECTOR_LENGTH_' +
                                        TZYVectorLength.ZydisStrings[Item.EVEX.VectorLength]);
            { tupleType             } Writer.WriteStr('ZYDIS_TUPLETYPE_' +
                                        TZYEVEXTupleType.ZydisStrings[Item.EVEX.TupleType]);
            { elementSize           } Writer.WriteStr('ZYDIS_IELEMENT_SIZE_' +
                                        TZYEVEXElementSize.ZydisStrings[Item.EVEX.ElementSize]);
            { functionality         } Writer.WriteStr('ZYDIS_EVEX_FUNC_' +
                                        TZYEVEXFunctionality.ZydisStrings[Item.EVEX.Functionality]);
            { maskPolicy            } Writer.WriteStr('ZYDIS_MASK_POLICY_' +
                                        TZYMEVEXMaskMode.ZydisStrings[Item.EVEX.MaskMode]);
            { acceptsZeroMask       } Writer.WriteStr(
                                        ZydisBool[mfAcceptsZeroMask in Item.EVEX.MaskFlags]);
            { isControlMask         } Writer.WriteStr(
                                        ZydisBool[mfIsControlMask in Item.EVEX.MaskFlags]);
            { broadcast             } Writer.WriteStr('ZYDIS_EVEX_STATIC_BROADCAST_' +
                                        TZYStaticBroadcast.ZydisStrings[Item.EVEX.StaticBroadcast]);
          end;
        iencMVEX:
          begin
            // ZydisInstructionDefinitionMVEX
            { functionality         } Writer.WriteStr('ZYDIS_MVEX_FUNC_' +
                                        TZYMVEXFunctionality.ZydisStrings[Item.MVEX.Functionality]);
            { maskPolicy            } Writer.WriteStr('ZYDIS_MASK_POLICY_' +
                                        TZYMEVEXMaskMode.ZydisStrings[Item.MVEX.MaskMode]);
            { hasElementGranularity } Writer.WriteStr(ZydisBool[Item.MVEX.HasElementGranularity]);
            { broadcast             } Writer.WriteStr('ZYDIS_MVEX_STATIC_BROADCAST_' +
                                        TZYStaticBroadcast.ZydisStrings[Item.MVEX.StaticBroadcast]);
          end;
      end;
    end);
end;

class function TZYDefinitionTableGenerator.GetRegisterConstraint(Operands: TZYInstructionOperands;
  Encoding: TZYOperandEncoding): TZYRegisterConstraint;
var
  I: Integer;
  O: TZYInstructionOperand;
begin
  Assert(Encoding in [opeModrmReg, opeModrmRm, opeNDSNDD]);
  Result := ocUnused;
  for I := 0 to Operands.NumberOfUsedOperands - 1 do
  begin
    O := Operands.Items[I];
    if (O.Encoding <> Encoding) then
    begin
      Continue;
    end;
    case O.OperandType of
      optImplicitReg  ,
      optImplicitMem  ,
      optImplicitImm1 : Result := ocNone;
      optGPR8         ,
      optGPR16        ,
      optGPR32        ,
      optGPR64        ,
      optGPR16_32_64  ,
      optGPR32_32_64  ,
      optGPR16_32_32  :
        if (Operands.Definition.Encoding in [iencEVEX, iencMVEX]) then
        begin
          // `.R'` and `.V'` are invalid for GPR registers, but `.X` is valid (ignored)
          case O.Encoding of
            opeModrmReg,
            opeNDSNDD  : Result := ocGPR;
            opeModrmRm : Result := ocNone;
          end;
        end else
        begin
          // These encodings don't have the `.R'` and `.V'` fields
          Result := ocNone;
        end;
      optFPR          ,
      optMMX          :
        begin
          // Never encoded in `EVEX`/`MVEX` or as `NDSNDD`. `.R` and `.B` are valid (ignored)
          Assert(not (Operands.Definition.Encoding in [iencEVEX, iencMVEX]));
          Assert(Encoding <> opeNDSNDD);
          Result := ocNone;
        end;
      optXMM          ,
      optYMM          ,
      optZMM          : Result := ocNone;
      optBND          : Result := ocBND;
      optSREG         :
        if (O.Index = 0) and (O.Action in [opaWrite]) then
        begin
          // The `CS`-register is not allowed as destination for the `MOV` instruction
          Result := ocSRDest;
        end else
        begin
          Result := ocSR;
        end;
      optCR           : Result := ocCR;
      optDR           : Result := ocDR;
      optMASK         :
        // MASK-registers can only use 3-bits, but `.B` and `.X` are valid (ignored)
        case O.Encoding of
          opeModrmReg,
          opeNDSNDD  : Result := ocMASK;
          opeModrmRm : Result := ocNone;
        end;
      optMEM          ,
      optAGEN         ,
      optMIB          : Result := ocNone;
      optMEMVSIBX     ,
      optMEMVSIBY     ,
      optMEMVSIBZ     : Result := ocVSIB;
      optIMM          ,
      optREL          ,
      optPTR          ,
      optMOFFS        : ;
    end;
  end;
end;

class function TZYDefinitionTableGenerator.HasVSIB(Definition: TZYInstructionDefinition): Boolean;
var
  I: Integer;
begin
  Result := false;
  for I := 0 to Definition.Operands.NumberOfUsedOperands - 1 do
  begin
    if (Definition.Operands.Items[I].OperandType in [optMemVSIBX, optMemVSIBY, optMemVSIBZ]) then
    begin
      Result := true;
      Break;
    end;
  end;
end;

class function TZYDefinitionTableGenerator.NumberOfUsedOperands(
  Operands: TZYInstructionOperands): Integer;
begin
  // This wrapper function takes care of the automatically generated FLAGS-register operand
  Result := Operands.NumberOfUsedOperands;
  if (Operands.Definition.AffectedFlags.AutomaticOperand.OperandType <> optUnused) then
  begin
    Inc(Result);
  end;
end;
{$ENDREGION}

{$REGION 'Class: TZYOperandTableGenerator'}
class procedure TZYOperandTableGenerator.Generate(Generator: TZYBaseGenerator;
  const Filename: String; Operands: TZYUniqueOperandList);
begin
  TZYTableGenerator<TZYInstructionOperand>.Generate(Generator, Filename, 'operandDefinitions',
    'ZydisOperandDefinition', Operands.Items,
    procedure(Writer: TZYTableItemWriter; Index: Integer; const Item: TZYInstructionOperand)
    var
      C: TZYRegisterClass;
      S: String;
    begin
      { type        } Writer.WriteStr('ZYDIS_SEMANTIC_OPTYPE_' +
                        TZYEnumOperandType.ZydisStrings[Item.OperandType]);
      { visibility  } Writer.WriteStr('ZYDIS_OPERAND_VISIBILITY_' +
                        TZYEnumOperandVisibility.ZydisStrings[Item.Visibility]);
      { action      } Writer.WriteStr('ZYDIS_OPERAND_ACTION_' +
                        TZYEnumOperandAction.ZydisStrings[Item.Action]);
      { size        } Writer.StructBegin;
                      { [0] } Writer.WriteDec(Item.Width16);
                      { [1] } Writer.WriteDec(Item.Width32);
                      { [2] } Writer.WriteDec(Item.Width64);
      { size        } Writer.StructEnd;
      { elementType } Writer.WriteStr('ZYDIS_IELEMENT_TYPE_' +
                        TZYEnumElementType.ZydisStrings[Item.ElementType]);
      case Item.OperandType of
        optUnused: Assert(false);
        optImplicitReg:
          begin
            { op  } Writer.StructBegin;
            { reg } Writer.StructBegin('reg');
            C := Item.Register.GetRegisterClass;
            if (C in [regcGPROSZ, regcGPRASZ, regcGPRSSZ]) or
              (Item.Register in [regASZIP, regSSZIP, regSSZFLAGS]) then
            begin
              S := 'STATIC';
              case C of
                regcGPROSZ : S := 'GPR_OSZ';
                regcGPRASZ : S := 'GPR_ASZ';
                regcGPRSSZ : S := 'GPR_SSZ';
              end;
              case Item.Register of
                regASZIP   : S := 'IP_ASZ';
                regSSZIP   : S := 'IP_SSZ';
                regSSZFLAGS: S := 'FLAGS_SSZ';
              end;
              { type  } Writer.WriteStr('ZYDIS_IMPLREG_TYPE_' + S);
              { reg   } Writer.StructBegin;
                        Assert(Item.Register.GetRegisterId <= $3F);
                        { id  } Writer.WriteHex(Item.Register.GetRegisterId and $3F, 'id');
              { reg   } Writer.StructEnd;
            end else
            begin
              { type  } Writer.WriteStr('ZYDIS_IMPLREG_TYPE_STATIC');
              { reg   } Writer.StructBegin;
                        { reg } Writer.WriteStr('ZYDIS_REGISTER_' +
                                  TZYEnumRegister.JSONStrings[Item.Register].ToUpper, 'reg');
              { reg   } Writer.StructEnd;
            end;
            { reg } Writer.StructEnd;
            { op  } Writer.StructEnd;
          end;
        optImplicitMem:
          begin
            { op  } Writer.StructBegin;
            { mem } Writer.StructBegin('mem');
                    { seg         } Writer.WriteDec(Ord(Item.MemorySegment));
                    { base        } Writer.WriteStr('ZYDIS_IMPLMEM_BASE_' +
                                      TZYBaseRegister.ZydisStrings[Item.MemoryBase]);
            { op  } Writer.StructEnd;
            { mem } Writer.StructEnd;
          end else
          begin
            { op  } Writer.StructBegin;
                    { encoding    } Writer.WriteStr('ZYDIS_OPERAND_ENCODING_' +
                                      TZYEnumOperandEncoding.ZydisStrings[Item.Encoding],
                                      'encoding');
            { op  } Writer.StructEnd;
          end;
      end;
    end);
end;
{$ENDREGION}

{$REGION 'Class: TZYEncodingTableGenerator'}
class procedure TZYEncodingTableGenerator.Generate(Generator: TZYBaseGenerator;
  const Filename: String; Encodings: TZYUniqueDefinitionPropertyList<TZYInstructionPartInfo>);
begin
  TZYTableGenerator<TZYInstructionPartInfo>.Generate(Generator, Filename, 'instructionEncodings',
    'ZydisInstructionEncodingInfo', Encodings.Items,
    procedure(Writer: TZYTableItemWriter; Index: Integer; const Item: TZYInstructionPartInfo)
    var
      S: String;
    begin
      if (Item.Parts = []) or (Item.Parts = [ipOpcode]) then
      begin
        S := '0';
      end else
      begin
        if (ipModrm in Item.Parts) then
        begin
          S := S + 'ZYDIS_INSTR_ENC_FLAG_HAS_MODRM | ';
        end;
        if (ipDisplacement in Item.Parts) then
        begin
          S := S + 'ZYDIS_INSTR_ENC_FLAG_HAS_DISP | ';
        end;
        if (ipImmediate0 in Item.Parts) then
        begin
          S := S + 'ZYDIS_INSTR_ENC_FLAG_HAS_IMM0 | ';
        end;
        if (ipImmediate1 in Item.Parts) then
        begin
          S := S + 'ZYDIS_INSTR_ENC_FLAG_HAS_IMM1 | ';
        end;
        if (ipForceRegForm in Item.Parts) then
        begin
          S := S + 'ZYDIS_INSTR_ENC_FLAG_FORCE_REG_FORM | ';
        end;
        Delete(S, Length(S) - 2, 3);
      end;
      { flags } Writer.WriteStr(S);
      { disp  } Writer.StructBegin;
                { size  } Writer.StructBegin;
                          { [0] } Writer.WriteDec(Item.Displacement.Width16);
                          { [1] } Writer.WriteDec(Item.Displacement.Width32);
                          { [2] } Writer.WriteDec(Item.Displacement.Width64);
                { size  } Writer.StructEnd;
      { disp  } Writer.StructEnd;
      { imm   } Writer.StructBegin;
                { [0] } Writer.StructBegin;
                        { size        } Writer.StructBegin;
                                        { [0] } Writer.WriteDec(Item.ImmediateA.Width16);
                                        { [1] } Writer.WriteDec(Item.ImmediateA.Width32);
                                        { [2] } Writer.WriteDec(Item.ImmediateA.Width64);
                        { size        } Writer.StructEnd;
                        { isSigned    } Writer.WriteStr(ZydisBool[Item.ImmediateA.IsSigned]);
                        { isRelative  } Writer.WriteStr(ZydisBool[Item.ImmediateA.IsRelative]);
                { [0] } Writer.StructEnd;
                { [1] } Writer.StructBegin;
                        { size        } Writer.StructBegin;
                                        { [0] } Writer.WriteDec(Item.ImmediateB.Width16);
                                        { [1] } Writer.WriteDec(Item.ImmediateB.Width32);
                                        { [2] } Writer.WriteDec(Item.ImmediateB.Width64);
                        { size        } Writer.StructEnd;
                        { isSigned    } Writer.WriteStr(ZydisBool[Item.ImmediateB.IsSigned]);
                        { isRelative  } Writer.WriteStr(ZydisBool[Item.ImmediateB.IsRelative]);
                { [2] } Writer.StructEnd;
      { imm   } Writer.StructEnd;
    end, 'static');
end;
{$ENDREGION}

{$REGION 'Class: TZYAccessedFlagsTableGenerator'}
class procedure TZYAccessedFlagsTableGenerator.Generate(Generator: TZYBaseGenerator;
  const Filename: String; AccessedFlags: TZYUniqueDefinitionPropertyList<TZYInstructionFlagsInfo>);
begin
  TZYTableGenerator<TZYInstructionFlagsInfo>.Generate(Generator, Filename, 'accessedFlags',
    'ZydisAccessedFlags', AccessedFlags.Items,
    procedure(Writer: TZYTableItemWriter; Index: Integer; const Item: TZYInstructionFlagsInfo)
    var
      I: Integer;
    begin
      { actions } Writer.StructBegin;
      for I := 0 to Item.Count - 1 do
      begin
        { [I] } Writer.WriteStr('ZYDIS_CPUFLAG_ACTION_' +
                  TZYFlagOperation.ZydisStrings[Item.Flags[I]]);
      end;
      { actions } Writer.StructEnd;
    end, 'static');
end;
{$ENDREGION}

{$REGION 'Class: TZYDecoderTableGenerator'}
class procedure TZYDecoderTableGenerator.Generate(Generator: TZYBaseGenerator;
  const Filename: String; TreeSnapshot: TZYTreeSnapshot;
  Encodings: TZYUniqueDefinitionPropertyList<TZYInstructionPartInfo>);
const
  TABLE_NAMES: array[TZYInstructionFilterClass] of String = (
    '',
    'XOP',
    'VEX',
    'EMVEX',
    'Opcode',
    'Mode',
    'ModeCompact',
    'ModrmMod',
    'ModrmModCompact',
    'ModrmReg',
    'ModrmRm',
    'MandatoryPrefix',
    'OperandSize',
    'AddressSize',
    'VectorLength',
    'REXW',
    'REXB',
    'EVEXB',
    'MVEXE',
    'ModeAMD',
    'ModeKNC',
    'ModeMPX',
    'ModeCET',
    'ModeLZCNT',
    'ModeTZCNT',
    'ModeWBNOINVD'
  );
  NODE_NAMES: array[TZYInstructionFilterClass] of String =
  (
    '',
    'XOP',
    'VEX',
    'EMVEX',
    'OPCODE',
    'MODE',
    'MODE_COMPACT',
    'MODRM_MOD',
    'MODRM_MOD_COMPACT',
    'MODRM_REG',
    'MODRM_RM',
    'MANDATORY_PREFIX',
    'OPERAND_SIZE',
    'ADDRESS_SIZE',
    'VECTOR_LENGTH',
    'REX_W',
    'REX_B',
    'EVEX_B',
    'MVEX_E',
    'MODE_AMD',
    'MODE_KNC',
    'MODE_MPX',
    'MODE_CET',
    'MODE_LZCNT',
    'MODE_TZCNT',
    'MODE_WBNOINVD'
  );
var
  Tables: TArray<TZYTableTemplate<PZYTreeItem>>;
  C: TZYInstructionFilterClass;
  F: TZYInstructionFilter;
begin
  for C := Low(TZYInstructionFilterClass) to High(TZYInstructionFilterClass) do
  begin
    F := TZYInstructionFilterInfo.Info[C];
    if (F.IsEditorOnly) then
    begin
      Continue;
    end;
    SetLength(Tables, Length(Tables) + 1);
    Tables[High(Tables)].Name     := 'filters' + TABLE_NAMES[C];
    Tables[High(Tables)].ItemType := 'ZydisDecoderTreeNode[' + F.NumberOfValues.ToString + ']';
    Tables[High(Tables)].Items    := @TreeSnapshot.Filters[C];
    case C of
      ifcEvexB:
        Tables[High(Tables)].Name := Tables[High(Tables)].Name + '.ifndef ZYDIS_DISABLE_EVEX';
      ifcMvexE:
        Tables[High(Tables)].Name := Tables[High(Tables)].Name + '.ifndef ZYDIS_DISABLE_MVEX';
    end;
  end;
  TZYTableGenerator<PZYTreeItem>.Generate(Generator, Filename, Tables,
    procedure(Writer: TZYTableItemWriter; Index: Integer; const Item: PZYTreeItem)
    var
      F: TZYInstructionFilter;
      I: Integer;
      V: PZYTreeItem;
    begin
      Assert(Item.ItemType = TZYTreeItemType.Filter);
      F := TZYInstructionFilterInfo.Info[Item.FilterClass];
      for I := 0 to F.NumberOfValues - 1 do
      begin
        V := @Item.Childs[I];
        case V^.ItemType of
          TZYTreeItemType.Invalid:
            begin
              Writer.WriteStr('ZYDIS_INVALID');
            end;
          TZYTreeItemType.Filter:
            begin
              Assert(V^.FilterId >= 0);
              Writer.WriteStr(Format('ZYDIS_FILTER(ZYDIS_NODETYPE_FILTER_%s, 0x%X)', [
                NODE_NAMES[V^.FilterClass], V^.FilterId]));
            end;
          TZYTreeItemType.Definition:
            begin
              Assert(V^.DefinitionId >= 0);
              Writer.WriteStr(Format('ZYDIS_DEFINITION(0x%X, 0x%X)', [
                Encodings.Mapping[V^.DefinitionEncoding][V^.DefinitionId], V^.DefinitionId]));
            end;
        end;
        {$WARNINGS OFF}
        if (I <> F.NumberOfValues - 1) then
        {$WARNINGS ON}
        begin
          Writer.WriteLine;
        end;
      end;
    end);
end;
{$ENDREGION}

{$REGION 'Class: TZYEncoderTableGenerator'}
class procedure TZYEncoderTableGenerator.Generate(Generator: TZYBaseGenerator;
  const Filename: String; Definitions: TZYDefinitionList; Mnemonics: TZYGeneratorEnum);
begin

end;
{$ENDREGION}

end.
