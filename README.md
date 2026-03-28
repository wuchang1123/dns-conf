# cn-dns-conf

将 [felixonmars/dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list) 的 **dnsmasq** 配置（`server=/域名/上游IP`）整理后输出为 **dnsmasq**、**SmartDNS** 与 **AdGuard Home** 可用的片段。脚本用 Bash 完成下载、去注释与格式转换。

## 依赖

- Bash、`curl`、`awk`（macOS / BSD `awk` 即可）

## 默认源文件

从 `BASE_URL`（默认同仓库 `master`）下载并合并：

| 文件 |
|------|
| `accelerated-domains.china.conf` |
| `google.china.conf` |
| `apple.china.conf` |

处理规则：

- 去掉行首（允许前导空格后）以 `#` 开头的行
- 去掉行尾 ` # ...` 形式的注释
- 只解析形如 `server=/example.com/1.2.3.4` 的行
- 三个文件按上述顺序合并；**同一域名保留首次出现的记录**
- 生成结果先写入临时目录，**全部成功后再整体替换 `out/`**；校验失败或中途报错时不会留下半成品

## 用法

```bash
./convert-dnsmasq-china.sh              # 下载并生成
./convert-dnsmasq-china.sh --no-download # 使用已有 upstream/ 下的文件
./convert-dnsmasq-china.sh -h            # 帮助
```

`--no-download` 可与其它参数任意顺序混写。

### 统一指定上游（可选）

将**所有域名**指向你指定的 DNS IP。第二个参数 **`<dns_alias>` 可省略**：省略时 SmartDNS 的 `-g` 组名与「按 IP 自动生成」规则一致（IPv4 为 `g_a_b_c_d`，例如 `223.5.5.5` → `g_223_5_5_5`）；提供别名则使用该名称（如 `alidns`）。

```bash
./convert-dnsmasq-china.sh 223.5.5.5          # 组名默认 g_223_5_5_5
./convert-dnsmasq-china.sh 223.5.5.5 alidns # 组名为 alidns
```

只写别名、不写 IP 会报错。不提供任何位置参数时，仍按各 dnsmasq 行里的 IP 与对应组名处理。  
指定 IP 后 **dnsmasq**、**AdGuard** 里每条规则的上游均为该地址；**SmartDNS** 的 `server … -g` 与 `nameserver …/组名` 使用上述组名规则。

## 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `BASE_URL` | `https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/refs/heads/master` | 列表下载根路径 |
| `INPUT_DIR` | `<脚本目录>/upstream` | 原始 `.conf` 存放处 |
| `OUT_DIR` | `<脚本目录>/out` | 生成文件输出目录 |
| `AG_BATCH` | `8` | **同一上游 IP** 下每行合并的域名个数：AdGuard（`[/d1/d2/.../]upstream`）与 dnsmasq（`server=/d1/d2/.../ip`）共用 |
| `SMARTDNS_DOMAINSET` | `yes` | `yes`：用 `domain-set` + 列表文件（紧凑）；`no`：每个域名一行 `nameserver` |
| `SMARTDNS_LIST_BASENAME` | `china-domains` | 全量域名列表文件名前缀（与 DNS 无关）：始终为 `basename.list` |

## 输出文件

均在 `OUT_DIR`（默认 `out/`）下。**本仓库已跟踪 `out/`**，可直接从 GitHub 浏览或下载（例如 Raw 链接），无需本地跑脚本。若上游列表有更新，可执行 `./convert-dnsmasq-china.sh` 后重新提交 `out/`。

| 文件 | 说明 |
|------|------|
| `dnsmasq-china.conf` | dnsmasq 片段：每行最多 `AG_BATCH` 个域名，`server=/d1/d2/.../IP`（与 AdGuard 分批规则相同）；`conf-file=/绝对路径/dnsmasq-china.conf` |
| `smartdns-china.conf` | SmartDNS 片段：在 `smartdns.conf` 里用 `conf-file /绝对路径/smartdns-china.conf` 引入 |
| `china-domains.list` | **全量域名**（一行一个），与使用哪台上游 DNS 无关；可改 `SMARTDNS_LIST_BASENAME`。单套上游时 SmartDNS 的 `domain-set -file` 也指向此文件 |
| `smartdns-domains_<组名>.list` | 仅当合并结果里存在**多套上游 IP** 时生成，供 SmartDNS 按组分区的 `domain-set` 使用；不影响 `china-domains.list` 的语义 |
| `adguard-upstream-china.txt` | AdGuard Home 的「上游」列表或 `upstream_dns_file` 内容：`[/域名1/域名2/.../]IP`，每行最多 `AG_BATCH` 个域名（同一 IP） |

