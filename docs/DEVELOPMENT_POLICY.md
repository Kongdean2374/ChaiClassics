# 開發、驗證與 TestFlight 策略

## 日常開發

集中完成一批修改，以程式碼檢查、語法、產生專案一致性及存檔相容檢查為主。Push／PR 僅執行 Linux 輕量檢查，保留 `test`、`codesign-extraction`、`release-tooling` 三個既有 check 名稱，不關閉分支保護。這些結果不宣稱已執行 Xcode、真實 codesign 或 UI。

## Bug 修正

先讀既有錯誤與重現步驟，再驗證受影響行為；需要 Mac 時合併修改後集中跑一次。沒有新證據不重跑相同完整工作。完整 CI、指定遊戲、Visual Smoke 與 iPad 截圖都保留手動入口；不由普通 Push 啟動。

## TestFlight Beta

Codex 在一批功能可測試時主動推送 main、綁定候選 tag，並觸發 `TestFlight`，預設 `beta`。所有數字版本都執行來源／版本／main／tag 驗證，不因 0.3.0 或未來版本前綴而略過。

Beta 使用輕量 Linux preflight，Mac 執行核心規則／存檔測試、match readonly、真正 Release archive、匯出 IPA 及上傳。沒有獨立的重複 Simulator 全遊戲編譯／UI 門檻，也不在 Linux 重裝並重跑完整 fastlane suite；真正簽署打包不省略。既有最小啟動／核心操作證據可以保留；程式啟動相關改動或明確致命問題須先針對性確認。一般排版、手感、邊界與長時間遊玩交由實機測試並列為未驗證。

上傳後，依當次 `provenance.txt` 的版本、Build Number、Commit 唯讀查詢 Apple；最多六次、間隔 30 秒，只重查尚未可見的 build，不重編譯或重新上傳。報告保存在 `testflight-apple-status`。`PROCESSING` 代表已收到且仍處理；`VALID` 也不等於外部 Beta 審查通過。來源不符、API 錯誤、FAILED／INVALID 明確失敗；尚不可見則明確 pending，由 Codex 讀取狀態，不盲目重傳。

## 正式發布

`full` 模式仍要求完整 CI／iPhone／iPad 證據。App Store preparation 明確呼叫完整 UI CI，仍須使用者確認實機及商店資料，不自動提交上架。簽署、TestFlight、App Store 的 `apple-release` group 保持 `cancel-in-progress: false`。

本次未變更遊戲、存檔、Bundle ID、Apple 憑證或 Secrets。保護設定讀取 API 回覆 403，沒有修改保護；既有 check 名稱與自動完成的輕量檢查均保留，以避免必要 check 永遠 Pending。
