# 既有簽署資產的 readonly 後置驗證

## Run 43818758376 的證據與限制

CI 成功；certificates／profiles／bundleIds 預檢均 HTTP 200。私人 ChaiClassics-Signing 的 commit 4bc217b0 已包含加密 Distribution certificate、private key 與 App Store profile。這證明資產已寫入，不代表 runner 的 profile 路徑、Keychain identity 或實際私鑰簽名已驗收。

舊 with_match_signing 把三種不同失敗統一為 MATCH_ASSETS：

1. 單一 sigh profile-path 環境變數沒有可讀檔案。
2. 描述檔過期／不是 App Store 用途。
3. Keychain 沒有有效 codesigning identity。

舊日誌未保留是哪個分支，私密原始 log 已刪除，不能斷言就是路徑錯或私鑰遺失。固定 fastlane 2.228.0 的 profile-path 命名確實是 sigh + 原始 Bundle ID + appstore + profile-path，以底線連接；Bundle ID 中的點不會改成底線。修正改用 Match::Utils 的命名函式，不猜測名稱，並且不再依賴單一變數。

該版 fastlane 的 profiles_path/install 仍用 legacy 目錄。新 verifier 同時搜尋 Xcode 16+ 的 Developer/Xcode/UserData 與 legacy MobileDevice 安裝目錄；不在公開日誌輸出實際使用者路徑。

## Run 43826441030：實際簽名已通過，最後抽取指令有誤

