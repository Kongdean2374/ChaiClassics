# 公開原始碼與私人 match 簽署

ChaiClassics 原始碼 Public、未加 LICENSE。簽署資產只放 **Private Kongdean2374/ChaiClassics-Signing/main**，match 使用 MATCH_PASSWORD 加密。倉庫 private 與加密都必須成立；原始 p8／PAT／加密密碼只在 GitHub Secrets，不進任何 repo。

所有簽署必須 workflow_dispatch + trusted main，先免簽署 CI，再 environment 注入憑證。PR／push CI 無 Apple Secrets，不使用 pull_request_target。production／signing-bootstrap 的 required reviewers 與 main 部署保護需管理員在 Settings 啟用，YAML 名稱不代表已配置。

初始化 Job 僅在 signing-bootstrap Environment 讀取 SIGNING_ASC_KEY_ID／SIGNING_ASC_ISSUER_ID／SIGNING_ASC_API_KEY_P8 Admin Secrets，再映射到 ASC_*。一般 TestFlight／App Store 保留原本 Developer API Key；Admin Key 不傳給 CI 或日常上傳。readonly TestFlight 不探測 Apple 憑證／Profile 管理 API，不把初始化權限強加給 Developer Key。

只有 Initialize Signing lane 是 match readonly:false。TestFlight 固定 readonly:true，Matchfile 的安全預設也是 true。限定一個 Bundle ID／Team，沒有 nuke、revoke、強制更新或自動撤銷其他 App 證書的功能；配額不足就失敗。不要為解決錯誤撤銷不明用途的團隊憑證。

SIGNING_REPO_PAT 只授權私人簽署 repo：初始化需 Contents read/write，readonly 可用 read。預檢驗證私密倉庫與 main，實際 clone/push 驗證真正權限。App repo GITHUB_TOKEN 始終 contents: read。match Git basic authorization 在記憶體由 PAT 建立，不把 PAT 放 clone URL。

有憑證的三個 lane 只透過 run_signing_lane.py：子工具全部原始輸出被捕捉到不公開的匿名臨時檔，完成後刪除；公開日誌只有固定錯誤碼。這比只依 GitHub 字串遮罩更能防止 Base64／轉換後的憑證洩漏。不要 print env、開 set -x、直接 cat fastlane 日誌或上傳敏感 artifact。

macOS 工作使用臨時 keychain，結束恢復原 keychain 清單與本 App 的原本 profile，清除新安裝 profile。match 在 ensure 清理解密 clone。不要把 p8、p12、cer、profile、keychain、IPA、CSR 或 build logs 加到 Git／Release／公開 artifact；gitignore 只是防呆。若外洩先撤銷該資產／Key，刪檔不會使已外洩秘密失效。

依賴由 Gemfile.lock 鎖定，actions pin commit。CI 用臨時測試金鑰驗證原始 PEM、readonly、權限與日誌抑制，不使用真 Apple 資產。實際 Apple 建立／簽署／上傳只有手動簽署流程才能驗證。

App 執行期沒有網路、帳號、analytics、廣告或推播；開發部署工具的 API 存取不進 App。隱私問卷仍需依實際二進位填寫。進度只在本機，卸載可能移除。

Apple API 診斷不依賴任意例外文字判定權限。獨立唯讀流程只允許三個固定 GET、HTTPS 固定 host、不跟隨 redirect／pagination、不重試；它不接收 match credentials。安全 IPC 僅准固定資源、數字 HTTP、固定分類及明確 allowlist code，禁止 request／response／headers／exception 原文。未知／格式／網路／5xx 不宣稱權限不足。report 與原始子程序 log 都在結束時刪除、不上傳 artifact。

Apps／Certificates 比較使用同一不可變 JWT，無刷新／重試。新增 IPC schema 2 僅准布林 JWT 檢查、兩個固定資源的 HTTP／白名單 code 與固定結論，不准 header／payload／實際 kid／iss／時間戳／token／私鑰。兩個結果各自收集後再失敗；401 不自動等同 403。手動唯讀 workflow 保持 Admin bootstrap 環境，沒有 match credentials。
