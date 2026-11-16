# App 0.1.1 改版驗收

本次只改 App、資源、測試與文件，沒有製作網站。Bundle ID、iOS 17+、既有題庫及 Apple 簽署／Actions 發布流程保留。

- 踩地雷移除模式 Picker，單點直接 reveal，長按 toggleFlag，沿用原 exclusive gesture 防止放開後再揭開。入口先選大小／雷數，以密度標明參考難度（≤13%／≤18%／>18%），不設關卡、每局隨機，明示經典盤面可能需要推測。9×9 依原生 viewport 放大置中，大盤原始格尺寸可原生平移縮放，更新計時不重設 zoom。
- 首頁三欄依真實棋盤產生未開始／進行中／完成／失敗摘要。三款入口分續玩與新局；覆寫／restart 一律確認。
- 數獨保留 150 題、stable IDs、原解鎖與完成紀錄、答案筆／鉛筆／擦除；不新增提示、解答或錯誤標記。玩家填入數字與候選筆記使用藍色，題目數字採一般文字色（淺色黑／深色白），不依正誤改色。滑塊新增真正上下左右向空格拖動、跟手位移及方向／距離判定，保留點擊與 VoiceOver 操作；維持可解盤面與原始局重置。
- 新設定另存 UserDefaults v1：預設跟隨系統、繁中；即時雙語與 light/dark/system，真正的 haptic feedback、遊戲前景保持螢幕喚醒。自動存檔固定開啟。
- 離線雙語 Privacy／Terms／Support 與 UserDefaults privacy manifest。公開 Github 支援連結已驗證，chaihome.cc 路由只在 WEBSITE_HANDOFF.md 規劃，App 不開啟未上線 URL。

## 儲存相容

`Core/Sudoku.swift`、`Minesweeper.swift`、`SlidingPuzzle.swift`、`SaveStore.swift` 與題庫／manifest 保持 0.1.0 原樣，新增的 Core helpers 都沒有加入原 Codable 存檔欄位。

`Tests/ChaiCoreTests/Fixtures/v010-*.json` 是 v0.1.0 schema 的合成固定測試快照，沒有使用者私人資料。包含數獨候選與完成紀錄、mode=flag 的地雷實際盤面與計時、滑塊 35 步盤面。Core 與 UI 測試共同使用；合法原檔讀取及偏好更動不改動遊戲檔案，更新後仍沿原 namespace／schema 1 寫入。

UI 測試的 reset／seed 只在 Debug Simulator 編譯，使用獨立 `ChaiClassicsUITests` 資料夾及 preferences suite，不接觸正式存檔；Release 沒有這個重設入口。原有四項 UI 測試斷言保留並擴充。

## 測試與待真機驗證

一般 CI 跑固定題庫 Exact Cover、Swift 單元測試與 Simulator 編譯；完整 UI 保留並改為 CI 手動 full_ui。TestFlight 依使用者要求只做快速安全預檢，再正式簽署／封存／上傳，優先進行實機驗收。UI 覆蓋長按只插旗、單點忽略舊 mode、旗／揭開狀態、9×9 frame 置中、大盤 pinch 後格子命中、三欄及真實摘要、紙本數獨、三外觀／兩語言、偏好重啟、三份舊進度與離線政策。新增螢幕像素檢查玩家藍字／原題一般字色、滑塊四方向／反向不動／恰好一次存檔、地雷大小與雷數選擇；Core 額外覆蓋 40×40／長條盤與極高密度首點安全。

仍須 TestFlight 0.1.1 在 iPhone／iPad 真機驗收：0.1.0 就地升級保留使用者實際資料、9×9 與 16×16／30×16／40×40 操作、旋轉／不同螢幕／動態字級、長按與雙指縮放衝突、背景／強制關閉恢復、實體 haptic 與保持喚醒、跟隨系統外觀。Simulator 通過不代表零 Bug。

ASC 的既有隱私申報、公開聯絡資訊與網站正式發布狀態仍待使用者確認。本次未修改 Secrets、憑證或 Private Signing repo，未觸發 TestFlight／App Store。

## 遊戲規則與難度複查

- 50 題簡單數獨各有 36 個給定數字。另以不呼叫原生成器分級器的單候選解題程式逐題確認：只靠某格剩唯一候選即可完成，沒有使用 hidden singles、分支或答案。中等需要 hidden singles；困難表示前述兩策略不足，不等於一定要猜。評級不等於新手一定能快速找出下一步；原題完全不修改。
- 地雷為經典隨機布局，難度按密度估計；沒有無猜測保證。原首點／連鎖／勝敗引擎不變，新增形狀、密度與旗標邊界回歸測試。
- 滑塊原打亂程度由合法隨機步行長度決定，保證可解但不保證最少解步數。新增手勢只呼叫同一個 move，沒有第二份規則或新的存檔欄位。
