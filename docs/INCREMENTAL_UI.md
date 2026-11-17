# 指定範圍驗證

GitHub Actions → CI → Run workflow 可選 `ui_scope`。`full` 執行全部 67 個 UI 案例；`part_a`、`part_b`、`part_c`、`part_d` 是依當次原始碼排序、不重複的四個分組。`expanded` 只執行新增 17 款完整對局路徑；也可以選單一遊戲。普通 push 不自動跑模擬器 UI。

每組仍執行規則／存檔測試及真正 Simulator 編譯。`runner` 可選標準 `macos-15` 或 `macos-15-intel`，預設不變，無付費機器。通過 A、B 後修 C，不必無條件重跑 A、B；用 `baseline_run` 提供原始 Run IDs，`affected` 會依真實來源證據挑選未通過或受影響項目。

跨 Run 證據以原始 XCTest 日誌、summary、來源 commit、Artifact 雜湊和逐案例相依原始碼重建。App 共用元件、Core、存檔、資源或未知依賴變動時，會保守地使相關／全部案例失效。測試斷言或共用測試工具有變動也必須重新驗證。不能拿任意綠色 Run、少數測試或不相符的舊原始碼假裝完整通過。

完成全部 67 個當前案例的可驗證覆蓋後，仍需同一候選版的 iPhone Visual 四項和 iPad 四張原生 PNG 加 22 款遊戲路徑證據。0.3.x TestFlight 禁止手動 QA 捷徑；不得把局部結果當成整體通過。

上述工作完全 unsigned、不讀取 Apple 金鑰、不建立憑證。正式 TestFlight 仍限 main／手動入口及既有 match readonly 資產；只有驗證門檻通過後才執行使用者已授權的上傳。
