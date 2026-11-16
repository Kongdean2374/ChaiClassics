# ChaiClassics 官方網站接手規格（交給後續 Codex）

狀態：**規劃契約，尚未建站、部署或驗證公開頁面。** 此次只做 iOS App 0.1.1；沒有網站、後台、DNS 或 App Store Connect 設定變更。不得把以下規劃路由寫成「已上線」。

## 產品事實與限制

- 品牌：Chai Classics／經典小遊戲；GitHub：Kongdean2374/ChaiClassics。
- iOS 17+，Bundle ID 固定 `cc.chaihome.chaiclassics`，版本目標 0.1.1。
- 現有且可玩的遊戲只有數獨、踩地雷、滑塊拼圖；沒有第四款與未實作的功能預告。
- 免費、離線、無廣告、無訂閱、無帳號。進度與設定在裝置內，沒有開發者雲端同步或資料恢復服務。
- 不得新增登入、支付、追蹤、分析或訂閱文案；網站若日後引入這些服務，必須重新檢查隱私政策及申報，不能沿用本版聲明。
- 不得虛構聯絡 Email、App Store ID、公開 TestFlight 邀請、下載量、評價、使用者見證或已上架狀態。倉庫公開不代表具有未明示的開源授權。

## 規劃路由（全部待製作／發布／驗證）

| 用途 | 路由 | 後續 ASC 欄位 |
| --- | --- | --- |
| 首頁 | https://chaihome.cc/chaiclassics/ | 可作 Marketing URL，確認實際公開後再填 |
| 隱私政策 | https://chaihome.cc/chaiclassics/privacy | Privacy Policy URL |
| 使用條款 | https://chaihome.cc/chaiclassics/terms | App 內選用的條款外連 |
| 支援 | https://chaihome.cc/chaiclassics/support | Support URL |

每條路由都需繁體中文與英文。建議用 `?lang=zh-Hant`／`?lang=en`，或由網站 Codex 與使用者確認語言 URL 策略，但上述四條基礎路徑不能變成 404。保持 HTTPS、可公開免登入讀取、手機可讀、可複製連結、標題與語言標記正確。不得為了政策頁要求接受 Cookie、登入或安裝 App。

## 首頁文案

繁中：

- 標題：經典小遊戲，隨時接著玩。
- 簡介：Chai Classics 收錄數獨、踩地雷與滑塊拼圖。免費、無廣告，離線也能遊玩；每次操作自動儲存。
- 數獨：三種難度各 50 題；紙本式答案筆、鉛筆與擦除，不提供提示、答案揭露或錯誤標記。
- 踩地雷：單點揭開、長按插旗；支援簡單、中等、困難與自訂盤面，大型棋盤可平移縮放。
- 滑塊拼圖：3×3、4×4、5×5，三種難度；保留盤面、步數與計時。
- 下載區：在使用者提供有效 App Store／公開 TestFlight 連結前，顯示「下載資訊待公布」，不要放假下載按鈕。

English:

- Heading: Classic games. Right where you left off.
- Intro: Chai Classics includes Sudoku, Minesweeper and Sliding Puzzle. Free, with no ads, and playable offline. Every move is saved automatically.
- Sudoku: 50 puzzles in each of three difficulties. Paper-style pen, pencil and eraser, with no hints, answer reveal or error marking.
- Minesweeper: Tap to reveal and hold to flag. Presets and custom boards, with pan and zoom for larger boards.
- Sliding Puzzle: 3×3, 4×4 and 5×5 boards in three difficulties. Tiles, moves and time are saved.
- Download area: Display “Download information to be announced” until an actual App Store or public TestFlight URL is supplied and verified.

## 0.1.1 更新紀錄文案

繁中：改善踩地雷的單點／長按操作、棋盤置中與縮放；首頁依真實存檔顯示狀態；改善續玩與關卡選單；新增系統／淺色／深色、繁中／英文、觸覺回饋與遊玩時螢幕喚醒偏好；新增離線隱私政策、使用條款及支援。保留 0.1.0 遊戲進度及既有 150 題。

