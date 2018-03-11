//
//  PPCCtx.m
//  PPCCPU
//
//  Created by copy/pasting an example on 11/06/2015.
//  Copyright (c) 2015 PK and others. All rights reserved.
//

#import "PPCCtx.h"
#import "PPCCPU.h"
#import <Hopper/CommonTypes.h>
#import <Hopper/CPUDefinition.h>
#import <Hopper/HPDisassembledFile.h>
#import "ppcd/CommonDefs.h"
#import "ppcd/ppcd.h"

@implementation PPCCtx {
    PPCCPU *_cpu;
    NSObject<HPDisassembledFile> *_file;
    bool _trackingLis;
    uint64_t lisArr[32];
    NSMutableArray<NSNumber*> *_lr;
    int64_t stackDisp;
}

- (instancetype)initWithCPU:(PPCCPU *)cpu andFile:(NSObject<HPDisassembledFile> *)file {
    if (self = [super init]) {
        _cpu = cpu;
        _file = file;
        _trackingLis = false;
        for (int i = 0; i < 32; ++i)
            lisArr[i] = ~0;
        _lr = [NSMutableArray new];
        stackDisp = 0;
    }
    return self;
}

- (NSObject<CPUDefinition> *)cpuDefinition {
    return _cpu;
}

- (void)initDisasmStructure:(DisasmStruct *)disasm withSyntaxIndex:(NSUInteger)syntaxIndex {
    bzero(disasm, sizeof(DisasmStruct));
}

// Analysis

- (Address)adjustCodeAddress:(Address)address {
    // Instructions are always aligned to a multiple of 4.
    return address & ~3;
}

- (uint8_t)cpuModeFromAddress:(Address)address {
    return 0;
}

- (BOOL)addressForcesACPUMode:(Address)address {
    return NO;
}

- (Address)nextAddressToTryIfInstructionFailedToDecodeAt:(Address)address forCPUMode:(uint8_t)mode {
    return ((address & ~3) + 4);
}

- (int)isNopAt:(Address)address {
    uint32_t word = [_file readUInt32AtVirtualAddress:address];
    return (word == 0x60000000) ? 4 : 0;
}

- (BOOL)hasProcedurePrologAt:(Address)address {
    // procedures usually begin with a "stwu r1, -X(r1)" or "blr" instruction
    uint32_t word = [_file readUInt32AtVirtualAddress:address];
    return (word & 0xffff8000) == 0x94218000 || word == 0x4e800020;
}

- (NSUInteger)detectedPaddingLengthAt:(Address)address {
#if 0
    NSUInteger len = 0;
    uint32_t readVal;
    while ((readVal = [_file readUInt32AtVirtualAddress:address]) == 0) {
        //NSObject<HPSection>* sec = [_file sectionForVirtualAddress:address];
        //printf("%08llX %04X %p\n", address, readVal, sec);
        address += 4;
        len += 4;
    }
    return len;
#endif
    return 0;
}

- (void)analysisBeginsAt:(Address)entryPoint {
    printf("analysisBeginsAt\n");
}

- (void)procedureAnalysisBeginsForProcedure:(NSObject<HPProcedure> *)procedure atEntryPoint:(Address)entryPoint {
    printf("procedureAnalysisBeginsForProcedure %p\n", procedure);
    _trackingLis = true;
}

- (void)performProcedureAnalysis:(NSObject<HPProcedure> *)procedure basicBlock:(NSObject<HPBasicBlock> *)basicBlock disasm:(DisasmStruct *)disasm {
    printf("performProcedureAnalysis %p\n", procedure);
}

