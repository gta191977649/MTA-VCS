undefined4 FUN_00101d30(undefined8 param_1,undefined8 param_2,undefined8 param_3,float *param_4)

{
  char cVar1;
  bool bVar2;
  undefined2 uVar3;
  int iVar4;
  int iVar5;
  int iVar6;
  long lVar7;
  long lVar8;
  ulong uVar9;
  undefined8 uVar10;
  int iVar11;
  float fVar12;
  float fVar13;
  undefined4 uVar14;
  float fVar15;
  float fVar16;
  float fStack_80;
  float fStack_7c;
  float fStack_78;
  undefined4 uStack_74;
  float fStack_70;
  undefined4 uStack_6c;
  undefined4 uStack_68;
  undefined4 uStack_64;
  
  iVar5 = 0;
  bVar2 = false;
  fVar13 = *param_4;
  fVar15 = param_4[1];
  fVar12 = param_4[2];
  iVar11 = (int)param_1;
  lVar7 = FUN_0020c310(*(undefined4 *)(iVar11 + 0x8a0));
  if (lVar7 != 0) {
    iVar5 = *(int *)(iVar11 + 0x8a0);
  }
  lVar7 = FUN_00219a78(param_1,*(undefined4 *)(iVar11 + 0x8a0));
  if (iVar5 == 0) {
LAB_00101ea8:
    uVar9 = *(ulong *)(iVar11 + 0x1c8);
  }
  else {
    lVar8 = FUN_0040d420();
    if (lVar8 != 0) {
      uVar9 = *(ulong *)(iVar5 + 0xcc8);
LAB_00101e0c:
      if ((uVar9 & 0x40000000000) == 0) {
        bVar2 = true;
      }
      else {
        lVar8 = FUN_0020c320(param_1);
        if (lVar8 == 0) {
          bVar2 = true;
          if (*(int *)(iVar11 + 0x550) != 6) goto LAB_00101ea8;
          iVar6 = *(int *)(iVar11 + 0x8f4);
        }
        else {
          iVar6 = *(int *)(iVar11 + 0x8f4);
        }
        if (iVar6 != 2) {
          FUN_001ffe90(param_1,0x13,1000,1);
          FUN_00200238(param_1,0x13);
          FUN_001ef918(param_1,1);
          *(ulong *)(iVar11 + 0x1c8) = *(ulong *)(iVar11 + 0x1c8) | 0x10000000;
          *(ulong *)(iVar11 + 0x1d0) = *(ulong *)(iVar11 + 0x1d0) | 0x80000000000;
          return 1;
        }
        bVar2 = true;
      }
      goto LAB_00101ea8;
    }
    iVar6 = *(int *)(*(int *)(iVar11 + 0x8a0) + 0x514);
    if (iVar6 == 0) {
      uVar9 = *(ulong *)(iVar11 + 0x1c8);
    }
    else if (iVar6 == *(int *)(iVar11 + 0x514)) {
      uVar9 = *(ulong *)(iVar11 + 0x1c8);
    }
    else {
      if (SQRT(fVar13 * fVar13 + fVar15 * fVar15 + fVar12 * fVar12) < 5.0) {
        uVar9 = *(ulong *)(iVar5 + 0xcc8);
        goto LAB_00101e0c;
      }
      uVar9 = *(ulong *)(iVar11 + 0x1c8);
    }
  }
  *(ulong *)(iVar11 + 0x1d0) = *(ulong *)(iVar11 + 0x1d0) & 0xfffff7ffffffffff;
  *(ulong *)(iVar11 + 0x1c8) = uVar9 & 0xfffff7ffefffffff;
  if ((DAT_004cd104 < *(uint *)(iVar11 + 0x6c0)) && ((uVar9 & 0x20000000000) == 0)) {
    FUN_001ef918(param_1,1);
    return 1;
  }
  if (iVar5 != 0) {
    if ((*(int *)(iVar11 + 0x550) == 6) && ((*(ulong *)(iVar5 + 0x918) & 0x1000000000000) != 0)) {
      iVar5 = *(int *)(iVar11 + 0x8c4);
LAB_00101f84:
      if (iVar5 != 0x36) {
        FUN_00201ef0(param_1);
        return 1;
      }
      return 1;
    }
    if ((*(ulong *)(iVar5 + 0x918) & 0x2000000000000) != 0) {
      iVar5 = *(int *)(iVar11 + 0x8c4);
      goto LAB_00101f84;
    }
    if ((*(ulong *)(*(int *)(iVar11 + 0x8a0) + 0xe8) & 0x10000000000) != 0) {
      iVar5 = *(int *)(iVar11 + 0x8c4);
      goto LAB_00101f84;
    }
    if (*(int *)(*(int *)(iVar11 + 0x8a0) + 0x8c4) == 0x41) {
      iVar5 = *(int *)(iVar11 + 0x8c4);
      goto LAB_00101f84;
    }
  }
  if (lVar7 == 0) {
    if (iVar5 != 0) {
      fStack_80 = *(float *)(iVar5 + 0x30) - *(float *)(iVar11 + 0x30);
      fStack_7c = *(float *)(iVar5 + 0x34) - *(float *)(iVar11 + 0x34);
      fStack_78 = *(float *)(iVar5 + 0x38) - *(float *)(iVar11 + 0x38);
      fVar12 = fStack_80 * fStack_80 + fStack_7c * fStack_7c + fStack_78 * fStack_78;
      if (49.0 < fVar12) {
        if (98.0 < fVar12) {
          bVar2 = false;
          FUN_00204038(0x40e00000,param_1,iVar5);
        }
        else {
          bVar2 = true;
          FUN_002045f0();
          FUN_00205db8(param_1);
          FUN_00219340(param_1,1);
          FUN_001ef918(param_1,1);
          FUN_00215868(0x447a0000,param_1,*(undefined4 *)(iVar11 + 0x50),0,0x2c);
          FUN_001f0d68(param_1,iVar5,1,1,0);
          FUN_001f1358(param_1,iVar5);
          FUN_00203a70(param_1,0x7fffffff);
        }
      }
      else if ((fVar12 < 24.5) && (*(int *)(iVar11 + 0x8c4) != 8)) {
        *(uint *)(iVar11 + 0x81c) = DAT_004cd104;
        fStack_80 = *(float *)(iVar5 + 0x30);
        fStack_7c = *(float *)(iVar5 + 0x34);
        FUN_00205a68(param_1,&fStack_80,3000);
        FUN_001ef918(param_1,5);
        *(ulong *)(iVar11 + 0x1c8) = *(ulong *)(iVar11 + 0x1c8) & 0xffffffffbfffffff;
        FUN_00218750(param_1);
        return 1;
      }
      goto LAB_00102140;
    }
LAB_00102198:
    iVar6 = *(int *)(iVar11 + 0x8a0);
  }
  else {
LAB_00102140:
    if ((iVar5 == 0) || (*(int *)(iVar11 + 0x550) == 6)) goto LAB_00102198;
    if (*(int *)(iVar11 + 0x8f4) == 2) {
      iVar6 = *(int *)(iVar11 + 0x8a0);
    }
    else if (*(char *)(iVar5 + 0x918) == '\0') {
      iVar6 = *(int *)(iVar11 + 0x8a0);
    }
    else {
      if ((*(ulong *)(iVar11 + 0x1d0) & 0x80000000000000) == 0) {
        FUN_003bb4e0(param_1,3);
        return 1;
      }
      iVar6 = *(int *)(iVar11 + 0x8a0);
    }
  }
  if (*(float *)(iVar6 + 0x4e4) <= 0.0) {
    *(ulong *)(iVar11 + 0x1c8) = *(ulong *)(iVar11 + 0x1c8) & 0xfffffeffffffffff | 0x18000000000;
    return 0;
  }
  fVar12 = 0.0;
  fVar13 = 0.3;
  iVar4 = FUN_00407120(*(undefined4 *)(*(char *)(iVar11 + 0x789) * 0x1c + iVar11 + 0x578));
  iVar6 = *(int *)(*(int *)(iVar11 + 0x8a0) + 0x8c4);
  fVar16 = SQRT(*param_4 * *param_4 + param_4[1] * param_4[1] + param_4[2] * param_4[2]);
  fVar15 = *(float *)(iVar4 + 8) * 0.2;
  if ((iVar6 == 0x3d) || (iVar6 == 0x3b)) {
    if (fVar15 <= 2.0) {
      cVar1 = *(char *)(iVar11 + 0x789);
      goto LAB_001022b0;
    }
    FUN_00218500(param_1,*(int *)(iVar11 + 0x8a0) + 0x30);
    fVar15 = 1.0;
    fVar13 = 0.5;
    fVar12 = fVar16;
  }
  else {
    cVar1 = *(char *)(iVar11 + 0x789);
LAB_001022b0:
    iVar6 = *(int *)(cVar1 * 0x1c + iVar11 + 0x578);
    if ((((iVar6 == 4) || (iVar6 == 3)) || (iVar6 == 6)) ||
       (((((iVar6 == 2 || (iVar6 == 5)) || ((iVar6 == 7 || ((iVar6 == 8 || (iVar6 == 9)))))) ||
         (iVar6 == 10)) || (iVar6 == 0xb)))) {
      FUN_00218500(param_1,*(int *)(iVar11 + 0x8a0) + 0x30);
      fVar12 = fVar15 * 0.4;
    }
    else {
      if (fVar16 <= 2.0) {
        if (iVar5 == 0) {
          iVar5 = *(int *)(iVar11 + 0x8a0);
        }
        else {
          if ((*(ulong *)(iVar5 + 0xcc8) & 0x200000000000) == 0) goto LAB_001023c8;
          iVar5 = *(int *)(iVar11 + 0x8a0);
        }
      }
      else {
        iVar5 = *(int *)(iVar11 + 0x8a0);
      }
      FUN_00218500(param_1,iVar5 + 0x30);
      fVar12 = fVar15 * 0.9;
      fVar15 = fVar15 * 1.1;
    }
    fVar13 = (float)((int)fVar12 * (uint)(0.8 < fVar12) | (uint)(0.8 >= fVar12) * 0x3f4ccccd);
    fVar12 = fVar16;
  }
LAB_001023c8:
  lVar8 = FUN_00219d50(*(undefined4 *)(iVar11 + 0x8a0));
  if ((lVar8 != 0) && (*(int *)(*(int *)(iVar11 + 0x8a0) + 0x8c4) != 0x3c)) {
    iVar5 = *(int *)(*(int *)(iVar11 + 0x8a0) + 0x480);
    if (iVar5 == 0) {
      return 0;
    }
    if ((*(ulong *)(iVar5 + 0xe8) & 0x10000000000) != 0) {
      iVar5 = *(int *)(iVar11 + 0x550);
LAB_00102914:
      if (iVar5 == 6) {
        iVar5 = *(int *)(iVar11 + 0x514);
        iVar4 = 0;
        iVar6 = iVar4;
        if ((((iVar5 != 0) && (((*(long *)(iVar5 + 0x48) << 0x1f) >> 0x20 & 7U) == 2)) &&
            (iVar6 = iVar5, *(int *)(iVar5 + 0x354) != 1)) &&
           (iVar6 = iVar4, *(int *)(iVar5 + 0x354) == 2)) {
          iVar6 = iVar5;
        }
        if (((iVar6 != 0) && (iVar5 = *(int *)(iVar11 + 0x8a0), iVar5 != 0)) &&
           ((*(int *)(iVar5 + 0x8c4) == 0x37 &&
            ((*(int *)(iVar5 + 0x480) == iVar6 && (lVar7 = FUN_0020c310(), lVar7 != 0)))))) {
          FUN_00327478(param_1,*(undefined4 *)(iVar11 + 0x8a0));
          return 0;
        }
      }
      FUN_00201ef0(param_1);
      return 2;
    }
    if (((*(long *)(iVar5 + 0x48) << 0x1c) >> 0x20 & 0x1fU) == 0xd) {
      iVar5 = *(int *)(iVar11 + 0x550);
      goto LAB_00102914;
    }
    lVar7 = FUN_0020c310();
    if (lVar7 == 0) {
      iVar5 = *(int *)(iVar11 + 0x8a0);
    }
    else {
      iVar5 = FUN_002852a8(0);
      if (*(short *)(iVar5 + 0x96) != 0) {
        iVar5 = *(int *)(iVar11 + 0x550);
        goto LAB_00102914;
      }
      iVar5 = *(int *)(iVar11 + 0x8a0);
    }
    FUN_001f0d68(param_1,*(undefined4 *)(iVar5 + 0x480),0,0,0);
    if (*(int *)(iVar11 + 0x8c4) == 0x3b) {
      return 0;
    }
    iVar5 = *(int *)(iVar11 + 0x8a0);
    if (*(int *)(iVar5 + 0x8c4) == 0x41) {
      return 0;
    }
    if (*(int *)(iVar11 + 0x8c4) == 0x10) {
      return 0;
    }
    if ((*(ulong *)(iVar11 + 0x1c8) & 0x20000000000) != 0) {
      return 0;
    }
    if (bVar2) {
      return 0;
    }
    if ((*(int *)(iVar11 + 0x550) == 6) ||
       ((*(ulong *)(*(int *)(iVar5 + 0x480) + 0x260) & 0x2000000000000) != 0)) {
      lVar7 = FUN_0021a158(param_1,iVar5);
      if (lVar7 == 0) {
        return 0;
      }
      FUN_00305f68(param_1,*(undefined4 *)(*(int *)(iVar11 + 0x8a0) + 0x480));
      return 0;
    }
    *(undefined2 *)(iVar11 + 0x8f2) = 0;
    iVar6 = *(int *)(iVar5 + 0x480);
    uVar3 = 10;
    if ((iVar5 != *(int *)(iVar6 + 900)) &&
       (uVar3 = 10, (*(ulong *)(iVar6 + 0x260) & 0x2000000000000) == 0)) {
      iVar6 = FUN_003f3968(iVar6,0);
      if (iVar5 == iVar6) {
        uVar3 = 8;
      }
      else {
        iVar5 = *(int *)(iVar11 + 0x8a0);
        iVar6 = FUN_003f3968(*(undefined4 *)(iVar5 + 0x480),1);
        if (iVar5 == iVar6) {
          uVar3 = 0xb;
        }
        else {
          iVar5 = *(int *)(iVar11 + 0x8a0);
          iVar6 = FUN_003f3968(*(undefined4 *)(iVar5 + 0x480),2);
          if (iVar5 != iVar6) {
            iVar5 = *(int *)(iVar11 + 0x8a0);
            goto LAB_00102ae0;
          }
          uVar3 = 9;
        }
      }
    }
    *(undefined2 *)(iVar11 + 0x8f2) = uVar3;
    iVar5 = *(int *)(iVar11 + 0x8a0);
LAB_00102ae0:
    FUN_00303800(&fStack_70,*(undefined4 *)(iVar5 + 0x480),*(undefined2 *)(iVar11 + 0x8f2),param_1);
    fStack_80 = fStack_70;
    fStack_7c = (float)uStack_6c;
    fStack_78 = (float)uStack_68;
    uStack_74 = uStack_64;
    FUN_0020b460(param_1,*(undefined4 *)(*(int *)(iVar11 + 0x8a0) + 0x480),
                 *(undefined2 *)(iVar11 + 0x8f2));
    FUN_001ef918(param_1,4);
    return 0;
  }
  if ((*(int *)(iVar11 + 0x8d4) == 1) || (*(int *)(iVar11 + 0x8d4) == 0)) {
    lVar8 = FUN_001fd9e0(param_1);
    if (lVar8 != 0) {
      FUN_001f0d68(param_1,*(undefined4 *)(iVar11 + 0x8a0),0,0,0);
      if ((*(int *)(iVar11 + 0x8c4) != 1) && (*(int *)(iVar11 + 0x8c4) != 0x10)) {
        iVar5 = *(int *)(iVar11 + 0x550);
        goto LAB_00102448;
      }
      FUN_00203e30(param_1);
    }
    iVar5 = *(int *)(iVar11 + 0x550);
  }
  else {
    iVar5 = *(int *)(iVar11 + 0x550);
  }
LAB_00102448:
  if (iVar5 == 6) {
    lVar8 = FUN_0020c310(*(undefined4 *)(iVar11 + 0x8a0));
    if (lVar8 != 0) {
      fVar16 = 1.5;
      if (*(int *)(iVar11 + 0x91c) != 0) {
        iVar5 = *(int *)(*(int *)(iVar11 + 0x8a0) + 0x8c4);
        if (iVar5 == 0x2d) {
          fVar16 = 3.5;
        }
        else {
          fVar16 = 1.5;
          if (iVar5 != 0x3c) {
            *(undefined4 *)(iVar11 + 0x91c) = 0;
          }
        }
      }
      if (fVar12 < fVar16) {
        if ((DAT_004cd104 < *(uint *)(*(int *)(iVar11 + 0x8a0) + 0x6c4)) ||
           (*(int *)(*(int *)(iVar11 + 0x8a0) + 0x8c4) == 0x3c)) {
          FUN_00327478(param_1);
          return 2;
        }
        iVar5 = *(int *)(iVar11 + 0x8c4);
        goto LAB_001024e4;
      }
    }
    iVar5 = *(int *)(iVar11 + 0x8c4);
  }
  else {
    iVar5 = *(int *)(iVar11 + 0x8c4);
  }
LAB_001024e4:
  if (iVar5 == 0x11) {
    fVar13 = fVar13 + 1.0;
  }
  if (fVar13 < fVar12) {
    if (lVar7 == 0) {
      uVar9 = *(ulong *)(iVar11 + 0x1d0);
    }
    else if ((*(ulong *)(iVar11 + 0x1c8) & 0x20000000000) == 0) {
      if (bVar2) {
        uVar9 = *(ulong *)(iVar11 + 0x1d0);
      }
      else {
        if (iVar5 != 8) {
          if ((*(ulong *)(iVar11 + 0x1c8) & 0x40000000) == 0) {
            FUN_00204038(fVar13,param_1,*(undefined4 *)(iVar11 + 0x8a0));
            return 0;
          }
          fStack_80 = 0.0;
          fStack_7c = 0.0;
          fStack_78 = 0.0;
          lVar7 = FUN_00218758();
          if (lVar7 == 0) {
            FUN_002189e0(&fStack_70,param_1);
            FUN_00307900(param_1,&fStack_70,&fStack_80);
          }
          lVar7 = FUN_00218758(param_1);
          if (lVar7 != 0) {
            FUN_00218bc8(&fStack_70,param_1);
            FUN_00218500(param_1,&fStack_70);
          }
          FUN_002189e0(&fStack_70,param_1);
          FUN_00203e90(*(undefined4 *)(iVar11 + 0x810),param_1,&fStack_70);
          return 0;
        }
        uVar9 = *(ulong *)(iVar11 + 0x1d0);
      }
    }
    else {
      uVar9 = *(ulong *)(iVar11 + 0x1d0);
    }
  }
  else {
    uVar9 = *(ulong *)(iVar11 + 0x1d0);
  }
  bVar2 = false;
  if (((uVar9 & 0x4000000000000000) != 0) &&
     (bVar2 = true, (*(ulong *)(iVar11 + 0x1d8) & 0x30) != 0x30)) {
    bVar2 = false;
  }
  if (fVar15 <= fVar12) {
    iVar6 = *(int *)(iVar11 + 0x8a0);
    if (bVar2) {
      iVar6 = *(int *)(iVar11 + 0x8a0);
      goto LAB_0010262c;
    }
  }
  else {
    iVar6 = *(int *)(iVar11 + 0x8a0);
LAB_0010262c:
    if ((*(int *)(iVar6 + 0x8c4) != 0x2e) && (*(int *)(iVar6 + 0x8c4) != 0x3c)) {
      if (iVar5 != 8) {
        if ((*(ulong *)(iVar11 + 0x1c8) & 0x200000000000) != 0) {
          FUN_0030a468(param_1,0);
          return 1;
        }
        if (((iVar5 == 0x11) || (iVar5 == 0x16)) || (iVar5 == 1)) {
          iVar5 = (**(code **)(*(int *)(iVar11 + 0x5c) + 0x70))(param_1);
          if ((*(uint *)(iVar5 + 8) >> 9 & 1) != 0) {
            return 0;
          }
          uVar10 = (**(code **)(*(int *)(iVar11 + 0x5c) + 0x70))(param_1);
          lVar7 = FUN_00125f78(uVar10);
          if (lVar7 != 0) {
            return 0;
          }
          uVar10 = (**(code **)(*(int *)(iVar11 + 0x5c) + 0x70))(param_1);
          iVar5 = (**(code **)(*(int *)((int)uVar10 + 0x28) + 8))(uVar10);
          if ((*(ulong *)(*(int *)(DAT_00481960 + 8) + iVar5 * 0x40 + 0x28) >> 0x22 & 1) != 0) {
            return 0;
          }
        }
        FUN_001ef918(param_1,1);
        (**(code **)(*(int *)(iVar11 + 0x5c) + 0x80))(param_1,0);
        FUN_001d0970(param_1,*(undefined4 *)(iVar11 + 0x8a0));
        uVar14 = FUN_0044a648(*(float *)(iVar11 + 0x30) -
                              *(float *)(*(int *)(iVar11 + 0x8a0) + 0x30),
                              *(float *)(*(int *)(iVar11 + 0x8a0) + 0x34) -
                              *(float *)(iVar11 + 0x34));
        *(undefined4 *)(iVar11 + 0x8e4) = uVar14;
        uVar14 = FUN_00408058();
        lVar7 = FUN_00443bc8(uVar14,500);
        FUN_00203ba0(param_1,(lVar7 << 1) >> 0x20);
        uVar14 = FUN_00408058();
        lVar7 = FUN_00443bc8(uVar14,0x578);
        FUN_00203a98(param_1,(int)((ulong)(lVar7 << 1) >> 0x20) + 100);
        *(ulong *)(iVar11 + 0x1c8) = *(ulong *)(iVar11 + 0x1c8) & 0xffbfffffffffffff;
        return 0;
      }
      iVar5 = *(int *)(iVar6 + 0x514);
      goto LAB_001027f4;
    }
  }
  iVar5 = *(int *)(iVar6 + 0x514);
LAB_001027f4:
  if (iVar5 == 0) {
    if (*(int *)(iVar11 + 0x514) == 0) {
      iVar5 = *(int *)(iVar11 + 0x8c4);
    }
    else if ((uVar9 & 0x80000000000) == 0) {
      iVar5 = *(int *)(iVar11 + 0x8c4);
    }
    else {
      *(ulong *)(iVar11 + 0x1c8) = *(ulong *)(iVar11 + 0x1c8) & 0xffffffffefffffff;
      *(ulong *)(iVar11 + 0x1d0) = uVar9 & 0xfffff7ffffffffff;
      iVar5 = *(int *)(iVar11 + 0x8c4);
    }
  }
  else {
    iVar5 = *(int *)(iVar11 + 0x8c4);
  }
  if (((iVar5 == 0x10) || (iVar5 == 0x11)) || (iVar5 == 8)) {
    return 0;
  }
  FUN_001ef918(param_1,1);
  if (*(int *)(*(char *)(iVar11 + 0x789) * 0x1c + iVar11 + 0x578) != 0) {
    return 0;
  }
  if (*(int *)(iVar11 + 0x8a0) != 0) {
    if (lVar7 != 0) {
      FUN_001d4320(param_1);
      return 0;
    }
    return 0;
  }
  return 0;
}