English: Improved Minesweeper tap/hold controls, board centering and zoom; real save-based home statuses; clearer continuation and level menus; system/light/dark appearance, Chinese/English, haptic and screen-awake preferences; and bundled offline privacy, terms and support pages. Existing 0.1.0 progress and all 150 released Sudoku puzzles are retained.

不得宣稱零 Bug、已完成真機驗收或已通過 App Store 審核。是否公開發布 0.1.1，需使用者確認。

## App 整合契約

- 本版 `App/LegalView.swift` 從 `App/Resources/{zh-Hant,en}.lproj/{Privacy,Terms,Support}.md` 離線讀取，沒有開啟以上規劃 URL。
- 現在唯一外部支援入口是已存在的 `https://github.com/Kongdean2374/ChaiClassics/issues`，以及文字說明中的 TestFlight Beta Feedback；App 內明示外連需要網路、提交 issue 可能需要 GitHub 帳號。沒有 Email。
- 以下文案與本機 Markdown 為相同版本。網站上線時需同步內容，保留文件版本與可見的更新說明；不要把 Apple 系統／TestFlight 診斷說成 App 自建追蹤，也不要把系統備份誤稱為 App 雲端同步。
- 網站四頁全部實際回傳 200、兩種語言內容完整、手機測試與 HTTPS 驗證後，另一個 App PR 才可加入選用外連。**仍須保留離線本機政策**，不得改成只用 WebView。
- 網站 Codex 不得修改 Apple 簽署、Secrets、Private Signing repo 或自動發布 App。ASC 的 Support URL／Privacy Policy URL，由使用者確認網站已公開後手動更新。
- App Store Connect 的實際 App Privacy 申報本次未讀取／修改。使用者需確認「資料未收集」是否與實際申報、TestFlight／Apple 平台行為及任何日後網站服務一致，不能由網站或 App Codex 假稱已核對。
- 營運主體、可公開聯絡資訊、適用法與爭議管轄尚未由使用者提供。不要自行補上虛構資料；正式對外法律文本如需新增這些條款，由使用者確認。
- App 的 `PrivacyInfo.xcprivacy` 以 CA92.1 宣告只供本 App 存取的 UserDefaults；政策是程式行為說明，不等於已完成 ASC 申報。Apple 原始文件：https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype

## 下列雙語政策原文（對應 App 離線版本）

### zh-Hant / Privacy

```text
# 隱私政策

文件版本：0.1.1

## 我們實際處理的資料

Chai Classics 是免費、離線、無廣告、無訂閱、無帳號的經典遊戲 App。目前程式未整合廣告、追蹤、分析 SDK，也不主動向開發者伺服器傳送個人資料或遊戲紀錄。

## 本機遊戲進度與設定

數獨的盤面、候選筆記與完成紀錄，踩地雷的雷位、旗、揭開狀態與計時，以及滑塊的盤面、步數與計時，保存在此 App 的裝置儲存空間。外觀、語言、觸覺回饋與螢幕喚醒偏好另存本機設定。這些資料用於提供遊戲與離線續玩。

自動儲存固定開啟；App 也保留上一份完整存檔，以便在可復原時修復中斷或損毀的檔案。無法安全讀取的檔案會保留並停止覆寫，不會為了重新開始而默默清除。

## 系統備份與 Apple 平台

依你的裝置設定，iOS 裝置備份或 iCloud 備份可能包含本機 App 資料。這由 Apple 的系統功能與相關政策管理，不是本 App 提供的帳號或雲端同步服務。透過 TestFlight 使用 App 時，Apple 可能依其測試服務條款處理診斷、當機與測試回饋。

## 選用的支援連結

只有你主動開啟外部 GitHub 支援頁面時，才會離開本機內容並使用網路。GitHub 依其政策處理你在該網站提供的資料；請勿公開張貼私人資訊、裝置識別碼或完整存檔。官方網站仍在籌備，App 目前使用內建政策與條款。

## 保存與刪除

本機資料通常保留至你重新開始相應遊戲、移除 App，或由系統清除。移除 App 可能刪除進度；備份與換機是否恢復，由裝置系統設定與實際備份狀況決定，App 不保證可復原。重新開始數獨單題不會清除已完成紀錄；每款遊戲使用獨立存檔。

## 更新與聯絡

資料處理行為變更時，會隨 App 更新調整本政策。支援方式請見「支援與聯絡」。目前沒有在 App 內公布聯絡 Email；請勿將尚未發布的網站網址視為已上線服務。
```

