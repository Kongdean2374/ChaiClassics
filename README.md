# ChaiClassics｜經典小遊戲

SwiftUI 原生離線合集，iPhone / iPad，iOS 17+。永久免費，無廣告、帳號、追蹤、內購或網路服務。Bundle ID：`cc.chaihome.chaiclassics`。

目前實作：三欄首頁、獨立原子存檔、完整數獨（簡單／中等／困難各 50 題）。沒有答案提示、錯誤標示或自動解題。只有完整合法盤面才顯示完成。

題庫已由本機獨立 Exact Cover 驗證：150 / 150 唯一解，0 失敗。Swift 與 iOS 編譯結果請以 [Actions](https://github.com/Kongdean2374/ChaiClassics/actions) 實際紀錄為準；開發環境為 Linux，沒有本機 Xcode。

## 開發

- `python3 scripts/verify_sudoku.py`：驗證題庫、難度與已發布 ID。
- `swift test`：純 Swift 規則與存檔測試。
- 在 Xcode 26+ 開啟 `ChaiClassics.xcodeproj`，選 `ChaiClassics` scheme 與 iPhone Simulator。
- `bash scripts/ci.sh`：macOS 上執行全部免簽署檢查與 Simulator 測試。

後續階段：踩地雷 → 滑塊拼圖 → 簽署發布流程。五子棋、接龍與記憶翻牌依規格等待使用者確認 TestFlight 穩定後加入。未完成遊戲不會出現在首頁。

目前沒有已驗證的 TestFlight 安裝版本；Apple 簽署及 App Store Connect 設定尚待完成。公開程式碼未附開源授權。
