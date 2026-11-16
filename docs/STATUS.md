# 實際階段紀錄

以下只記錄已觀察結果。最新狀態以對應 Actions run 為準。

| 階段 | GitHub commit | 實際結果 |
| --- | --- | --- |
| SwiftUI 專案、數獨、150 題、獨立存檔與 CI | ee96ca2 | 題庫驗證、7 項 Swift 測試、App build 成功；Simulator test 的 x86_64／arm64 連結混用失敗（exit 65） |
| 修正 Simulator 架構 | ba143d9 | [CI 成功](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43805302202)：Xcode 26.3、7 項 Swift 測試、App build、數獨 XCUITest 成功 |
| 踩地雷 | bdb1ede | [CI 成功](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43805940791)：首點安全、自訂、旗標、連鎖、勝敗、平移縮放，400 組種子盤面測試 |
| 滑塊拼圖與三款整合 UI 測試 | e2b42bd | 已提交，CI 結果待補：三種大小／難度、900 組可解性種子測試、存檔恢復 |
| 發布流程與操作文件 | 1d65287 / 4d40bb1 | 手動 main、先 CI 後 Secrets、臨時 keychain、TestFlight upload、App Store 不送審；Apple 端尚未實跑 |

本機 Linux：Exact Cover 150 / 150 唯一解，0 失敗；plist／scheme XML／全部 JSON 解析成功；缺 Secrets 檢查按預期以非 0 結束並列出名稱。Linux 沒有 Swift／Xcode，iOS 結果全部來自真正 macOS Actions。

尚未完成／無法驗證：

- 真機 iPhone／iPad 觸控、縮放、不同尺寸、背景／強制關閉及效能驗收。
- Apple Developer、App Record、Bundle ID 是否可用、簽署資產與 ASC Key 有效性。
- Repository／Environment Secrets 的存在與內容（本工作階段無可讀取其設定的介面）。
- production required reviewers／main 分支環境保護尚未由管理員設定確認。
- fastlane 已在免簽署 CI 成功安裝並載入 lanes；實際 Apple 簽署、TestFlight 上傳、Apple 處理、Beta Review、商店 metadata 與送審尚未實跑。
- 五子棋、Klondike、記憶翻牌與其餘遊戲尚未開始；依規格等待使用者確認 TestFlight 穩定。

發布工具額外檢查：[release-tooling 成功紀錄](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43806421013)，Ruby 3.3／Bundler 2.5.23、fastlane 2.228.0，Syntax OK 且兩個 lanes 載入；解析出的 Gemfile.lock 已固定。這不表示簽署或 Apple 上傳已成功。
