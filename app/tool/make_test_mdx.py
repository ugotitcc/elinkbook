"""產生自製的 MDX／MDD 測試檔（MDict 格式 v2.0），供 epic-63 的單元測試使用。

本檔完全自寫，未複製任何第三方程式碼；只使用 Python 標準函式庫。
格式細節取自 MDict 的公開檔案結構說明，產出的檔案僅供測試，不含真實字典內容。

用法：
    python3 -X utf8 make_test_mdx.py <kind> <out_path> [--entries N] [--body-bytes N]

kind：
    zlib                      50 筆，zlib 壓縮、KeyCaseSensitive=No
    mdd                       最小 MDD（圖片與 CSS 各一筆）
    images                    成對的 MDX（pic 詞條）與 MDD（PNG 與 MP3）
    fake-lzo                  記錄區塊標成 LZO（實際內容任意），用來測不支援壓縮
    truncated                 把正常檔砍半，模擬下載中斷
    cut-records               砍掉檔尾 80 位元組（只傷到記錄區塊，檔頭與鍵區完整）
    html                      詞條含 entry://、bword://、#x、sound://、http:// 與
                              <link href="ghychyz.css">，標頭有 StyleSheet
    strip-key                 StripKey=Yes，鍵含「一」等 CJK 字
    case-sensitive            KeyCaseSensitive=Yes，只收小寫鍵 apple
    placeholder-title         Title 是預設佔位字串，Description 有內容
    placeholder-title-empty   同上但 Description 為空（顯示名稱應退回檔名）
    v1                        MDict 1.2 版格式（4 位元組數字、鍵區標頭無 checksum、
                              鍵區塊資訊不壓縮），供 validateBlocks 的 v1 路徑測試
    strip-phrases             StripKey=Yes，鍵含空白與連字號的英文片語
                              （a la carte／a-bomb／a b／apple），檔內依「去空白標點、
                              轉小寫」後的鍵排序（真實製作工具的慣例）
    encrypted-yes             標頭 Encrypted="Yes"（舊格式的記錄區塊加密，等同 1）
    multi-block               區塊上限調到 512 位元組，約 300 筆、含跨區塊的重複鍵
                              （dupkey 60 筆），測鍵區塊／記錄區塊的跨塊路徑
    large / large-cjk         合成大檔，供 Issue 6a 記憶體補測（不進版控）

產物為二進位檔，請勿手改；要調整測試資料就改本檔後重新產生。
"""

import argparse
import base64
import os
import random
import struct
import unicodedata
import zlib

BLOCK_LIMIT = 64 * 1024  # 每個記錄／關鍵字區塊解壓後上限

# 預設佔位標題：MDict 工具在沒有真標題時會寫入這個字串。
PLACEHOLDER_TITLE = "Title (No HTML code allowed)"


# ---------------------------------------------------------------- 小工具
def _xml_attr(value: str) -> str:
    """把字串放進 XML 屬性值（雙引號包住）。"""
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def _sort_key(key: str, strip_key: bool) -> str:
    """檔內排序用的鍵。StripKey=Yes 時去掉空白與標點再轉小寫。"""
    if strip_key:
        key = "".join(
            ch for ch in key if not (ch.isspace() or unicodedata.category(ch).startswith("P"))
        )
    return key.lower()


