// Copyright 2021 Google LLC
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree.

#include <xnnpack/assembly.h>

# void xnn_qs8_igemm_minmax_ukernel_1x8c8__aarch64_neon_mlal_padal(
#     size_t mr,                 x0
#     size_t nc,                 x1
#     size_t kc,                 x2 / x0
#     size_t ks,                 x3 / x9
#     const int8_t**restrict a,  x4
#     const int8_t* restrict w,  x5
#     int8_t* restrict c,        x6
#     size_t cm_stride,          x7
#     size_t cn_stride,                  [sp] -> x10
#     size_t a_offset,                   [sp + 8] -> x11
#     const float* zero,                 [sp + 16] -> x12
#     const xnn_f32_minmax_params params [sp + 24] -> x8

# d8-d15, x19-x30 need to be preserved if used. x18 is reserved by the OS.

# Register usage
# A0 x13  v0  v6
# B   x5  v4  v5  v8  v9
# C0  x6 v16 v18 v20 v22 v24 v26 v28 v30
# temp0   v2 v10 v12 v14

BEGIN_FUNCTION xnn_qs8_igemm_minmax_ukernel_1x8c8__aarch64_neon_mlal_padal

        LDP     x10, x11, [sp]        // Load cn_stride, a_offset
        LDP     x12, x8, [sp, 16]     // Load zero, params pointer

        # Save d8,d9,d10,d12,d14 on stack
        STP     d8, d9, [sp, -48]!
        STP     d10, d12, [sp, 16]
        STR     d14, [sp, 32]
        ADD     x2, x2, 7             // kc = (kc + 7) & ~7
        BIC     x2, x2, 7

        .p2align 3
0:
        # Load initial bias from w into accumulators
        LDP     s16, s18, [x5], 8
        LDP     s20, s22, [x5], 8
        LDP     s24, s26, [x5], 8
        LDP     s28, s30, [x5], 8
        MOV     x9, x3  // p = ks

        .p2align 3
1:
        # Load next 2 A pointers
        LDR     x13, [x4], 8

        CMP     x13, x12           // if a0 == zero
        ADD     x13, x13, x11      // a0 += a_offset
        CSEL    x13, x12, x13, EQ  //   a0 = zero, else += a0 + a_offset

        # Is there at least 16 bytes for main loop?
        SUBS    x0, x2, 16          // k = kc - 16
        B.LO    4f

         # Main loop - 16 bytes of A
        .p2align 3
2:
        LDP     d0, d6, [x13], 16
        LDP     d4, d5, [x5]
        LDP     d8, d9, [x5, 64]
        SMULL    v2.8h, v4.8b, v0.8b
        SMULL   v10.8h, v5.8b, v0.8b
        LDP     d4, d5, [x5, 16]
        SMLAL    v2.8h, v8.8b, v6.8b
        SMLAL   v10.8h, v9.8b, v6.8b

        LDP     d8, d9, [x5, 80]
        SMULL   v12.8h, v4.8b, v0.8b
        SADALP  v16.4s,  v2.8h
        SMULL   v14.8h, v5.8b, v0.8b
        SADALP  v18.4s, v10.8h
        LDP     d4, d5, [x5, 32]
        SMLAL   v12.8h, v8.8b, v6.8b
        SMLAL   v14.8h, v9.8b, v6.8b

        LDP     d8, d9, [x5, 96]
        SMULL    v2.8h, v4.8b, v0.8b
        SADALP  v20.4s, v12.8h
        SMULL   v10.8h, v5.8b, v0.8b
        SADALP  v22.4s, v14.8h
        LDP     d4, d5, [x5, 48]
        SMLAL    v2.8h, v8.8b, v6.8b
        SMLAL   v10.8h, v9.8b, v6.8b

        LDP     d8, d9, [x5, 112]
        SMULL   v12.8h, v4.8b, v0.8b
        SADALP  v24.4s,  v2.8h
        SMULL   v14.8h, v5.8b, v0.8b
        SADALP  v26.4s, v10.8h
        SMLAL   v12.8h, v8.8b, v6.8b
        SMLAL   v14.8h, v9.8b, v6.8b
        ADD     x5, x5, 128

        SADALP  v28.4s, v12.8h
        SUBS    x0, x0, 16
        SADALP  v30.4s, v14.8h
        B.HS    2b

        # Is there a remainder?- 8 bytes of A
        TBNZ    x0, 3, 4f

        # ks loop
        SUBS    x9, x9, 8   // ks -= MR * sizeof(int8_t*)
        B.HI    1b