以下为 **`main` 分支** 上 `out/` 的 Raw 地址（可直接 `curl -O` 或在路由器里填 URL；若你使用 fork 或其它分支，请把路径中的用户名、仓库名或 `main` 改成自己的）：

| 文件 | Raw 下载地址 |
|------|--------------|
| dnsmasq | [dnsmasq-china.conf](https://raw.githubusercontent.com/wuchang1123/cn-dns-conf/main/out/dnsmasq-china.conf) |
| SmartDNS | [smartdns-china.conf](https://raw.githubusercontent.com/wuchang1123/cn-dns-conf/main/out/smartdns-china.conf) |
| 纯域名列表 | [china-domains.list](https://raw.githubusercontent.com/wuchang1123/cn-dns-conf/main/out/china-domains.list) |
| AdGuard Home | [adguard-upstream-china.txt](https://raw.githubusercontent.com/wuchang1123/cn-dns-conf/main/out/adguard-upstream-china.txt) |

直链模板（自行替换 `OWNER`、`REPO`、分支名）：

```text
https://raw.githubusercontent.com/OWNER/REPO/main/out/<文件名>
```

### dnsmasq 说明

- 与上游列表语义一致，仅去掉注释并按合并规则去重；使用 `conf-file` 引入即可。
- dnsmasq 的 `--server` 支持「多段域名 + 末尾上游」写法，与 `--address` 类似：`server=/a.com/b.com/1.2.3.4`。脚本在**连续且相同上游 IP** 的记录上按 `AG_BATCH`（默认 8）合并为一行。

### SmartDNS 说明

- 默认模式用官方 [域名集合（domain-set）](https://pymumu.github.io/smartdns/config/domain-rule/)：`domain-set` 指向列表文件，`nameserver /domain-set:集合名/上游组名` 把「中国域名」指到对应 `server … -g 组名`。
- **`china-domains.list`** 始终为全量域名表，与上游无关。仅一套上游时，`domain-set -file` 即该文件。多套上游时，会额外生成 **`smartdns-domains_<组名>.list`**（组名中的非安全字符会替换为 `_`），仅用于 SmartDNS 分区，**不再**使用 `china-domains-1.list` 这类命名。
- **上游 IP 与组名**仍在 `server` / `nameserver` 的 **GROUP** 部分（例如 `g_114_114_114_114`）。

### AdGuard Home 说明

- 将生成文件内容粘贴到「DNS 上游服务器」，或配置为 `upstream_dns_file`（路径以你部署为准）。
- 多域名同行语法为官方支持的 `[/a/b/]1.1.1.1` 形式；仅当连续记录为**同一上游 IP** 时才会合并到一行。

## 示例

```bash
# 使用本地已下载的列表，统一走阿里 DNS，SmartDNS 组名为 alidns
./convert-dnsmasq-china.sh --no-download 223.5.5.5 alidns

# AdGuard 每行 12 个域名
AG_BATCH=12 ./convert-dnsmasq-china.sh --no-download

# SmartDNS 改为逐域名 nameserver（超大单文件）
SMARTDNS_DOMAINSET=no ./convert-dnsmasq-china.sh --no-download
```

## 克隆与生成

- `upstream/` 仍由 `.gitignore` 忽略（体积大，随脚本下载即可）。
- `out/` 已纳入 Git，克隆后可直接使用 `out/` 内文件。
- 需要与上游同步时在本机执行：

```bash
./convert-dnsmasq-china.sh
```

## 发布到 GitHub

1. 在 GitHub 新建空仓库（不要勾选添加 README，避免首次推送冲突）。
2. 在项目根目录执行：

```bash
git init
git add convert-dnsmasq-china.sh README.md .gitignore out/
git commit -m "Initial commit: dnsmasq-china-list converter"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

将 `<你的用户名>`、`<仓库名>` 换成实际值。若使用 SSH，把 `origin` URL 改为 `git@github.com:用户名/仓库名.git`。

## 自动更新（GitHub Actions）

仓库含 [`.github/workflows/daily-update.yml`](.github/workflows/daily-update.yml)：

- **定时**：每天 **`Asia/Shanghai` 0:00**（`cron: 0 0 * * *` + `timezone: Asia/Shanghai`）拉取上游并执行 `convert-dnsmasq-china.sh`，若有差异则提交并推送 **`out/`**。
- **手动**：在 GitHub 仓库 **Actions** 页选择 **Daily refresh out/** → **Run workflow**。

首次使用请在仓库 **Settings → Actions → General → Workflow permissions** 中勾选 **Read and write permissions**（否则无法 `git push`）。

## 许可

脚本与生成配置的使用请同时遵守上游项目 [dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list) 的许可与声明。
