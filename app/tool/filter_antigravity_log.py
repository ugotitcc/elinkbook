#!/usr/bin/env python3
"""
filter_antigravity_log.py — 過濾 Antigravity CLI 日誌噪音

目的：
  Antigravity 的 log 前綴 `ERROR: logging before google.Init:` 會讓所有行
  看起來都是 ERROR，且 Windows 上 `grep_handler.go:518` 的 Windows 路徑
  Bug 會洪水式噴 1000+ 行，完全蓋掉真正需要關注的錯誤。

  此腳本過濾兩類無害噪音：
    1. grep_handler.go:518 — Windows `C:/U:/` 冒號解析 Bug (佔真 E 的 91%)
    2. logging before google.Init: I... — 被誤標為 ERROR 的 INFO

  保留：
    - 真正的 E (error) 與 W (warn)
    - 例如 token 刷新失敗、CORTEX 規則等需要關注的訊息

用法：
  # 過濾最新的一份 log
  python app/tool/filter_antigravity_log.py

  # 過濾指定檔案
  python app/tool/filter_antigravity_log.py -f C:/Users/huthief/.gemini/antigravity-cli/log/cli-20260907_135357.log

  # 只看統計，不輸出內容
  python app/tool/filter_antigravity_log.py --stats

  # 即時 tail (每 2 秒刷新)
  python app/tool/filter_antigravity_log.py --follow

  # 輸出到檔案
  python app/tool/filter_antigravity_log.py -o filtered.log

  # PowerShell 一鍵別名 (見 filter_antigravity_log.ps1)
  ./app/tool/filter_antigravity_log.ps1
  ./app/tool/filter_antigravity_log.ps1 -Follow
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
import time

# 預設 log 目錄
DEFAULT_LOG_DIR = pathlib.Path(r"C:\Users\huthief\.gemini\antigravity-cli\log")

# --- 過濾規則 ---

# 1. Windows grep_handler Bug：整行丟棄
GREP_HANDLER_PATTERN = re.compile(r"grep_handler\.go:518.*Error parsing grep result")

# 2. 被誤標為 ERROR 的 INFO：`ERROR: logging before google.Init: I...`
#    真實等級是 I，完全無害，丟棄
FAKE_ERROR_INFO_PATTERN = re.compile(r"logging before google\.Init:\s*I\d{4}")

# 可選：額外降噪（預設保留，僅 --aggressive 才過濾）
AGGRESSIVE_PATTERNS = [
    re.compile(r"skipping component during resolution: empty component"),  # 空 prompt 章節
    re.compile(r"Invalid rule trigger: CORTEX_MEMORY_TRIGGER_UNSPECIFIED"),
]


def should_keep(line: str, aggressive: bool = False) -> bool:
    """判斷該行是否應保留。"""
    if GREP_HANDLER_PATTERN.search(line):
        return False
    if FAKE_ERROR_INFO_PATTERN.search(line):
        return False
    if aggressive:
        for pat in AGGRESSIVE_PATTERNS:
            if pat.search(line):
                return False
    return True


def classify_line(line: str) -> str:
    """回傳 glog 真實等級 I/W/E 或 '?'"""
    m = re.search(r"logging before google\.Init:\s*([IWE])\d{4}", line)
    return m.group(1) if m else "?"


def find_latest_log(log_dir: pathlib.Path) -> pathlib.Path | None:
    if not log_dir.exists():
        return None
    logs = sorted(log_dir.glob("cli-*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    return logs[0] if logs else None


def filter_file(
    src: pathlib.Path,
    dst_stream,
    aggressive: bool = False,
    stats_only: bool = False,
) -> dict:
    text = src.read_text(encoding="utf-8", errors="ignore")
    lines = text.splitlines()

    stats = {
        "total": len(lines),
        "kept": 0,
        "dropped_grep": 0,
        "dropped_fake_info": 0,
        "dropped_aggressive": 0,
        "kept_E": 0,
        "kept_W": 0,
        "kept_I": 0,
        "kept_unknown": 0,
    }

    kept_lines: list[str] = []

    for line in lines:
        if GREP_HANDLER_PATTERN.search(line):
            stats["dropped_grep"] += 1
            continue
        if FAKE_ERROR_INFO_PATTERN.search(line):
            stats["dropped_fake_info"] += 1
            continue
        if aggressive:
            dropped = False
            for pat in AGGRESSIVE_PATTERNS:
                if pat.search(line):
                    stats["dropped_aggressive"] += 1
                    dropped = True
                    break
            if dropped:
                continue

        # 保留
        stats["kept"] += 1
        lvl = classify_line(line)
        if lvl == "E":
            stats["kept_E"] += 1
        elif lvl == "W":
            stats["kept_W"] += 1
        elif lvl == "I":
            stats["kept_I"] += 1
        else:
            stats["kept_unknown"] += 1
        kept_lines.append(line)

    if not stats_only:
        for l in kept_lines:
            print(l, file=dst_stream)

    return stats


def print_stats(stats: dict, src: pathlib.Path):
    dropped = stats["total"] - stats["kept"]
    # 使用英文避免 Windows cp950 終端亂碼
    print(f"\n{'='*60}", file=sys.stderr)
    print(f"Source: {src}", file=sys.stderr)
    print(f"Total: {stats['total']}  |  Kept: {stats['kept']}  |  Dropped: {dropped} ({dropped*100//max(1,stats['total'])}%)", file=sys.stderr)
    print(f"  - grep_handler.go:518 (Windows Bug): {stats['dropped_grep']}", file=sys.stderr)
    print(f"  - Fake ERROR/INFO (I-level):         {stats['dropped_fake_info']}", file=sys.stderr)
    if stats["dropped_aggressive"]:
        print(f"  - aggressive extra:                  {stats['dropped_aggressive']}", file=sys.stderr)
    print(f"Kept breakdown: E={stats['kept_E']} W={stats['kept_W']} I={stats['kept_I']} ?={stats['kept_unknown']}", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)
    if stats["kept_E"] == 0 and stats["kept_W"] == 0:
        print("[OK] No real errors/warnings after filtering", file=sys.stderr)
    elif stats["kept_E"] < 20:
        print(f"[!] {stats['kept_E']} real errors remain - check output above", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="過濾 Antigravity CLI 日誌噪音")
    parser.add_argument("-f", "--file", type=pathlib.Path, default=None, help="指定 log 檔案 (預設：最新一份)")
    parser.add_argument("-d", "--dir", type=pathlib.Path, default=DEFAULT_LOG_DIR, help="log 目錄")
    parser.add_argument("-o", "--output", type=pathlib.Path, default=None, help="輸出到檔案 (預設：stdout)")
    parser.add_argument("--stats", action="store_true", help="只顯示統計，不輸出內容")
    parser.add_argument("--follow", action="store_true", help="即時 tail 模式 (每 2 秒刷新)")
    parser.add_argument("--aggressive", action="store_true", help="額外過濾 CORTEX/empty component 等次要噪音")
    args = parser.parse_args()

    src = args.file or find_latest_log(args.dir)
    if src is None or not src.exists():
        print(f"Log not found (dir: {args.dir})", file=sys.stderr)
        sys.exit(1)

    if args.follow:
        print(f"Following {src} (Ctrl+C to stop) ...", file=sys.stderr)
        last_size = 0
        try:
            while True:
                cur_size = src.stat().st_size
                if cur_size != last_size:
                    # 重新過濾全檔（簡單可靠；log 檔不大）
                    stats = filter_file(src, sys.stdout, aggressive=args.aggressive, stats_only=False)
                    last_size = cur_size
                time.sleep(2)
        except KeyboardInterrupt:
            print("\n停止 following", file=sys.stderr)
        return

    # 單次模式
    if args.output:
        with args.output.open("w", encoding="utf-8") as out:
            stats = filter_file(src, out, aggressive=args.aggressive, stats_only=args.stats)
        # 同時把統計印到 stderr
        print_stats(stats, src)
        print(f"Written: {args.output}", file=sys.stderr)
    else:
        # stdout 輸出過濾後內容，統計走 stderr 避免污染 pipe
        stats = filter_file(src, sys.stdout, aggressive=args.aggressive, stats_only=args.stats)
        print_stats(stats, src)


if __name__ == "__main__":
    main()
