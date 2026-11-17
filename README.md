# ChaiClassics｜經典小遊戲

[![CI](https://github.com/Kongdean2374/ChaiClassics/actions/workflows/ci.yml/badge.svg)](https://github.com/Kongdean2374/ChaiClassics/actions/workflows/ci.yml)

SwiftUI 原生 iPhone／iPad 離線合集，iOS 17+。免費、無廣告、帳號、訂閱、追蹤或遊戲後端。
Bundle ID：`cc.chaihome.chaiclassics`。Public 原始碼，未另授予開源授權。

0.2.0 實作包含 **8 款可玩、13 款尚未推出，共 21 款邏輯遊戲**：

| 可玩 | 規則與模式 |
| --- | --- |
| 數獨 | 簡單／中等／困難各 50 題，已獨立驗證唯一解；答案筆、鉛筆、擦除，玩家藍色字跡；無答案提示或錯誤標示 |
| 踩地雷 | 隨機盤面、自訂尺寸與雷數、首點安全、單點揭開／長按插旗、原生平移縮放 |
| 滑塊拼圖 | 3×3／4×4／5×5、四方向滑動與相鄰點擊、合法打亂、計時與步數 |
| 井字棋 | 本機雙人或電腦、三種 AI 難度、先後手；困難使用完整 minimax |
| 四子棋 | 7×6 重力落子、四向四連、雙人或有運算上限的三種 AI |
| 24 點 | 精確分數運算、所有括號組合、復原／重設／新題；1,362 組獨立驗證可解題目 |
| 記憶翻牌 | 4×4／4×5／6×6、兩張翻牌狀態機、配對鎖定與未配對延遲翻回 |
| 迷宮 | 9×9／15×15／21×21 可重現隨機完美迷宮、方向鍵與滑動、碰牆限制 |

尚未推出：數織、數和、華容道、五子棋、黑白棋、貪吃蛇、俄羅斯方塊、打磚塊，
以及接龍資料夾內的經典接龍、蜘蛛接龍、新接龍、金字塔接龍、三峰接龍。
這些入口清楚顯示尚未推出，不偽裝成可玩遊戲。

首頁一般字級維持三欄，共 17 張卡片；接龍二級目錄是 5 張卡片。首頁只顯示名稱、玩法與可玩狀態，
進度留在遊戲選單。輔助大字級會調整欄數，並以多行顯示完整標題。

所有遊戲獨立存檔、可恢復及重玩。沿用 0.1.x 三款遊戲的存檔命名空間、格式與原有 150 題數獨；
不因更新清除進度。系統／淺色／深色、繁中／英文、觸覺回饋、遊玩時保持螢幕喚醒，
及雙語離線隱私政策／條款／支援入口維持共用。官方網站：https://classics.chaihome.cc/ 。

## 驗證與發布

普通 push／PR 執行無 Apple 憑證的程式、相容性及工具檢查。
GitHub Actions → **CI → Run workflow** 可選 `ui_scope`：
`full` 是完整整合，`memory`、`sliding` 等只測受影響遊戲及相關流程。
先局部修正、局部重驗，發布前再做必要整合，避免每個小修都重跑所有遊戲。
局部驗證明確標示範圍；測試工具修復的跨 Run 證據須通過 App 未變、斷言未變及逐案例來源驗證。
詳見 [選擇性測試](docs/INCREMENTAL_UI.md)。

[iPad Screenshots](https://github.com/Kongdean2374/ChaiClassics/actions/workflows/ipad-screenshots.yml)
會執行真正的 13 吋 iPad 模擬器，保留四張原生直向 PNG、五款新遊戲路徑、尺寸報告與 XCTest 結果。
以 Actions 的實際通過數和原始產物為準；不能以編譯成功或局部測試代替整體驗收。

0.2.0 的 TestFlight 由受信任候選版及驗證門檻控制，完成後可由 Codex 代為觸發並追蹤 Apple 處理。
普通提交不自動上傳。簽署沿用私人倉庫的 **match readonly** 資產；不要重新初始化或撤銷憑證。
不自動正式提交 App Store 或公開上架；上傳、處理完成、內部可用與外部 Beta 審核分開回報。

```sh
python3 scripts/verify_sudoku.py
swift test
bash scripts/ci.sh                 # macOS 完整路徑
CHAI_UI_SCOPE=memory bash scripts/ci.sh ui  # macOS 指定 UI 範圍
```

Xcode 26+ 開啟 `ChaiClassics.xcodeproj` 的 `ChaiClassics` scheme。
新增 Swift 檔案後執行 `python3 scripts/create_project.py`。

- [0.2.0 進度](docs/V020_PROGRESS.md)、[發布規格](docs/v020-release.md)、[驗證證據](docs/v020-verification.md)
- [存檔與架構](docs/ARCHITECTURE.md)、[題庫規格](docs/SUDOKU_PUZZLES.md)
- [發布與 Secrets](docs/RELEASING.md)、[簽署資產唯讀驗證](docs/SIGNING_ASSET_VERIFICATION.md)
- [歷史 0.1.1 改版](docs/RELEASE_0.1.1.md)、[網站接手文件](docs/WEBSITE_HANDOFF.md)
