# Triage Labels（分流標籤）

各 skill 以五種標準分流角色來溝通。本檔案將這些角色對應到此儲存庫工單追蹤系統中實際使用的標籤字串。

| mattpocock/skills 中的標籤 | 本儲存庫的標籤 | 意義 |
| --------------------------- | --------------------- | ----------------------------------------- |
| `needs-triage`               | `needs-triage`         | 維護者需評估此工單 |
| `needs-info`                 | `needs-info`           | 等待回報者提供更多資訊 |
| `ready-for-agent`            | `ready-for-agent`      | 規格已完整，可交給 AFK agent 處理 |
| `ready-for-human`            | `ready-for-human`      | 需要真人實作 |
| `wontfix`                    | `wontfix`              | 不予處理 |

當某個 skill 提到某個角色時（例如「套用 AFK-ready 分流標籤」），請使用本表對應的標籤字串。

備註：這些標籤目前尚未在 Gitea 儲存庫上建立——請在某個 skill 第一次嘗試套用標籤前，先用 `tea labels create` 建立好。
