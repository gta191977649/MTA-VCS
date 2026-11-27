
void FUN_003ef910(undefined8 param_1,long param_2)

{
  short sVar1;
  bool bVar2;
  int iVar3;
  long lVar4;
  undefined8 uVar5;
  ulong uVar6;
  int iVar7;
  int iVar8;
  int iVar9;
  float fVar10;
  
  iVar8 = (int)param_1;
  bVar2 = false;
  if ((*(char *)(iVar8 + 0x264) == '\x01') && (bVar2 = true, *(int *)(iVar8 + 0x354) == 1)) {
    bVar2 = false;
  }
  if (!bVar2) {
    return;
  }
  uVar6 = (*(long *)(iVar8 + 0x48) << 0x1c) >> 0x20 & 0x1f;
  if ((uVar6 != 2) && (uVar6 != 3)) {
    return;
  }
  if (((((*(ulong *)(iVar8 + 0x260) & 0x10000000000) == 0) &&
       (sVar1 = *(short *)(iVar8 + 0x56), sVar1 != 0x105)) && (sVar1 != 0xdb)) &&
     ((sVar1 != 0xcf && (sVar1 != 0xea)))) {
    iVar7 = *(int *)(iVar8 + 900);
  }
  else {
    lVar4 = FUN_0024a430();
    if (param_2 == lVar4) {
      uVar5 = FUN_0024a430();
      FUN_002379e0(uVar5,1);
      return;
    }
    iVar7 = *(int *)(iVar8 + 900);
  }
  if ((((iVar7 != 0) && (*(int *)(iVar7 + 0x8f4) != 2)) &&
      ((((iVar7 = *(int *)(iVar7 + 0x550), iVar7 == 7 ||
         (((iVar7 == 8 || (iVar7 == 9)) || (iVar7 == 10)))) ||
        (((iVar7 == 0xb || (iVar7 == 0xc)) || (iVar7 == 0xd)))) ||
       ((iVar7 == 0xe || (iVar7 == 0xf)))))) && (lVar4 = FUN_0024a430(), param_2 == lVar4)) {
    iVar9 = 200;
    FUN_003bb670(*(undefined4 *)(iVar8 + 900),8,param_2);
    iVar7 = 0;
    if (*(char *)(iVar8 + 0x235) == '\0') {
      return;
    }
    do {
      lVar4 = FUN_003f3968(param_1,iVar7);
      if (((lVar4 != 0) && (iVar3 = FUN_003f3968(param_1,iVar7), *(int *)(iVar3 + 0x8a4) != 8)) &&
         (iVar3 = FUN_003f3968(param_1,iVar7), *(int *)(iVar3 + 0x8f4) != 2)) {
        uVar5 = FUN_003f3968(param_1,iVar7);
        FUN_003bb670(uVar5,8,param_2);
        iVar3 = FUN_003f3968(param_1,iVar7);
        *(int *)(iVar3 + 0x6dc) = DAT_004cd104 + iVar9;
        iVar9 = iVar9 + 200;
      }
      iVar7 = iVar7 + 1;
    } while (iVar7 < (int)(uint)*(byte *)(iVar8 + 0x235));
    return;
  }
  if (*(char *)(iVar8 + 0x214) == '\x03') {
    iVar7 = *(int *)(iVar8 + 900);
LAB_003efb60:
    if ((iVar7 != 0) && (*(int *)(iVar7 + 0x8a4) != 0x10)) {
      if (*(char *)(iVar8 + 0x214) == '\x03') {
        *(undefined1 *)(iVar8 + 0x214) = 3;
      }
      else {
        *(char *)(iVar8 + 0x217) = (char)(int)((float)(int)*(char *)(iVar8 + 0x217) * 1.5);
        *(undefined1 *)(iVar8 + 0x214) = 3;
      }
    }
  }
  else {
    fVar10 = (float)FUN_004080b8();
    if (0.5 < fVar10) {
      if (*(char *)(iVar8 + 0x215) == '\x01') {
        iVar7 = *(int *)(iVar8 + 900);
        goto LAB_003efb60;
      }
      iVar7 = *(int *)(iVar8 + 900);
    }
    else {
      iVar7 = *(int *)(iVar8 + 900);
    }
    if (((iVar7 != 0) && (*(int *)(iVar7 + 0x8f4) != 2)) && (*(int *)(iVar8 + 0x354) != 4)) {
      *(ulong *)(iVar7 + 0x1c8) = *(ulong *)(iVar7 + 0x1c8) | 0x800000000000;
      FUN_003bb670(iVar7,0x10,param_1);
      FUN_00174a90(iVar7,0x77);
    }
    iVar9 = 200;
    iVar7 = 0;
    if (*(char *)(iVar8 + 0x235) != '\0') {
      do {
        lVar4 = FUN_003f3968(param_1,iVar7);
        if (((lVar4 != 0) && (iVar3 = FUN_003f3968(param_1,iVar7), *(int *)(iVar3 + 0x8a4) != 0x10))
           && (iVar3 = FUN_003f3968(param_1,iVar7), *(int *)(iVar3 + 0x8f4) != 2)) {
          iVar3 = FUN_003f3968(param_1,iVar7);
          *(ulong *)(iVar3 + 0x1c8) = *(ulong *)(iVar3 + 0x1c8) | 0x800000000000;
          uVar5 = FUN_003f3968(param_1,iVar7);
          FUN_003bb670(uVar5,0x10,param_1);
          iVar3 = FUN_003f3968(param_1,iVar7);
          *(int *)(iVar3 + 0x6dc) = DAT_004cd104 + iVar9;
          iVar9 = iVar9 + 200;
          uVar5 = FUN_003f3968(param_1,iVar7);
          FUN_00174a90(uVar5,0x77);
        }
        iVar7 = iVar7 + 1;
      } while (iVar7 < (int)(uint)*(byte *)(iVar8 + 0x235));
    }
  }
  return;
}

