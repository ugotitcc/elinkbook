#!/usr/bin/env python3
"""
epic-54 Issue 34：直排兩欄錯位（176 裝置像素水平空白帶）影像偵測腳本。

背景：
在 Chrome 91 等舊版 WebView 上，直排多欄忽略根元素上下內距，使欄間隔比頁高多出一個
column-gap（72 CSS px ≈ WAVE 真機 176 裝置像素）。翻頁累積偏移後，單一畫面會同時
出現「上一頁尾巴＋下一頁開頭」的上下兩欄，兩欄之間隔著一條橫跨整個內容寬度的水平無墨空帶。
正常直排頁面的文字行由上而下延伸，段落間距為垂直方向，不會出現橫跨全寬的大高度水平空帶。

用法：
  python app/tool/detect_two_column_gap.py <png>...

輸出：
  <檔名> maxBlankBand=<像素> BUG|ok
  <檔名> INVALID frac=<有墨比例>

結束碼：
  0 = 全部為 ok
  1 = 任一張為 BUG（或 INVALID）
"""

import glob
import sys
import numpy as np
from PIL import Image

TOP_MARGIN = 100
BOTTOM_MARGIN = 60
LEFT_MARGIN = 80
RIGHT_MARGIN = 40

INK_THRESHOLD = 128
MIN_INK_FRAC = 0.03
MAX_INK_FRAC = 0.50
BUG_BAND_THRESHOLD = 80


def analyze_image(path: str) -> tuple[str, bool]:
    img = Image.open(path).convert('L')
    arr = np.asarray(img)
    h, w = arr.shape
    region = arr[TOP_MARGIN : h - BOTTOM_MARGIN, LEFT_MARGIN : w - RIGHT_MARGIN]
    ink = region < INK_THRESHOLD
    frac = float(ink.mean())
    if frac > MAX_INK_FRAC or frac < MIN_INK_FRAC:
        return f'{path} INVALID frac={frac:.4f}', True

    # 每一列（水平方向）是否有任何有墨像素
    row_has_ink = ink.any(axis=1)
    max_blank = 0
    current_blank = 0
    for has_ink in row_has_ink:
        if not has_ink:
            current_blank += 1
            if current_blank > max_blank:
                max_blank = current_blank
        else:
            current_blank = 0

    is_bug = max_blank > BUG_BAND_THRESHOLD
    verdict = 'BUG' if is_bug else 'ok'
    return f'{path} maxBlankBand={max_blank} {verdict}', is_bug


def main(argv: list[str]) -> int:
    if not argv:
        print('用法: python app/tool/detect_two_column_gap.py <png>...', file=sys.stderr)
        return 2

    paths: list[str] = []
    for arg in argv:
        expanded = sorted(glob.glob(arg))
        paths.extend(expanded if expanded else [arg])

    any_bug = False
    for path in paths:
        line, is_bug = analyze_image(path)
        print(line)
        if is_bug:
            any_bug = True

    return 1 if any_bug else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
