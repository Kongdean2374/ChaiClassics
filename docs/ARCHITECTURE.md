# 架構與存檔

`Core/` 是不依賴 SwiftUI 的 ChaiCore Swift Package，App 透過本機 package dependency 使用相同規則。`App/` 為 SwiftUI 介面；`ZoomBoard` 用原生 UIScrollView 支援大踩地雷盤面平移縮放。沒有遠端 package 或 App 執行期網路呼叫。

新增遊戲：

1. 在 GameID 加入永不改名的 case，在 GameRegistry 加入名稱、圖示及類別；共用三欄首頁會自動增加卡片。
2. 在 Core 建立 Codable 規則／狀態，將遊戲操作與完成判定留在引擎，勿放在繪圖程式中。
3. 建立 App 專用 menu/play view，並在 HomeView 共用路由加上目的地。AppModel 加入該遊戲載入、驗證、交易式儲存與摘要。
4. 使用自己的 namespace、schemaVersion 與測試，不可重用另一遊戲的檔案。
5. 執行 `python3 scripts/create_project.py` 更新已提交的原生 Xcode 工程，加入規則與 UI 測試，CI 通過才交付。

只有完整實作的遊戲才能註冊。未註冊遊戲不會出現在首頁，沒有預告／假按鈕。

## 儲存協定

路徑為 Application Support/ChaiClassics，`sudoku.json`、`minesweeper.json`、`sliding.json` 分別包含 `{schemaVersion:1,payload:...}`。設定頁沒有尚未支援的音效開關；目前遊戲全為靜音。

每次有效操作都在主執行緒經 SaveStore 同步原子寫入，成功後才更新可見狀態；沒有尚未落盤的背景寫入佇列。背景切換再 flush。計時以遊戲畫面活躍時每秒記錄，不計算暫停、返回、背景或離線時段。

每次寫入前，上一份完整檔案原子寫成 `.backup`，主檔再以 Foundation `.atomic` 置換。中斷 staging 不影響既有主檔。主檔無法解碼時嘗試備份，保留 `.corrupt` 證據後修復主檔；沒有有效備份時封鎖該遊戲，避免靜默重設。語義不合法的可解碼資料也會封鎖，需另行修復。其他遊戲仍可玩。

未來 schema 比現版新時不讀舊備份、不覆寫。真正升版時用 `load(version:migrate:)` 接收舊 envelope，明確轉換後再 save 新版；測試已包含 1→2、未來版本拒寫與備份復原。本版尚無需要遷移的已發布舊 schema。

數獨以 stable puzzle ID 對應 boards 與 completed 集合，清除本題不清除已完成紀錄。每難度獨立以前一題完成解鎖下一題。更新題庫只能追加，不能靠陣列位置遷移。舊題存檔、候選、當前模式全部保留。踩地雷首次揭開後保存實際雷位；重啟不重新擲骰。

## 0.1.1 App 層

AppPreferences／PreferencesStore 使用獨立 `chaiclassics.preferences.v1` UserDefaults key；GameSummary 只計算真實盤面摘要，不更動已發布 Codable 欄位。遊戲原 namespace、schemaVersion=1 與題庫不變。

AppText 讀 Apple `.lproj/Localizable.strings`，並在根 View 注入 locale／preferredColorScheme；UIKit zoom host 明確同步外觀。ZoomBoard 由 UIScrollView 原生 transform 計算觸控座標，純 BoardViewport helper 算 min scale 與置中量，計時更新不重置 zoom。GameplayActivity 僅在前景、可操作時套用 keep-awake，離開／暫停恢復正常鎖屏。

離線法律文件與 privacy manifest 由專案生成器加入 resources，網站只交接規格。詳細內容見 RELEASE_0.1.1.md 與 WEBSITE_HANDOFF.md。
