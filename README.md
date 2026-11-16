# ChaiClassics｜經典小遊戲

[![CI](https://github.com/Kongdean2374/ChaiClassics/actions/workflows/ci.yml/badge.svg)](https://github.com/Kongdean2374/ChaiClassics/actions/workflows/ci.yml)

SwiftUI 原生離線合集，iPhone / iPad，iOS 17+。永久免費，無廣告、帳號、追蹤、內購或執行期網路服務。Bundle ID：`cc.chaihome.chaiclassics`。Public 原始碼，未附開源授權。

目前實作的可操作遊戲：

- 數獨：三種難度各 50 題、順序解鎖、答案筆／鉛筆／擦除、無答案提示或錯誤標示。只有完整合法盤面顯示完成。
- 踩地雷：9×9／16×16／30×16、自訂 5～40 邊長、首點安全、連鎖、旗標、勝敗、原生平移縮放。
- 滑塊拼圖：3×3／4×4／5×5、三種打亂程度、只准移動相鄰塊、步數、計時、完成判定。

首頁固定三欄，遊戲獨立存檔；每步同步原子寫入，保留上一份備份。退出、切換遊戲、背景和重啟可恢復最近成功寫入狀態。沒有未完成遊戲卡片。

## 實際驗證與限制

150 題均已用獨立 Exact Cover 驗證唯一解，三類各 50，0 失敗。第一階段 [修正後 CI](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43805302202) 已成功通過 7 項 Swift 測試、Xcode 26.3 App 編譯與數獨模擬器測試。踩地雷、滑塊與發布流程的最新實測請查看 Actions 與 [階段紀錄](docs/STATUS.md)，不要把「已寫好 workflow」當成已通過或已上傳。

目前**沒有真實可下載的 TestFlight build**，Apple 簽署／API 設定未在本工作階段驗證，真機觸控／縮放／效能仍需使用者完成。GitHub Secrets 的值不應貼在聊天或公開 repo。

## 開發與 CI

```sh
python3 scripts/verify_sudoku.py  # 獨立唯一解／分類／immutable manifest
swift test                      # 純 Swift 引擎、存檔與種子測試
bash scripts/ci.sh              # macOS：以上 + Xcode build + iOS Simulator XCUITest
```

Xcode 26+ 開啟 `ChaiClassics.xcodeproj`，選 `ChaiClassics` scheme 與 iPhone Simulator。不需要第三方 iOS package，也不必在 CI 動態下載專案產生器。新增 SwiftUI 檔案後跑 `python3 scripts/create_project.py` 更新已提交工程。

CI 每次 main push／PR 執行，無 Apple Secrets，任一步失敗會失敗。TestFlight 與 App Store 為手動 main workflow，前者簽署上傳，後者只選入已測 build、準備 release notes，**不自動送審／公開上架**。production environment 審核保護需在 GitHub Settings 設定。

文件：

- [架構、新增遊戲、存檔與 migration](docs/ARCHITECTURE.md)
- [題庫生成、驗證及追加 051](docs/SUDOKU_PUZZLES.md)
- [測試與 iPhone 驗收](docs/TESTING.md)
- [Secrets、TestFlight、App Store 發布](docs/RELEASING.md)
- [公開倉庫安全](docs/SECURITY.md)

下一階段依附件規格：使用者確認 TestFlight 穩定後，逐款加入五子棋、Klondike 與記憶翻牌，再準備 1.0。其餘經典遊戲保留模組擴充方式，不先做空殼。