- (void)performInstructionSpecificAnalysis:(DisasmStruct *)disasm forProcedure:(NSObject<HPProcedure> *)procedure inSegment:(NSObject<HPSegment> *)segment {
    printf("performInstructionSpecificAnalysis %s %p\n", disasm->instruction.mnemonic, procedure);
    
    // LIS/ADDI resolved address
    for (int i = 0; i < DISASM_MAX_OPERANDS; ++i) {
        DisasmOperand *operand = disasm->operand + i;
        if (operand->userData[0] & DISASM_PPC_OPER_LIS_ADDI) {
            if ([_file segmentForVirtualAddress:operand->userData[1]])
            {
                [segment addReferencesToAddress:operand->userData[1] fromAddress:disasm->virtualAddr];
            }
            else
            {
                [_file setInlineComment:[NSString stringWithFormat:@"0x%08llX", operand->userData[1]] atVirtualAddress:disasm->virtualAddr reason:CCReason_Automatic];
            }
            break;
        }
    }
    
    // Stack register handling
    if (disasm->instruction.userData & DISASM_PPC_INST_LOAD_STORE &&
        disasm->operand[2].type & DISASM_BUILD_REGISTER_INDEX_MASK(1)) {
        if (disasm->operand[0].type & DISASM_BUILD_REGISTER_INDEX_MASK(1) &&
            !strcmp(disasm->instruction.mnemonic, "stwu")) {
            stackDisp = disasm->operand[1].immediateValue;
            [procedure setVariableName:@"BP" forDisplacement:disasm->operand[1].immediateValue];
        } else {
            int64_t imm = disasm->operand[1].immediateValue + stackDisp;
            if (imm < 0) {
                [procedure setVariableName:[NSString stringWithFormat:@"var_%llX", -imm] forDisplacement:disasm->operand[1].immediateValue];
            } else {
                if (imm == 4 && disasm->instruction.mnemonic[0] == 's')
                    [procedure setVariableName:@"LRpush" forDisplacement:disasm->operand[1].immediateValue];
                else if (imm == 4 && disasm->instruction.mnemonic[0] == 'l')
                    [procedure setVariableName:@"LRpop" forDisplacement:disasm->operand[1].immediateValue];
                else
                    [procedure setVariableName:[NSString stringWithFormat:@"arg_%llX", imm] forDisplacement:disasm->operand[1].immediateValue];
            }
        }
    }
}

- (void)updateProcedureAnalysis:(DisasmStruct *)disasm {
    printf("updateProcedureAnalysis %s\n", disasm->instruction.mnemonic);
}

- (void)procedureAnalysisContinuesOnBasicBlock:(NSObject<HPBasicBlock> *)basicBlock {
    printf("procedureAnalysisContinuesOnBasicBlock\n");
}

- (void)procedureAnalysisOfPrologForProcedure:(NSObject<HPProcedure> *)procedure atEntryPoint:(Address)entryPoint {
    printf("procedureAnalysisOfPrologForProcedure %p\n", procedure);
}

- (void)procedureAnalysisOfEpilogForProcedure:(NSObject<HPProcedure> *)procedure atEntryPoint:(Address)entryPoint {
    printf("procedureAnalysisOfEpilogForProcedure %p\n", procedure);
}

- (void)procedureAnalysisEndedForProcedure:(NSObject<HPProcedure> *)procedure atEntryPoint:(Address)entryPoint {
    printf("procedureAnalysisEndedForProcedure %p\n", procedure);
    _trackingLis = false;
    for (int i = 0; i < 32; ++i)
        lisArr[i] = ~0;
    stackDisp = 0;
}

- (void)analysisEnded {
    printf("analysisEnded\n");
}

- (Address)getThunkDestinationForInstructionAt:(Address)address {
    return BAD_ADDRESS;
}

- (void)resetDisassembler {

}

- (uint8_t)estimateCPUModeAtVirtualAddress:(Address)address {
    return 0;
}

- (int)disassembleSingleInstruction:(DisasmStruct *)disasm usingProcessorMode:(NSUInteger)mode {
    disasm->instruction.branchType = DISASM_BRANCH_NONE;
    disasm->instruction.addressValue = 0;
    disasm->instruction.userData = 0;
    for (int i=0; i<DISASM_MAX_REG_CLASSES; i++) {
        disasm->implicitlyReadRegisters[i] = 0;
        disasm->implicitlyWrittenRegisters[i] = 0;
    }
    for (int i=0; i<DISASM_MAX_OPERANDS; i++) {
        disasm->operand[i].type = DISASM_OPERAND_NO_OPERAND;
        disasm->operand[i].accessMode = DISASM_ACCESS_NONE;
        bzero(&disasm->operand[i].memory, sizeof(disasm->operand[i].memory));
        disasm->operand[i].isBranchDestination = 0;
        disasm->operand[i].userData[0] = 0;
    }
    
    PPCD_CB d;
    d.pc = disasm->virtualAddr;
    d.instr = [_file readUInt32AtVirtualAddress:disasm->virtualAddr];
    d.disasm = disasm;
    d.lisArr = _trackingLis ? lisArr : NULL;
    PPCDisasm(&d);
    
#if 0
    if (_trackingLis) {
        printf ("%08X  %08X  %-12s%-30s\n", d.pc, d.instr, d.mnemonic, d.operands);
    }
#endif
    
    //if ((d.iclass & PPC_DISA_ILLEGAL) == PPC_DISA_ILLEGAL) return DISASM_UNKNOWN_OPCODE;

    return 4; //All instructions are 4 bytes
}

- (BOOL)instructionHaltsExecutionFlow:(DisasmStruct *)disasm {
    return NO;
}