def truncate(data: bytes) -> bytes:
    """砍掉後半，模擬下載中斷的損壞檔。"""
    return data[: len(data) // 2]


def cut_record_tail(data: bytes) -> bytes:
    """砍掉檔尾 80 位元組。記錄區塊在檔案最後，所以檔頭與關鍵字區仍完整，
    initDict 會成功，但記錄位移會超出可用區塊（模擬只下載一部分）。"""
    return data[:-80]


def large_entries(n: int, body_bytes: int):
    """合成大量詞條。內文用固定種子的隨機位元組做 base64，zlib 壓縮率約 75%，
    避免重複內容被壓到很小而讓效能量測失去代表性。"""
    rng = random.Random(0)
    raw_len = (body_bytes * 3) // 4 + 3
    entries = []
    for i in range(n):
        body = base64.b64encode(rng.randbytes(raw_len)).decode("ascii")[:body_bytes]
        entries.append((f"word{i:07d}", body))
    return entries


def large_cjk_entries(n: int, body_bytes: int):
    """Issue 6a 補測用：40 萬筆、鍵為 3 個 CJK 字元（UTF-16），內文用固定種子的
    隨機 base64（與 large_entries 相同的理由：避免壓縮率失真）。"""
    rng = random.Random(0)
    raw_len = (body_bytes * 3) // 4 + 3
    pool = 3000  # U+4E00 起連續 3000 個 CJK 字
    entries = []
    for i in range(n):
        a, rem = divmod(i, pool * pool)
        b, c = divmod(rem, pool)
        key = chr(0x4E00 + a) + chr(0x4E00 + b) + chr(0x4E00 + c)
        body = base64.b64encode(rng.randbytes(raw_len)).decode("ascii")[:body_bytes]
        entries.append((key, body))
    return entries


def _pack_block(decomp: bytes, compression: int) -> bytes:
    """壓縮區塊 = 4 位元組小端型態 + 4 位元組大端 Adler-32(解壓後) + 資料。"""
    adler = struct.pack(">I", zlib.adler32(decomp) & 0xFFFFFFFF)
    if compression == 0:
        payload = decomp
    elif compression == 2:
        payload = zlib.compress(decomp)
    elif compression == 1:
        payload = b"\x5a" * 64  # 假的 LZO：型態標 1，內容為任意位元組
    else:
        raise ValueError(f"不支援的壓縮型態 {compression}")
    return struct.pack("<I", compression) + adler + payload


def _encode_text(text: str, utf16: bool) -> bytes:
    return text.encode("utf-16-le" if utf16 else "utf-8")


def _term(utf16: bool) -> bytes:
    return b"\x00\x00" if utf16 else b"\x00"


def _text_len(text: str, utf16: bool) -> int:
    """鍵長度：UTF-8 以位元組計，UTF-16 以 code unit 計。"""
    return len(text.encode("utf-16-le")) // 2 if utf16 else len(text.encode("utf-8"))


def _header_bytes(xml: str) -> bytes:
    """檔頭：4 位元組大端長度 + UTF-16LE XML（結尾含 \\x00\\x00，長度與 Adler-32 都計入）
    + 4 位元組小端 Adler-32。"""
    body = (xml + "\r\n\x00").encode("utf-16-le")
    return struct.pack(">I", len(body)) + body + struct.pack("<I", zlib.adler32(body) & 0xFFFFFFFF)


def _group(items, size_of, limit):
    """把 items 依 size_of 累加，不超過 limit 分組（單一項目超過時獨佔一組）。"""
    groups, cur, cur_size = [], [], 0
    for it in items:
        s = size_of(it)
        if cur and cur_size + s > limit:
            groups.append(cur)
            cur, cur_size = [], 0
        cur.append(it)
        cur_size += s
    if cur:
        groups.append(cur)
    return groups


def _assemble(
    header_xml: str,
    keys,
    records,
    *,
    utf16_keys: bool,
    record_compression: int,
    block_limit: int = BLOCK_LIMIT,
    v1: bool = False,
) -> bytes:
    """keys: 已排序的鍵字串；records: 與 keys 同序的記錄位元組（已含結尾字元）。

    v1=True 時輸出 MDict 1.2 版結構：數字 4 位元組、鍵區標頭只有 4 個數字且
    沒有 checksum、鍵區塊資訊不壓縮、鍵文字長度欄位 1 位元組且無結尾字元。"""
    num = ">I" if v1 else ">Q"
    # --- 記錄區
    offsets, acc = [], 0
    for r in records:
        offsets.append(acc)
        acc += len(r)
    rec_groups = _group(list(range(len(records))), lambda i: len(records[i]), block_limit)
    rec_blocks, rec_info = [], []
    for g in rec_groups:
        decomp = b"".join(records[i] for i in g)
        blk = _pack_block(decomp, record_compression)
        rec_blocks.append(blk)
        rec_info.append((len(blk), len(decomp)))
    rec_info_bytes = b"".join(struct.pack(num, c) + struct.pack(num, d) for c, d in rec_info)
    rec_blocks_bytes = b"".join(rec_blocks)
    record_section = (
        b"".join(
            struct.pack(num, v)
            for v in (len(rec_blocks), len(records), len(rec_info_bytes), len(rec_blocks_bytes))
        )
        + rec_info_bytes
        + rec_blocks_bytes
    )

    # --- 關鍵字區
    term = _term(utf16_keys)

    def key_entry(i):
        return struct.pack(num, offsets[i]) + _encode_text(keys[i], utf16_keys) + term

    key_groups = _group(list(range(len(keys))), lambda i: len(key_entry(i)), block_limit // 2)
    key_blocks, info_parts = [], []
    for g in key_groups:
        decomp = b"".join(key_entry(i) for i in g)
        blk = _pack_block(decomp, 2)
        key_blocks.append(blk)
        head, tail = keys[g[0]], keys[g[-1]]
        if v1:
            info_parts.append(
                struct.pack(num, len(g))
                + struct.pack(">B", _text_len(head, utf16_keys)) + _encode_text(head, utf16_keys)
                + struct.pack(">B", _text_len(tail, utf16_keys)) + _encode_text(tail, utf16_keys)
                + struct.pack(num, len(blk)) + struct.pack(num, len(decomp))
            )
        else:
            info_parts.append(
                struct.pack(">Q", len(g))
                + struct.pack(">H", _text_len(head, utf16_keys)) + _encode_text(head, utf16_keys) + term
                + struct.pack(">H", _text_len(tail, utf16_keys)) + _encode_text(tail, utf16_keys) + term
                + struct.pack(">2Q", len(blk), len(decomp))
            )
    info_decomp = b"".join(info_parts)
    key_blocks_bytes = b"".join(key_blocks)
    if v1:
        # v1：鍵區標頭 4 個數字、無 checksum；鍵區塊資訊直接存放、不壓縮。
        key_head = b"".join(
            struct.pack(num, v)
            for v in (len(key_blocks), len(keys), len(info_decomp), len(key_blocks_bytes))
        )
        key_section = key_head + info_decomp + key_blocks_bytes
    else:
        info_block = _pack_block(info_decomp, 2)
        key_head = struct.pack(">5Q", len(key_blocks), len(keys), len(info_decomp), len(info_block), len(key_blocks_bytes))
        key_section = key_head + struct.pack(">I", zlib.adler32(key_head) & 0xFFFFFFFF) + info_block + key_blocks_bytes

    return _header_bytes(header_xml) + key_section + record_section


# ---------------------------------------------------------------- 公開函式
def build_mdx(
    entries,
    *,
    encoding: str,
    record_compression: int,
    key_case_sensitive: bool = False,
    strip_key: bool = False,
    title: str = "Test fixture",
    description: str = "epic-63 test fixture",
    stylesheet: str = "",
    block_limit: int = BLOCK_LIMIT,
    v1: bool = False,
    encrypted: str = "0",
) -> bytes:
    """entries: list[(key, text)]。encoding：'UTF-8' 或 'UTF-16'（UTF-16LE）。

    排序：strip_key=True 時依「去空白標點、轉小寫」後的鍵（真實製作工具的慣例），
    否則依小寫鍵；同鍵維持輸入順序（穩定排序）。"""
    utf16 = encoding.upper() == "UTF-16"
    ordered = sorted(entries, key=lambda kv: _sort_key(kv[0], strip_key))
    keys = [k for k, _ in ordered]
    rec_term = _term(utf16)
    records = [_encode_text(t, utf16) + rec_term for _, t in ordered]
    xml = (
        f'<Dictionary GeneratedByEngineVersion="{"1.2" if v1 else "2.0"}" '
        f'RequiredEngineVersion="{"1.2" if v1 else "2.0"}" Encrypted="{encrypted}" '
        f'Encoding="{encoding}" Format="Html" '
        f'KeyCaseSensitive="{"Yes" if key_case_sensitive else "No"}" '
        f'StripKey="{"Yes" if strip_key else "No"}" '
        f'Title="{_xml_attr(title)}" Description="{_xml_attr(description)}" '
        f'StyleSheet="{_xml_attr(stylesheet)}" />'
    )
    return _assemble(
        xml,
        keys,
        records,
        utf16_keys=utf16,
        record_compression=record_compression,
        block_limit=block_limit,
        v1=v1,
    )


def build_mdd(entries) -> bytes:
    """entries: list[(key, bytes)]。MDD 的鍵固定為 UTF-16LE，記錄不加結尾字元。"""
    ordered = sorted(entries, key=lambda kv: kv[0].lower())
    keys = [k for k, _ in ordered]
    records = [b for _, b in ordered]
    xml = (
        '<Library_Data GeneratedByEngineVersion="2.0" RequiredEngineVersion="2.0" Encrypted="0" '
        'Encoding="" Format="" KeyCaseSensitive="No" StripKey="No" Compact="Yes" Compat="Yes" '
        'Title="" Description="mdd test fixture" DataSourceFormat="106" StyleSheet="" />'
    )
    return _assemble(xml, keys, records, utf16_keys=True, record_compression=2)


def _make_png(size: int, cross: bool) -> bytes:
    """產生 size×size 的灰階 PNG：黑色粗外框、白底，cross 為真時再畫兩條對角線。

    只用標準函式庫（struct、zlib）。圖要夠大、夠黑白分明，真機（含電子紙）上
    肉眼一看就知道圖有沒有顯示；1×1 的圖看不出來。
    """
    import struct
    import zlib

    border = max(2, size // 16)
    rows = []
    for y in range(size):
        row = bytearray([0])  # 每列的濾鏡型別 0（None）
        for x in range(size):
            on_border = (
                x < border or y < border or x >= size - border or y >= size - border
            )
            on_cross = cross and (abs(x - y) < border or abs(x - (size - 1 - y)) < border)
            row.append(0 if (on_border or on_cross) else 255)
        rows.append(bytes(row))

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 0, 0, 0, 0)  # 8 位元灰階
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(b"".join(rows)))
        + chunk(b"IEND", b"")
    )


