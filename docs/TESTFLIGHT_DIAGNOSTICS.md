# TestFlight 建置／匯出診斷

## Run 43831551303 的可重現阻斷

該 run 使用 a3e66a5、fastlane 2.228.0、Xcode 26.3，match readonly 與 XCODE_PROFILE_READY 成功後幾乎立即出現舊 UPLOAD_FAILED。原始私密子程序日誌已依安全政策刪除，因此不能還原當時 stack；該碼也不能證明已開始上傳。

原 beta 傳入 `export_method: "app-store-connect"`。鎖定的 Gym::Options 對此欄位有 verify_block，允許 app-store 等舊名稱，不含 app-store-connect。新的 regression 直接呼叫已安裝 2.228.0 的 BuildAppAction.available_options／FastlaneCore::Configuration，使用原值必須得到 Unsupported export_method，發生在 action 執行／archive 前；修正版 archive、export 的完整參數必須全部通過同一真實 validator。這是已找出的確定第一個阻斷，不能據此宣稱後續正式匯出或上傳已成功。

`codesigning_identity` 在該版沒有拒絕 SHA-1 的 verify_block，build command 只是把它設為 CODE_SIGN_IDENTITY；它不是已證實的這次根因。但 Gym 說明契約要求完整名稱，因此現在從已通過 DER／Team／Distribution 檢查的同一張憑證取得完整 CN，並再次核對其 SHA-1。原指紋仍用於實際私鑰 probe、匯出 signingCertificate，archive 也重新比對內嵌 leaf DER 與原 profile bytes，不依名稱任意選另一張證書。

## 匯出相容性與驗證界線

Gym 參數與 export plist method 使用相容的 `app-store`。Xcode 26 的新名稱是 app-store-connect；macOS CI 讀取實際選定 Xcode 的 help，要求它仍列出 app-store 舊名稱，並由鎖定 Gym 實際產生 export plist，核對 method、manual、destination=export、signingCertificate、profile mapping 與不自動改 build number。此組合不會讓 Xcode 自行上傳。

無 Secrets CI 不執行正式 signed IPA export，也不呼叫 Apple。它證明 options／plist／Xcode 文件相容；真正 archive、export IPA 與 ASC transfer 仍須在使用者手動 TestFlight run 驗收。不可將這些測試稱為首次 TestFlight 已成功。

## 固定階段與安全診斷

| 失敗碼 | 實際範圍 |
| --- | --- |
| UPLOAD_AUTH | Developer Key 初始化、ASC App／build 查詢、版本／build number 預檢；不自動把所有例外視為權限不足 |
| BUILD_CONFIG | 已驗證憑證的完整身分名稱／SHA-1 綁定、真實 Gym 全參數驗證 |
| ARCHIVE | build_app(skip_package_ipa:true)、strict signature、archive leaf DER／embedded profile 精確配對 |
| EXPORT_IPA | build_app(skip_build_archive:true)、IPA 存在且路徑符合預期、準備 provenance |
| UPLOAD_TRANSFER | 實際 upload_to_testflight；此階段失敗可能有部分資料已送達 ASC，先查 ASC 再決定新 run |

各階段使用結構化白名單 report。公開輸出只含固定完成階段、失敗碼、reason enum 與可取得的數字 HTTP 狀態（401／403／404／429／常見 5xx 等）；不公開 exception、response body、標頭、識別碼、路徑、憑證、私鑰或 Token。沒有可用 HTTP 證據時顯示 unknown；不猜測角色不足。raw fastlane/xcodebuild/Transporter 輸出仍被隔離捕捉與刪除，磁碟 build log 不上傳 artifact。report 不完整或資產驗收不完整時，子程序 exit 0 也不能被當作成功。

代表性 reason：EXPORT_METHOD_UNSUPPORTED、GYM_OPTIONS_REJECTED、IDENTITY_BINDING、APP_RECORD_MISSING、BUILD_NUMBER_CONFLICT、AUTH_REJECTED、ACCESS_REJECTED、RATE_LIMITED、APPLE_SERVER、ARCHIVE_CERT_EXTRACT、ARCHIVE_CERT_MISMATCH、ARCHIVE_PROFILE_MISMATCH、IPA_MISSING。其餘工具錯誤只回傳對應階段的 COMMAND_FAILED／TRANSFER_FAILED／UNKNOWN，不刊出原始文字。

## 下一次手動重試

1. 等修正 commit 的完整 CI 通過。
2. Actions → TestFlight → **Run workflow**，選 main 與版本；開全新 run，不能按舊 run 的 Re-run，因為那會沿用舊 commit。
3. 沿用現有 Developer ASC Key 與 Team／match Secrets。所有 match 呼叫仍為 readonly，不新建／撤銷／替換證書，不改私人簽署 repo，也不操作 ChaiPhoto。
4. Build number 仍以新 run counter 產生並查 ASC 防重複／倒退；依序通過五個階段才表示傳輸呼叫完成。ASC 處理、Beta Review 與真機可安裝仍是後續驗收。

此次只推送程式、文件及執行無 Secrets CI，不自動執行 TestFlight、readonly Apple workflow 或初始化。沒有根據要求重建憑證或更換 API Key。