3:
        # Add columns
        ADDP    v16.4s, v16.4s, v18.4s
        ADDP    v20.4s, v20.4s, v22.4s
        LD1R    {v4.4s}, [x8], 4
        ADDP    v24.4s, v24.4s, v26.4s
        ADDP    v28.4s, v28.4s, v30.4s
        LD1R    {v7.4s}, [x8], 4
        ADDP    v0.4s, v16.4s, v20.4s
        ADDP    v1.4s, v24.4s, v28.4s

        # Apply params - scale, shift, bias and clamp
        SQRDMULH        v0.4s, v0.4s, v4.4s
        SQRDMULH        v1.4s, v1.4s, v4.4s
        CMEQ    v4.4s, v7.4s, 0
        LD1R    {v5.8h}, [x8], 2
        BIC      v6.16b, v0.16b, v4.16b
        BIC     v16.16b, v1.16b, v4.16b
        SSRA    v0.4s,  v6.4s, 31
        SSRA    v1.4s, v16.4s, 31
        SRSHL   v0.4s, v0.4s, v7.4s
        SRSHL   v1.4s, v1.4s, v7.4s
        SQXTN   v0.4h, v0.4s
        SQXTN2  v0.8h, v1.4s
        SUBS    x1, x1, 8
        SQADD   v0.8h, v0.8h, v5.8h
        SQXTN   v0.8b, v0.8h
        LD1R    {v1.16b}, [x8], 1
        LD1R    {v2.16b}, [x8]
        SMAX    v0.8b, v0.8b, v1.8b
        SUB     x8, x8, 11       // rewind params pointer
        SMIN    v0.8b, v0.8b, v2.8b
        B.LO    5f

        # Store full 2 x 8
        ST1     {v0.8b}, [x6], x10

        SUB     x4, x4, x3  // a -= ks

        # nc loop
        B.HI    0b

        # Restore d8,d9,d10,d12,d14 from stack
        LDR     d14, [sp, 32]
        LDP     d10, d12, [sp, 16]
        LDP     d8, d9, [sp], 48
        RET

        # Remainder - 8 bytes of A
        .p2align 3
4:
        LDR     d0, [x13]
        LDP     d4, d5, [x5]
        LDP     d6, d7, [x5, 16]
        SMULL    v2.8h, v4.8b, v0.8b
        SMULL   v10.8h, v5.8b, v0.8b
        SMULL   v12.8h, v6.8b, v0.8b
        SADALP  v16.4s,  v2.8h
        SMULL   v14.8h, v7.8b, v0.8b
        SADALP  v18.4s, v10.8h
        LDP     d4, d5, [x5, 32]
        SMULL    v2.8h, v4.8b, v0.8b
        SADALP  v20.4s, v12.8h
        SMULL   v10.8h, v5.8b, v0.8b
        SADALP  v22.4s, v14.8h
        LDP     d6, d7, [x5, 48]
        SMULL   v12.8h, v6.8b, v0.8b
        SADALP  v24.4s,  v2.8h
        SMULL   v14.8h, v7.8b, v0.8b
        SADALP  v26.4s, v10.8h
        ADD     x5, x5, 64
        SADALP  v28.4s, v12.8h
        SADALP  v30.4s, v14.8h

        # ks loop
        SUBS    x9, x9, 8  // ks -= MR * sizeof(int8_t*)
        B.HI    1b
        B       3b

        # Store odd width
        .p2align 3
5:
        TBZ     x1, 2, 6f
        STR     s0, [x6], 4
        EXT     v0.16b, v0.16b, v0.16b, 4

6:
        TBZ     x1, 1, 7f
        ST1     {v0.h}[0], [x6], 2
        EXT     v0.16b, v0.16b, v0.16b, 2
7:
        TBZ     x1, 0, 8f
        ST1     {v0.b}[0], [x6]
8:
        # Restore d8,d9,d10,d12,d14 from stack
        LDR     d14, [sp, 32]
        LDP     d10, d12, [sp, 16]
        LDP     d8, d9, [sp], 48
        RET

END_FUNCTION xnn_qs8_igemm_minmax_ukernel_1x8c8__aarch64_neon_mlal_padal

#ifdef __ELF__
.section ".note.GNU-stack","",%progbits
#endif
