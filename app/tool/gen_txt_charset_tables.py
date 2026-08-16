"""依 epic-11-multi-format-reader Issue 4 規劃：從 Unicode.org 發布的
Microsoft 字碼頁對照表下載 Big5 (CP950) 與 GBK (CP936) 雙位元組→Unicode
對照資料，產生 app/lib/library/txt_charset_tables.dart（純資料，無邏輯，
勿手動修改）。執行一次即可，結果提交進版控，之後不需要重跑，除非要更新
來源資料版本。
"""
import base64
import re
import struct
import urllib.request
from pathlib import Path

SOURCES = {
    'Big5': 'https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP950.TXT',
    'Gbk': 'https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP936.TXT',
}


def fetch_table(url):
    with urllib.request.urlopen(url, timeout=30) as resp:
        text = resp.read().decode('utf-8')
    entries = []
    for line in text.splitlines():
        m = re.match(r'^0x([0-9A-Fa-f]{4})\s+0x([0-9A-Fa-f]{4})', line)
        if not m:
            continue
        entries.append((int(m.group(1), 16), int(m.group(2), 16)))
    entries.sort()
    keys = [e for e, _ in entries]
    assert keys == sorted(set(keys)), '鍵值須嚴格遞增且不重複（供 Dart 端二分搜尋）'
    return entries


def pack_base64(entries):
    keys = struct.pack('<%dH' % len(entries), *(k for k, _ in entries))
    vals = struct.pack('<%dH' % len(entries), *(v for _, v in entries))
    return base64.b64encode(keys).decode(), base64.b64encode(vals).decode()


def main():
    out_lines = [
        '// GENERATED FILE — 由 app/tool/gen_txt_charset_tables.py 產生，請勿手動修改。',
        '//',
        '// 資料來源（epic-11-multi-format-reader Issue 4）：Unicode.org 發布的 Microsoft',
        '// 字碼頁對照表，雙位元組值 → Unicode 碼點的直接對照（非 WHATWG pointer-index',
        '// 演算法格式，查表不需額外演算法轉換）：',
        '//   Big5（CP950）：https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP950.TXT',
        '//   GBK （CP936）：https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP936.TXT',
        '// big5-hkscs 優先層與 big5 共用同一份表（HKSCS 是 Big5 的向上相容超集，本專案',
        '// 未取得可直接使用的位元組對映表，增補字元退化為 U+FFFD，屬已知有界限制，見',
        '// txt_charset_detection.dart 文件註解）。',
        '',
    ]
    for name, url in SOURCES.items():
        entries = fetch_table(url)
        keys_b64, vals_b64 = pack_base64(entries)
        const_prefix = 'k' + name + 'Table'
        out_lines.append(f'// {name}：{len(entries)} 筆雙位元組項目。')
        out_lines.append(f"const String {const_prefix}KeysBase64 = '{keys_b64}';")
        out_lines.append(f"const String {const_prefix}ValuesBase64 = '{vals_b64}';")
        out_lines.append('')
    out_path = Path(__file__).resolve().parent.parent / 'lib' / 'library' / 'txt_charset_tables.dart'
    out_path.write_text('\n'.join(out_lines), encoding='utf-8')
    print(f'寫入 {out_path}（{out_path.stat().st_size} bytes）')


if __name__ == '__main__':
    main()