### zh-Hant / Terms

```text
# 使用條款

文件版本：0.1.1

## 使用方式

Chai Classics 提供免費的個人休閒遊戲，不包含廣告、訂閱、購買或帳號。所有遊戲可離線操作；選用的外部支援連結需要網路。請遵守適用法令與你使用的 Apple 平台條款。

## 遊戲與資料

遊戲依各自規則運作。數獨採紙本玩法，不提供提示、正確答案揭露或錯誤標記；只有整盤合法完成時才記錄完成。遊戲紀錄與偏好存於本機，不提供由開發者伺服器恢復進度的服務。

重新開始或開新局可能取代該局資料，App 會先要求確認。更新會盡力保留既有進度，但裝置故障、儲存空間不足、移除 App 或系統處理仍可能造成資料無法使用。請依自己的需要管理裝置備份。

## 權利與合理使用

App 的程式、名稱及素材權利屬各原權利人。原始碼公開不會自動授予超出倉庫明示授權或另行許可的權利。請勿冒用 App 或開發者名義，或以違法方式使用相關內容。

## 可用性與責任

在適用法律允許的範圍內，App 依現況提供，不承諾零錯誤、不間斷可用或所有資料皆可恢復。法律規定不得排除或限制的消費者權利，不受本段影響。外部服務由各服務提供者管理。

## 更新與支援

功能、條款或相容性可能隨版本更新調整。支援方式以 App 內「支援與聯絡」所列資訊為準；官方網站仍在籌備，不代表目前已有對外網站或 Email 服務。
```

### zh-Hant / Support

```text
# 支援與聯絡

文件版本：0.1.1

## 官方網站籌備中

chaihome.cc 的 ChaiClassics 網站尚待製作與發布。本版不會開啟尚未驗證上線的政策或支援網址；內建隱私政策與使用條款可離線閱讀。

## 如何回報問題

TestFlight 測試者可使用 TestFlight 的「傳送 Beta 版回饋」。也可選擇下方的 GitHub 問題回報入口；外部網站需要網路，提出問題可能需要 GitHub 帳號。遊玩本 App 不需要帳號。

回報時請描述 App 版本、iOS 版本、裝置型號、遊戲名稱、重現步驟與預期結果。請避免提供私人資訊、裝置識別碼、Apple 金鑰或完整存檔；公開 issue 對所有人可見。

## 存檔出現問題時

請先保留 App，不要為了排錯刪除 App 或重新開始。確認裝置有可用空間；若顯示資料待處理，App 會停止覆寫該款遊戲資料以保護原檔。其他未受影響的遊戲仍可使用。

## 目前聯絡管道

目前使用 TestFlight 回饋與公開 GitHub 問題回報。尚未提供聯絡 Email，也不承諾特定回覆時間。正式網站與聯絡方式完成並驗證後，才會在後續版本整合。
```

### en / Privacy

