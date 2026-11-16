# 實際階段紀錄

以下只記錄已觀察結果。最新狀態以對應 Actions run 為準。

| 階段 | GitHub commit | 實際結果 |
| --- | --- | --- |
| SwiftUI 專案、數獨、150 題、獨立存檔與 CI | ee96ca2 | 題庫驗證、7 項 Swift 測試、App build 成功；Simulator test 的 x86_64／arm64 連結混用失敗（exit 65） |
| 修正 Simulator 架構 | ba143d9 | [CI 成功](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43805302202)：Xcode 26.3、7 項 Swift 測試、App build、數獨 XCUITest 成功 |
| 踩地雷 | bdb1ede | [CI 成功](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43805940791)：首點安全、自訂、旗標、連鎖、勝敗、平移縮放，400 組種子盤面測試 |
| 滑塊拼圖與三款整合 UI 測試 | e2b42bd | [CI 成功](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43806065079)：三種大小／難度、900 組可解性種子測試、12 項 Swift／4 項 UI 測試成功 |
| 發布流程與操作文件 | 1d65287 / 4d40bb1 | 手動 main、先 CI 後 Secrets、臨時 keychain、TestFlight upload、App Store 不送審；Apple 端尚未實跑 |

本機 Linux：Exact Cover 150 / 150 唯一解，0 失敗；plist／scheme XML／全部 JSON 解析成功；缺 Secrets 檢查按預期以非 0 結束並列出名稱。Linux 沒有 Swift／Xcode，iOS 結果全部來自真正 macOS Actions。

尚未完成／無法驗證：

- 真機 iPhone／iPad 觸控、縮放、不同尺寸、背景／強制關閉及效能驗收。
- Apple Developer、App Record、Bundle ID 是否可用、簽署資產與 ASC Key 有效性。
- 使用者已配置 ASC 原始 p8、match PAT／密碼與 APPLE_TEAM_ID；真實 Apple 權限與 match 首次生成尚待手動初始化流程驗證。
- production required reviewers／main 分支環境保護尚未由管理員設定確認。
- fastlane 已在免簽署 CI 成功安裝並載入 lanes；實際 Apple 簽署、TestFlight 上傳、Apple 處理、Beta Review、商店 metadata 與送審尚未實跑。
- 五子棋、Klondike、記憶翻牌與其餘遊戲尚未開始；依規格等待使用者確認 TestFlight 穩定。

發布工具額外檢查：[release-tooling 成功紀錄](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43806421013)，Ruby 3.3／Bundler 2.5.23、fastlane 2.228.0，Syntax OK 且兩個 lanes 載入；解析出的 Gemfile.lock 已固定。這不表示簽署或 Apple 上傳已成功。

簽署架構已改為私人 ChaiClassics-Signing/main 的 fastlane match：Initialize Signing 手動建立／加密推送，TestFlight readonly，ASC_API_KEY_P8 為原始文字，不要求手動 p12。新版本結果以 Actions 為準；不得把程式修改與實際 Apple 生成／上傳混為一談。

首次初始化環境已按使用者設定改為 signing-bootstrap；三個 SIGNING_ASC_* Admin Secrets 僅映射至初始化 Job 的 ASC_*。一般 TestFlight 維持 Developer Key，共用 Team ID／PAT／MATCH_PASSWORD 保留。本次明確不執行初始化；真實 Apple 簽署資產狀態未因此改變。

Run 43810107847 的診斷缺陷已確認：舊 APPLE_ACCESS 丟失 HTTP 與資源，不足以證明權限問題。已加入分資源／HTTP 的安全診斷與獨立手動唯讀 workflow；實際 Apple 根因仍無法由已刪除的舊私密 log 還原。本次不重跑 Initialize Signing、不執行 Apple 請求、不修改任何憑證。詳見 APPLE_SIGNING_DIAGNOSTICS.md。

唯讀診斷進一步改為同一 Admin JWT 的 Apps／Certificates 對照，新增僅布林的 JWT 欄位／簽章檢查，區分共同 401 與單一資源失敗。這些自動測試使用臨時假資料／模擬 HTTP；此次沒有執行 Apple workflow，實際 401 根因須由使用者手動診斷取得新結果。

Run 43818758376 已證實 Apple 預檢 200、私人 repo 既有加密資產寫入成功；舊 MATCH_ASSETS 無法區分三個後置失敗。新版本改為分階段 readonly 後置驗證，增加現代／legacy 路徑 fallback 與真實本機私鑰簽名配對檢查；不重跑初始化／TestFlight。真資產手動驗證尚未執行，見 SIGNING_ASSET_VERIFICATION.md。

更新：使用者手動執行 Run 43826441030，真資產下載／匯入、描述檔、Keychain 配對、私鑰簽名與 strict verify 均成功；最後 ASSET_SIGNED_CERT_PAIR。發現 codesign optional extraction prefix 被錯誤拆開，已修正為單一 `--extract-certificates=...` argv，保留 DER 精確比對，細分 command／內容／不符三種錯誤並增加真實 macOS 系統 binary 的無 Secrets 回歸測試。修正後完整真資產驗收仍待使用者手動 readonly run，不重跑初始化／TestFlight，也不調整 Apple 資產或 ChaiPhoto。