- (void)performBranchesAnalysis:(DisasmStruct *)disasm computingNextAddress:(Address *)next andBranches:(NSMutableArray<NSNumber *> *)branches forProcedure:(NSObject<HPProcedure> *)procedure basicBlock:(NSObject<HPBasicBlock> *)basicBlock ofSegment:(NSObject<HPSegment> *)segment calledAddresses:(NSMutableArray<NSNumber *> *)calledAddresses callsites:(NSMutableArray<NSNumber *> *)callSitesAddresses {
#if 0
    if (disasm->instruction.branchType == DISASM_BRANCH_CALL)
    {
        [_cpu->_lr addObject:@(disasm->virtualAddr + 4)];
        printf("JUST PUSHED %d\n", [_cpu->_lr count]);
        *next = disasm->instruction.addressValue;
    }
    else if (disasm->instruction.branchType == DISASM_BRANCH_RET)
    {
        printf(" WILL POP %d\n", [_cpu->_lr count]);
        *next = [[_cpu->_lr lastObject] unsignedIntegerValue];
        [_cpu->_lr removeLastObject];
    }
#endif
    if (disasm->instruction.branchType == DISASM_BRANCH_CALL) {
        [callSitesAddresses addObject:@(disasm->instruction.addressValue)];
        *next = disasm->virtualAddr + 4;
    } else if (disasm->instruction.branchType == DISASM_BRANCH_RET) {
        *next = BAD_ADDRESS;
    } else {
        [branches addObject:@(disasm->instruction.addressValue)];
        *next = disasm->virtualAddr + 4;
    }
    printf("%08X NEXT %08X %d\n", disasm->virtualAddr, *next, disasm->instruction.branchType);
}

// Printing

- (NSObject<HPASMLine> *)buildMnemonicString:(DisasmStruct *)disasm inFile:(NSObject<HPDisassembledFile> *)file {
    NSObject<HPHopperServices> *services = _cpu.hopperServices;
    NSObject<HPASMLine> *line = [services blankASMLine];
    [line appendMnemonic:@(disasm->instruction.mnemonic)];
    return line;
}

static RegClass GetRegisterClass(DisasmOperandType type)
{
    for (int i = 0; i < DISASM_MAX_REG_CLASSES; ++i)
        if (type & DISASM_BUILD_REGISTER_CLS_MASK(i))
            return i;
    return -1;
}

static int GetRegisterIndex(DisasmOperandType type)
{
    for (int i = 0; i < DISASM_MAX_REG_INDEX; ++i)
        if (type & DISASM_BUILD_REGISTER_INDEX_MASK(i))
            return i;
    return -1;
}

- (NSObject<HPASMLine> *)buildOperandString:(DisasmStruct *)disasm forOperandIndex:(NSUInteger)operandIndex inFile:(NSObject<HPDisassembledFile> *)file raw:(BOOL)raw {
    if (operandIndex >= DISASM_MAX_OPERANDS) return nil;
    DisasmOperand *operand = disasm->operand + operandIndex;
    if (operand->type == DISASM_OPERAND_NO_OPERAND) return nil;
   
    // Get the format requested by the user
    ArgFormat format = [file formatForArgument:operandIndex atVirtualAddress:disasm->virtualAddr];
    
    NSObject<HPHopperServices> *services = _cpu.hopperServices;
    NSObject<HPASMLine> *line = [services blankASMLine];
    
    if (operand->type & DISASM_OPERAND_CONSTANT_TYPE) {
        if ((format == Format_Default || format == Format_StackVariable) &&
            disasm->instruction.userData & DISASM_PPC_INST_LOAD_STORE &&
            disasm->operand[2].type & DISASM_BUILD_REGISTER_INDEX_MASK(1) && operandIndex == 1) {
            NSObject<HPProcedure> *proc = [file procedureAt:disasm->virtualAddr];
            if (proc) {
                NSString *variableName = [proc variableNameForDisplacement:operand->immediateValue];
                if (variableName) {
                    [line appendVariableName:variableName withDisplacement:operand->immediateValue];
                    [line setIsOperand:operandIndex startingAtIndex:0];
                    return line;
                }
            }
        }
        
        if (format == Format_Default) {
            if (disasm->instruction.addressValue != 0) {
                format = Format_Address;
            }
            else {
                if (operand->userData[0] & DISASM_PPC_OPER_IMM_HEX || llabs(operand->immediateValue) > 255)
                    format = Format_Hexadecimal | Format_Signed;
                else
                    format = Format_Decimal | Format_Signed;
            }
        }
        [line append:[file formatNumber:operand->immediateValue
                                     at:disasm->virtualAddr usingFormat:format
                             andBitSize:32]];
    }
    else if (operand->type & DISASM_OPERAND_REGISTER_TYPE || operand->type & DISASM_OPERAND_MEMORY_TYPE) {
        RegClass regCls = GetRegisterClass(operand->type);
        int regIdx = GetRegisterIndex(operand->type);
        [line appendRegister:[_cpu registerIndexToString:regIdx
                                                 ofClass:regCls
                                             withBitSize:32
                                                position:DISASM_LOWPOSITION
                                          andSyntaxIndex:file.userRequestedSyntaxIndex]
                     ofClass:regCls
                    andIndex:regIdx];
    }
    else if (operand->type & DISASM_OPERAND_OTHER) {
        [line appendRegister:@(operand->userString)];
    }
    
    [line setIsOperand:operandIndex startingAtIndex:0];
    
    return line;
}

