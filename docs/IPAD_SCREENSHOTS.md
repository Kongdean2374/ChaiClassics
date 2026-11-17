# iPad 13 吋模擬器截圖與驗證

此流程只執行模擬器編譯、UI 測試及截圖，不會簽署 IPA、呼叫 Apple 帳戶 API、上傳 TestFlight 或送審 App Store。版本與 Bundle ID 不變，不修改正式遊戲規則、畫面或存檔。

## 從 iPhone 手動執行

1. 使用 Safari 開啟 [iPad Screenshots](https://github.com/Kongdean2374/ChaiClassics/actions/workflows/ipad-screenshots.yml)，登入有權執行工作流程的 GitHub 帳號。
2. 點 **Run workflow**，Branch 選 **main**。Runner 預設 **macos-15**（標準 ARM runner），Device name 保留 **auto**。
3. 點 **Run workflow** 開始。流程會列出 iPad 與 Runtime、明確選擇 13 吋 iPad Pro，然後編譯並執行四個獨立測試。
4. 開啟該次 Run。完成後先看 Summary 中的裝置、像素與測試摘要，再往下找到 **Artifacts**。
5. 點 **ChaiClassics-iPad-AppStore-Screenshots** 下載 ZIP。Safari 的下載圖示可開啟「檔案 → 下載項目」，點 ZIP 解壓縮。
6. 解壓後根目錄的四個 PNG 就是原生截圖；先看 REPORT.md／README.txt 的實際驗證結果，再決定是否用於 App Store Connect。GitHub 即使是公開倉庫，也可能要求登入才能下載 Artifact。

## 輸出內容

| 檔案 | 真實 App 畫面 |
| --- | --- |
| 01_iPad_Home.png | 繁體中文、深色首頁，三款遊戲入口 |
| 02_iPad_Sudoku.png | 數獨進行中棋盤與操作區 |
| 03_iPad_Minesweeper.png | 踩地雷進行中棋盤及遊戲資訊 |
| 04_iPad_SlidingPuzzle.png | 滑塊進行中棋盤與數字方塊 |

另附 device.json、report.json、REPORT.md／README.txt、原始 PNG／文字 XCTAttachment、test-summary.json，以及建置／模擬器啟動／UI 測試／匯出紀錄。完整 unsigned xcresult（含系統測試錄影）另外保存在 **ChaiClassics-iPad-XCTest-Results**，讓手機下載四張圖時不必一併下載大型錄影。兩份 Artifact 都是隔離測試種子的畫面與診斷；不含簽署憑證、API Key、私人進度或 IPA。

只有 PNG 原始像素為 **2064 × 2752** 或 **2048 × 2732**，且直向、機型與 XCTest manifest 相符、四項 UI 測試真正通過時，才宣告驗證成功。腳本只複製原圖，不縮放、裁切、拉伸或合成。尺寸不符合、圖片缺失、錯機型或測試略過，都會清楚失敗／標示未驗證。

## 裝置、Runtime 與 Runner

- 預設列出已安裝且可用的 iPad，優先選擇符合 Deployment Target 的最新穩定 iOS Runtime 和真正 13 吋 iPad Pro。
- 若 Runtime 和 13 吋 device type 已安裝，但尚未建立該 Simulator，可在當次臨時 runner 建立模擬裝置，不下載額外 Runtime。
- 指定 Device name 時必須與 inventory 名稱完全一致；找不到就報錯。不會退回 iPhone，也不將 12.9 吋裝置稱為 13 吋。
- 兩個標準 pool 均已確認能列出 13 吋 iPad Pro M5 與 iOS 26.2；ARM 在同份 UI 測試的實測案例執行較快，因此選 **macos-15** 為預設。若當次 image 的 inventory 不含合適機型／Runtime，可手動換成標準 **macos-15-intel** 再執行，並比較兩次 device.json。不使用付費大型 runner。GitHub image 會更新，實際可用性以該次 inventory 為準。
- 不改動既有 select_xcode.sh；沿用其選擇已安裝穩定 Xcode 的規則。Xcode、Runtime、CPU 架構與實際機型會寫入報告，不能由工作流程名稱推定已驗證。

## 測試與失敗診斷

重用 ChaiClassicsVisualSmokeTests、visual-gallery sandbox、v010 三款既有種子和 XCTAttachment。四個新 iPad 方法在 iPhone 上明確略過；原有 iPhone 四項測試保留。iPad 工作流程只選取這四個方法，不執行整套 iPhone 測試。

檢查涵蓋首頁三欄、數獨數字輸入／擦除、踩地雷旗標與棋盤可見性、滑塊真實移動、返回、暫停／繼續、重新開始及 iPad popover。截圖前確認主要控制項與棋盤在畫面內，無鍵盤或確認選單遮擋。

某款遊戲測試失敗時，其他獨立案例仍可執行；always 步驟會盡量匯出成功截圖與失敗紀錄。紅色 Run 的 Artifact 仍有分析價值，但不能因圖片存在就宣稱所有測試通過。未完成或損毀的 xcresult 也會保留，報告會標示匯出／驗證失敗。

首次啟動 iOS Runtime 的資料遷移與 XCTest 分成兩個步驟，啟動上限 10 分鐘、測試上限 25 分鐘。這些是逾時保護，並非正常耗時預估；實際進度可直接看對應步驟。此分離避免冷啟動吃掉測試時間，讓 xcodebuild 能完成並關閉 xcresult。布局診斷中不存在的容器只記為不存在，不會阻擋已取得的原圖。

現有 App 在 iPad 上使用部分固定內容寬度：首頁約 720pt、數獨約 560pt、滑塊約 540pt；小型踩地雷棋盤有既有倍率上限，因此大螢幕可能有較多留白。請以實際 PNG 與布局 JSON 判讀；本任務只記錄證據，不為了截圖重構 App。

已觀察到一項入口點擊問題：在 13 吋 iPad 直向、繁中／深色、有既存進度時，踩地雷與滑塊選單的「繼續上次遊戲」寬列中央點擊後，畫面仍停在選單。可見於 [ARM 執行紀錄](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43988218024) 的兩份失敗 UI hierarchy；按鈕範圍為 x=20、寬 992pt，播放圖示實際在 x=40～82pt，中央有大幅透明留白。測試改點按按鈕內可見的播放區，再嚴格要求遊玩頁的 restart 與棋格出現；不以修改導航狀態或跳過 App 選單來繞過操作。這項既有 UI 問題保留供後續 App 改版評估，本次不修改正式介面。

本文件是執行說明；是否實際成功，請看對應 Commit 的 Run 與 Artifact 報告。模擬器驗證不等同實體 iPad 的觸控、效能或 App Store 審核通過。
