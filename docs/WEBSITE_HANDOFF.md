# ChaiClassics 官方網站與 App 整合契約

狀態：正式網站已由使用者提供；App 已整合網站並於 0.1.3 精修介面，沒有部署網站、修改 DNS、App Store Connect、Secrets 或簽署資產。

## 已驗證的公開入口

本次以 HTTPS GET 實際檢查，以下繁中與英文八頁均回應 HTTP 200，支援頁與頁尾公開信箱均為 `a090825159@icloud.com`。

| 用途 | 繁體中文 | English |
| --- | --- | --- |
| 首頁 | https://classics.chaihome.cc/ | https://classics.chaihome.cc/en/ |
| 隱私政策 | https://classics.chaihome.cc/privacy/ | https://classics.chaihome.cc/en/privacy/ |
| 使用條款 | https://classics.chaihome.cc/terms/ | https://classics.chaihome.cc/en/terms/ |
| 支援 | https://classics.chaihome.cc/support/ | https://classics.chaihome.cc/en/support/ |

舊版文件中 `https://chaihome.cc/chaiclassics/` 規劃路由已被上表取代。不要把舊規劃路由當成正式入口。網站的公開商店下載網址目前仍未確認，不得虛構 App Store ID 或公開 TestFlight 邀請。

## App 實際整合方式

- `Core/OfficialWebsite.swift` 集中管理信箱、語言路由及 URLComponents 郵件草稿；不使用 WebView、不在背景抓取網站。
- 設定分成一般、遊戲偏好、支援、法律、關於。外觀與語言即時生效；觸覺、螢幕喚醒與自動存檔行為不變。
- `App/LegalView.swift` 保留 `App/Resources/{zh-Hant,en}.lproj/{Privacy,Terms,Support}.md` 離線文件，並提供所選語言的官方對應頁。
- 官方郵件入口開啟可編輯草稿，預填實際 App 與 iOS 版本，提示填寫遊戲、裝置型號（選填）、問題、重現步驟及預期結果；由使用者確認寄出。沒有自動寄信、附件、存檔上傳或支援帳號。
- 支援頁提供可編輯草稿與回報欄位、可選取／點按複製的信箱及手動寄信替代方式；不加入假想 Bug 案例或開發流程說明。
- 同一個 Bundle ID `cc.chaihome.chaiclassics`、同一套政策、設定與功能用於 TestFlight 和正式版本，不另設 Beta App。
- 三款遊戲、本機偏好鍵、獨立存檔、150 題與完成紀錄均保留；沒有開發者雲端同步或遠端復原服務。

## 網站後續需核對的實際差異

本次唯讀核對發現兩項需要網站維護者在正式送審前處理：

1. 網站隱私政策與條款仍顯示「發布前核對草稿／Pre-publication review draft」。網站維護者需完成內容核對並更新發布標示，不應將草稿宣稱為已完成最終審核。
2. HTML 實際載入 `static.cloudflareinsights.com/beacon.min.js` 的 Cloudflare Web Analytics beacon，但網站隱私政策稱沒有訪客追蹤或 Analytics。請依實際營運選擇停用該服務，或準確更新兩語政策。App 本身沒有新增分析 SDK，也不嵌入網站程式；不能據此將網站的聲明直接套用到 App。

網站支援工具目前在瀏覽器整理選填草稿，透過 mailto 開啟郵件，使用者點按才複製內容，未見表單後端、fetch 或 localStorage 保存回報。後續若新增後端、統計或第三方工具，須重新核對政策與資料申報。

## 提交商店時使用的欄位

使用者可將上表的首頁填入 Marketing URL、支援頁填入 Support URL、隱私政策填入 Privacy Policy URL；英文語系使用 /en/ 對應頁。本次沒有自動變更 App Store Connect 欄位、外部測試審查或 App Store 送審。

App Privacy 申報須由擁有者依實際功能及 Apple 規則確認；本次沒有讀取或修改申報。App 的 `PrivacyInfo.xcprivacy` 保持既有 UserDefaults CA92.1 與未追蹤宣告，不等於商店申報已完成。

## 版本與驗證交接

App 0.1.2 整合官方政策與郵件；0.1.3 精修設定及正式支援介面。政策文件修訂版維持 0.1.2，與 App 視覺版本分開。沒有網站部署或遊戲玩法改動。

一般 CI 驗證核心規則與存檔、八條官方路由組合、郵件特殊字元與欄位隔離、雙語資源及專案編譯。網站可達性由本次實際 GET 核對，單元測試不依賴外部網路。

真機需確認外部瀏覽器、已設定／未設定郵件服務、可編輯草稿、信箱選取、繁英切換、深淺色與原存檔續玩。完整 Simulator UI 仍保留為手動選項，不在一般推送自動執行。僅在使用者手動執行 TestFlight 時簽署與上傳。