使用者手動執行的 [readonly run](https://github.com/Kongdean2374/ChaiClassics/actions/runs/43826441030) 已依序通過 profile、Bundle／Team／期限、certificate、Keychain identity、PRIVATE_KEY_SIGNED 與 SIGNATURE_VERIFIED；最後報 ASSET_SIGNED_CERT_PAIR。這證明本次既有資產可下載、解密、匯入及實際簽名，不是 Apple API 權限或私鑰簽名失敗。但最後的內嵌 DER 配對還未完成，不能宣稱整個驗收成功。

發現 verifier 將 codesign 的 optional argument 拆成 `--extract-certificates` 與獨立 prefix；codesign 會把 prefix 當作待檢查的 binary，而不是抽取位置。已改為單一 argv `--extract-certificates=...`，繼續嚴格比較 leaf DER。原 mock 過度接受錯誤語法，已改成拒絕拆開的 prefix。

CI 新增獨立 macOS job，對系統既有已簽署 binary 唯讀重現舊語法失敗，並直接執行 production extractor 驗證正確語法及 DER。該 job 不讀取 Secrets、不呼叫 match、不修改 Keychain，也不建立任何證書。另將抽取 command 失敗、輸出缺失／無效、真正 DER 不符分成三個固定碼。

## 目前政策：資產已初始化，只重用

所有公開 lane 與 match_options 都強制 readonly:true，傳 false 會立即以 ASSET_READONLY_REQUIRED 拒絕。既有 Initialize Signing 入口也鎖定 readonly，不再提供自動建立、重發、撤銷或替換證書的路徑。不要重新執行 Initialize Signing。

match readonly 在此固定版本會讀取、解密、安裝既有資產，但不登入 Developer Portal、不產生新資產、不 encrypt/push 回私人 repo。缺失或過期就停止。只指定 cc.chaihome.chaiclassics，其他 App（包括 ChaiPhoto）的 Apple 資產完全不做修改。

## 檔案與程式位置

- fastlane/Fastfile：with_match_signing 管理臨時 keychain、呼叫 readonly match、建立 SDK hints、呼叫驗證器與清理；verify_signing_assets 是獨立唯讀 lane。
- fastlane/lib/signing_asset_verifier.rb：描述檔發現、內容／Bundle／Team／期限／用途、憑證／Keychain identity／真實簽名與配對。
- scripts/signing_asset_report.py 與 run_signing_lane.py：固定碼／階段 allowlist、敏感 log 抑制與成功報告完整性。
- .github/workflows/verify-signing-assets.yml：獨立 main 手動入口。

## 依序驗證，不跳過實際簽名

1. 使用 Match::Utils 取得 path、UUID、profile name；也接受 match lane context 的本 App 名稱 mapping。
2. path hint 缺少／指向失效檔案時，按 UUID／name 及兩個安裝目錄尋找本 App。不同 App 的檔案只忽略、不選取、不修改；多個衝突 UUID 不任意挑選。
3. security cms 解碼與 plist schema 檢查。Bundle ID 必須精確相同；允許舊 App ID Prefix 與 Team ID 不同，但 prefix 必須是 profile 宣告的 prefix，TeamIdentifier／team entitlement 仍要匹配設定。
4. 分開確認 profile 有效期限、iOS App Store 用途、DeveloperCertificates 的可解析性／期限／Distribution 類型及 certificate OU team。
5. security find-certificate 只查臨時 keychain，證書 DER 必須存在於 profile 的 DeveloperCertificates；不能只相信名稱。
6. security find-identity 的有效 codesigning identity fingerprint 必須對應上述 profile certificate，不能任選第一個 identity。
7. 用 xcrun clang 編譯私密暫存 Mach-O；使用該 identity 與臨時 keychain 真正執行 codesign（不取 timestamp）。再 strict verify 簽章、抽出內嵌 leaf certificate，DER 必須與 profile certificate 完全一致。沒有跳過／假成功開關。
8. 只將已驗證的本 App profile 準備到新／舊 Xcode 目錄；已占用且內容不同就拒絕，不覆蓋。結束恢復原本本 App profiles、移除新暫存安裝與臨時 keychain，不清除其他 App 的檔案。

這驗證真實本機私鑰操作及 certificate/profile 配對，不會建置正式 IPA 或上傳 TestFlight。

## 固定錯誤碼

| 階段 | 固定碼 |
| --- | --- |
| readonly／Keychain／match | ASSET_READONLY_REQUIRED、ASSET_KEYCHAIN_SETUP、ASSET_MATCH_READ |
| 尋找／讀取／解碼 | ASSET_PROFILE_PATH、ASSET_PROFILE_READ、ASSET_PROFILE_DECODE |
| 結構／選擇衝突 | ASSET_PROFILE_CONTENT、ASSET_PROFILE_AMBIGUOUS、ASSET_PROFILE_METADATA |
| App／Team／Profile 期限／用途 | ASSET_BUNDLE_ID、ASSET_TEAM_ID、ASSET_PROFILE_EXPIRED、ASSET_PROFILE_TYPE |
| Certificate | ASSET_CERT_CONTENT、ASSET_CERT_EXPIRED、ASSET_CERT_NOT_YET_VALID、ASSET_CERT_TEAM、ASSET_CERT_TYPE |
| Keychain 配對 | ASSET_KEYCHAIN_CERT、ASSET_CERT_PROFILE_PAIR、ASSET_DISTRIBUTION_IDENTITY、ASSET_IDENTITY_AMBIGUOUS |
| 真實私鑰操作 | ASSET_PROBE_BUILD、ASSET_PRIVATE_KEY_SIGN、ASSET_SIGNATURE_VERIFY |
| 內嵌憑證抽取／配對 | ASSET_CERT_EXTRACT（command 失敗）、ASSET_EMBEDDED_CERT_CONTENT（leaf 缺失／無效）、ASSET_SIGNED_CERT_PAIR（實際 DER 不符） |
| Xcode 準備／未知 | ASSET_PROFILE_INSTALL、ASSET_INTERNAL |

ASSET_PRIVATE_KEY_SIGN 不等同「私鑰一定不存在」；ACL、解鎖、信任鏈／WWDR 或工具問題也可能使 codesign 失敗。不要因為一個失敗自動重建證書。

## 手動執行方式

1. 在 Public ChaiClassics → Actions 開啟 **Verify Signing Assets (read only)**。
2. Run workflow，分支選 main。
3. Environment 使用既有 signing-bootstrap。只讀取共用 APPLE_TEAM_ID、SIGNING_REPO_PAT、MATCH_PASSWORD；PAT 只需私人 Signing repo 的 Contents read。**不需要 ASC API Key，亦不注入 Admin／Developer Key。**
4. 看固定階段結果，成功必須到 XCODE_PROFILE_READY；失敗看 ASSET_* 碼。不要為此重跑 Initialize Signing 或觸發 TestFlight。

公開 log 只包含固定 stage／code、profile source 的 enum、path hint 為 missing/stale/present。沒有路徑、UUID、Team 值、certificate fingerprint／內容、私鑰、密碼、JWT／PAT、原始 command/error output。原始子程序 log 與安全 report 在私密暫存目錄處理後刪除，沒有 signing artifact。

## 測試與尚未實跑項目

CI 用合成 X509／profile、模擬 macOS command adapter 驗證路徑 fallback、現代／legacy 目錄、精確配對、其他 App 不受影響、簽名／verify／extract 任何失敗都拒絕，以及固定碼無敏感資訊。額外 macOS job 對系統 binary 使用真正 codesign，測 production extractor，不使用私人 repo 真資產。

Run 43826441030 是使用者手動觸發，已提供上面列出的真資產通過階段。修正抽取語法後仍需使用者手動重跑 readonly workflow，完整通過 XCODE_PROFILE_READY 才算驗收；程式修正及 CI 不會自動重跑 readonly、Initialize Signing 或 TestFlight。既有證書可實際簽名，沒有依據要求調整 Apple 後台、重新初始化或重建證書。