- (NSObject<HPASMLine> *)buildCompleteOperandString:(DisasmStruct *)disasm inFile:(NSObject<HPDisassembledFile> *)file raw:(BOOL)raw {
    NSObject<HPHopperServices> *services = _cpu.hopperServices;
    
    NSObject<HPASMLine> *line = [services blankASMLine];
    
    int op_index = 0;
    
    if (disasm->instruction.userData & DISASM_PPC_INST_LOAD_STORE)
    {
        NSObject<HPASMLine> *part = [self buildOperandString:disasm forOperandIndex:0 inFile:file raw:raw];
        if (part == nil) return line;
        [line append:part];
        [line appendRawString:@", "];
        
        part = [self buildOperandString:disasm forOperandIndex:1 inFile:file raw:raw];
        if (part == nil) return line;
        [line append:part];
        [line appendRawString:@"("];
        
        part = [self buildOperandString:disasm forOperandIndex:2 inFile:file raw:raw];
        if (part == nil) return line;
        [line append:part];
        [line appendRawString:@")"];
        
        op_index = 3;
    }
    
    for (; op_index<=DISASM_MAX_OPERANDS; op_index++) {
        NSObject<HPASMLine> *part = [self buildOperandString:disasm forOperandIndex:op_index inFile:file raw:raw];
        if (part == nil) break;
        if (op_index) [line appendRawString:@", "];
        [line append:part];
        
        // LIS/ADDI resolved address
        DisasmOperand *operand = disasm->operand + op_index;
        if (operand->userData[0] & DISASM_PPC_OPER_RLWIMI) {
            int ra = GetRegisterIndex(disasm->operand[0].type);
            int rs = GetRegisterIndex(disasm->operand[1].type);
            int sh = (int)operand->userData[1];
            int mb = (int)operand->userData[2];
            int me = (int)operand->userData[3];
            if (sh == 0) {
                [line appendComment:[NSString stringWithFormat:@" # r%d = r%d & 0x%08X", ra, rs, MASK32VAL(mb, me)]];
            } else if (me + sh > 31) {
                // Actually a shift right
                [line appendComment:[NSString stringWithFormat:@" # r%d = (r%d >> %d) & 0x%08X", ra, rs, 32 - sh, MASK32VAL(mb, me)]];
            } else {
                [line appendComment:[NSString stringWithFormat:@" # r%d = (r%d << %d) & 0x%08X", ra, rs, sh, MASK32VAL(mb, me)]];
            }
        }
    }
    
    return line;
}

// Decompiler

- (BOOL)canDecompileProcedure:(NSObject<HPProcedure> *)procedure {
    return NO;
}

- (Address)skipHeader:(NSObject<HPBasicBlock> *)basicBlock ofProcedure:(NSObject<HPProcedure> *)procedure {
    return basicBlock.from;
}

- (Address)skipFooter:(NSObject<HPBasicBlock> *)basicBlock ofProcedure:(NSObject<HPProcedure> *)procedure {
    return basicBlock.to;
}

- (ASTNode *)rawDecodeArgumentIndex:(int)argIndex
                           ofDisasm:(DisasmStruct *)disasm
                  ignoringWriteMode:(BOOL)ignoreWrite
                    usingDecompiler:(Decompiler *)decompiler {
    return nil;
}

- (ASTNode *)decompileInstructionAtAddress:(Address)a
                                    disasm:(DisasmStruct *)d
                                 addNode_p:(BOOL *)addNode_p
                           usingDecompiler:(Decompiler *)decompiler {
    return nil;
}

// Assembler

- (NSData *)assembleRawInstruction:(NSString *)instr atAddress:(Address)addr forFile:(NSObject<HPDisassembledFile> *)file withCPUMode:(uint8_t)cpuMode usingSyntaxVariant:(NSUInteger)syntax error:(NSError **)error {
    return nil;
}

- (BOOL)instructionCanBeUsedToExtractDirectMemoryReferences:(DisasmStruct *)disasmStruct {
    return YES;
}

- (BOOL)instructionOnlyLoadsAddress:(DisasmStruct *)disasmStruct {
    return NO;
}

- (BOOL)instructionMayBeASwitchStatement:(DisasmStruct *)disasmStruct {
    return NO;
}

@end
