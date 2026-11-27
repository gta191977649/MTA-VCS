
/* WARNING: Removing unreachable block (ram,0x002b09fc) */

void FUN_002b0200(void)

{
  short sVar1;
  undefined4 uVar2;
  bool bVar3;
  int *piVar4;
  int *piVar5;
  byte bVar6;
  float *pfVar7;
  uint uVar8;
  long lVar9;
  ulong uVar10;
  int iVar11;
  int iVar12;
  int iVar13;
  int iVar14;
  float fVar15;
  float fVar16;
  float fVar17;
  float fVar18;
  float fVar19;
  float fVar20;
  float fVar21;
  float fStack_a0;
  float fStack_9c;
  float fStack_98;
  undefined4 uStack_94;
  int *piStack_90;
  
  piVar5 = DAT_00487aac;
  piVar4 = DAT_00487aa4;
  uVar8 = (ushort)DAT_004cd124 & 0x1f;
  piStack_90 = DAT_00487a94;
  pfVar7 = (float *)FUN_0024a458(DAT_004cd128);
  fVar17 = *pfVar7;
  fVar15 = pfVar7[1];
  fVar18 = pfVar7[2];
  iVar11 = piVar4[2];
  iVar14 = uVar8 * iVar11;
  iVar11 = uVar8 * iVar11 + iVar11;
  iVar13 = iVar14 + 0x1f;
  if (-1 < iVar14) {
    iVar13 = iVar14;
  }
  iVar14 = iVar11 + 0x1f;
  if (-1 < iVar11) {
    iVar14 = iVar11;
  }
  iVar13 = iVar13 >> 5;
  if (iVar13 < iVar14 >> 5) {
    do {
      iVar11 = 0;
      if (((-1 < iVar13) && (iVar13 < piVar4[2])) && ((*(byte *)(piVar4[1] + iVar13) & 0x80) == 0))
      {
        iVar11 = *piVar4 + iVar13 * 0x220;
      }
      if ((iVar11 != 0) && (lVar9 = FUN_00131708(iVar11), lVar9 != 0)) {
        fVar16 = *(float *)(iVar11 + 0x30) - fVar17;
        fVar19 = *(float *)(iVar11 + 0x34) - fVar15;
        fVar20 = *(float *)(iVar11 + 0x38) - fVar18;
        fStack_9c = *(float *)(iVar11 + 0x194) - fVar15;
        fStack_a0 = *(float *)(iVar11 + 400) - fVar17;
        fStack_98 = *(float *)(iVar11 + 0x198) - fVar18;
        fVar16 = SQRT(fVar16 * fVar16 + fVar19 * fVar19 + fVar20 * fVar20);
        if (*(char *)(iVar11 + 0x1dc) == '\x03') {
          if (((long)*(short *)(iVar11 + 0x56) == (ulong)*(ushort *)(DAT_0048a040 + 0x44)) ||
             ((fVar19 = fVar16,
              (long)*(short *)(iVar11 + 0x56) == (ulong)*(ushort *)(DAT_0048a040 + 0xf4) &&
              (lVar9 = (**(code **)(*(int *)(iVar11 + 0x5c) + 0x14))(iVar11), lVar9 == 0)))) {
            if (120.0 < fVar16) {
              FUN_0018fa50(iVar11,1);
              iVar12 = *(int *)(iVar11 + 0x5c);
              goto LAB_002b04e0;
            }
          }
          else if (((51.0 < fVar19) ||
                   (((20.0 < fVar19 && (lVar9 = FUN_003c4318(iVar11), lVar9 == 0)) ||
                    (*(uint *)(iVar11 + 0x1d0) < DAT_004cd104)))) &&
                  (FUN_0018fa50(iVar11,1), iVar11 != 0)) {
            iVar12 = *(int *)(iVar11 + 0x5c);
LAB_002b04e0:
            (**(code **)(iVar12 + 0x10))(iVar11,3);
          }
        }
        else if (((80.0 < fVar16) &&
                 (80.0 < SQRT(fStack_a0 * fStack_a0 + fStack_9c * fStack_9c + fStack_98 * fStack_98)
                 )) && ((*(char *)(iVar11 + 0x1dc) != '\x04' &&
                        (lVar9 = FUN_002b12f8(iVar11), lVar9 != 0)))) {
          FUN_002b1070(iVar11);
        }
      }
      iVar13 = iVar13 + 1;
    } while (iVar13 < iVar14 >> 5);
    iVar11 = piVar5[2];
  }
  else {
    iVar11 = piVar5[2];
  }
  iVar14 = uVar8 * iVar11;
  iVar11 = uVar8 * iVar11 + iVar11;
  iVar13 = iVar14 + 0x1f;
  if (-1 < iVar14) {
    iVar13 = iVar14;
  }
  iVar14 = iVar11 + 0x1f;
  if (-1 < iVar11) {
    iVar14 = iVar11;
  }
  iVar13 = iVar13 >> 5;
  if (iVar13 < iVar14 >> 5) {
    fVar16 = 80.0;
    iVar11 = iVar13 * 0x60;
    do {
      iVar12 = 0;
      if (((-1 < iVar13) && (iVar13 < piVar5[2])) && ((*(byte *)(piVar5[1] + iVar13) & 0x80) == 0))
      {
        iVar12 = *piVar5 + iVar11;
      }
      if (iVar12 != 0) {
        fStack_a0 = *(float *)(iVar12 + 0x30) - fVar17;
        fStack_9c = *(float *)(iVar12 + 0x34) - fVar15;
        fStack_98 = *(float *)(iVar12 + 0x38) - fVar18;
        if (SQRT(fStack_a0 * fStack_a0 + fStack_9c * fStack_9c + fStack_98 * fStack_98) < fVar16) {
          FUN_002b0e78();
        }
      }
      iVar13 = iVar13 + 1;
      iVar11 = iVar11 + 0x60;
    } while (iVar13 < iVar14 >> 5);
  }
  iVar11 = piStack_90[2] + -1;
  if (iVar11 != -1) {
    fVar18 = -0.9;
    do {
      if (((iVar11 < 0) || (piStack_90[2] <= iVar11)) ||
         ((*(byte *)(piStack_90[1] + iVar11) & 0x80) != 0)) {
        iVar14 = 0;
      }
      else {
        iVar14 = *piStack_90 + iVar11 * 0xd20;
      }
      if ((((iVar14 != 0) && (lVar9 = FUN_0020c310(iVar14), lVar9 == 0)) &&
          (lVar9 = FUN_001ffa80(iVar14), lVar9 != 0)) && (lVar9 = FUN_00219d50(iVar14), lVar9 == 0))
      {
        iVar13 = DAT_004cd104 - *(int *)(iVar14 + 0x6e8);
        if (*(int *)(iVar14 + 0x8c4) == 0x3a) {
          if (30000 < iVar13) {
            uVar10 = *(ulong *)(iVar14 + 0x1c8);
LAB_002b0770:
            *(ulong *)(iVar14 + 0x1c8) = uVar10 | 0x8000000000000000;
            goto LAB_002b0778;
          }
          lVar9 = FUN_002a9e08();
          if (lVar9 == 0) goto LAB_002b0778;
          uVar10 = *(ulong *)(iVar14 + 0x1c8);
          if (15000 < iVar13) goto LAB_002b0770;
        }
        else {
LAB_002b0778:
          uVar10 = *(ulong *)(iVar14 + 0x1c8);
        }
        if (((uVar10 & 0x8000000000000000) == 0) ||
           (lVar9 = FUN_0036ed68(*(undefined4 *)(iVar14 + 0x50)), lVar9 != 0)) {
          fVar19 = *(float *)(iVar14 + 0x30) - fVar17;
          fVar16 = *(float *)(iVar14 + 0x34) - fVar15;
          fVar16 = SQRT(fVar19 * fVar19 + fVar16 * fVar16);
          bVar3 = false;
          if (*(int *)(iVar14 + 0x550) < 7) {
            uVar10 = *(ulong *)(iVar14 + 0x1d0);
LAB_002b080c:
            if (((uVar10 & 0x40000000) != 0) && (*(int *)(iVar14 + 0x538) != 0)) {
              fVar16 = 0.0;
            }
          }
          else {
            if (0xf < *(int *)(iVar14 + 0x550)) {
              uVar10 = *(ulong *)(iVar14 + 0x1d0);
              goto LAB_002b080c;
            }
            fVar16 = fVar16 - 30.0;
          }
          fVar19 = (float)FUN_002b44c8();
          if ((DAT_006f4ca0 * fVar19 * 65.0 < fVar16) ||
             (((*(ulong *)(iVar14 + 0x1d0) & 4) == 0 &&
              (fVar19 = (float)FUN_002b44c8(), fVar19 * DAT_006f4ca0 * 51.0 < fVar16)))) {
            bVar3 = true;
LAB_002b0970:
            uVar10 = *(ulong *)(iVar14 + 0x48);
          }
          else {
            fVar19 = (float)FUN_002b44c8();
            if (fVar16 <= fVar19 * 20.0) {
              if (*(int *)(iVar14 + 0x550) == 6) {
                iVar13 = DAT_004cd104 + 10000;
              }
              else {
                iVar13 = DAT_004cd104 + 4000;
              }
              *(int *)(iVar14 + 0x4ec) = iVar13;
              goto LAB_002b0970;
            }
            if (*(uint *)(iVar14 + 0x4ec) < DAT_004cd104) {
              lVar9 = FUN_003c4318(iVar14);
              if (lVar9 == 0) {
                iVar13 = (uint)DAT_006f4520 * 0x270;
                sVar1 = *(short *)(&DAT_006f4540 + iVar13);
                if (((sVar1 == 7) || (sVar1 == 0x27)) || (sVar1 == 0x2e)) goto LAB_002b0970;
                if (sVar1 == 0x2f) {
                  uVar10 = *(ulong *)(iVar14 + 0x48);
                }
                else if (*(int *)(&DAT_006f45c8 + iVar13) == 0) {
                  if (*(int *)(&DAT_006f45cc + iVar13) == 0) {
                    bVar3 = *(int *)(&DAT_006f45c4 + iVar13) == 0;
                    goto LAB_002b0970;
                  }
                  uVar10 = *(ulong *)(iVar14 + 0x48);
                }
                else {
                  uVar10 = *(ulong *)(iVar14 + 0x48);
                }
              }
              else {
                uVar10 = *(ulong *)(iVar14 + 0x48);
              }
            }
            else {
              uVar10 = *(ulong *)(iVar14 + 0x48);
            }
          }
          if ((uVar10 & 0x100000000) != 0) {
            bVar3 = false;
          }
          if (bVar3) {
            if ((*(int *)(iVar14 + 0x8c4) == 0x3a) &&
               ((*(ulong *)(iVar14 + 0x1c8) & 0x8000000000000000) == 0)) {
              fStack_a0 = *(float *)(iVar14 + 0x30);
              fStack_9c = *(float *)(iVar14 + 0x34);
              fStack_98 = *(float *)(iVar14 + 0x38);
              uStack_94 = *(undefined4 *)(iVar14 + 0x3c);
              bVar6 = FUN_00408058();
              fVar16 = (float)bVar6 * 0.02453125;
              uVar8 = FUN_00408058();
              uVar8 = (uVar8 & 0xffff) % 3;
              if (uVar8 == 1) {
                fVar20 = (float)FUN_0044a0e0(fVar16);
                fVar19 = (float)FUN_0044a2d0(fVar16);
                fVar19 = fVar19 * 0.9;
                fVar21 = (float)FUN_0044a2d0(fVar16);
                fVar16 = (float)FUN_0044a0e0(fVar16);
                fVar16 = fVar16 * fVar18;
                uVar2 = DAT_00489188;
LAB_002b0ab4:
                FUN_003898e8(fVar20 * 0.9,fVar19,fVar21 * 0.9,fVar16,0x40800000,0x3f800000,1,uVar2,
                             &fStack_a0,0xff,0xff,0xff,0xff,40000);
              }
              else if (uVar8 < 2) {
                if (uVar8 == 0) {
                  fVar20 = (float)FUN_0044a0e0(fVar16);
                  fVar19 = (float)FUN_0044a2d0(fVar16);
                  fVar19 = fVar19 * 0.9;
                  fVar21 = (float)FUN_0044a2d0(fVar16);
                  fVar16 = (float)FUN_0044a0e0(fVar16);
                  fVar16 = fVar16 * fVar18;
                  uVar2 = DAT_00489184;
                  goto LAB_002b0ab4;
                }
              }
              else if (uVar8 == 2) {
                fVar19 = (float)FUN_0044a0e0(fVar16);
                fVar20 = (float)FUN_0044a2d0(fVar16);
                fVar20 = fVar20 * 0.9;
                fVar21 = (float)FUN_0044a2d0(fVar16);
                fVar16 = (float)FUN_0044a0e0(fVar16);
                FUN_003898e8(fVar19 * 0.9,fVar20,fVar21 * 0.9,fVar16 * fVar18,0x40800000,0x3f800000,
                             1,DAT_0048918c,&fStack_a0,0xff,0xff,0xff,0xff,40000);
              }
            }
            if ((*(short *)(iVar14 + 0x56) == -1) || (lVar9 = FUN_003c4318(iVar14), lVar9 == 0)) {
              FUN_002b33a0(iVar14);
            }
            else {
              *(ulong *)(iVar14 + 0x1c8) = *(ulong *)(iVar14 + 0x1c8) | 0x8000000000000000;
            }
          }
        }
        else {
          FUN_002b33a0(iVar14);
        }
      }
      iVar11 = iVar11 + -1;
    } while (iVar11 != -1);
  }
  return;
}