```text
# Privacy Policy

Document version: 0.1.1

## Data the app actually handles

Chai Classics is a free, offline collection of classic games, with no ads, subscriptions or accounts. The current code includes no advertising, tracking or analytics SDK and does not actively send personal data or game records to a developer server.

## Local progress and preferences

Sudoku boards, pencil notes and completion history; Minesweeper mine positions, flags, revealed cells and time; and Sliding Puzzle tiles, moves and time are stored in the app’s storage on this device. Appearance, language, haptic and screen-awake preferences are stored separately in local settings. These records provide gameplay and offline continuation.

Autosave is always enabled. The app keeps the previous complete save for recovery when possible. Files that cannot be read safely are preserved and protected from overwriting, rather than silently cleared.

## System backups and Apple services

Depending on your device settings, an iOS device backup or iCloud backup may include local app data. Apple’s system features and policies govern these backups; the app does not provide an account or cloud-sync service. If you use TestFlight, Apple may handle diagnostics, crashes and testing feedback under its testing-service terms.

## Optional support links

Network access is used when you choose to open the external GitHub support page. GitHub handles information you provide there under its own policies. Do not post private information, device identifiers or complete save files publicly. The official website is being prepared; policies and terms are bundled in the app.

## Retention and deletion

Local records generally remain until you restart the relevant game, remove the app or the system clears its storage. Removing the app may delete progress. Recovery through backups or device transfer depends on system settings and available backups and is not guaranteed. Restarting a Sudoku board preserves completion history. Each game has a separate save.

## Changes and contact

Changes in data handling will be reflected in a future app update and policy. See Support & Contact for current support options. No contact email is published in the app at this time. Planned website routes are not presented as live services.
```

### en / Terms

```text
# Terms of Use

Document version: 0.1.1

## Use of the app

Chai Classics provides free games for personal recreation, without ads, subscriptions, purchases or accounts. All games work offline. Optional external support links require internet. Follow applicable law and the terms of the Apple services you use.

## Gameplay and records

Each game follows its own rules. Sudoku uses a paper-style approach with no hints, answer reveal or error marking. Completion is recorded only for a legally completed board. Game records and preferences are stored locally; no developer-server recovery service is provided.

Restarting or beginning a new session may replace that session’s records, and the app asks for confirmation first. Updates aim to retain progress, but device failures, limited storage, app removal or system actions may make data unavailable. Manage device backups according to your needs.

## Rights and reasonable use

Rights in the software, name and materials belong to their respective owners. Public source availability does not itself grant rights beyond an explicit repository license or separate permission. Do not impersonate the app or its developer or use the materials unlawfully.

## Availability and responsibility

To the extent permitted by applicable law, the app is provided as available, without a promise of zero defects, uninterrupted availability or recoverability of every record. Consumer rights that cannot lawfully be excluded or limited remain unaffected. External services are managed by their providers.

## Updates and support

Features, terms and compatibility may change with app updates. Current support options are listed under Support & Contact. The official website is in preparation; this does not imply an existing public website or email service.
```

### en / Support

```text
# Support & Contact

Document version: 0.1.1

## Official website in preparation

The ChaiClassics website on chaihome.cc has not yet been built and published for this release. The app does not open policy or support routes that have not been verified as live. Bundled Privacy Policy and Terms of Use remain readable offline.

## Reporting an issue

TestFlight testers can use Send Beta Feedback in TestFlight. You can also choose the GitHub issue tracker below. The external website needs internet, and submitting an issue may require a GitHub account. Playing the app does not require an account.

Include the app version, iOS version, device model, game name, reproduction steps and expected result. Avoid sharing private information, device identifiers, Apple keys or full save files. Public issues are visible to everyone.

## If a save has a problem

Keep the app installed. Do not remove it or restart a game merely to troubleshoot. Check available device storage. If a save needs attention, the app stops overwriting that game’s records to protect the original. Unaffected games remain available.

## Current contact channels

Current channels are TestFlight feedback and public GitHub issues. No contact email or response-time commitment is published. Website and contact details will be integrated only after they are completed and verified.
```