_TINY_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000d49444154789c6360f8cfc000000301010018dd8db00000000049454e44ae426082"
)


def _small_entries(n: int):
    """前四筆涵蓋：同一個折疊鍵的兩筆記錄（apple／Apple）、拉丁擴充字元、CJK。"""
    base = [
        ("apple", "<b>apple</b> 蘋果"),
        ("Apple", "<b>Apple</b> 蘋果公司"),
        ("café", "<b>café</b> 咖啡館"),
        ("相濡以沫", "<b>相濡以沫</b> 比喻同處困境，互相扶持"),
    ]
    extra = [(f"w{i:04d}", f"<p>definition {i}</p>") for i in range(max(0, n - len(base)))]
    return (base + extra)[:n]


def _html_entries():
    """Task 4／Task 5／Task 9 的連結、錨點與 CSS 測試資料。詞條都排在最前面，方便抽樣。

    `apple` 刻意是完整 HTML 文件（含 `<title>`），讓 Task 9 的真機整合測試
    不必執行 JavaScript 也能用 `getTitle()` 判斷「頁面已載入」與「頁面
    JavaScript 沒有執行」。最前面三個 20vh 的區塊連結讓點擊座標穩定。
    """
    apple = (
        '<html><head><meta charset="utf-8">'
        '<title>MDX 詞條 apple</title>'
        '<link rel="stylesheet" href="ghychyz.css">'
        '</head><body style="margin:0">'
        '<a href="entry://banana" style="display:block;height:20vh">entry</a>'
        '<a href="#n1" style="display:block;height:20vh">anchor</a>'
        '<a href="entry://#n1" style="display:block;height:20vh">'
        'entry anchor</a>'
        '<h1>apple</h1><p>蘋果</p>'
        '<a href="entry://apple">apple（entry）</a>'
        '<a href="entry://Apple">Apple（entry，大小寫不同）</a>'
        '<a href="entry://apple#n1">apple 的義項（entry＋錨點）</a>'
        '<a href="#n1">本頁義項（純錨點）</a>'
        '<a href="bword://banana">banana（bword）</a>'
        '<a href="sound://apple.wav">發音（sound）</a>'
        '<a href="http://example.com">外部網站</a>'
        '<p id="js-target">原值</p>'
        # Task 9：JavaScript 關閉時，這段不得改動 title 或 DOM。
        '<script>document.title="JS_RAN";'
        'document.body.setAttribute("data-js-ran","yes");'
        'document.getElementById("js-target").textContent="已變更";</script>'
        # Task 9：任何對外請求都應被攔截成 404。
        '<img id="remote-image" src="https://example.com/mdx-probe.png">'
        '<div style="height:3000px"></div>'
        '<p id="n1">義項一</p>'
        '</body></html>'
    )
    banana = (
        '<html><head><meta charset="utf-8">'
        '<title>MDX 詞條 banana</title></head>'
        '<body><b>banana</b> 香蕉</body></html>'
    )
    return [
        ("apple", apple),
        ("banana", banana),
        ("天地", '<b>天地</b> <a href="entry://%E5%A4%A9%E5%9C%B0">自身連結</a>'),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "kind",
        choices=[
            "zlib",
            "mdd",
            "images",
            "fake-lzo",
            "truncated",
            "cut-records",
            "html",
            "strip-key",
            "case-sensitive",
            "placeholder-title",
            "placeholder-title-empty",
            "v1",
            "strip-phrases",
            "multi-block",
            "encrypted-yes",
            "large",
            "large-cjk",
        ],
    )
    ap.add_argument("out")
    ap.add_argument("--entries", type=int, default=None)
    ap.add_argument("--body-bytes", type=int, default=330)
    a = ap.parse_args()

    if a.kind == "mdd":
        data = build_mdd([("\\pic\\a b.png", _TINY_PNG), ("\\css\\x.css", b"body{color:#000}")])
    elif a.kind == "images":
        mdx_data = build_mdx(
            [("pic", '<h3>pic</h3><p>圖片測試：下面應有兩張黑框方塊圖（第一張有叉）。</p>'
                   '<p><img src="pic/a b.png"> <img src="pic/sub/c.png"></p>')],
            encoding="UTF-8",
            record_compression=2,
            title="Images test fixture",
            description="epic-63 images test fixture",
        )
        mdd_data = build_mdd([
            (r"\pic\a b.png", _make_png(64, cross=True)),
            (r"\pic\sub\c.png", _make_png(64, cross=False)),
            (r"\snd\x.mp3", b"ID3\x03\x00\x00\x00\x00\x00\x00fake-mp3-bytes"),
        ])
        mdd_out = os.path.splitext(a.out)[0] + ".mdd"
        with open(mdd_out, "wb") as f:
            f.write(mdd_data)
        print(f"images (mdd): {len(mdd_data)} bytes -> {mdd_out}")
        data = mdx_data
    elif a.kind == "large":
        data = build_mdx(
            large_entries(a.entries or 400000, a.body_bytes),
            encoding="UTF-8",
            record_compression=2,
        )
    elif a.kind == "large-cjk":
        data = build_mdx(
            large_cjk_entries(a.entries or 400000, a.body_bytes),
            encoding="UTF-16",
            record_compression=2,
        )
    elif a.kind == "html":
        # StyleSheet 屬性固定是三行一組（編號、開始片段、結束片段）；
        # 只有一行會讓 dict_reader 的解析爆掉，所以這裡給一組合法的值。
        data = build_mdx(
            _html_entries(),
            encoding="UTF-8",
            record_compression=2,
            stylesheet='1\n<span class="ghychyz-s1">\n</span>',
        )
    elif a.kind == "strip-key":
        entries = [("一", "<b>一</b> 數字之一"), ("二", "<b>二</b> 數字之二")] + [
            (f"w{i:04d}", f"<p>definition {i}</p>") for i in range(48)
        ]
        data = build_mdx(
            entries,
            encoding="UTF-8",
            record_compression=2,
            strip_key=True,
        )
    elif a.kind == "v1":
        data = build_mdx(
            _small_entries(a.entries or 50),
            encoding="UTF-8",
            record_compression=2,
            v1=True,
        )
    elif a.kind == "encrypted-yes":
        # 舊格式的記錄區塊加密旗標：標頭寫 Encrypted="Yes"（等同 1）。
        data = build_mdx(
            _small_entries(a.entries or 50),
            encoding="UTF-8",
            record_compression=2,
            encrypted="Yes",
        )
    elif a.kind == "strip-phrases":
        # 刻意讓「原字串順序」與「去空白標點後順序」不同：
        # 原字串：a b < a la carte < a-bomb < apple；去除後：ab < abomb < alacarte < apple。
        entries = [
            ("a la carte", "<b>a la carte</b> 照菜單點菜"),
            ("a-bomb", "<b>a-bomb</b> 原子彈"),
            ("apple", "<b>apple</b> 蘋果"),
            ("a b", "<b>a b</b> 空白測試"),
        ] + [(f"w{i:04d}", f"<p>definition {i}</p>") for i in range(46)]
        data = build_mdx(entries, encoding="UTF-8", record_compression=2, strip_key=True)
    elif a.kind == "multi-block":
        # 區塊上限 512 位元組：鍵區塊約 256 位元組、記錄區塊 512 位元組。
        entries = [(f"k{i:04d}", f"<p>entry {i}</p>") for i in range(240)] + [
            ("dupkey", f"<p>dup-{i:03d}</p>") for i in range(60)
        ]
        data = build_mdx(entries, encoding="UTF-8", record_compression=2, block_limit=512)
    elif a.kind == "case-sensitive":
        # 只收小寫鍵；查詢 APPLE 時不得命中。
        entries = [("apple", "<b>apple</b> 蘋果（區分大小寫）")] + [
            (f"w{i:04d}", f"<p>definition {i}</p>") for i in range(49)
        ]
        data = build_mdx(
            entries,
            encoding="UTF-8",
            record_compression=2,
            key_case_sensitive=True,
        )
    elif a.kind in ("placeholder-title", "placeholder-title-empty"):
        description = (
            "<b>測試辭典</b><br>第二行不該出現在名稱裡"
            if a.kind == "placeholder-title"
            else ""
        )
        data = build_mdx(
            _small_entries(a.entries or 50),
            encoding="UTF-8",
            record_compression=2,
            title=PLACEHOLDER_TITLE,
            description=description,
        )
    else:
        entries = _small_entries(a.entries or 50)
        compression = 1 if a.kind == "fake-lzo" else 2
        data = build_mdx(entries, encoding="UTF-8", record_compression=compression)
        if a.kind == "truncated":
            data = truncate(data)
        elif a.kind == "cut-records":
            data = cut_record_tail(data)
    with open(a.out, "wb") as f:
        f.write(data)
    print(f"{a.kind}: {len(data)} bytes -> {a.out}")


if __name__ == "__main__":
    main()
