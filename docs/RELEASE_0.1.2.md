# ChaiClassics 0.1.2

正式網站政策與支援整合，以及設定整理。同一 App 供 TestFlight、外部測試與正式發行使用；未建立另一個測試版 App。

## 變更

- 設定整理為一般、遊戲偏好、支援、法律、關於；將偏好說明併入控制項，保留原偏好值與即時切換。
- 隱私政策、使用條款與支援保留繁中／英文離線內容，新增對應官方網站入口。
- 支援改用官方公開信箱 a090825159@icloud.com，開啟預填 App／iOS 版本與問題欄位的可編輯草稿；只有使用者確認才寄出。提供回報格式範例與無郵件 App 時的替代指引。
- 遊戲玩法、Bundle ID、150 題數獨、獨立存檔與偏好儲存鍵保持不變。
- 簽署、match readonly、Release Archive、IPA 匯出及上傳流程保持不變，僅將手動 TestFlight 預設版本更新為 0.1.2。

## 驗證範圍

一般 CI 執行 Swift 核心與存檔測試、官方網址／郵件 URL 測試、150 題唯一解驗證、Python 資源檢查、Ruby／YAML 發布安全檢查及 iOS Simulator 編譯。實際結果以本次 Commit 的 CI Run 為準。新增 UI 斷言保留在手動完整 UI 測試中；不自動開啟瀏覽器、寄信或執行正式簽署工作流程。

## 真機驗收

1. 由 0.1.1 直接更新，確認三款舊進度與外觀、語言、偏好均保留。
2. 離線開啟繁中／英文政策與支援；開啟網路後確認對應官方頁。
3. 在有郵件服務的裝置開啟回報，檢查收件人、版本、可修改欄位；取消草稿不會寄出。
4. 無預設郵件服務時，確認支援頁可選取信箱並手動新增信件。
5. 檢查設定的深色／淺色、大字體、VoiceOver 與 iPhone／iPad 排版。

## 網站交接

政策目前仍有草稿標示，以及 Cloudflare Analytics 實際程式與網站聲明不一致的兩項核對事項，詳見 WEBSITE_HANDOFF.md。本次未修改網站或 App Store Connect；一般 CI 通過不代表完成商店審核或真機驗收。

## 手動上傳

GitHub Actions → TestFlight → Run workflow → main → version 0.1.2。保留既有簽署設定；不要執行 Initialize Signing。此版本不自動觸發 TestFlight、修改憑證或送審。
