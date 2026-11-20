# Solace 部署与账号信息

## Cloudflare Pages

- **项目名称**：`solace`
- **正式域名**：`solace-doc.pages.dev`
- **账号 ID**：`151ba5486fc6e9e9eef7bd321c101ed0`（新账号；旧账号 `af48f65049fad4485235e33a5b4a43e1` 与旧域名 `solace-auth-v2.pages.dev` 不再使用）
- **部署身份**：使用 **API Token**（`CLOUDFLARE_API_TOKEN`，需 Pages:Edit），不再走 GitHub OAuth（旧 GitHub 账号已停用）。
- **部署方式**：`wrangler pages deploy . --project-name solace`
- **构建输出目录**：`solace/`（`wrangler.toml` 中 `pages_build_output_dir = "."`，含 `compatibility_date` 与 `nodejs_compat`，否则 `DecompressionStream` 会因 `node:stream` 报错）

## 部署前准备

1. 确保 wrangler 已登录：`npx wrangler login`（用 GitHub 登录方式）
2. 或设置环境变量：`CLOUDFLARE_API_TOKEN`（需要 API Token，权限含 Pages:Edit）

## 完整部署命令

```bash
cd /c/Users/Administrator/Desktop/Solace/solace
npx wrangler pages deploy . --project-name solace
```

## 版本更新（发布新版本时同步）

以下 5 个文件的版本号必须保持一致：
1. `pubspec.yaml` — `version: x.x.x+xxx`
2. `lib/config/constants.dart` — `AppVersion.version` / `AppVersion.build`
3. `solace/version.json` — `version` / `build`
4. `solace/_worker.js` — `VERSION_DATA.latestVersion` / `buildNumber`
5. `solace/index.html`、`solace/*.html` — 页脚版本号 `v19.0.1+8304`