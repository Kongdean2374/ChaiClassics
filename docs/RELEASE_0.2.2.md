# ChaiClassics 0.2.2

本版在 `develop/0.2.2` 整合八款遊戲的共用對局流程、個別遊戲設定、遊玩紀錄與使用者選取的本機備份。沿用 0.2.1 的棋盤美術與互動節奏；八款可玩、十七款尚未推出的目錄數量不變。本文件描述改版範圍與驗證方法，未列出的 CI、Simulator 或 Apple 結果仍待實際執行。

## 對局與本機資料

- 各遊戲採共用暫停與結算流程。暫停保留模糊背景中的真實棋盤，提供離開與繼續；結算提供完成返回與查看棋盤。新局與取代進度必須先確認，不能因取消對話框而寫入新盤面。
- 對局時間、暫停狀態與每局識別分開保存；背景、設定、返回、已結束狀態停止接受輸入與 AI 回覆。井字棋與四子棋保留至少 450 ms 的 AI 回應間隔，四子棋先完成真正的落子動畫再開始下一次 AI 等待。
- 各遊戲設定集中管理該遊戲的偏好與統計。新的模式、難度與先手預設只影響下一局，不能改寫正在繼續的盤面；歷史紀錄可依遊戲、難度、結果與日期篩選。
- 備份由使用者透過系統 Files 選取或匯出，格式為具版本與明確遊戲範圍的 JSON。匯入必須驗證資料並確認；單一遊戲的資料操作不得改動其他遊戲。沒有新增伺服器、自動雲端同步或帳號。
- 原有遊戲存檔命名空間、Bundle ID、150 題數獨及已發布規則仍須通過升級回歸。歷史版本文件及離線法律文件的既有版本標示不隨 App 版號機械替換。

## 版本與專案生成

`scripts/create_project.py` 的 Debug `MARKETING_VERSION` 與 Release `CHAI_RELEASE_VERSION` 預設均為 `0.2.2`。Release 仍使用原有簽署工作流程傳入的版本及 Build Number；生成專案內的開發用 Build `1` 不代表可重用已上傳的 Apple 版本組合。

執行 `python3 scripts/create_project.py` 會依排序收錄目前 `App/*.swift`、`UITests/*.swift` 與資源。Core 由既有本機 Swift Package 的 `Core` target 自動編譯，新增 Core 原始碼不需要再加入 App 的 Sources phase。產物應可重複生成且內容一致。

## CI 與發布界線

- 普通 CI push 清單新增 `develop/0.2.2`，保留 `main`、`develop/0.2.0` 與 `develop/0.2.1`。
- Visual Smoke 與 iPad Screenshots 的手動、免簽署驗證信任 `develop/0.2.2`，保留原有分支及手動觸發限制。
- 候選版、依賴範圍及歷史窄範圍重用驗證器接受新的明確分支名稱。原有 SHA、祖先關係、測試本文、執行結果、artifact digest 與完整覆蓋檢查保留；開發分支證據本身仍不能授權上傳。歷史窄範圍路徑繼續綁定原來的基準，不因版號更新而放寬可重用內容。
- TestFlight 的版本輸入預設與唯讀狀態查詢預設改為 `0.2.2`。簽署／上傳 job、Secrets 對應、match readonly、main-only 與 App Store 不送審界線不變。普通 develop 提交不自動上傳。
- 0.2.1 的 App／Core／共享 UI 已有改動時，不能把舊版截圖或舊測試成功直接當成 0.2.2 的完整驗收；需要依現有證據工具判斷並重新執行受影響流程。

## 驗證方法

本機無 Apple 憑證檢查：

```sh
python3 scripts/create_project.py
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/verify_sudoku.py
swift test --jobs 4
bundle exec ruby tests/workflow_config_test.rb
```

macOS／Xcode 26 以上另執行以下路徑，保存實際結果而非只記錄編譯成功：

```sh
bash scripts/ci.sh verify
bash scripts/ci.sh unit
bash scripts/ci.sh build
CHAI_UI_SCOPE=full bash scripts/ci.sh ui
```

完整回歸模式另以同一候選 SHA 執行受信任分支上的 Visual Smoke 與 iPad Screenshots，核對原始 PNG、XCTest summary/log、八款開始／暫停／背景／離開／恢復／結算／查看棋盤，以及設定隔離、歷史紀錄與匯入／匯出的確認及失敗路徑。AI、翻牌、落子與迷宮的暫停／背景取消必須使用真實遊戲狀態測試。完整測試保留，可分別手動執行；本次 Beta 不等待全套截圖與完整 UI 回歸。

### 本次 TestFlight Beta 門檻

依使用者最新要求，`TestFlight` 預設 `validation_mode: beta`，直接進入既有的免簽署工具／安全預檢與正式簽署編譯、封存及上傳，不等待模擬器或自動 UI 測試。`scripts/verify_beta_candidate.py --manual-qa` 仍核對受信任 main 手動觸發、版本、候選 tag 與來源，產生明確的人工 QA Beta 記錄；它不宣稱任何 CI 或 UI 測試通過。簽署沿用既有 match readonly，正式封存失敗仍會阻擋上傳。

完整的 50 項 UI、三項關鍵 UI、Visual Smoke 與 iPad 測試保留，可自行手動執行。嚴格的 Beta 證據驗證路徑及 `validation_mode: full` 仍保留；正式完整模式仍需同 SHA 的 CI／Visual／iPad 成功證據。人工 QA 記錄不能當成完整回歸或 App Store 上架證明。

遊戲操作、暫停／恢復／刪除、搜尋鍵盤、真機安裝、ProMotion／120 Hz 手感、觸覺回饋、Files 匯入匯出、iPad 輔助使用與其餘模式由開發者及外部 Beta 測試者檢查。觸發 TestFlight 後回報連結並停止等待；觸發成功不代表 IPA 已上傳、Apple 處理完成或 Beta 已可下載。

發布驗收另外記錄來源 commit、候選 tag、CI／Visual／iPad run URL、裝置與通過數，以及 TestFlight 的上傳、Apple 處理、內部可用與外部 Beta 審查狀態。此版本文件不代表其中任何 Apple 步驟已完成，也不會自行觸發工作流程。

## 本次本機檢查

2026-11-17 的未提交 0.2.2 工作樹已完成以下版本／工具檢查：

- 58 項針對版本、候選版、依賴範圍與歷史窄範圍證據的 Python 測試通過，包含新分支不能直接授權發布及 SHA 不符拒絕。
- `tests/workflow_config_test.rb` 檢查所有 workflow YAML，保留原有 Secrets、main／manual、簽署與上傳隔離檢查；新增 Beta／完整模式與未知模式拒絕的回歸檢查。
- 專案重複生成內容一致，所有 `App/*.swift` 均有收錄；TestFlight 的 signed upload job 與修改前逐位元組相同。只調整免簽署預檢的 Beta／完整候選選擇。

這些是本機版本／工具檢查，不代表完整 Python／Swift、iOS Simulator、CI 或 TestFlight 已通過。完整驗收結果須由最終 commit 的原始產物補充。
