# 正式簽署 Release Archive 診斷

## Run 43853135322 的證據與限制

8fe6b19 的 CI、UPLOAD_AUTH、BUILD_CONFIG、match readonly、XCODE_PROFILE_READY 與私鑰／DER 驗證已成功。失敗為 ARCHIVE／COMMAND_FAILED，EXPORT_IPA 和 UPLOAD_TRANSFER 未執行。

舊 `verify_archive!` 每個失敗分支均回傳特定 reason，未知例外也轉 ARCHIVE_CONTENT_INVALID；它不會回傳 COMMAND_FAILED。因而可將這次失敗定位在 `build_app` 呼叫內部，尚不能分清 Gym 準備、xcodebuild archive、Gym 封存後處理。原始私密日誌已隨 runner／wrapper 清理，不能事後還原。沒有證據把此結果歸因於 Apple 憑證、Keychain 私鑰不存在或 API 角色不足。

已查明設定缺陷：舊 builder 在全域 xcargs 傳 DEVELOPMENT_TEAM、PROVISIONING_PROFILE_SPECIFIER、OTHER_CODE_SIGN_FLAGS，Gym 也會把 codesigning_identity 轉成全域 CODE_SIGN_IDENTITY。這些會套用其他 target；本專案包含 Swift Package ChaiCore 與資源 bundle。已改為全域只傳 CHAI_* 自訂值，由 app 的 Release target 綁定標準簽署設定，不把 app profile 強加給依賴。CI 用真實 Xcode -showBuildSettings 比對舊全域 profile 與新 app-only 綁定，並驗證正式 Gym command generator 不再加全域 identity。這項設定缺陷與 Run 的具體 xcodebuild 錯誤是否相同，仍須以下手動 signed workflow 取得證據；不宣稱本次已完成正式封存。

## 手動工作流程

Actions → **Diagnose Signed Archive** → **Run workflow** → main，版本可保持 0.1.0。工作獨立執行，不需再跑整套 TestFlight。

- 使用 signing-bootstrap，只映射 APPLE_TEAM_ID、SIGNING_REPO_PAT、MATCH_PASSWORD；不注入 Admin／Developer ASC API Key。
- match readonly:true 匯入既有加密資產、保留原本真實私鑰 probe、certificate/profile DER 配對與 XCODE_PROFILE_READY。
- 與 beta 共用同一 ChaiArchive::Session、同一 app-scoped settings、同一 build_app archive options，真正執行 iOS Device／Release／signed archive；禁止 skip_codesigning、skip_archive、skip_build_archive 與全域標準簽署覆寫。
- 不匯出 IPA、不呼叫 upload_to_testflight、不查 ASC、不建立／撤銷／替換憑證、不 push 私人簽署倉庫、不動 ChaiPhoto。
- 僅 main／workflow_dispatch，與其他簽署流程共用 apple-release concurrency。沒有任何 artifact 上傳步驟。

## 什麼才表示真實封存成功

必須該手動 run 整體 success，且同時看到 XCODE_PROFILE_READY 及依序完成：

1. BUILD_SETTINGS_CHECKED：參數範圍／私密工作目錄有效，沒有 unsigned／跳過封存或全域 profile 覆寫。
2. BUILD_APP_RETURNED：build_app 已返回，與後置驗證明確分離。
3. ARCHIVE_FORMAT_VALID：有有效 xcarchive Info.plist、ArchiveVersion=2 與正確 ApplicationPath。
4. ARCHIVE_APP_VALID：app 的 Bundle ID 正確，CFBundleSupportedPlatforms 包含 iPhoneOS。
5. ARCHIVE_SIGNATURE_VALID：對真正封存 app 執行 codesign --verify --strict。
6. ARCHIVE_CERTIFICATE_MATCH：抽出實際封存 app 的 leaf certificate，DER 精確等於前面已驗證的 Distribution certificate。
7. ARCHIVE_PROFILE_MATCH：實際 embedded.mobileprovision bytes 精確等於前面已驗證的 profile。
8. SIGNED_ARCHIVE_VERIFIED，phase=COMPLETE／status=complete。

單獨的 CI、unsigned archive、參數檢查、BUILD_APP_RETURNED 或 **ARCHIVE SUCCEEDED** 都不能代替這組完整驗收；沒有 unsigned fallback。

## 安全診斷的讀法

報告區分 BUILD_SETTINGS、BUILD_APP、VERIFY_ARCHIVE、COMPLETE。原始日誌中的 **ARCHIVE FAILED**／**ARCHIVE SUCCEEDED** 只轉成 command=failed／succeeded；沒有觀察到標記就顯示 not_observed，不能據此斷言沒有執行命令。

| 固定碼 | 已觀察事實 |
| --- | --- |
| XCODEBUILD_ARCHIVE_FAILED | build_app 未返回，原始 xcodebuild 有 ARCHIVE FAILED 標記 |
| GYM_POST_ARCHIVE_FAILED | build_app 未返回，但 xcodebuild 已有 ARCHIVE SUCCEEDED；錯在 Gym 後處理，並非我們的 verify_archive! |
| BUILD_APP_FAILED_UNCLASSIFIED | build_app 未返回，日誌缺少明確命令標記，保留未知 |
| ARCHIVE_VALIDATION_FAILED | build_app 已返回，之後格式／app／簽章／憑證／profile 驗證失敗，另顯示固定 verification code |

解析器另區分 COMPILE、SIGNING、PROFILE、KEYCHAIN、SWIFT_PACKAGE、BUILD_SETTINGS、ARCHIVE_FORMAT、BUILD_TOOL、DIAGNOSTIC。例：SWIFT_COMPILE_ERROR、LINKER_FAILED、PROFILE_NOT_APPLICABLE、PACKAGE_PROFILE_OVERRIDE、KEYCHAIN_ACCESS_DENIED、PACKAGE_RESOLUTION_FAILED、BUILD_SETTINGS_TIMEOUT。可有多個相關碼；不自動把 generic codesign／errSecInternalComponent 認定為 Keychain 無私鑰。

所有 raw fastlane／xcodebuild／error_info、Gym build logs、DerivedData 與 xcarchive 只放 runner 的私密暫存樹，根目錄 0700、子程序 umask 077，離開 wrapper 清除。解析器不跟隨私密根目錄外的 symlink，輸出只由固定 enum 組成，絕不回傳命中的原句、識別碼、憑證、密碼、JWT／Token、請求標頭或敏感路徑。原始 log 不上傳 artifact；TestFlight 原有 provenance 僅保留版本／build／公開 commit。

## 何時重試 TestFlight

先等修正 commit 的一般 CI 成功，再由使用者手動執行上述 Diagnose Signed Archive。只有它完整通過 SIGNED_ARCHIVE_VERIFIED，才適合開啟**新的** TestFlight main run。若診斷失敗，先依固定 phase／code 修正；不要用重跑整套 TestFlight 排錯，也不要重建憑證。正式 IPA export、ASC transfer 與 Apple 後續處理仍需各階段分別驗收。

此次程式更新不會自動觸發此正式簽署 workflow、Initialize Signing 或 TestFlight。一般 CI 的合成簽署資產／mock commands 與 unsigned archive，只驗證實作及設定範圍，不能宣稱已在正式資產上封存成功。
