# macOS runner 容量與 Intel 切換

TestFlight Run [43929674085](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43929674085) 的 CI/test 未取得 hosted runner，GitHub 註記：`The job was not acquired by Runner of type hosted even after multiple attempts`，並提示 macOS ARM64 capacity constraints。上傳工作 skipped，沒有進入簽署／IPA 上傳。

GitHub 官方 [runner labels](https://github.com/actions/runner-images#available-images) 現在把 `macos-15` 對應到 ARM64；`macos-15-intel` 是獨立的 x64 標準 runner。這次只將 `.github/workflows/ci.yml` 的兩個 macOS 工作與 `testflight.yml` 的 upload 工作改為 `macos-15-intel`，沒有使用 `-large`／`-xlarge` 付費大型 runner。

[Intel macOS 15 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md#xcode) 提供 Xcode 26.3（17C529），但預設是較舊 Xcode，因此保留 `scripts/select_xcode.sh` 的明確 Xcode 26+ 選擇與缺 SDK 時失敗檢查。Simulator 架構沿用 `platform.machine()`，在 Intel 上選 x86_64；正式封存仍用 `generic/platform=iOS` 產生 iOS Device arm64，沒有加入全域 ARCHS 覆寫。

match readonly、既有私鑰／憑證配對、Developer API Key、Secrets、Environment、main／手動限制、release concurrency 與全部安全回歸檢查保留。其他 Apple 工作流程、私人簽署倉庫、憑證與 App 程式碼不在本次變更範圍。TestFlight 的手動觸發／權限／concurrency 標頭與簽署上傳 Job 以固定雜湊保護，只允許明確的版號、runner 與預檢依賴變更；預檢另驗證無 Apple Secrets。

Intel 也可能排隊；切換是避開已確認的 ARM64 容量瓶頸，不代表保證立即取得機器。須以新 main 的完整 CI 實際驗證 Intel 編譯、Swift／UI 測試與發布工具相容性。

首次 Intel CI [43935523740](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43935523740) 已成功取得兩台機器並選用 Xcode 26.3。19 項 Swift 測試與 App 編譯通過；雙語法律 UI 流程實測 162 秒，超過原 120 秒上限，後續測試遇到 app termination 失敗並重啟 runner。重啟後各 UI 操作有通過紀錄，但整輪仍為 failure，不能當作完整通過。

因此將 UI 每項預設／最大時間改成 180／240 秒，仍啟用 XCTest timeouts；整個 App 工作限制 45 分鐘。全部 UI 斷言、測試數量、序列執行與測試內容保留。`scripts/ci.sh` 預設仍跑完整流程；CI 分開呼叫 verify／unit／build／ui，直接顯示題庫相容性、Swift 測試、App 編譯及 UI 測試四個階段。未知階段會失敗，不能靜默跳過。

## 手動重新觸發

舊 Run 綁定舊 commit；對舊 Run 按 Re-run 仍使用舊 runner 設定。從 TestFlight 工作流程頁面新開 Run workflow，選 main；Version 已預填 0.1.1，Apple Team ID 留空。TestFlight 不再等待完整模擬器 UI。

發布流程使用 `apple-release` concurrency 且不自動取消既有工作。若舊 Run 仍停在排隊，先在 GitHub 確認它尚未進入 upload 並取消該舊 Run，才新開上述工作，避免新的執行等待舊鎖或重複上傳。若舊 Run 已開始簽署／上傳，讓它完成。本次修正與一般 CI 不會自動觸發 TestFlight。

## 使用者要求的精簡發布路徑

依使用者「不要一直測到無法實機測試」的明確調整：TestFlight 只先跑 Linux 快速預檢（題庫唯一解、Python／Ruby／YAML 與簽署工具安全回歸，不含 Apple Secrets），通過後直接進入原本 match readonly、真實 iOS Device Release archive／export／upload。不再呼叫整份遊戲 CI，也沒有新增 CI 證明重用系統。

一般 push／PR CI 保留題庫、存檔相容性、Swift 單元測試、Simulator App 編譯及工具檢查；完整 UI 測試與所有斷言仍保留，改由 GitHub Actions → CI → Run workflow → main → full_ui=true 手動執行。`bash scripts/ci.sh` 仍會在本機跑全部階段。這是將耗時的 UI 驗證改為按需執行，不代表本次每次快速 CI 都執行了 UI。

數獨測試用求解器將每格相同的佔用數字集合從建立九次改為一次，150 題、候選順序、解數上限及斷言都未改；實際加速幅度以新 CI 紀錄為準。優先透過 TestFlight 在 iPhone／iPad 做就地升級與真機操作驗收。
