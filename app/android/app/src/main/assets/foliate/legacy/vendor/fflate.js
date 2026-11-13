var r = Uint8Array, a = Uint16Array, e = Int32Array, n = new r([0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0, 0, 0, 0]), i = new r([0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 0, 0]), t = new r([16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]), f = function(r2, n2) {
  for (var i2 = new a(31), t2 = 0; t2 < 31; ++t2) i2[t2] = n2 += 1 << r2[t2 - 1];
  var f2 = new e(i2[30]);
  for (t2 = 1; t2 < 30; ++t2) for (var o2 = i2[t2]; o2 < i2[t2 + 1]; ++o2) f2[o2] = o2 - i2[t2] << 5 | t2;
  return { b: i2, r: f2 };
}, o = f(n, 2), v = o.b, l = o.r;
v[28] = 258, l[258] = 28;
for (var u = f(i, 0).b, c = new a(32768), d = 0; d < 32768; ++d) {
  var w = (43690 & d) >> 1 | (21845 & d) << 1;
  w = (61680 & (w = (52428 & w) >> 2 | (13107 & w) << 2)) >> 4 | (3855 & w) << 4, c[d] = ((65280 & w) >> 8 | (255 & w) << 8) >> 1;
}
var b = function(r2, e2, n2) {
  for (var i2 = r2.length, t2 = 0, f2 = new a(e2); t2 < i2; ++t2) r2[t2] && ++f2[r2[t2] - 1];
  var o2, v2 = new a(e2);
  for (t2 = 1; t2 < e2; ++t2) v2[t2] = v2[t2 - 1] + f2[t2 - 1] << 1;
  if (n2) {
    o2 = new a(1 << e2);
    var l2 = 15 - e2;
    for (t2 = 0; t2 < i2; ++t2) if (r2[t2]) for (var u = t2 << 4 | r2[t2], d = e2 - r2[t2], w = v2[r2[t2] - 1]++ << d, b2 = w | (1 << d) - 1; w <= b2; ++w) o2[c[w] >> l2] = u;
  } else for (o2 = new a(i2), t2 = 0; t2 < i2; ++t2) r2[t2] && (o2[t2] = c[v2[r2[t2] - 1]++] >> 15 - r2[t2]);
  return o2;
}, s = new r(288);
for (d = 0; d < 144; ++d) s[d] = 8;
for (d = 144; d < 256; ++d) s[d] = 9;
for (d = 256; d < 280; ++d) s[d] = 7;
for (d = 280; d < 288; ++d) s[d] = 8;
var h = new r(32);
for (d = 0; d < 32; ++d) h[d] = 5;
var y = b(s, 9, 1), g = b(h, 5, 1), p = function(r2) {
  for (var a2 = r2[0], e2 = 1; e2 < r2.length; ++e2) r2[e2] > a2 && (a2 = r2[e2]);
  return a2;
}, k = function(r2, a2, e2) {
  var n2 = a2 / 8 | 0;
  return (r2[n2] | r2[n2 + 1] << 8) >> (7 & a2) & e2;
}, m = function(r2, a2) {
  var e2 = a2 / 8 | 0;
  return (r2[e2] | r2[e2 + 1] << 8 | r2[e2 + 2] << 16) >> (7 & a2);
}, x = ["unexpected EOF", "invalid block type", "invalid length/literal", "invalid distance", "stream finished", "no stream handler", , "no callback", "invalid UTF-8 data", "extra field too long", "date not in range 1980-2099", "filename too long", "stream finishing", "invalid zip data"], T = function(r2, a2, e2) {
  var n2 = new Error(a2 || x[r2]);
  if (n2.code = r2, Error.captureStackTrace && Error.captureStackTrace(n2, T), !e2) throw n2;
  return n2;
}, E = function(a2, e2, f2, o2) {
  var l2 = a2.length, c = o2 ? o2.length : 0;
  if (!l2 || e2.f && !e2.l) return f2 || new r(0);
  var d = !f2, w = d || 2 != e2.i, s2 = e2.i;
  d && (f2 = new r(3 * l2));
  var h2 = function(a3) {
    var e3 = f2.length;
    if (a3 > e3) {
      var n2 = new r(Math.max(2 * e3, a3));
      n2.set(f2), f2 = n2;
    }
  }, x2 = e2.f || 0, E2 = e2.p || 0, z2 = e2.b || 0, A2 = e2.l, U2 = e2.d, D = e2.m, F = e2.n, M = 8 * l2;
  do {
    if (!A2) {
      x2 = k(a2, E2, 1);
      var S = k(a2, E2 + 1, 3);
      if (E2 += 3, !S) {
        var I = a2[(N = 4 + ((E2 + 7) / 8 | 0)) - 4] | a2[N - 3] << 8, O = N + I;
        if (O > l2) {
          s2 && T(0);
          break;
        }
        w && h2(z2 + I), f2.set(a2.subarray(N, O), z2), e2.b = z2 += I, e2.p = E2 = 8 * O, e2.f = x2;
        continue;
      }
      if (1 == S) A2 = y, U2 = g, D = 9, F = 5;
      else if (2 == S) {
        var j = k(a2, E2, 31) + 257, q = k(a2, E2 + 10, 15) + 4, B = j + k(a2, E2 + 5, 31) + 1;
        E2 += 14;
        for (var C = new r(B), G = new r(19), H = 0; H < q; ++H) G[t[H]] = k(a2, E2 + 3 * H, 7);
        E2 += 3 * q;
        var J = p(G), K = (1 << J) - 1, L = b(G, J, 1);
        for (H = 0; H < B; ) {
          var N, P = L[k(a2, E2, K)];
          if (E2 += 15 & P, (N = P >> 4) < 16) C[H++] = N;
          else {
            var Q = 0, R = 0;
            for (16 == N ? (R = 3 + k(a2, E2, 3), E2 += 2, Q = C[H - 1]) : 17 == N ? (R = 3 + k(a2, E2, 7), E2 += 3) : 18 == N && (R = 11 + k(a2, E2, 127), E2 += 7); R--; ) C[H++] = Q;
          }
        }
        var V = C.subarray(0, j), W = C.subarray(j);
        D = p(V), F = p(W), A2 = b(V, D, 1), U2 = b(W, F, 1);
      } else T(1);
      if (E2 > M) {
        s2 && T(0);
        break;
      }
    }
    w && h2(z2 + 131072);
    for (var X = (1 << D) - 1, Y = (1 << F) - 1, Z = E2; ; Z = E2) {
      var $ = (Q = A2[m(a2, E2) & X]) >> 4;
      if ((E2 += 15 & Q) > M) {
        s2 && T(0);
        break;
      }
      if (Q || T(2), $ < 256) f2[z2++] = $;
      else {
        if (256 == $) {
          Z = E2, A2 = null;
          break;
        }
        var _ = $ - 254;
        if ($ > 264) {
          var rr = n[H = $ - 257];
          _ = k(a2, E2, (1 << rr) - 1) + v[H], E2 += rr;
        }
        var ar = U2[m(a2, E2) & Y], er = ar >> 4;
        ar || T(3), E2 += 15 & ar;
        W = u[er];
        if (er > 3) {
          rr = i[er];
          W += m(a2, E2) & (1 << rr) - 1, E2 += rr;
        }
        if (E2 > M) {
          s2 && T(0);
          break;
        }
        w && h2(z2 + 131072);
        var nr = z2 + _;
        if (z2 < W) {
          var ir = c - W, tr = Math.min(W, nr);
          for (ir + z2 < 0 && T(3); z2 < tr; ++z2) f2[z2] = o2[ir + z2];
        }
        for (; z2 < nr; ++z2) f2[z2] = f2[z2 - W];
      }
    }
    e2.l = A2, e2.p = Z, e2.b = z2, e2.f = x2, A2 && (x2 = 1, e2.m = D, e2.d = U2, e2.n = F);
  } while (!x2);
  return z2 != f2.length && d ? (function(a3, e3, n2) {
    return (null == n2 || n2 > a3.length) && (n2 = a3.length), new r(a3.subarray(e3, n2));
  })(f2, 0, z2) : f2.subarray(0, z2);
}, z = new r(0);
function A(r2, a2) {
  return E(r2.subarray((e2 = r2, n2 = a2 && a2.dictionary, (8 != (15 & e2[0]) || e2[0] >> 4 > 7 || (e2[0] << 8 | e2[1]) % 31) && T(6, "invalid zlib data"), (e2[1] >> 5 & 1) == +!n2 && T(6, "invalid zlib data: " + (32 & e2[1] ? "need" : "unexpected") + " dictionary"), 2 + (e2[1] >> 3 & 4)), -4), { i: 2 }, a2 && a2.out, a2 && a2.dictionary);
  var e2, n2;
}
var U = "undefined" != typeof TextDecoder && new TextDecoder();
try {
  U.decode(z, { stream: true });
} catch (r2) {
}
export {
  A as unzlibSync
};
