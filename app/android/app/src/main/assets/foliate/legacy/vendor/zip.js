const e = -2, t = -3, n = -5, i = [0, 1, 3, 7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095, 8191, 16383, 32767, 65535], r = [96, 7, 256, 0, 8, 80, 0, 8, 16, 84, 8, 115, 82, 7, 31, 0, 8, 112, 0, 8, 48, 0, 9, 192, 80, 7, 10, 0, 8, 96, 0, 8, 32, 0, 9, 160, 0, 8, 0, 0, 8, 128, 0, 8, 64, 0, 9, 224, 80, 7, 6, 0, 8, 88, 0, 8, 24, 0, 9, 144, 83, 7, 59, 0, 8, 120, 0, 8, 56, 0, 9, 208, 81, 7, 17, 0, 8, 104, 0, 8, 40, 0, 9, 176, 0, 8, 8, 0, 8, 136, 0, 8, 72, 0, 9, 240, 80, 7, 4, 0, 8, 84, 0, 8, 20, 85, 8, 227, 83, 7, 43, 0, 8, 116, 0, 8, 52, 0, 9, 200, 81, 7, 13, 0, 8, 100, 0, 8, 36, 0, 9, 168, 0, 8, 4, 0, 8, 132, 0, 8, 68, 0, 9, 232, 80, 7, 8, 0, 8, 92, 0, 8, 28, 0, 9, 152, 84, 7, 83, 0, 8, 124, 0, 8, 60, 0, 9, 216, 82, 7, 23, 0, 8, 108, 0, 8, 44, 0, 9, 184, 0, 8, 12, 0, 8, 140, 0, 8, 76, 0, 9, 248, 80, 7, 3, 0, 8, 82, 0, 8, 18, 85, 8, 163, 83, 7, 35, 0, 8, 114, 0, 8, 50, 0, 9, 196, 81, 7, 11, 0, 8, 98, 0, 8, 34, 0, 9, 164, 0, 8, 2, 0, 8, 130, 0, 8, 66, 0, 9, 228, 80, 7, 7, 0, 8, 90, 0, 8, 26, 0, 9, 148, 84, 7, 67, 0, 8, 122, 0, 8, 58, 0, 9, 212, 82, 7, 19, 0, 8, 106, 0, 8, 42, 0, 9, 180, 0, 8, 10, 0, 8, 138, 0, 8, 74, 0, 9, 244, 80, 7, 5, 0, 8, 86, 0, 8, 22, 192, 8, 0, 83, 7, 51, 0, 8, 118, 0, 8, 54, 0, 9, 204, 81, 7, 15, 0, 8, 102, 0, 8, 38, 0, 9, 172, 0, 8, 6, 0, 8, 134, 0, 8, 70, 0, 9, 236, 80, 7, 9, 0, 8, 94, 0, 8, 30, 0, 9, 156, 84, 7, 99, 0, 8, 126, 0, 8, 62, 0, 9, 220, 82, 7, 27, 0, 8, 110, 0, 8, 46, 0, 9, 188, 0, 8, 14, 0, 8, 142, 0, 8, 78, 0, 9, 252, 96, 7, 256, 0, 8, 81, 0, 8, 17, 85, 8, 131, 82, 7, 31, 0, 8, 113, 0, 8, 49, 0, 9, 194, 80, 7, 10, 0, 8, 97, 0, 8, 33, 0, 9, 162, 0, 8, 1, 0, 8, 129, 0, 8, 65, 0, 9, 226, 80, 7, 6, 0, 8, 89, 0, 8, 25, 0, 9, 146, 83, 7, 59, 0, 8, 121, 0, 8, 57, 0, 9, 210, 81, 7, 17, 0, 8, 105, 0, 8, 41, 0, 9, 178, 0, 8, 9, 0, 8, 137, 0, 8, 73, 0, 9, 242, 80, 7, 4, 0, 8, 85, 0, 8, 21, 80, 8, 258, 83, 7, 43, 0, 8, 117, 0, 8, 53, 0, 9, 202, 81, 7, 13, 0, 8, 101, 0, 8, 37, 0, 9, 170, 0, 8, 5, 0, 8, 133, 0, 8, 69, 0, 9, 234, 80, 7, 8, 0, 8, 93, 0, 8, 29, 0, 9, 154, 84, 7, 83, 0, 8, 125, 0, 8, 61, 0, 9, 218, 82, 7, 23, 0, 8, 109, 0, 8, 45, 0, 9, 186, 0, 8, 13, 0, 8, 141, 0, 8, 77, 0, 9, 250, 80, 7, 3, 0, 8, 83, 0, 8, 19, 85, 8, 195, 83, 7, 35, 0, 8, 115, 0, 8, 51, 0, 9, 198, 81, 7, 11, 0, 8, 99, 0, 8, 35, 0, 9, 166, 0, 8, 3, 0, 8, 131, 0, 8, 67, 0, 9, 230, 80, 7, 7, 0, 8, 91, 0, 8, 27, 0, 9, 150, 84, 7, 67, 0, 8, 123, 0, 8, 59, 0, 9, 214, 82, 7, 19, 0, 8, 107, 0, 8, 43, 0, 9, 182, 0, 8, 11, 0, 8, 139, 0, 8, 75, 0, 9, 246, 80, 7, 5, 0, 8, 87, 0, 8, 23, 192, 8, 0, 83, 7, 51, 0, 8, 119, 0, 8, 55, 0, 9, 206, 81, 7, 15, 0, 8, 103, 0, 8, 39, 0, 9, 174, 0, 8, 7, 0, 8, 135, 0, 8, 71, 0, 9, 238, 80, 7, 9, 0, 8, 95, 0, 8, 31, 0, 9, 158, 84, 7, 99, 0, 8, 127, 0, 8, 63, 0, 9, 222, 82, 7, 27, 0, 8, 111, 0, 8, 47, 0, 9, 190, 0, 8, 15, 0, 8, 143, 0, 8, 79, 0, 9, 254, 96, 7, 256, 0, 8, 80, 0, 8, 16, 84, 8, 115, 82, 7, 31, 0, 8, 112, 0, 8, 48, 0, 9, 193, 80, 7, 10, 0, 8, 96, 0, 8, 32, 0, 9, 161, 0, 8, 0, 0, 8, 128, 0, 8, 64, 0, 9, 225, 80, 7, 6, 0, 8, 88, 0, 8, 24, 0, 9, 145, 83, 7, 59, 0, 8, 120, 0, 8, 56, 0, 9, 209, 81, 7, 17, 0, 8, 104, 0, 8, 40, 0, 9, 177, 0, 8, 8, 0, 8, 136, 0, 8, 72, 0, 9, 241, 80, 7, 4, 0, 8, 84, 0, 8, 20, 85, 8, 227, 83, 7, 43, 0, 8, 116, 0, 8, 52, 0, 9, 201, 81, 7, 13, 0, 8, 100, 0, 8, 36, 0, 9, 169, 0, 8, 4, 0, 8, 132, 0, 8, 68, 0, 9, 233, 80, 7, 8, 0, 8, 92, 0, 8, 28, 0, 9, 153, 84, 7, 83, 0, 8, 124, 0, 8, 60, 0, 9, 217, 82, 7, 23, 0, 8, 108, 0, 8, 44, 0, 9, 185, 0, 8, 12, 0, 8, 140, 0, 8, 76, 0, 9, 249, 80, 7, 3, 0, 8, 82, 0, 8, 18, 85, 8, 163, 83, 7, 35, 0, 8, 114, 0, 8, 50, 0, 9, 197, 81, 7, 11, 0, 8, 98, 0, 8, 34, 0, 9, 165, 0, 8, 2, 0, 8, 130, 0, 8, 66, 0, 9, 229, 80, 7, 7, 0, 8, 90, 0, 8, 26, 0, 9, 149, 84, 7, 67, 0, 8, 122, 0, 8, 58, 0, 9, 213, 82, 7, 19, 0, 8, 106, 0, 8, 42, 0, 9, 181, 0, 8, 10, 0, 8, 138, 0, 8, 74, 0, 9, 245, 80, 7, 5, 0, 8, 86, 0, 8, 22, 192, 8, 0, 83, 7, 51, 0, 8, 118, 0, 8, 54, 0, 9, 205, 81, 7, 15, 0, 8, 102, 0, 8, 38, 0, 9, 173, 0, 8, 6, 0, 8, 134, 0, 8, 70, 0, 9, 237, 80, 7, 9, 0, 8, 94, 0, 8, 30, 0, 9, 157, 84, 7, 99, 0, 8, 126, 0, 8, 62, 0, 9, 221, 82, 7, 27, 0, 8, 110, 0, 8, 46, 0, 9, 189, 0, 8, 14, 0, 8, 142, 0, 8, 78, 0, 9, 253, 96, 7, 256, 0, 8, 81, 0, 8, 17, 85, 8, 131, 82, 7, 31, 0, 8, 113, 0, 8, 49, 0, 9, 195, 80, 7, 10, 0, 8, 97, 0, 8, 33, 0, 9, 163, 0, 8, 1, 0, 8, 129, 0, 8, 65, 0, 9, 227, 80, 7, 6, 0, 8, 89, 0, 8, 25, 0, 9, 147, 83, 7, 59, 0, 8, 121, 0, 8, 57, 0, 9, 211, 81, 7, 17, 0, 8, 105, 0, 8, 41, 0, 9, 179, 0, 8, 9, 0, 8, 137, 0, 8, 73, 0, 9, 243, 80, 7, 4, 0, 8, 85, 0, 8, 21, 80, 8, 258, 83, 7, 43, 0, 8, 117, 0, 8, 53, 0, 9, 203, 81, 7, 13, 0, 8, 101, 0, 8, 37, 0, 9, 171, 0, 8, 5, 0, 8, 133, 0, 8, 69, 0, 9, 235, 80, 7, 8, 0, 8, 93, 0, 8, 29, 0, 9, 155, 84, 7, 83, 0, 8, 125, 0, 8, 61, 0, 9, 219, 82, 7, 23, 0, 8, 109, 0, 8, 45, 0, 9, 187, 0, 8, 13, 0, 8, 141, 0, 8, 77, 0, 9, 251, 80, 7, 3, 0, 8, 83, 0, 8, 19, 85, 8, 195, 83, 7, 35, 0, 8, 115, 0, 8, 51, 0, 9, 199, 81, 7, 11, 0, 8, 99, 0, 8, 35, 0, 9, 167, 0, 8, 3, 0, 8, 131, 0, 8, 67, 0, 9, 231, 80, 7, 7, 0, 8, 91, 0, 8, 27, 0, 9, 151, 84, 7, 67, 0, 8, 123, 0, 8, 59, 0, 9, 215, 82, 7, 19, 0, 8, 107, 0, 8, 43, 0, 9, 183, 0, 8, 11, 0, 8, 139, 0, 8, 75, 0, 9, 247, 80, 7, 5, 0, 8, 87, 0, 8, 23, 192, 8, 0, 83, 7, 51, 0, 8, 119, 0, 8, 55, 0, 9, 207, 81, 7, 15, 0, 8, 103, 0, 8, 39, 0, 9, 175, 0, 8, 7, 0, 8, 135, 0, 8, 71, 0, 9, 239, 80, 7, 9, 0, 8, 95, 0, 8, 31, 0, 9, 159, 84, 7, 99, 0, 8, 127, 0, 8, 63, 0, 9, 223, 82, 7, 27, 0, 8, 111, 0, 8, 47, 0, 9, 191, 0, 8, 15, 0, 8, 143, 0, 8, 79, 0, 9, 255], a = [80, 5, 1, 87, 5, 257, 83, 5, 17, 91, 5, 4097, 81, 5, 5, 89, 5, 1025, 85, 5, 65, 93, 5, 16385, 80, 5, 3, 88, 5, 513, 84, 5, 33, 92, 5, 8193, 82, 5, 9, 90, 5, 2049, 86, 5, 129, 192, 5, 24577, 80, 5, 2, 87, 5, 385, 83, 5, 25, 91, 5, 6145, 81, 5, 7, 89, 5, 1537, 85, 5, 97, 93, 5, 24577, 80, 5, 4, 88, 5, 769, 84, 5, 49, 92, 5, 12289, 82, 5, 13, 90, 5, 3073, 86, 5, 193, 192, 5, 24577], s = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258, 0, 0], o = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0, 112, 112], l = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577], c = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13], u = 15;
function d() {
  let e2, i2, r2, a2, d2, f2;
  function h2(e3, i3, s2, o2, l2, c2, h3, w3, _2, b2, p2) {
    let m2, g2, y2, x2, k2, v2, S2, z2, A2, U2, D2, E2, T2, F2, O2;
    U2 = 0, k2 = s2;
    do {
      r2[e3[i3 + U2]]++, U2++, k2--;
    } while (0 !== k2);
    if (r2[0] == s2) return h3[0] = -1, w3[0] = 0, 0;
    for (z2 = w3[0], v2 = 1; v2 <= u && 0 === r2[v2]; v2++) ;
    for (S2 = v2, z2 < v2 && (z2 = v2), k2 = u; 0 !== k2 && 0 === r2[k2]; k2--) ;
    for (y2 = k2, z2 > k2 && (z2 = k2), w3[0] = z2, F2 = 1 << v2; v2 < k2; v2++, F2 <<= 1) if ((F2 -= r2[v2]) < 0) return t;
    if ((F2 -= r2[k2]) < 0) return t;
    for (r2[k2] += F2, f2[1] = v2 = 0, U2 = 1, T2 = 2; 0 != --k2; ) f2[T2] = v2 += r2[U2], T2++, U2++;
    k2 = 0, U2 = 0;
    do {
      0 !== (v2 = e3[i3 + U2]) && (p2[f2[v2]++] = k2), U2++;
    } while (++k2 < s2);
    for (s2 = f2[y2], f2[0] = k2 = 0, U2 = 0, x2 = -1, E2 = -z2, d2[0] = 0, D2 = 0, O2 = 0; S2 <= y2; S2++) for (m2 = r2[S2]; 0 != m2--; ) {
      for (; S2 > E2 + z2; ) {
        if (x2++, E2 += z2, O2 = y2 - E2, O2 = O2 > z2 ? z2 : O2, (g2 = 1 << (v2 = S2 - E2)) > m2 + 1 && (g2 -= m2 + 1, T2 = S2, v2 < O2)) for (; ++v2 < O2 && !((g2 <<= 1) <= r2[++T2]); ) g2 -= r2[T2];
        if (O2 = 1 << v2, b2[0] + O2 > 1440) return t;
        d2[x2] = D2 = b2[0], b2[0] += O2, 0 !== x2 ? (f2[x2] = k2, a2[0] = v2, a2[1] = z2, v2 = k2 >>> E2 - z2, a2[2] = D2 - d2[x2 - 1] - v2, _2.set(a2, 3 * (d2[x2 - 1] + v2))) : h3[0] = D2;
      }
      for (a2[1] = S2 - E2, U2 >= s2 ? a2[0] = 192 : p2[U2] < o2 ? (a2[0] = p2[U2] < 256 ? 0 : 96, a2[2] = p2[U2++]) : (a2[0] = c2[p2[U2] - o2] + 16 + 64, a2[2] = l2[p2[U2++] - o2]), g2 = 1 << S2 - E2, v2 = k2 >>> E2; v2 < O2; v2 += g2) _2.set(a2, 3 * (D2 + v2));
      for (v2 = 1 << S2 - 1; k2 & v2; v2 >>>= 1) k2 ^= v2;
      for (k2 ^= v2, A2 = (1 << E2) - 1; (k2 & A2) != f2[x2]; ) x2--, E2 -= z2, A2 = (1 << E2) - 1;
    }
    return 0 !== F2 && 1 != y2 ? n : 0;
  }
  function w2(t2) {
    let n2;
    for (e2 || (e2 = [], i2 = [], r2 = new Int32Array(16), a2 = [], d2 = new Int32Array(u), f2 = new Int32Array(16)), i2.length < t2 && (i2 = []), n2 = 0; n2 < t2; n2++) i2[n2] = 0;
    for (n2 = 0; n2 < 16; n2++) r2[n2] = 0;
    for (n2 = 0; n2 < 3; n2++) a2[n2] = 0;
    d2.set(r2.subarray(0, u), 0), f2.set(r2.subarray(0, 16), 0);
  }
  this.inflate_trees_bits = function(r3, a3, s2, o2, l2) {
    let c2;
    return w2(19), e2[0] = 0, c2 = h2(r3, 0, 19, 19, null, null, s2, a3, o2, e2, i2), c2 == t ? l2.msg = "oversubscribed dynamic bit lengths tree" : c2 != n && 0 !== a3[0] || (l2.msg = "incomplete dynamic bit lengths tree", c2 = t), c2;
  }, this.inflate_trees_dynamic = function(r3, a3, u2, d3, f3, _2, b2, p2, m2) {
    let g2;
    return w2(288), e2[0] = 0, g2 = h2(u2, 0, r3, 257, s, o, _2, d3, p2, e2, i2), 0 != g2 || 0 === d3[0] ? (g2 == t ? m2.msg = "oversubscribed literal/length tree" : -4 != g2 && (m2.msg = "incomplete literal/length tree", g2 = t), g2) : (w2(288), g2 = h2(u2, r3, a3, 0, l, c, b2, f3, p2, e2, i2), 0 != g2 || 0 === f3[0] && r3 > 257 ? (g2 == t ? m2.msg = "oversubscribed distance tree" : g2 == n ? (m2.msg = "incomplete distance tree", g2 = t) : -4 != g2 && (m2.msg = "empty distance tree with lengths", g2 = t), g2) : 0);
  };
}
d.inflate_trees_fixed = function(e2, t2, n2, i2) {
  return e2[0] = 9, t2[0] = 5, n2[0] = r, i2[0] = a, 0;
};
function f() {
  const n2 = this;
  let r2, a2, s2, o2, l2 = 0, c2 = 0, u2 = 0, d2 = 0, f2 = 0, h2 = 0, w2 = 0, _2 = 0, b2 = 0, p2 = 0;
  function m2(e2, n3, r3, a3, s3, o3, l3, c3) {
    let u3, d3, f3, h3, w3, _3, b3, p3, m3, g2, y2, x2, k2, v2, S2, z2;
    b3 = c3.next_in_index, p3 = c3.avail_in, w3 = l3.bitb, _3 = l3.bitk, m3 = l3.write, g2 = m3 < l3.read ? l3.read - m3 - 1 : l3.end - m3, y2 = i[e2], x2 = i[n3];
    do {
      for (; _3 < 20; ) p3--, w3 |= (255 & c3.read_byte(b3++)) << _3, _3 += 8;
      if (u3 = w3 & y2, d3 = r3, f3 = a3, z2 = 3 * (f3 + u3), 0 !== (h3 = d3[z2])) for (; ; ) {
        if (w3 >>= d3[z2 + 1], _3 -= d3[z2 + 1], 16 & h3) {
          for (h3 &= 15, k2 = d3[z2 + 2] + (w3 & i[h3]), w3 >>= h3, _3 -= h3; _3 < 15; ) p3--, w3 |= (255 & c3.read_byte(b3++)) << _3, _3 += 8;
          for (u3 = w3 & x2, d3 = s3, f3 = o3, z2 = 3 * (f3 + u3), h3 = d3[z2]; ; ) {
            if (w3 >>= d3[z2 + 1], _3 -= d3[z2 + 1], 16 & h3) {
              for (h3 &= 15; _3 < h3; ) p3--, w3 |= (255 & c3.read_byte(b3++)) << _3, _3 += 8;
              if (v2 = d3[z2 + 2] + (w3 & i[h3]), w3 >>= h3, _3 -= h3, g2 -= k2, m3 >= v2) S2 = m3 - v2, m3 - S2 > 0 && 2 > m3 - S2 ? (l3.win[m3++] = l3.win[S2++], l3.win[m3++] = l3.win[S2++], k2 -= 2) : (l3.win.set(l3.win.subarray(S2, S2 + 2), m3), m3 += 2, S2 += 2, k2 -= 2);
              else {
                S2 = m3 - v2;
                do {
                  S2 += l3.end;
                } while (S2 < 0);
                if (h3 = l3.end - S2, k2 > h3) {
                  if (k2 -= h3, m3 - S2 > 0 && h3 > m3 - S2) do {
                    l3.win[m3++] = l3.win[S2++];
                  } while (0 != --h3);
                  else l3.win.set(l3.win.subarray(S2, S2 + h3), m3), m3 += h3, S2 += h3, h3 = 0;
                  S2 = 0;
                }
              }
              if (m3 - S2 > 0 && k2 > m3 - S2) do {
                l3.win[m3++] = l3.win[S2++];
              } while (0 != --k2);
              else l3.win.set(l3.win.subarray(S2, S2 + k2), m3), m3 += k2, S2 += k2, k2 = 0;
              break;
            }
            if (64 & h3) return c3.msg = "invalid distance code", k2 = c3.avail_in - p3, k2 = _3 >> 3 < k2 ? _3 >> 3 : k2, p3 += k2, b3 -= k2, _3 -= k2 << 3, l3.bitb = w3, l3.bitk = _3, c3.avail_in = p3, c3.total_in += b3 - c3.next_in_index, c3.next_in_index = b3, l3.write = m3, t;
            u3 += d3[z2 + 2], u3 += w3 & i[h3], z2 = 3 * (f3 + u3), h3 = d3[z2];
          }
          break;
        }
        if (64 & h3) return 32 & h3 ? (k2 = c3.avail_in - p3, k2 = _3 >> 3 < k2 ? _3 >> 3 : k2, p3 += k2, b3 -= k2, _3 -= k2 << 3, l3.bitb = w3, l3.bitk = _3, c3.avail_in = p3, c3.total_in += b3 - c3.next_in_index, c3.next_in_index = b3, l3.write = m3, 1) : (c3.msg = "invalid literal/length code", k2 = c3.avail_in - p3, k2 = _3 >> 3 < k2 ? _3 >> 3 : k2, p3 += k2, b3 -= k2, _3 -= k2 << 3, l3.bitb = w3, l3.bitk = _3, c3.avail_in = p3, c3.total_in += b3 - c3.next_in_index, c3.next_in_index = b3, l3.write = m3, t);
        if (u3 += d3[z2 + 2], u3 += w3 & i[h3], z2 = 3 * (f3 + u3), 0 === (h3 = d3[z2])) {
          w3 >>= d3[z2 + 1], _3 -= d3[z2 + 1], l3.win[m3++] = d3[z2 + 2], g2--;
          break;
        }
      }
      else w3 >>= d3[z2 + 1], _3 -= d3[z2 + 1], l3.win[m3++] = d3[z2 + 2], g2--;
    } while (g2 >= 258 && p3 >= 10);
    return k2 = c3.avail_in - p3, k2 = _3 >> 3 < k2 ? _3 >> 3 : k2, p3 += k2, b3 -= k2, _3 -= k2 << 3, l3.bitb = w3, l3.bitk = _3, c3.avail_in = p3, c3.total_in += b3 - c3.next_in_index, c3.next_in_index = b3, l3.write = m3, 0;
  }
  n2.init = function(e2, t2, n3, i2, l3, c3) {
    r2 = 0, w2 = e2, _2 = t2, s2 = n3, b2 = i2, o2 = l3, p2 = c3, a2 = null;
  }, n2.proc = function(n3, g2, y2) {
    let x2, k2, v2, S2, z2, A2, U2, D2 = 0, E2 = 0, T2 = 0;
    for (T2 = g2.next_in_index, S2 = g2.avail_in, D2 = n3.bitb, E2 = n3.bitk, z2 = n3.write, A2 = z2 < n3.read ? n3.read - z2 - 1 : n3.end - z2; ; ) switch (r2) {
      case 0:
        if (A2 >= 258 && S2 >= 10 && (n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, y2 = m2(w2, _2, s2, b2, o2, p2, n3, g2), T2 = g2.next_in_index, S2 = g2.avail_in, D2 = n3.bitb, E2 = n3.bitk, z2 = n3.write, A2 = z2 < n3.read ? n3.read - z2 - 1 : n3.end - z2, 0 != y2)) {
          r2 = 1 == y2 ? 7 : 9;
          break;
        }
        u2 = w2, a2 = s2, c2 = b2, r2 = 1;
      case 1:
        for (x2 = u2; E2 < x2; ) {
          if (0 === S2) return n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
          y2 = 0, S2--, D2 |= (255 & g2.read_byte(T2++)) << E2, E2 += 8;
        }
        if (k2 = 3 * (c2 + (D2 & i[x2])), D2 >>>= a2[k2 + 1], E2 -= a2[k2 + 1], v2 = a2[k2], 0 === v2) {
          d2 = a2[k2 + 2], r2 = 6;
          break;
        }
        if (16 & v2) {
          f2 = 15 & v2, l2 = a2[k2 + 2], r2 = 2;
          break;
        }
        if (!(64 & v2)) {
          u2 = v2, c2 = k2 / 3 + a2[k2 + 2];
          break;
        }
        if (32 & v2) {
          r2 = 7;
          break;
        }
        return r2 = 9, g2.msg = "invalid literal/length code", y2 = t, n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
      case 2:
        for (x2 = f2; E2 < x2; ) {
          if (0 === S2) return n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
          y2 = 0, S2--, D2 |= (255 & g2.read_byte(T2++)) << E2, E2 += 8;
        }
        l2 += D2 & i[x2], D2 >>= x2, E2 -= x2, u2 = _2, a2 = o2, c2 = p2, r2 = 3;
      case 3:
        for (x2 = u2; E2 < x2; ) {
          if (0 === S2) return n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
          y2 = 0, S2--, D2 |= (255 & g2.read_byte(T2++)) << E2, E2 += 8;
        }
        if (k2 = 3 * (c2 + (D2 & i[x2])), D2 >>= a2[k2 + 1], E2 -= a2[k2 + 1], v2 = a2[k2], 16 & v2) {
          f2 = 15 & v2, h2 = a2[k2 + 2], r2 = 4;
          break;
        }
        if (!(64 & v2)) {
          u2 = v2, c2 = k2 / 3 + a2[k2 + 2];
          break;
        }
        return r2 = 9, g2.msg = "invalid distance code", y2 = t, n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
      case 4:
        for (x2 = f2; E2 < x2; ) {
          if (0 === S2) return n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
          y2 = 0, S2--, D2 |= (255 & g2.read_byte(T2++)) << E2, E2 += 8;
        }
        h2 += D2 & i[x2], D2 >>= x2, E2 -= x2, r2 = 5;
      case 5:
        for (U2 = z2 - h2; U2 < 0; ) U2 += n3.end;
        for (; 0 !== l2; ) {
          if (0 === A2 && (z2 == n3.end && 0 !== n3.read && (z2 = 0, A2 = z2 < n3.read ? n3.read - z2 - 1 : n3.end - z2), 0 === A2 && (n3.write = z2, y2 = n3.inflate_flush(g2, y2), z2 = n3.write, A2 = z2 < n3.read ? n3.read - z2 - 1 : n3.end - z2, z2 == n3.end && 0 !== n3.read && (z2 = 0, A2 = z2 < n3.read ? n3.read - z2 - 1 : n3.end - z2), 0 === A2))) return n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
          n3.win[z2++] = n3.win[U2++], A2--, U2 == n3.end && (U2 = 0), l2--;
        }
        r2 = 0;
        break;
      case 6:
        if (0 === A2 && (z2 == n3.end && 0 !== n3.read && (z2 = 0, A2 = z2 < n3.read ? n3.read - z2 - 1 : n3.end - z2), 0 === A2 && (n3.write = z2, y2 = n3.inflate_flush(g2, y2), z2 = n3.write, A2 = z2 < n3.read ? n3.read - z2 - 1 : n3.end - z2, z2 == n3.end && 0 !== n3.read && (z2 = 0, A2 = z2 < n3.read ? n3.read - z2 - 1 : n3.end - z2), 0 === A2))) return n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
        y2 = 0, n3.win[z2++] = d2, A2--, r2 = 0;
        break;
      case 7:
        if (E2 > 7 && (E2 -= 8, S2++, T2--), n3.write = z2, y2 = n3.inflate_flush(g2, y2), z2 = n3.write, A2 = z2 < n3.read ? n3.read - z2 - 1 : n3.end - z2, n3.read != n3.write) return n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
        r2 = 8;
      case 8:
        return y2 = 1, n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
      case 9:
        return y2 = t, n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
      default:
        return y2 = e, n3.bitb = D2, n3.bitk = E2, g2.avail_in = S2, g2.total_in += T2 - g2.next_in_index, g2.next_in_index = T2, n3.write = z2, n3.inflate_flush(g2, y2);
    }
  }, n2.free = function() {
  };
}
const h = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];
function w(r2, a2) {
  const s2 = this;
  let o2, l2 = 0, c2 = 0, u2 = 0, w2 = 0;
  const _2 = [0], b2 = [0], p2 = new f();
  let m2 = 0, g2 = new Int32Array(4320);
  const y2 = new d();
  s2.bitk = 0, s2.bitb = 0, s2.win = new Uint8Array(a2), s2.end = a2, s2.read = 0, s2.write = 0, s2.reset = function(e2, t2) {
    t2 && (t2[0] = 0), 6 == l2 && p2.free(e2), l2 = 0, s2.bitk = 0, s2.bitb = 0, s2.read = s2.write = 0;
  }, s2.reset(r2, null), s2.inflate_flush = function(e2, t2) {
    let i2, r3, a3;
    return r3 = e2.next_out_index, a3 = s2.read, i2 = (a3 <= s2.write ? s2.write : s2.end) - a3, i2 > e2.avail_out && (i2 = e2.avail_out), 0 !== i2 && t2 == n && (t2 = 0), e2.avail_out -= i2, e2.total_out += i2, e2.next_out.set(s2.win.subarray(a3, a3 + i2), r3), r3 += i2, a3 += i2, a3 == s2.end && (a3 = 0, s2.write == s2.end && (s2.write = 0), i2 = s2.write - a3, i2 > e2.avail_out && (i2 = e2.avail_out), 0 !== i2 && t2 == n && (t2 = 0), e2.avail_out -= i2, e2.total_out += i2, e2.next_out.set(s2.win.subarray(a3, a3 + i2), r3), r3 += i2, a3 += i2), e2.next_out_index = r3, s2.read = a3, t2;
  }, s2.proc = function(n2, r3) {
    let a3, f2, x2, k2, v2, S2, z2, A2;
    for (k2 = n2.next_in_index, v2 = n2.avail_in, f2 = s2.bitb, x2 = s2.bitk, S2 = s2.write, z2 = S2 < s2.read ? s2.read - S2 - 1 : s2.end - S2; ; ) {
      let U2, D2, E2, T2, F2, O2, C2, W2;
      switch (l2) {
        case 0:
          for (; x2 < 3; ) {
            if (0 === v2) return s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
            r3 = 0, v2--, f2 |= (255 & n2.read_byte(k2++)) << x2, x2 += 8;
          }
          switch (a3 = 7 & f2, m2 = 1 & a3, a3 >>> 1) {
            case 0:
              f2 >>>= 3, x2 -= 3, a3 = 7 & x2, f2 >>>= a3, x2 -= a3, l2 = 1;
              break;
            case 1:
              U2 = [], D2 = [], E2 = [[]], T2 = [[]], d.inflate_trees_fixed(U2, D2, E2, T2), p2.init(U2[0], D2[0], E2[0], 0, T2[0], 0), f2 >>>= 3, x2 -= 3, l2 = 6;
              break;
            case 2:
              f2 >>>= 3, x2 -= 3, l2 = 3;
              break;
            case 3:
              return f2 >>>= 3, x2 -= 3, l2 = 9, n2.msg = "invalid block type", r3 = t, s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
          }
          break;
        case 1:
          for (; x2 < 32; ) {
            if (0 === v2) return s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
            r3 = 0, v2--, f2 |= (255 & n2.read_byte(k2++)) << x2, x2 += 8;
          }
          if ((~f2 >>> 16 & 65535) != (65535 & f2)) return l2 = 9, n2.msg = "invalid stored block lengths", r3 = t, s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
          c2 = 65535 & f2, f2 = x2 = 0, l2 = 0 !== c2 ? 2 : 0 !== m2 ? 7 : 0;
          break;
        case 2:
          if (0 === v2) return s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
          if (0 === z2 && (S2 == s2.end && 0 !== s2.read && (S2 = 0, z2 = S2 < s2.read ? s2.read - S2 - 1 : s2.end - S2), 0 === z2 && (s2.write = S2, r3 = s2.inflate_flush(n2, r3), S2 = s2.write, z2 = S2 < s2.read ? s2.read - S2 - 1 : s2.end - S2, S2 == s2.end && 0 !== s2.read && (S2 = 0, z2 = S2 < s2.read ? s2.read - S2 - 1 : s2.end - S2), 0 === z2))) return s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
          if (r3 = 0, a3 = c2, a3 > v2 && (a3 = v2), a3 > z2 && (a3 = z2), s2.win.set(n2.read_buf(k2, a3), S2), k2 += a3, v2 -= a3, S2 += a3, z2 -= a3, 0 != (c2 -= a3)) break;
          l2 = 0 !== m2 ? 7 : 0;
          break;
        case 3:
          for (; x2 < 14; ) {
            if (0 === v2) return s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
            r3 = 0, v2--, f2 |= (255 & n2.read_byte(k2++)) << x2, x2 += 8;
          }
          if (u2 = a3 = 16383 & f2, (31 & a3) > 29 || (a3 >> 5 & 31) > 29) return l2 = 9, n2.msg = "too many length or distance symbols", r3 = t, s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
          if (a3 = 258 + (31 & a3) + (a3 >> 5 & 31), !o2 || o2.length < a3) o2 = [];
          else for (A2 = 0; A2 < a3; A2++) o2[A2] = 0;
          f2 >>>= 14, x2 -= 14, w2 = 0, l2 = 4;
        case 4:
          for (; w2 < 4 + (u2 >>> 10); ) {
            for (; x2 < 3; ) {
              if (0 === v2) return s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
              r3 = 0, v2--, f2 |= (255 & n2.read_byte(k2++)) << x2, x2 += 8;
            }
            o2[h[w2++]] = 7 & f2, f2 >>>= 3, x2 -= 3;
          }
          for (; w2 < 19; ) o2[h[w2++]] = 0;
          if (_2[0] = 7, a3 = y2.inflate_trees_bits(o2, _2, b2, g2, n2), 0 != a3) return (r3 = a3) == t && (o2 = null, l2 = 9), s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
          w2 = 0, l2 = 5;
        case 5:
          for (; a3 = u2, !(w2 >= 258 + (31 & a3) + (a3 >> 5 & 31)); ) {
            let e2, c3;
            for (a3 = _2[0]; x2 < a3; ) {
              if (0 === v2) return s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
              r3 = 0, v2--, f2 |= (255 & n2.read_byte(k2++)) << x2, x2 += 8;
            }
            if (a3 = g2[3 * (b2[0] + (f2 & i[a3])) + 1], c3 = g2[3 * (b2[0] + (f2 & i[a3])) + 2], c3 < 16) f2 >>>= a3, x2 -= a3, o2[w2++] = c3;
            else {
              for (A2 = 18 == c3 ? 7 : c3 - 14, e2 = 18 == c3 ? 11 : 3; x2 < a3 + A2; ) {
                if (0 === v2) return s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
                r3 = 0, v2--, f2 |= (255 & n2.read_byte(k2++)) << x2, x2 += 8;
              }
              if (f2 >>>= a3, x2 -= a3, e2 += f2 & i[A2], f2 >>>= A2, x2 -= A2, A2 = w2, a3 = u2, A2 + e2 > 258 + (31 & a3) + (a3 >> 5 & 31) || 16 == c3 && A2 < 1) return o2 = null, l2 = 9, n2.msg = "invalid bit length repeat", r3 = t, s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
              c3 = 16 == c3 ? o2[A2 - 1] : 0;
              do {
                o2[A2++] = c3;
              } while (0 != --e2);
              w2 = A2;
            }
          }
          if (b2[0] = -1, F2 = [], O2 = [], C2 = [], W2 = [], F2[0] = 9, O2[0] = 6, a3 = u2, a3 = y2.inflate_trees_dynamic(257 + (31 & a3), 1 + (a3 >> 5 & 31), o2, F2, O2, C2, W2, g2, n2), 0 != a3) return a3 == t && (o2 = null, l2 = 9), r3 = a3, s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
          p2.init(F2[0], O2[0], g2, C2[0], g2, W2[0]), l2 = 6;
        case 6:
          if (s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, 1 != (r3 = p2.proc(s2, n2, r3))) return s2.inflate_flush(n2, r3);
          if (r3 = 0, p2.free(n2), k2 = n2.next_in_index, v2 = n2.avail_in, f2 = s2.bitb, x2 = s2.bitk, S2 = s2.write, z2 = S2 < s2.read ? s2.read - S2 - 1 : s2.end - S2, 0 === m2) {
            l2 = 0;
            break;
          }
          l2 = 7;
        case 7:
          if (s2.write = S2, r3 = s2.inflate_flush(n2, r3), S2 = s2.write, z2 = S2 < s2.read ? s2.read - S2 - 1 : s2.end - S2, s2.read != s2.write) return s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
          l2 = 8;
        case 8:
          return r3 = 1, s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
        case 9:
          return r3 = t, s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
        default:
          return r3 = e, s2.bitb = f2, s2.bitk = x2, n2.avail_in = v2, n2.total_in += k2 - n2.next_in_index, n2.next_in_index = k2, s2.write = S2, s2.inflate_flush(n2, r3);
      }
    }
  }, s2.free = function(e2) {
    s2.reset(e2, null), s2.win = null, g2 = null;
  }, s2.set_dictionary = function(e2, t2, n2) {
    s2.win.set(e2.subarray(t2, t2 + n2), 0), s2.read = s2.write = n2;
  }, s2.sync_point = function() {
    return 1 == l2 ? 1 : 0;
  };
}
const _ = 13, b = [0, 0, 255, 255];
function p() {
  const i2 = this;
  function r2(t2) {
    return t2 && t2.istate ? (t2.total_in = t2.total_out = 0, t2.msg = null, t2.istate.mode = 7, t2.istate.blocks.reset(t2, null), 0) : e;
  }
  i2.mode = 0, i2.method = 0, i2.was = [0], i2.need = 0, i2.marker = 0, i2.wbits = 0, i2.inflateEnd = function(e2) {
    return i2.blocks && i2.blocks.free(e2), i2.blocks = null, 0;
  }, i2.inflateInit = function(t2, n2) {
    return t2.msg = null, i2.blocks = null, n2 < 8 || n2 > 15 ? (i2.inflateEnd(t2), e) : (i2.wbits = n2, t2.istate.blocks = new w(t2, 1 << n2), r2(t2), 0);
  }, i2.inflate = function(i3, r3) {
    let a2, s2;
    if (!i3 || !i3.istate || !i3.next_in) return e;
    const o2 = i3.istate;
    for (r3 = 4 == r3 ? n : 0, a2 = n; ; ) switch (o2.mode) {
      case 0:
        if (0 === i3.avail_in) return a2;
        if (a2 = r3, i3.avail_in--, i3.total_in++, 8 != (15 & (o2.method = i3.read_byte(i3.next_in_index++)))) {
          o2.mode = _, i3.msg = "unknown compression method", o2.marker = 5;
          break;
        }
        if (8 + (o2.method >> 4) > o2.wbits) {
          o2.mode = _, i3.msg = "invalid win size", o2.marker = 5;
          break;
        }
        o2.mode = 1;
      case 1:
        if (0 === i3.avail_in) return a2;
        if (a2 = r3, i3.avail_in--, i3.total_in++, s2 = 255 & i3.read_byte(i3.next_in_index++), ((o2.method << 8) + s2) % 31 != 0) {
          o2.mode = _, i3.msg = "incorrect header check", o2.marker = 5;
          break;
        }
        if (!(32 & s2)) {
          o2.mode = 7;
          break;
        }
        o2.mode = 2;
      case 2:
        if (0 === i3.avail_in) return a2;
        a2 = r3, i3.avail_in--, i3.total_in++, o2.need = (255 & i3.read_byte(i3.next_in_index++)) << 24 & 4278190080, o2.mode = 3;
      case 3:
        if (0 === i3.avail_in) return a2;
        a2 = r3, i3.avail_in--, i3.total_in++, o2.need += (255 & i3.read_byte(i3.next_in_index++)) << 16 & 16711680, o2.mode = 4;
      case 4:
        if (0 === i3.avail_in) return a2;
        a2 = r3, i3.avail_in--, i3.total_in++, o2.need += (255 & i3.read_byte(i3.next_in_index++)) << 8 & 65280, o2.mode = 5;
      case 5:
        return 0 === i3.avail_in ? a2 : (a2 = r3, i3.avail_in--, i3.total_in++, o2.need += 255 & i3.read_byte(i3.next_in_index++), o2.mode = 6, 2);
      case 6:
        return o2.mode = _, i3.msg = "need dictionary", o2.marker = 0, e;
      case 7:
        if (a2 = o2.blocks.proc(i3, a2), a2 == t) {
          o2.mode = _, o2.marker = 0;
          break;
        }
        if (0 == a2 && (a2 = r3), 1 != a2) return a2;
        a2 = r3, o2.blocks.reset(i3, o2.was), o2.mode = 12;
      case 12:
        return i3.avail_in = 0, 1;
      case _:
        return t;
      default:
        return e;
    }
  }, i2.inflateSetDictionary = function(t2, n2, i3) {
    let r3 = 0, a2 = i3;
    if (!t2 || !t2.istate || 6 != t2.istate.mode) return e;
    const s2 = t2.istate;
    return a2 >= 1 << s2.wbits && (a2 = (1 << s2.wbits) - 1, r3 = i3 - a2), s2.blocks.set_dictionary(n2, r3, a2), s2.mode = 7, 0;
  }, i2.inflateSync = function(i3) {
    let a2, s2, o2, l2, c2;
    if (!i3 || !i3.istate) return e;
    const u2 = i3.istate;
    if (u2.mode != _ && (u2.mode = _, u2.marker = 0), 0 === (a2 = i3.avail_in)) return n;
    for (s2 = i3.next_in_index, o2 = u2.marker; 0 !== a2 && o2 < 4; ) i3.read_byte(s2) == b[o2] ? o2++ : o2 = 0 !== i3.read_byte(s2) ? 0 : 4 - o2, s2++, a2--;
    return i3.total_in += s2 - i3.next_in_index, i3.next_in_index = s2, i3.avail_in = a2, u2.marker = o2, 4 != o2 ? t : (l2 = i3.total_in, c2 = i3.total_out, r2(i3), i3.total_in = l2, i3.total_out = c2, u2.mode = 7, 0);
  }, i2.inflateSyncPoint = function(t2) {
    return t2 && t2.istate && t2.istate.blocks ? t2.istate.blocks.sync_point() : e;
  };
}
function m() {
}
m.prototype = { inflateInit(e2) {
  const t2 = this;
  return t2.istate = new p(), e2 || (e2 = 15), t2.istate.inflateInit(t2, e2);
}, inflate(t2) {
  const n2 = this;
  return n2.istate ? n2.istate.inflate(n2, t2) : e;
}, inflateEnd() {
  const t2 = this;
  if (!t2.istate) return e;
  const n2 = t2.istate.inflateEnd(t2);
  return t2.istate = null, n2;
}, inflateSync() {
  const t2 = this;
  return t2.istate ? t2.istate.inflateSync(t2) : e;
}, inflateSetDictionary(t2, n2) {
  const i2 = this;
  return i2.istate ? i2.istate.inflateSetDictionary(i2, t2, n2) : e;
}, read_byte(e2) {
  return this.next_in[e2];
}, read_buf(e2, t2) {
  return this.next_in.subarray(e2, e2 + t2);
} };
const g = 4294967295, y = 65535, x = 33639248, k = 101075792, v = 22, S = void 0, z = "undefined", A = "function";
class U {
  constructor(e2) {
    return class extends TransformStream {
      constructor(t2, n2) {
        const i2 = new e2(n2);
        super({ transform(e3, t3) {
          t3.enqueue(i2.append(e3));
        }, flush(e3) {
          const t3 = i2.flush();
          t3 && e3.enqueue(t3);
        } });
      }
    };
  }
}
let D = 2;
try {
  typeof navigator != z && navigator.hardwareConcurrency && (D = navigator.hardwareConcurrency);
} catch (e2) {
}
const E = { chunkSize: 524288, maxWorkers: D, terminateWorkerTimeout: 5e3, useWebWorkers: true, useCompressionStream: true, workerScripts: S, CompressionStreamNative: typeof CompressionStream != z && CompressionStream, DecompressionStreamNative: typeof DecompressionStream != z && DecompressionStream }, T = Object.assign({}, E);
function F(e2) {
  const { baseURL: t2, chunkSize: n2, maxWorkers: i2, terminateWorkerTimeout: r2, useCompressionStream: a2, useWebWorkers: s2, Deflate: o2, Inflate: l2, CompressionStream: c2, DecompressionStream: u2, workerScripts: d2 } = e2;
  if (O("baseURL", t2), O("chunkSize", n2), O("maxWorkers", i2), O("terminateWorkerTimeout", r2), O("useCompressionStream", a2), O("useWebWorkers", s2), o2 && (T.CompressionStream = new U(o2)), l2 && (T.DecompressionStream = new U(l2)), O("CompressionStream", c2), O("DecompressionStream", u2), d2 !== S) {
    const { deflate: e3, inflate: t3 } = d2;
    if ((e3 || t3) && (T.workerScripts || (T.workerScripts = {})), e3) {
      if (!Array.isArray(e3)) throw new Error("workerScripts.deflate must be an array");
      T.workerScripts.deflate = e3;
    }
    if (t3) {
      if (!Array.isArray(t3)) throw new Error("workerScripts.inflate must be an array");
      T.workerScripts.inflate = t3;
    }
  }
}
function O(e2, t2) {
  t2 !== S && (T[e2] = t2);
}
const C = [];
for (let e2 = 0; e2 < 256; e2++) {
  let t2 = e2;
  for (let e3 = 0; e3 < 8; e3++) 1 & t2 ? t2 = t2 >>> 1 ^ 3988292384 : t2 >>>= 1;
  C[e2] = t2;
}
class W {
  constructor(e2) {
    this.crc = e2 || -1;
  }
  append(e2) {
    let t2 = 0 | this.crc;
    for (let n2 = 0, i2 = 0 | e2.length; n2 < i2; n2++) t2 = t2 >>> 8 ^ C[255 & (t2 ^ e2[n2])];
    this.crc = t2;
  }
  get() {
    return ~this.crc;
  }
}
class j extends TransformStream {
  constructor() {
    let e2;
    const t2 = new W();
    super({ transform(e3, n2) {
      t2.append(e3), n2.enqueue(e3);
    }, flush() {
      const n2 = new Uint8Array(4);
      new DataView(n2.buffer).setUint32(0, t2.get()), e2.value = n2;
    } }), e2 = this;
  }
}
const M = { concat(e2, t2) {
  if (0 === e2.length || 0 === t2.length) return e2.concat(t2);
  const n2 = e2[e2.length - 1], i2 = M.getPartial(n2);
  return 32 === i2 ? e2.concat(t2) : M._shiftRight(t2, i2, 0 | n2, e2.slice(0, e2.length - 1));
}, bitLength(e2) {
  const t2 = e2.length;
  if (0 === t2) return 0;
  const n2 = e2[t2 - 1];
  return 32 * (t2 - 1) + M.getPartial(n2);
}, clamp(e2, t2) {
  if (32 * e2.length < t2) return e2;
  const n2 = (e2 = e2.slice(0, Math.ceil(t2 / 32))).length;
  return t2 &= 31, n2 > 0 && t2 && (e2[n2 - 1] = M.partial(t2, e2[n2 - 1] & 2147483648 >> t2 - 1, 1)), e2;
}, partial: (e2, t2, n2) => 32 === e2 ? t2 : (n2 ? 0 | t2 : t2 << 32 - e2) + 1099511627776 * e2, getPartial: (e2) => Math.round(e2 / 1099511627776) || 32, _shiftRight(e2, t2, n2, i2) {
  for (void 0 === i2 && (i2 = []); t2 >= 32; t2 -= 32) i2.push(n2), n2 = 0;
  if (0 === t2) return i2.concat(e2);
  for (let r3 = 0; r3 < e2.length; r3++) i2.push(n2 | e2[r3] >>> t2), n2 = e2[r3] << 32 - t2;
  const r2 = e2.length ? e2[e2.length - 1] : 0, a2 = M.getPartial(r2);
  return i2.push(M.partial(t2 + a2 & 31, t2 + a2 > 32 ? n2 : i2.pop(), 1)), i2;
} }, L = { bytes: { fromBits(e2) {
  const t2 = M.bitLength(e2) / 8, n2 = new Uint8Array(t2);
  let i2;
  for (let r2 = 0; r2 < t2; r2++) 3 & r2 || (i2 = e2[r2 / 4]), n2[r2] = i2 >>> 24, i2 <<= 8;
  return n2;
}, toBits(e2) {
  const t2 = [];
  let n2, i2 = 0;
  for (n2 = 0; n2 < e2.length; n2++) i2 = i2 << 8 | e2[n2], 3 & ~n2 || (t2.push(i2), i2 = 0);
  return 3 & n2 && t2.push(M.partial(8 * (3 & n2), i2)), t2;
} } }, P = { sha1: class {
  constructor(e2) {
    const t2 = this;
    t2.blockSize = 512, t2._init = [1732584193, 4023233417, 2562383102, 271733878, 3285377520], t2._key = [1518500249, 1859775393, 2400959708, 3395469782], e2 ? (t2._h = e2._h.slice(0), t2._buffer = e2._buffer.slice(0), t2._length = e2._length) : t2.reset();
  }
  reset() {
    const e2 = this;
    return e2._h = e2._init.slice(0), e2._buffer = [], e2._length = 0, e2;
  }
  update(e2) {
    const t2 = this;
    "string" == typeof e2 && (e2 = L.utf8String.toBits(e2));
    const n2 = t2._buffer = M.concat(t2._buffer, e2), i2 = t2._length, r2 = t2._length = i2 + M.bitLength(e2);
    if (r2 > 9007199254740991) throw new Error("Cannot hash more than 2^53 - 1 bits");
    const a2 = new Uint32Array(n2);
    let s2 = 0;
    for (let e3 = t2.blockSize + i2 - (t2.blockSize + i2 & t2.blockSize - 1); e3 <= r2; e3 += t2.blockSize) t2._block(a2.subarray(16 * s2, 16 * (s2 + 1))), s2 += 1;
    return n2.splice(0, 16 * s2), t2;
  }
  finalize() {
    const e2 = this;
    let t2 = e2._buffer;
    const n2 = e2._h;
    t2 = M.concat(t2, [M.partial(1, 1)]);
    for (let e3 = t2.length + 2; 15 & e3; e3++) t2.push(0);
    for (t2.push(Math.floor(e2._length / 4294967296)), t2.push(0 | e2._length); t2.length; ) e2._block(t2.splice(0, 16));
    return e2.reset(), n2;
  }
  _f(e2, t2, n2, i2) {
    return e2 <= 19 ? t2 & n2 | ~t2 & i2 : e2 <= 39 ? t2 ^ n2 ^ i2 : e2 <= 59 ? t2 & n2 | t2 & i2 | n2 & i2 : e2 <= 79 ? t2 ^ n2 ^ i2 : void 0;
  }
  _S(e2, t2) {
    return t2 << e2 | t2 >>> 32 - e2;
  }
  _block(e2) {
    const t2 = this, n2 = t2._h, i2 = Array(80);
    for (let t3 = 0; t3 < 16; t3++) i2[t3] = e2[t3];
    let r2 = n2[0], a2 = n2[1], s2 = n2[2], o2 = n2[3], l2 = n2[4];
    for (let e3 = 0; e3 <= 79; e3++) {
      e3 >= 16 && (i2[e3] = t2._S(1, i2[e3 - 3] ^ i2[e3 - 8] ^ i2[e3 - 14] ^ i2[e3 - 16]));
      const n3 = t2._S(5, r2) + t2._f(e3, a2, s2, o2) + l2 + i2[e3] + t2._key[Math.floor(e3 / 20)] | 0;
      l2 = o2, o2 = s2, s2 = t2._S(30, a2), a2 = r2, r2 = n3;
    }
    n2[0] = n2[0] + r2 | 0, n2[1] = n2[1] + a2 | 0, n2[2] = n2[2] + s2 | 0, n2[3] = n2[3] + o2 | 0, n2[4] = n2[4] + l2 | 0;
  }
} }, R = { aes: class {
  constructor(e2) {
    const t2 = this;
    t2._tables = [[[], [], [], [], []], [[], [], [], [], []]], t2._tables[0][0][0] || t2._precompute();
    const n2 = t2._tables[0][4], i2 = t2._tables[1], r2 = e2.length;
    let a2, s2, o2, l2 = 1;
    if (4 !== r2 && 6 !== r2 && 8 !== r2) throw new Error("invalid aes key size");
    for (t2._key = [s2 = e2.slice(0), o2 = []], a2 = r2; a2 < 4 * r2 + 28; a2++) {
      let e3 = s2[a2 - 1];
      (a2 % r2 == 0 || 8 === r2 && a2 % r2 == 4) && (e3 = n2[e3 >>> 24] << 24 ^ n2[e3 >> 16 & 255] << 16 ^ n2[e3 >> 8 & 255] << 8 ^ n2[255 & e3], a2 % r2 == 0 && (e3 = e3 << 8 ^ e3 >>> 24 ^ l2 << 24, l2 = l2 << 1 ^ 283 * (l2 >> 7))), s2[a2] = s2[a2 - r2] ^ e3;
    }
    for (let e3 = 0; a2; e3++, a2--) {
      const t3 = s2[3 & e3 ? a2 : a2 - 4];
      o2[e3] = a2 <= 4 || e3 < 4 ? t3 : i2[0][n2[t3 >>> 24]] ^ i2[1][n2[t3 >> 16 & 255]] ^ i2[2][n2[t3 >> 8 & 255]] ^ i2[3][n2[255 & t3]];
    }
  }
  encrypt(e2) {
    return this._crypt(e2, 0);
  }
  decrypt(e2) {
    return this._crypt(e2, 1);
  }
  _precompute() {
    const e2 = this._tables[0], t2 = this._tables[1], n2 = e2[4], i2 = t2[4], r2 = [], a2 = [];
    let s2, o2, l2, c2;
    for (let e3 = 0; e3 < 256; e3++) a2[(r2[e3] = e3 << 1 ^ 283 * (e3 >> 7)) ^ e3] = e3;
    for (let u2 = s2 = 0; !n2[u2]; u2 ^= o2 || 1, s2 = a2[s2] || 1) {
      let a3 = s2 ^ s2 << 1 ^ s2 << 2 ^ s2 << 3 ^ s2 << 4;
      a3 = a3 >> 8 ^ 255 & a3 ^ 99, n2[u2] = a3, i2[a3] = u2, c2 = r2[l2 = r2[o2 = r2[u2]]];
      let d2 = 16843009 * c2 ^ 65537 * l2 ^ 257 * o2 ^ 16843008 * u2, f2 = 257 * r2[a3] ^ 16843008 * a3;
      for (let n3 = 0; n3 < 4; n3++) e2[n3][u2] = f2 = f2 << 24 ^ f2 >>> 8, t2[n3][a3] = d2 = d2 << 24 ^ d2 >>> 8;
    }
    for (let n3 = 0; n3 < 5; n3++) e2[n3] = e2[n3].slice(0), t2[n3] = t2[n3].slice(0);
  }
  _crypt(e2, t2) {
    if (4 !== e2.length) throw new Error("invalid aes block size");
    const n2 = this._key[t2], i2 = n2.length / 4 - 2, r2 = [0, 0, 0, 0], a2 = this._tables[t2], s2 = a2[0], o2 = a2[1], l2 = a2[2], c2 = a2[3], u2 = a2[4];
    let d2, f2, h2, w2 = e2[0] ^ n2[0], _2 = e2[t2 ? 3 : 1] ^ n2[1], b2 = e2[2] ^ n2[2], p2 = e2[t2 ? 1 : 3] ^ n2[3], m2 = 4;
    for (let e3 = 0; e3 < i2; e3++) d2 = s2[w2 >>> 24] ^ o2[_2 >> 16 & 255] ^ l2[b2 >> 8 & 255] ^ c2[255 & p2] ^ n2[m2], f2 = s2[_2 >>> 24] ^ o2[b2 >> 16 & 255] ^ l2[p2 >> 8 & 255] ^ c2[255 & w2] ^ n2[m2 + 1], h2 = s2[b2 >>> 24] ^ o2[p2 >> 16 & 255] ^ l2[w2 >> 8 & 255] ^ c2[255 & _2] ^ n2[m2 + 2], p2 = s2[p2 >>> 24] ^ o2[w2 >> 16 & 255] ^ l2[_2 >> 8 & 255] ^ c2[255 & b2] ^ n2[m2 + 3], m2 += 4, w2 = d2, _2 = f2, b2 = h2;
    for (let e3 = 0; e3 < 4; e3++) r2[t2 ? 3 & -e3 : e3] = u2[w2 >>> 24] << 24 ^ u2[_2 >> 16 & 255] << 16 ^ u2[b2 >> 8 & 255] << 8 ^ u2[255 & p2] ^ n2[m2++], d2 = w2, w2 = _2, _2 = b2, b2 = p2, p2 = d2;
    return r2;
  }
} }, B = { getRandomValues(e2) {
  const t2 = new Uint32Array(e2.buffer), n2 = (e3) => {
    let t3 = 987654321;
    const n3 = 4294967295;
    return function() {
      t3 = 36969 * (65535 & t3) + (t3 >> 16) & n3;
      return (((t3 << 16) + (e3 = 18e3 * (65535 & e3) + (e3 >> 16) & n3) & n3) / 4294967296 + 0.5) * (Math.random() > 0.5 ? 1 : -1);
    };
  };
  for (let i2, r2 = 0; r2 < e2.length; r2 += 4) {
    const e3 = n2(4294967296 * (i2 || Math.random()));
    i2 = 987654071 * e3(), t2[r2 / 4] = 4294967296 * e3() | 0;
  }
  return e2;
} }, I = { ctrGladman: class {
  constructor(e2, t2) {
    this._prf = e2, this._initIv = t2, this._iv = t2;
  }
  reset() {
    this._iv = this._initIv;
  }
  update(e2) {
    return this.calculate(this._prf, e2, this._iv);
  }
  incWord(e2) {
    if (255 & ~(e2 >> 24)) e2 += 1 << 24;
    else {
      let t2 = e2 >> 16 & 255, n2 = e2 >> 8 & 255, i2 = 255 & e2;
      255 === t2 ? (t2 = 0, 255 === n2 ? (n2 = 0, 255 === i2 ? i2 = 0 : ++i2) : ++n2) : ++t2, e2 = 0, e2 += t2 << 16, e2 += n2 << 8, e2 += i2;
    }
    return e2;
  }
  incCounter(e2) {
    0 === (e2[0] = this.incWord(e2[0])) && (e2[1] = this.incWord(e2[1]));
  }
  calculate(e2, t2, n2) {
    let i2;
    if (!(i2 = t2.length)) return [];
    const r2 = M.bitLength(t2);
    for (let r3 = 0; r3 < i2; r3 += 4) {
      this.incCounter(n2);
      const i3 = e2.encrypt(n2);
      t2[r3] ^= i3[0], t2[r3 + 1] ^= i3[1], t2[r3 + 2] ^= i3[2], t2[r3 + 3] ^= i3[3];
    }
    return M.clamp(t2, r2);
  }
} }, N = { importKey: (e2) => new N.hmacSha1(L.bytes.toBits(e2)), pbkdf2(e2, t2, n2, i2) {
  if (n2 = n2 || 1e4, i2 < 0 || n2 < 0) throw new Error("invalid params to pbkdf2");
  const r2 = 1 + (i2 >> 5) << 2;
  let a2, s2, o2, l2, c2;
  const u2 = new ArrayBuffer(r2), d2 = new DataView(u2);
  let f2 = 0;
  const h2 = M;
  for (t2 = L.bytes.toBits(t2), c2 = 1; f2 < (r2 || 1); c2++) {
    for (a2 = s2 = e2.encrypt(h2.concat(t2, [c2])), o2 = 1; o2 < n2; o2++) for (s2 = e2.encrypt(s2), l2 = 0; l2 < s2.length; l2++) a2[l2] ^= s2[l2];
    for (o2 = 0; f2 < (r2 || 1) && o2 < a2.length; o2++) d2.setInt32(f2, a2[o2]), f2 += 4;
  }
  return u2.slice(0, i2 / 8);
}, hmacSha1: class {
  constructor(e2) {
    const t2 = this, n2 = t2._hash = P.sha1, i2 = [[], []];
    t2._baseHash = [new n2(), new n2()];
    const r2 = t2._baseHash[0].blockSize / 32;
    e2.length > r2 && (e2 = new n2().update(e2).finalize());
    for (let t3 = 0; t3 < r2; t3++) i2[0][t3] = 909522486 ^ e2[t3], i2[1][t3] = 1549556828 ^ e2[t3];
    t2._baseHash[0].update(i2[0]), t2._baseHash[1].update(i2[1]), t2._resultHash = new n2(t2._baseHash[0]);
  }
  reset() {
    const e2 = this;
    e2._resultHash = new e2._hash(e2._baseHash[0]), e2._updated = false;
  }
  update(e2) {
    this._updated = true, this._resultHash.update(e2);
  }
  digest() {
    const e2 = this, t2 = e2._resultHash.finalize(), n2 = new e2._hash(e2._baseHash[1]).update(t2).finalize();
    return e2.reset(), n2;
  }
  encrypt(e2) {
    if (this._updated) throw new Error("encrypt on already updated hmac called!");
    return this.update(e2), this.digest(e2);
  }
} }, V = typeof crypto != z && typeof crypto.getRandomValues == A, q = "Invalid password", H = "Invalid signature", K = "zipjs-abort-check-password";
function Z(e2) {
  return V ? crypto.getRandomValues(e2) : B.getRandomValues(e2);
}
const G = 16, J = { name: "PBKDF2" }, Q = Object.assign({ hash: { name: "HMAC" } }, J), X = Object.assign({ iterations: 1e3, hash: { name: "SHA-1" } }, J), Y = ["deriveBits"], $ = [8, 12, 16], ee = [16, 24, 32], te = 10, ne = [0, 0, 0, 0], ie = typeof crypto != z, re = ie && crypto.subtle, ae = ie && typeof re != z, se = L.bytes, oe = R.aes, le = I.ctrGladman, ce = N.hmacSha1;
let ue = ie && ae && typeof re.importKey == A, de = ie && ae && typeof re.deriveBits == A;
class fe extends TransformStream {
  constructor({ password: e2, rawPassword: t2, signed: n2, encryptionStrength: i2, checkPasswordOnly: r2 }) {
    super({ start() {
      Object.assign(this, { ready: new Promise(((e3) => this.resolveReady = e3)), password: be(e2, t2), signed: n2, strength: i2 - 1, pending: new Uint8Array() });
    }, async transform(e3, t3) {
      const n3 = this, { password: i3, strength: a2, resolveReady: s2, ready: o2 } = n3;
      i3 ? (await (async function(e4, t4, n4, i4) {
        const r3 = await _e(e4, t4, n4, me(i4, 0, $[t4])), a3 = me(i4, $[t4]);
        if (r3[0] != a3[0] || r3[1] != a3[1]) throw new Error(q);
      })(n3, a2, i3, me(e3, 0, $[a2] + 2)), e3 = me(e3, $[a2] + 2), r2 ? t3.error(new Error(K)) : s2()) : await o2;
      const l2 = new Uint8Array(e3.length - te - (e3.length - te) % G);
      t3.enqueue(we(n3, e3, l2, 0, te, true));
    }, async flush(e3) {
      const { signed: t3, ctr: n3, hmac: i3, pending: r3, ready: a2 } = this;
      if (i3 && n3) {
        await a2;
        const s2 = me(r3, 0, r3.length - te), o2 = me(r3, r3.length - te);
        let l2 = new Uint8Array();
        if (s2.length) {
          const e4 = ye(se, s2);
          i3.update(e4);
          const t4 = n3.update(e4);
          l2 = ge(se, t4);
        }
        if (t3) {
          const e4 = me(ge(se, i3.digest()), 0, te);
          for (let t4 = 0; t4 < te; t4++) if (e4[t4] != o2[t4]) throw new Error(H);
        }
        e3.enqueue(l2);
      }
    } });
  }
}
class he extends TransformStream {
  constructor({ password: e2, rawPassword: t2, encryptionStrength: n2 }) {
    let i2;
    super({ start() {
      Object.assign(this, { ready: new Promise(((e3) => this.resolveReady = e3)), password: be(e2, t2), strength: n2 - 1, pending: new Uint8Array() });
    }, async transform(e3, t3) {
      const n3 = this, { password: i3, strength: r2, resolveReady: a2, ready: s2 } = n3;
      let o2 = new Uint8Array();
      i3 ? (o2 = await (async function(e4, t4, n4) {
        const i4 = Z(new Uint8Array($[t4])), r3 = await _e(e4, t4, n4, i4);
        return pe(i4, r3);
      })(n3, r2, i3), a2()) : await s2;
      const l2 = new Uint8Array(o2.length + e3.length - e3.length % G);
      l2.set(o2, 0), t3.enqueue(we(n3, e3, l2, o2.length, 0));
    }, async flush(e3) {
      const { ctr: t3, hmac: n3, pending: r2, ready: a2 } = this;
      if (n3 && t3) {
        await a2;
        let s2 = new Uint8Array();
        if (r2.length) {
          const e4 = t3.update(ye(se, r2));
          n3.update(e4), s2 = ge(se, e4);
        }
        i2.signature = ge(se, n3.digest()).slice(0, te), e3.enqueue(pe(s2, i2.signature));
      }
    } }), i2 = this;
  }
}
function we(e2, t2, n2, i2, r2, a2) {
  const { ctr: s2, hmac: o2, pending: l2 } = e2, c2 = t2.length - r2;
  let u2;
  for (l2.length && (t2 = pe(l2, t2), n2 = (function(e3, t3) {
    if (t3 && t3 > e3.length) {
      const n3 = e3;
      (e3 = new Uint8Array(t3)).set(n3, 0);
    }
    return e3;
  })(n2, c2 - c2 % G)), u2 = 0; u2 <= c2 - G; u2 += G) {
    const e3 = ye(se, me(t2, u2, u2 + G));
    a2 && o2.update(e3);
    const r3 = s2.update(e3);
    a2 || o2.update(r3), n2.set(ge(se, r3), u2 + i2);
  }
  return e2.pending = me(t2, u2), n2;
}
async function _e(e2, t2, n2, i2) {
  e2.password = null;
  const r2 = await (async function(e3, t3, n3, i3, r3) {
    if (!ue) return N.importKey(t3);
    try {
      return await re.importKey(e3, t3, n3, i3, r3);
    } catch (e4) {
      return ue = false, N.importKey(t3);
    }
  })("raw", n2, Q, false, Y), a2 = await (async function(e3, t3, n3) {
    if (!de) return N.pbkdf2(t3, e3.salt, X.iterations, n3);
    try {
      return await re.deriveBits(e3, t3, n3);
    } catch (i3) {
      return de = false, N.pbkdf2(t3, e3.salt, X.iterations, n3);
    }
  })(Object.assign({ salt: i2 }, X), r2, 8 * (2 * ee[t2] + 2)), s2 = new Uint8Array(a2), o2 = ye(se, me(s2, 0, ee[t2])), l2 = ye(se, me(s2, ee[t2], 2 * ee[t2])), c2 = me(s2, 2 * ee[t2]);
  return Object.assign(e2, { keys: { key: o2, authentication: l2, passwordVerification: c2 }, ctr: new le(new oe(o2), Array.from(ne)), hmac: new ce(l2) }), c2;
}
function be(e2, t2) {
  return t2 === S ? (function(e3) {
    if (typeof TextEncoder == z) {
      e3 = unescape(encodeURIComponent(e3));
      const t3 = new Uint8Array(e3.length);
      for (let n2 = 0; n2 < t3.length; n2++) t3[n2] = e3.charCodeAt(n2);
      return t3;
    }
    return new TextEncoder().encode(e3);
  })(e2) : t2;
}
function pe(e2, t2) {
  let n2 = e2;
  return e2.length + t2.length && (n2 = new Uint8Array(e2.length + t2.length), n2.set(e2, 0), n2.set(t2, e2.length)), n2;
}
function me(e2, t2, n2) {
  return e2.subarray(t2, n2);
}
function ge(e2, t2) {
  return e2.fromBits(t2);
}
function ye(e2, t2) {
  return e2.toBits(t2);
}
const xe = 12;
class ke extends TransformStream {
  constructor({ password: e2, passwordVerification: t2, checkPasswordOnly: n2 }) {
    super({ start() {
      Object.assign(this, { password: e2, passwordVerification: t2 }), Ae(this, e2);
    }, transform(e3, t3) {
      const i2 = this;
      if (i2.password) {
        const t4 = Se(i2, e3.subarray(0, xe));
        if (i2.password = null, t4[11] != i2.passwordVerification) throw new Error(q);
        e3 = e3.subarray(xe);
      }
      n2 ? t3.error(new Error(K)) : t3.enqueue(Se(i2, e3));
    } });
  }
}
class ve extends TransformStream {
  constructor({ password: e2, passwordVerification: t2 }) {
    super({ start() {
      Object.assign(this, { password: e2, passwordVerification: t2 }), Ae(this, e2);
    }, transform(e3, t3) {
      const n2 = this;
      let i2, r2;
      if (n2.password) {
        n2.password = null;
        const t4 = Z(new Uint8Array(xe));
        t4[11] = n2.passwordVerification, i2 = new Uint8Array(e3.length + t4.length), i2.set(ze(n2, t4), 0), r2 = xe;
      } else i2 = new Uint8Array(e3.length), r2 = 0;
      i2.set(ze(n2, e3), r2), t3.enqueue(i2);
    } });
  }
}
function Se(e2, t2) {
  const n2 = new Uint8Array(t2.length);
  for (let i2 = 0; i2 < t2.length; i2++) n2[i2] = De(e2) ^ t2[i2], Ue(e2, n2[i2]);
  return n2;
}
function ze(e2, t2) {
  const n2 = new Uint8Array(t2.length);
  for (let i2 = 0; i2 < t2.length; i2++) n2[i2] = De(e2) ^ t2[i2], Ue(e2, t2[i2]);
  return n2;
}
function Ae(e2, t2) {
  const n2 = [305419896, 591751049, 878082192];
  Object.assign(e2, { keys: n2, crcKey0: new W(n2[0]), crcKey2: new W(n2[2]) });
  for (let n3 = 0; n3 < t2.length; n3++) Ue(e2, t2.charCodeAt(n3));
}
function Ue(e2, t2) {
  let [n2, i2, r2] = e2.keys;
  e2.crcKey0.append([t2]), n2 = ~e2.crcKey0.get(), i2 = Te(Math.imul(Te(i2 + Ee(n2)), 134775813) + 1), e2.crcKey2.append([i2 >>> 24]), r2 = ~e2.crcKey2.get(), e2.keys = [n2, i2, r2];
}
function De(e2) {
  const t2 = 2 | e2.keys[2];
  return Ee(Math.imul(t2, 1 ^ t2) >>> 8);
}
function Ee(e2) {
  return 255 & e2;
}
function Te(e2) {
  return 4294967295 & e2;
}
const Fe = "deflate-raw";
class Oe extends TransformStream {
  constructor(e2, { chunkSize: t2, CompressionStream: n2, CompressionStreamNative: i2 }) {
    super({});
    const { compressed: r2, encrypted: a2, useCompressionStream: s2, zipCrypto: o2, signed: l2, level: c2 } = e2, u2 = this;
    let d2, f2, h2 = We(super.readable);
    a2 && !o2 || !l2 || (d2 = new j(), h2 = Le(h2, d2)), r2 && (h2 = Me(h2, s2, { level: c2, chunkSize: t2 }, i2, n2)), a2 && (o2 ? h2 = Le(h2, new ve(e2)) : (f2 = new he(e2), h2 = Le(h2, f2))), je(u2, h2, (() => {
      let e3;
      a2 && !o2 && (e3 = f2.signature), a2 && !o2 || !l2 || (e3 = new DataView(d2.value.buffer).getUint32(0)), u2.signature = e3;
    }));
  }
}
class Ce extends TransformStream {
  constructor(e2, { chunkSize: t2, DecompressionStream: n2, DecompressionStreamNative: i2 }) {
    super({});
    const { zipCrypto: r2, encrypted: a2, signed: s2, signature: o2, compressed: l2, useCompressionStream: c2 } = e2;
    let u2, d2, f2 = We(super.readable);
    a2 && (r2 ? f2 = Le(f2, new ke(e2)) : (d2 = new fe(e2), f2 = Le(f2, d2))), l2 && (f2 = Me(f2, c2, { chunkSize: t2 }, i2, n2)), a2 && !r2 || !s2 || (u2 = new j(), f2 = Le(f2, u2)), je(this, f2, (() => {
      if ((!a2 || r2) && s2) {
        const e3 = new DataView(u2.value.buffer);
        if (o2 != e3.getUint32(0, false)) throw new Error(H);
      }
    }));
  }
}
function We(e2) {
  return Le(e2, new TransformStream({ transform(e3, t2) {
    e3 && e3.length && t2.enqueue(e3);
  } }));
}
function je(e2, t2, n2) {
  t2 = Le(t2, new TransformStream({ flush: n2 })), Object.defineProperty(e2, "readable", { get: () => t2 });
}
function Me(e2, t2, n2, i2, r2) {
  try {
    e2 = Le(e2, new (t2 && i2 ? i2 : r2)(Fe, n2));
  } catch (i3) {
    if (!t2) return e2;
    try {
      e2 = Le(e2, new r2(Fe, n2));
    } catch (t3) {
      return e2;
    }
  }
  return e2;
}
function Le(e2, t2) {
  return e2.pipeThrough(t2);
}
const Pe = "message", Re = "start", Be = "pull", Ie = "data", Ne = "close", Ve = "inflate";
class qe extends TransformStream {
  constructor(e2, t2) {
    super({});
    const n2 = this, { codecType: i2 } = e2;
    let r2;
    i2.startsWith("deflate") ? r2 = Oe : i2.startsWith(Ve) && (r2 = Ce);
    let a2 = 0, s2 = 0;
    const o2 = new r2(e2, t2), l2 = super.readable, c2 = new TransformStream({ transform(e3, t3) {
      e3 && e3.length && (s2 += e3.length, t3.enqueue(e3));
    }, flush() {
      Object.assign(n2, { inputSize: s2 });
    } }), u2 = new TransformStream({ transform(e3, t3) {
      e3 && e3.length && (a2 += e3.length, t3.enqueue(e3));
    }, flush() {
      const { signature: e3 } = o2;
      Object.assign(n2, { signature: e3, outputSize: a2, inputSize: s2 });
    } });
    Object.defineProperty(n2, "readable", { get: () => l2.pipeThrough(c2).pipeThrough(o2).pipeThrough(u2) });
  }
}
class He extends TransformStream {
  constructor(e2) {
    let t2;
    super({ transform: function n2(i2, r2) {
      if (t2) {
        const e3 = new Uint8Array(t2.length + i2.length);
        e3.set(t2), e3.set(i2, t2.length), i2 = e3, t2 = null;
      }
      i2.length > e2 ? (r2.enqueue(i2.slice(0, e2)), n2(i2.slice(e2), r2)) : t2 = i2;
    }, flush(e3) {
      t2 && t2.length && e3.enqueue(t2);
    } });
  }
}
let Ke = typeof Worker != z;
class Ze {
  constructor(e2, { readable: t2, writable: n2 }, { options: i2, config: r2, streamOptions: a2, useWebWorkers: s2, transferStreams: o2, scripts: l2 }, c2) {
    const { signal: u2 } = a2;
    return Object.assign(e2, { busy: true, readable: t2.pipeThrough(new He(r2.chunkSize)).pipeThrough(new Ge(t2, a2), { signal: u2 }), writable: n2, options: Object.assign({}, i2), scripts: l2, transferStreams: o2, terminate: () => new Promise(((t3) => {
      const { worker: n3, busy: i3 } = e2;
      n3 ? (i3 ? e2.resolveTerminated = t3 : (n3.terminate(), t3()), e2.interface = null) : t3();
    })), onTaskFinished() {
      const { resolveTerminated: t3 } = e2;
      t3 && (e2.resolveTerminated = null, e2.terminated = true, e2.worker.terminate(), t3()), e2.busy = false, c2(e2);
    } }), (s2 && Ke ? Xe : Qe)(e2, r2);
  }
}
class Ge extends TransformStream {
  constructor(e2, { onstart: t2, onprogress: n2, size: i2, onend: r2 }) {
    let a2 = 0;
    super({ async start() {
      t2 && await Je(t2, i2);
    }, async transform(e3, t3) {
      a2 += e3.length, n2 && await Je(n2, a2, i2), t3.enqueue(e3);
    }, async flush() {
      e2.size = a2, r2 && await Je(r2, a2);
    } });
  }
}
async function Je(e2, ...t2) {
  try {
    await e2(...t2);
  } catch (e3) {
  }
}
function Qe(e2, t2) {
  return { run: () => (async function({ options: e3, readable: t3, writable: n2, onTaskFinished: i2 }, r2) {
    try {
      const i3 = new qe(e3, r2);
      await t3.pipeThrough(i3).pipeTo(n2, { preventClose: true, preventAbort: true });
      const { signature: a2, inputSize: s2, outputSize: o2 } = i3;
      return { signature: a2, inputSize: s2, outputSize: o2 };
    } finally {
      i2();
    }
  })(e2, t2) };
}
function Xe(e2, t2) {
  const { baseURL: n2, chunkSize: i2 } = t2;
  if (!e2.interface) {
    let r2;
    try {
      r2 = (function(e3, t3, n3) {
        const i3 = { type: "module" };
        let r3, a2;
        typeof e3 == A && (e3 = e3());
        try {
          r3 = new URL(e3, t3);
        } catch (t4) {
          r3 = e3;
        }
        if (Ye) try {
          a2 = new Worker(r3);
        } catch (e4) {
          Ye = false, a2 = new Worker(r3, i3);
        }
        else a2 = new Worker(r3, i3);
        return a2.addEventListener(Pe, ((e4) => (async function({ data: e5 }, t4) {
          const { type: n4, value: i4, messageId: r4, result: a3, error: s2 } = e5, { reader: o2, writer: l2, resolveResult: c2, rejectResult: u2, onTaskFinished: d2 } = t4;
          try {
            if (s2) {
              const { message: e6, stack: t5, code: n5, name: i5 } = s2, r5 = new Error(e6);
              Object.assign(r5, { stack: t5, code: n5, name: i5 }), f2(r5);
            } else {
              if (n4 == Be) {
                const { value: e6, done: n5 } = await o2.read();
                et({ type: Ie, value: e6, done: n5, messageId: r4 }, t4);
              }
              n4 == Ie && (await l2.ready, await l2.write(new Uint8Array(i4)), et({ type: "ack", messageId: r4 }, t4)), n4 == Ne && f2(null, a3);
            }
          } catch (s3) {
            et({ type: Ne, messageId: r4 }, t4), f2(s3);
          }
          function f2(e6, t5) {
            e6 ? u2(e6) : c2(t5), l2 && l2.releaseLock(), d2();
          }
        })(e4, n3))), a2;
      })(e2.scripts[0], n2, e2);
    } catch (n3) {
      return Ke = false, Qe(e2, t2);
    }
    Object.assign(e2, { worker: r2, interface: { run: () => (async function(e3, t3) {
      let n3, i3;
      const r3 = new Promise(((e4, t4) => {
        n3 = e4, i3 = t4;
      }));
      Object.assign(e3, { reader: null, writer: null, resolveResult: n3, rejectResult: i3, result: r3 });
      const { readable: a2, options: s2, scripts: o2 } = e3, { writable: l2, closed: c2 } = (function(e4) {
        let t4;
        const n4 = new Promise(((e5) => t4 = e5)), i4 = new WritableStream({ async write(t5) {
          const n5 = e4.getWriter();
          await n5.ready, await n5.write(t5), n5.releaseLock();
        }, close() {
          t4();
        }, abort: (t5) => e4.getWriter().abort(t5) });
        return { writable: i4, closed: n4 };
      })(e3.writable), u2 = et({ type: Re, scripts: o2.slice(1), options: s2, config: t3, readable: a2, writable: l2 }, e3);
      u2 || Object.assign(e3, { reader: a2.getReader(), writer: l2.getWriter() });
      const d2 = await r3;
      u2 || await l2.getWriter().close();
      return await c2, d2;
    })(e2, { chunkSize: i2 }) } });
  }
  return e2.interface;
}
let Ye = true, $e = true;
function et(e2, { worker: t2, writer: n2, onTaskFinished: i2, transferStreams: r2 }) {
  try {
    let { value: n3, readable: i3, writable: a2 } = e2;
    const s2 = [];
    if (n3 && (n3.byteLength < n3.buffer.byteLength ? e2.value = n3.buffer.slice(0, n3.byteLength) : e2.value = n3.buffer, s2.push(e2.value)), r2 && $e ? (i3 && s2.push(i3), a2 && s2.push(a2)) : e2.readable = e2.writable = null, s2.length) try {
      return t2.postMessage(e2, s2), true;
    } catch (n4) {
      $e = false, e2.readable = e2.writable = null, t2.postMessage(e2);
    }
    else t2.postMessage(e2);
  } catch (e3) {
    throw n2 && n2.releaseLock(), i2(), e3;
  }
}
let tt = [];
const nt = [];
let it = 0;
async function rt(e2, t2) {
  const { options: n2, config: i2 } = t2, { transferStreams: r2, useWebWorkers: a2, useCompressionStream: s2, codecType: o2, compressed: l2, signed: c2, encrypted: u2 } = n2, { workerScripts: d2, maxWorkers: f2 } = i2;
  t2.transferStreams = r2 || r2 === S;
  const h2 = !(l2 || c2 || u2 || t2.transferStreams);
  return t2.useWebWorkers = !h2 && (a2 || a2 === S && i2.useWebWorkers), t2.scripts = t2.useWebWorkers && d2 ? d2[o2] : [], n2.useCompressionStream = s2 || s2 === S && i2.useCompressionStream, (await (async function() {
    const n3 = tt.find(((e3) => !e3.busy));
    if (n3) return at(n3), new Ze(n3, e2, t2, w2);
    if (tt.length < f2) {
      const n4 = { indexWorker: it };
      return it++, tt.push(n4), new Ze(n4, e2, t2, w2);
    }
    return new Promise(((n4) => nt.push({ resolve: n4, stream: e2, workerOptions: t2 })));
  })()).run();
  function w2(e3) {
    if (nt.length) {
      const [{ resolve: t3, stream: n3, workerOptions: i3 }] = nt.splice(0, 1);
      t3(new Ze(e3, n3, i3, w2));
    } else e3.worker ? (at(e3), (function(e4, t3) {
      const { config: n3 } = t3, { terminateWorkerTimeout: i3 } = n3;
      Number.isFinite(i3) && i3 >= 0 && (e4.terminated ? e4.terminated = false : e4.terminateTimeout = setTimeout((async () => {
        tt = tt.filter(((t4) => t4 != e4));
        try {
          await e4.terminate();
        } catch (e5) {
        }
      }), i3));
    })(e3, t2)) : tt = tt.filter(((t3) => t3 != e3));
  }
}
function at(e2) {
  const { terminateTimeout: t2 } = e2;
  t2 && (clearTimeout(t2), e2.terminateTimeout = null);
}
const st = 65536, ot = "writable";
class lt {
  constructor() {
    this.size = 0;
  }
  init() {
    this.initialized = true;
  }
}
class ct extends lt {
  get readable() {
    const e2 = this, { chunkSize: t2 = st } = e2, n2 = new ReadableStream({ start() {
      this.chunkOffset = 0;
    }, async pull(i2) {
      const { offset: r2 = 0, size: a2, diskNumberStart: s2 } = n2, { chunkOffset: o2 } = this;
      i2.enqueue(await pt(e2, r2 + o2, Math.min(t2, a2 - o2), s2)), o2 + t2 > a2 ? i2.close() : this.chunkOffset += t2;
    } });
    return n2;
  }
}
class ut extends ct {
  constructor(e2) {
    super(), Object.assign(this, { blob: e2, size: e2.size });
  }
  async readUint8Array(e2, t2) {
    const n2 = this, i2 = e2 + t2, r2 = e2 || i2 < n2.size ? n2.blob.slice(e2, i2) : n2.blob;
    let a2 = await r2.arrayBuffer();
    return a2.byteLength > t2 && (a2 = a2.slice(e2, i2)), new Uint8Array(a2);
  }
}
class dt extends lt {
  constructor(e2) {
    super();
    const t2 = new TransformStream(), n2 = [];
    e2 && n2.push(["Content-Type", e2]), Object.defineProperty(this, ot, { get: () => t2.writable }), this.blob = new Response(t2.readable, { headers: n2 }).blob();
  }
  getData() {
    return this.blob;
  }
}
class ft extends dt {
  constructor(e2) {
    super(e2), Object.assign(this, { encoding: e2, utf8: !e2 || "utf-8" == e2.toLowerCase() });
  }
  async getData() {
    const { encoding: e2, utf8: t2 } = this, n2 = await super.getData();
    if (n2.text && t2) return n2.text();
    {
      const t3 = new FileReader();
      return new Promise(((i2, r2) => {
        Object.assign(t3, { onload: ({ target: e3 }) => i2(e3.result), onerror: () => r2(t3.error) }), t3.readAsText(n2, e2);
      }));
    }
  }
}
class ht extends ct {
  constructor(e2) {
    super(), this.readers = e2;
  }
  async init() {
    const e2 = this, { readers: t2 } = e2;
    e2.lastDiskNumber = 0, e2.lastDiskOffset = 0, await Promise.all(t2.map((async (n2, i2) => {
      await n2.init(), i2 != t2.length - 1 && (e2.lastDiskOffset += n2.size), e2.size += n2.size;
    }))), super.init();
  }
  async readUint8Array(e2, t2, n2 = 0) {
    const i2 = this, { readers: r2 } = this;
    let a2, s2 = n2;
    -1 == s2 && (s2 = r2.length - 1);
    let o2 = e2;
    for (; o2 >= r2[s2].size; ) o2 -= r2[s2].size, s2++;
    const l2 = r2[s2], c2 = l2.size;
    if (o2 + t2 <= c2) a2 = await pt(l2, o2, t2);
    else {
      const r3 = c2 - o2;
      a2 = new Uint8Array(t2), a2.set(await pt(l2, o2, r3)), a2.set(await i2.readUint8Array(e2 + r3, t2 - r3, n2), r3);
    }
    return i2.lastDiskNumber = Math.max(s2, i2.lastDiskNumber), a2;
  }
}
class wt extends lt {
  constructor(e2, t2 = 4294967295) {
    super();
    const n2 = this;
    let i2, r2, a2;
    Object.assign(n2, { diskNumber: 0, diskOffset: 0, size: 0, maxSize: t2, availableSize: t2 });
    const s2 = new WritableStream({ async write(t3) {
      const { availableSize: s3 } = n2;
      if (a2) t3.length >= s3 ? (await o2(t3.slice(0, s3)), await l2(), n2.diskOffset += i2.size, n2.diskNumber++, a2 = null, await this.write(t3.slice(s3))) : await o2(t3);
      else {
        const { value: s4, done: o3 } = await e2.next();
        if (o3 && !s4) throw new Error("Writer iterator completed too soon");
        i2 = s4, i2.size = 0, i2.maxSize && (n2.maxSize = i2.maxSize), n2.availableSize = n2.maxSize, await _t(i2), r2 = s4.writable, a2 = r2.getWriter(), await this.write(t3);
      }
    }, async close() {
      await a2.ready, await l2();
    } });
    async function o2(e3) {
      const t3 = e3.length;
      t3 && (await a2.ready, await a2.write(e3), i2.size += t3, n2.size += t3, n2.availableSize -= t3);
    }
    async function l2() {
      r2.size = i2.size, await a2.close();
    }
    Object.defineProperty(n2, ot, { get: () => s2 });
  }
}
async function _t(e2, t2) {
  if (!e2.init || e2.initialized) return Promise.resolve();
  await e2.init(t2);
}
function bt(e2) {
  return Array.isArray(e2) && (e2 = new ht(e2)), e2 instanceof ReadableStream && (e2 = { readable: e2 }), e2;
}
function pt(e2, t2, n2, i2) {
  return e2.readUint8Array(t2, n2, i2);
}
const mt = "\0\u263A\u263B\u2665\u2666\u2663\u2660\u2022\u25D8\u25CB\u25D9\u2642\u2640\u266A\u266B\u263C\u25BA\u25C4\u2195\u203C\xB6\xA7\u25AC\u21A8\u2191\u2193\u2192\u2190\u221F\u2194\u25B2\u25BC !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\u2302\xC7\xFC\xE9\xE2\xE4\xE0\xE5\xE7\xEA\xEB\xE8\xEF\xEE\xEC\xC4\xC5\xC9\xE6\xC6\xF4\xF6\xF2\xFB\xF9\xFF\xD6\xDC\xA2\xA3\xA5\u20A7\u0192\xE1\xED\xF3\xFA\xF1\xD1\xAA\xBA\xBF\u2310\xAC\xBD\xBC\xA1\xAB\xBB\u2591\u2592\u2593\u2502\u2524\u2561\u2562\u2556\u2555\u2563\u2551\u2557\u255D\u255C\u255B\u2510\u2514\u2534\u252C\u251C\u2500\u253C\u255E\u255F\u255A\u2554\u2569\u2566\u2560\u2550\u256C\u2567\u2568\u2564\u2565\u2559\u2558\u2552\u2553\u256B\u256A\u2518\u250C\u2588\u2584\u258C\u2590\u2580\u03B1\xDF\u0393\u03C0\u03A3\u03C3\xB5\u03C4\u03A6\u0398\u03A9\u03B4\u221E\u03C6\u03B5\u2229\u2261\xB1\u2265\u2264\u2320\u2321\xF7\u2248\xB0\u2219\xB7\u221A\u207F\xB2\u25A0 ".split(""), gt = 256 == mt.length;
function yt(e2, t2) {
  return t2 && "cp437" == t2.trim().toLowerCase() ? (function(e3) {
    if (gt) {
      let t3 = "";
      for (let n2 = 0; n2 < e3.length; n2++) t3 += mt[e3[n2]];
      return t3;
    }
    return new TextDecoder().decode(e3);
  })(e2) : new TextDecoder(t2).decode(e2);
}
const xt = "filename", kt = "rawFilename", vt = "comment", St = "rawComment", zt = "uncompressedSize", At = "compressedSize", Ut = "offset", Dt = "diskNumberStart", Et = "lastModDate", Tt = "rawLastModDate", Ft = "lastAccessDate", Ot = "rawLastAccessDate", Ct = "creationDate", Wt = "rawCreationDate", jt = [xt, kt, At, zt, Et, Tt, vt, St, Ft, Ct, Ut, Dt, Dt, "internalFileAttribute", "externalFileAttribute", "msDosCompatible", "zip64", "encrypted", "version", "versionMadeBy", "zipCrypto", "directory", "bitFlag", "signature", "filenameUTF8", "commentUTF8", "compressionMethod", "extraField", "rawExtraField", "extraFieldZip64", "extraFieldUnicodePath", "extraFieldUnicodeComment", "extraFieldAES", "extraFieldNTFS", "extraFieldExtendedTimestamp"];
class Mt {
  constructor(e2) {
    jt.forEach(((t2) => this[t2] = e2[t2]));
  }
}
const Lt = "File format is not recognized", Pt = "Zip64 extra field not found", Rt = "Compression method not supported", Bt = "Split zip file", It = "utf-8", Nt = "cp437", Vt = [[zt, g], [At, g], [Ut, g], [Dt, y]], qt = { [y]: { getValue: tn, bytes: 4 }, [g]: { getValue: nn, bytes: 8 } };
class Ht {
  constructor(e2, t2 = {}) {
    Object.assign(this, { reader: bt(e2), options: t2, config: T });
  }
  async *getEntriesGenerator(e2 = {}) {
    const t2 = this;
    let { reader: n2 } = t2;
    const { config: i2 } = t2;
    if (await _t(n2), n2.size !== S && n2.readUint8Array || (n2 = new ut(await new Response(n2.readable).blob()), await _t(n2)), n2.size < v) throw new Error(Lt);
    n2.chunkSize = (function(e3) {
      return Math.max(e3.chunkSize, 64);
    })(i2);
    const r2 = await (async function(e3, t3, n3, i3, r3) {
      const a3 = new Uint8Array(4);
      !(function(e4, t4, n4) {
        e4.setUint32(t4, n4, true);
      })(rn(a3), 0, t3);
      const s3 = i3 + r3;
      return await o3(i3) || await o3(Math.min(s3, n3));
      async function o3(t4) {
        const r4 = n3 - t4, s4 = await pt(e3, r4, t4);
        for (let e4 = s4.length - i3; e4 >= 0; e4--) if (s4[e4] == a3[0] && s4[e4 + 1] == a3[1] && s4[e4 + 2] == a3[2] && s4[e4 + 3] == a3[3]) return { offset: r4 + e4, buffer: s4.slice(e4, e4 + i3).buffer };
      }
    })(n2, 101010256, n2.size, v, 1048560);
    if (!r2) {
      throw 134695760 == tn(rn(await pt(n2, 0, 4))) ? new Error(Bt) : new Error("End of central directory not found");
    }
    const a2 = rn(r2);
    let s2 = tn(a2, 12), o2 = tn(a2, 16);
    const l2 = r2.offset, c2 = en(a2, 20), u2 = l2 + v + c2;
    let d2 = en(a2, 4);
    const f2 = n2.lastDiskNumber || 0;
    let h2 = en(a2, 6), w2 = en(a2, 8), _2 = 0, b2 = 0;
    if (o2 == g || s2 == g || w2 == y || h2 == y) {
      const e3 = rn(await pt(n2, r2.offset - 20, 20));
      if (117853008 == tn(e3, 0)) {
        o2 = nn(e3, 8);
        let t3 = await pt(n2, o2, 56, -1), i3 = rn(t3);
        const a3 = r2.offset - 20 - 56;
        if (tn(i3, 0) != k && o2 != a3) {
          const e4 = o2;
          o2 = a3, _2 = o2 - e4, t3 = await pt(n2, o2, 56, -1), i3 = rn(t3);
        }
        if (tn(i3, 0) != k) throw new Error("End of Zip64 central directory locator not found");
        d2 == y && (d2 = tn(i3, 16)), h2 == y && (h2 = tn(i3, 20)), w2 == y && (w2 = nn(i3, 32)), s2 == g && (s2 = nn(i3, 40)), o2 -= s2;
      }
    }
    if (o2 >= n2.size && (_2 = n2.size - o2 - s2 - v, o2 = n2.size - s2 - v), f2 != d2) throw new Error(Bt);
    if (o2 < 0) throw new Error(Lt);
    let p2 = 0, m2 = await pt(n2, o2, s2, h2), z2 = rn(m2);
    if (s2) {
      const e3 = r2.offset - s2;
      if (tn(z2, p2) != x && o2 != e3) {
        const t3 = o2;
        o2 = e3, _2 += o2 - t3, m2 = await pt(n2, o2, s2, h2), z2 = rn(m2);
      }
    }
    const A2 = r2.offset - o2 - (n2.lastDiskOffset || 0);
    if (s2 != A2 && A2 >= 0 && (s2 = A2, m2 = await pt(n2, o2, s2, h2), z2 = rn(m2)), o2 < 0 || o2 >= n2.size) throw new Error(Lt);
    const U2 = Qt(t2, e2, "filenameEncoding"), D2 = Qt(t2, e2, "commentEncoding");
    for (let r3 = 0; r3 < w2; r3++) {
      const a3 = new Kt(n2, i2, t2.options);
      if (tn(z2, p2) != x) throw new Error("Central directory header not found");
      Zt(a3, z2, p2 + 6);
      const s3 = Boolean(a3.bitFlag.languageEncodingFlag), o3 = p2 + 46, l3 = o3 + a3.filenameLength, c3 = l3 + a3.extraFieldLength, u3 = en(z2, p2 + 4), d3 = true, f3 = m2.subarray(o3, l3), h3 = en(z2, p2 + 32), g2 = c3 + h3, y2 = m2.subarray(c3, g2), k2 = s3, v2 = s3, A3 = d3 && !(16 & ~$t(z2, p2 + 38)), E3 = tn(z2, p2 + 42) + _2;
      Object.assign(a3, { versionMadeBy: u3, msDosCompatible: d3, compressedSize: 0, uncompressedSize: 0, commentLength: h3, directory: A3, offset: E3, diskNumberStart: en(z2, p2 + 34), internalFileAttribute: en(z2, p2 + 36), externalFileAttribute: tn(z2, p2 + 38), rawFilename: f3, filenameUTF8: k2, commentUTF8: v2, rawExtraField: m2.subarray(l3, c3) });
      const T3 = Qt(t2, e2, "decodeText") || yt, F2 = k2 ? It : U2 || Nt, O2 = v2 ? It : D2 || Nt;
      let C2 = T3(f3, F2);
      C2 === S && (C2 = yt(f3, F2));
      let W2 = T3(y2, O2);
      W2 === S && (W2 = yt(y2, O2)), Object.assign(a3, { rawComment: y2, filename: C2, comment: W2, directory: A3 || C2.endsWith("/") }), b2 = Math.max(E3, b2), await Gt(a3, a3, z2, p2 + 6), a3.zipCrypto = a3.encrypted && !a3.extraFieldAES;
      const j2 = new Mt(a3);
      j2.getData = (e3, t3) => a3.getData(e3, j2, t3), p2 = g2;
      const { onprogress: M2 } = e2;
      if (M2) try {
        await M2(r3 + 1, w2, new Mt(a3));
      } catch (e3) {
      }
      yield j2;
    }
    const E2 = Qt(t2, e2, "extractPrependedData"), T2 = Qt(t2, e2, "extractAppendedData");
    return E2 && (t2.prependedData = b2 > 0 ? await pt(n2, 0, b2) : new Uint8Array()), t2.comment = c2 ? await pt(n2, l2 + v, c2) : new Uint8Array(), T2 && (t2.appendedData = u2 < n2.size ? await pt(n2, u2, n2.size - u2) : new Uint8Array()), true;
  }
  async getEntries(e2 = {}) {
    const t2 = [];
    for await (const n2 of this.getEntriesGenerator(e2)) t2.push(n2);
    return t2;
  }
  async close() {
  }
}
class Kt {
  constructor(e2, t2, n2) {
    Object.assign(this, { reader: e2, config: t2, options: n2 });
  }
  async getData(e2, t2, n2 = {}) {
    const i2 = this, { reader: r2, offset: a2, diskNumberStart: s2, extraFieldAES: o2, compressionMethod: l2, config: c2, bitFlag: u2, signature: d2, rawLastModDate: f2, uncompressedSize: h2, compressedSize: w2 } = i2, _2 = t2.localDirectory = {}, b2 = rn(await pt(r2, a2, 30, s2));
    let p2 = Qt(i2, n2, "password"), m2 = Qt(i2, n2, "rawPassword");
    const g2 = Qt(i2, n2, "passThrough");
    if (p2 = p2 && p2.length && p2, m2 = m2 && m2.length && m2, o2 && 99 != o2.originalCompressionMethod) throw new Error(Rt);
    if (0 != l2 && 8 != l2 && !g2) throw new Error(Rt);
    if (67324752 != tn(b2, 0)) throw new Error("Local file header not found");
    Zt(_2, b2, 4), _2.rawExtraField = _2.extraFieldLength ? await pt(r2, a2 + 30 + _2.filenameLength, _2.extraFieldLength, s2) : new Uint8Array(), await Gt(i2, _2, b2, 4, true), Object.assign(t2, { lastAccessDate: _2.lastAccessDate, creationDate: _2.creationDate });
    const y2 = i2.encrypted && _2.encrypted && !g2, x2 = y2 && !o2;
    if (g2 || (t2.zipCrypto = x2), y2) {
      if (!x2 && o2.strength === S) throw new Error("Encryption method not supported");
      if (!p2 && !m2) throw new Error("File contains encrypted entry");
    }
    const k2 = a2 + 30 + _2.filenameLength + _2.extraFieldLength, v2 = w2, z2 = r2.readable;
    Object.assign(z2, { diskNumberStart: s2, offset: k2, size: v2 });
    const U2 = Qt(i2, n2, "signal"), D2 = Qt(i2, n2, "checkPasswordOnly");
    D2 && (e2 = new WritableStream()), e2 = (function(e3) {
      e3.writable === S && typeof e3.next == A && (e3 = new wt(e3)), e3 instanceof WritableStream && (e3 = { writable: e3 });
      const { writable: t3 } = e3;
      return t3.size === S && (t3.size = 0), e3 instanceof wt || Object.assign(e3, { diskNumber: 0, diskOffset: 0, availableSize: 1 / 0, maxSize: 1 / 0 }), e3;
    })(e2), await _t(e2, g2 ? w2 : h2);
    const { writable: E2 } = e2, { onstart: T2, onprogress: F2, onend: O2 } = n2, C2 = { options: { codecType: Ve, password: p2, rawPassword: m2, zipCrypto: x2, encryptionStrength: o2 && o2.strength, signed: Qt(i2, n2, "checkSignature") && !g2, passwordVerification: x2 && (u2.dataDescriptor ? f2 >>> 8 & 255 : d2 >>> 24 & 255), signature: d2, compressed: 0 != l2 && !g2, encrypted: i2.encrypted && !g2, useWebWorkers: Qt(i2, n2, "useWebWorkers"), useCompressionStream: Qt(i2, n2, "useCompressionStream"), transferStreams: Qt(i2, n2, "transferStreams"), checkPasswordOnly: D2 }, config: c2, streamOptions: { signal: U2, size: v2, onstart: T2, onprogress: F2, onend: O2 } };
    let W2 = 0;
    try {
      ({ outputSize: W2 } = await rt({ readable: z2, writable: E2 }, C2));
    } catch (e3) {
      if (!D2 || e3.message != K) throw e3;
    } finally {
      const e3 = Qt(i2, n2, "preventClose");
      E2.size += W2, e3 || E2.locked || await E2.getWriter().close();
    }
    return D2 ? S : e2.getData ? e2.getData() : E2;
  }
}
function Zt(e2, t2, n2) {
  const i2 = e2.rawBitFlag = en(t2, n2 + 2), r2 = !(1 & ~i2), a2 = tn(t2, n2 + 6);
  Object.assign(e2, { encrypted: r2, version: en(t2, n2), bitFlag: { level: (6 & i2) >> 1, dataDescriptor: !(8 & ~i2), languageEncodingFlag: !(2048 & ~i2) }, rawLastModDate: a2, lastModDate: Xt(a2), filenameLength: en(t2, n2 + 22), extraFieldLength: en(t2, n2 + 24) });
}
async function Gt(e2, t2, n2, i2, r2) {
  const { rawExtraField: a2 } = t2, s2 = t2.extraField = /* @__PURE__ */ new Map(), o2 = rn(new Uint8Array(a2));
  let l2 = 0;
  try {
    for (; l2 < a2.length; ) {
      const e3 = en(o2, l2), t3 = en(o2, l2 + 2);
      s2.set(e3, { type: e3, data: a2.slice(l2 + 4, l2 + 4 + t3) }), l2 += 4 + t3;
    }
  } catch (e3) {
  }
  const c2 = en(n2, i2 + 4);
  Object.assign(t2, { signature: tn(n2, i2 + 10), uncompressedSize: tn(n2, i2 + 18), compressedSize: tn(n2, i2 + 14) });
  const u2 = s2.get(1);
  u2 && (!(function(e3, t3) {
    t3.zip64 = true;
    const n3 = rn(e3.data), i3 = Vt.filter((([e4, n4]) => t3[e4] == n4));
    for (let r3 = 0, a3 = 0; r3 < i3.length; r3++) {
      const [s3, o3] = i3[r3];
      if (t3[s3] == o3) {
        const i4 = qt[o3];
        t3[s3] = e3[s3] = i4.getValue(n3, a3), a3 += i4.bytes;
      } else if (e3[s3]) throw new Error(Pt);
    }
  })(u2, t2), t2.extraFieldZip64 = u2);
  const d2 = s2.get(28789);
  d2 && (await Jt(d2, xt, kt, t2, e2), t2.extraFieldUnicodePath = d2);
  const f2 = s2.get(25461);
  f2 && (await Jt(f2, vt, St, t2, e2), t2.extraFieldUnicodeComment = f2);
  const h2 = s2.get(39169);
  h2 ? (!(function(e3, t3, n3) {
    const i3 = rn(e3.data), r3 = $t(i3, 4);
    Object.assign(e3, { vendorVersion: $t(i3, 0), vendorId: $t(i3, 2), strength: r3, originalCompressionMethod: n3, compressionMethod: en(i3, 5) }), t3.compressionMethod = e3.compressionMethod;
  })(h2, t2, c2), t2.extraFieldAES = h2) : t2.compressionMethod = c2;
  const w2 = s2.get(10);
  w2 && (!(function(e3, t3) {
    const n3 = rn(e3.data);
    let i3, r3 = 4;
    try {
      for (; r3 < e3.data.length && !i3; ) {
        const t4 = en(n3, r3), a3 = en(n3, r3 + 2);
        1 == t4 && (i3 = e3.data.slice(r3 + 4, r3 + 4 + a3)), r3 += 4 + a3;
      }
    } catch (e4) {
    }
    try {
      if (i3 && 24 == i3.length) {
        const n4 = rn(i3), r4 = n4.getBigUint64(0, true), a3 = n4.getBigUint64(8, true), s3 = n4.getBigUint64(16, true);
        Object.assign(e3, { rawLastModDate: r4, rawLastAccessDate: a3, rawCreationDate: s3 });
        const o3 = Yt(r4), l3 = Yt(a3), c3 = { lastModDate: o3, lastAccessDate: l3, creationDate: Yt(s3) };
        Object.assign(e3, c3), Object.assign(t3, c3);
      }
    } catch (e4) {
    }
  })(w2, t2), t2.extraFieldNTFS = w2);
  const _2 = s2.get(21589);
  _2 && (!(function(e3, t3, n3) {
    const i3 = rn(e3.data), r3 = $t(i3, 0), a3 = [], s3 = [];
    n3 ? (1 & ~r3 || (a3.push(Et), s3.push(Tt)), 2 & ~r3 || (a3.push(Ft), s3.push(Ot)), 4 & ~r3 || (a3.push(Ct), s3.push(Wt))) : e3.data.length >= 5 && (a3.push(Et), s3.push(Tt));
    let o3 = 1;
    a3.forEach(((n4, r4) => {
      if (e3.data.length >= o3 + 4) {
        const a4 = tn(i3, o3);
        t3[n4] = e3[n4] = new Date(1e3 * a4);
        const l3 = s3[r4];
        e3[l3] = a4;
      }
      o3 += 4;
    }));
  })(_2, t2, r2), t2.extraFieldExtendedTimestamp = _2);
  const b2 = s2.get(6534);
  b2 && (t2.extraFieldUSDZ = b2);
}
async function Jt(e2, t2, n2, i2, r2) {
  const a2 = rn(e2.data), s2 = new W();
  s2.append(r2[n2]);
  const o2 = rn(new Uint8Array(4));
  o2.setUint32(0, s2.get(), true);
  const l2 = tn(a2, 1);
  Object.assign(e2, { version: $t(a2, 0), [t2]: yt(e2.data.subarray(5)), valid: !r2.bitFlag.languageEncodingFlag && l2 == tn(o2, 0) }), e2.valid && (i2[t2] = e2[t2], i2[t2 + "UTF8"] = true);
}
function Qt(e2, t2, n2) {
  return t2[n2] === S ? e2.options[n2] : t2[n2];
}
function Xt(e2) {
  const t2 = (4294901760 & e2) >> 16, n2 = 65535 & e2;
  try {
    return new Date(1980 + ((65024 & t2) >> 9), ((480 & t2) >> 5) - 1, 31 & t2, (63488 & n2) >> 11, (2016 & n2) >> 5, 2 * (31 & n2), 0);
  } catch (e3) {
  }
}
function Yt(e2) {
  return new Date(Number(e2 / BigInt(1e4) - BigInt(116444736e5)));
}
function $t(e2, t2) {
  return e2.getUint8(t2);
}
function en(e2, t2) {
  return e2.getUint16(t2, true);
}
function tn(e2, t2) {
  return e2.getUint32(t2, true);
}
function nn(e2, t2) {
  return Number(e2.getBigUint64(t2, true));
}
function rn(e2) {
  return new DataView(e2.buffer);
}
F({ Inflate: function(e2) {
  const t2 = new m(), i2 = e2 && e2.chunkSize ? Math.floor(2 * e2.chunkSize) : 131072, r2 = new Uint8Array(i2);
  let a2 = false;
  t2.inflateInit(), t2.next_out = r2, this.append = function(e3, s2) {
    const o2 = [];
    let l2, c2, u2 = 0, d2 = 0, f2 = 0;
    if (0 !== e3.length) {
      t2.next_in_index = 0, t2.next_in = e3, t2.avail_in = e3.length;
      do {
        if (t2.next_out_index = 0, t2.avail_out = i2, 0 !== t2.avail_in || a2 || (t2.next_in_index = 0, a2 = true), l2 = t2.inflate(0), a2 && l2 === n) {
          if (0 !== t2.avail_in) throw new Error("inflating: bad input");
        } else if (0 !== l2 && 1 !== l2) throw new Error("inflating: " + t2.msg);
        if ((a2 || 1 === l2) && t2.avail_in === e3.length) throw new Error("inflating: bad input");
        t2.next_out_index && (t2.next_out_index === i2 ? o2.push(new Uint8Array(r2)) : o2.push(r2.subarray(0, t2.next_out_index))), f2 += t2.next_out_index, s2 && t2.next_in_index > 0 && t2.next_in_index != u2 && (s2(t2.next_in_index), u2 = t2.next_in_index);
      } while (t2.avail_in > 0 || 0 === t2.avail_out);
      return o2.length > 1 ? (c2 = new Uint8Array(f2), o2.forEach((function(e4) {
        c2.set(e4, d2), d2 += e4.length;
      }))) : c2 = o2[0] ? new Uint8Array(o2[0]) : new Uint8Array(), c2;
    }
  }, this.flush = function() {
    t2.inflateEnd();
  };
} });
export {
  ut as BlobReader,
  dt as BlobWriter,
  ft as TextWriter,
  Ht as ZipReader,
  F as configure
};
