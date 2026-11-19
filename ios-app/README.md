# ZeyuVPN：自己的 iPhone VPN App

一个只给自己用的 iPhone App：导入服务器的 `vless://` 链接，点一下就连上。国内网站直连，其他走新加坡服务器。

> **当前状态：代码已备好，还没编译测试过。** 第一次在 Xcode 里构建时，可能要小改几处（把报错发给 Claude 就行）。

```
┌──────────── iPhone ────────────┐
│  ZeyuVPN App（界面、开关）       │
│        │ 系统 VPN 接口           │
│  Tunnel 扩展 ── Xray 内核 ──────┼──→ 新加坡服务器 ──→ Claude / Google …
│        └─ 国内网站、国内 IP ─────┼──→ 直连
└────────────────────────────────┘
```

---

## 要准备什么

| 项目 | 说明 | 费用 |
|---|---|---|
| Mac | 你的 M4 Mac 就行 | — |
| Xcode | Mac App Store 下载，约 15–20GB 空间 | 免费 |
| Go | <https://go.dev/dl/>，编译 Xray 内核用 | 免费 |
| Apple 开发者账号（个人） | **必须付费**：免费账号开不了 VPN 功能 | 约 A$149 / 年 |
| iPhone + 数据线 | 第一次安装要连 Mac | — |

不用注册公司，也不用上架 App Store。

---

## 操作步骤

### 1. 加入 Apple 开发者计划

1. 打开 <https://developer.apple.com/programs/enroll/>，用你的 Apple ID 登录。
2. 选 **Individual / Sole Proprietor（个人）**，付款。审核一般几小时到两天。
3. 通过后打开 <https://developer.apple.com/account> → **Membership details**，记下 **Team ID**（10 位字母数字）。

### 2. 安装 Xcode 和 Go

1. Mac App Store 搜 **Xcode** 安装，装完**打开一次**，同意协议，等它装完组件（iOS 平台会提示下载，点下载）。
2. 打开「终端」，运行：
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
3. 去 <https://go.dev/dl/> 下载 macOS 安装包（Apple 芯片选 **arm64**），双击安装。装完**重新打开终端**。

### 3. 生成工程

在终端运行（把 `你的TeamID` 换成第 1 步记下的）：

```bash
git clone https://github.com/Zeyu-0210/vps-setup.git
cd vps-setup/ios-app
TEAM_ID=你的TeamID bash setup.sh
```

脚本会自动：编译 Xray 内核（第一次 5–15 分钟）→ 下载国内分流数据 → 生成 `ZeyuVPN.xcodeproj` 并用 Xcode 打开。

### 4. 装到 iPhone 上

1. Xcode 菜单 **Settings → Accounts**，点 **+** 登录你的 Apple ID（开发者账号那个）。
2. 左边点最上面的 **ZeyuVPN** 工程，分别选中 **ZeyuVPN** 和 **Tunnel** 两个 target，在 **Signing & Capabilities** 里确认 Team 是你自己。
3. 用数据线连上 iPhone，手机上点「信任这台电脑」。
4. Xcode 顶部的设备列表里选你的 iPhone，点 **▶**。
5. 第一次会提示打开**开发者模式**：iPhone **设置 → 隐私与安全性 → 开发者模式**，打开后手机会重启。重启后再点一次 ▶。

### 5. 开始用

1. 打开 ZeyuVPN，点「导入」，粘贴服务器的 `vless://` 链接（服务器上 `cat /root/vless-link.txt` 能看到），点保存。
2. 系统弹出「ZeyuVPN 想添加 VPN 配置」，点**允许**，输入锁屏密码。
3. 点中间的大按钮，变蓝就是连上了。下面的「Google 连通测试」显示毫秒数就说明能用。

### 6. 每年续一次

开发者账号到期前续费，然后连上 Mac 再点一次 ▶ 重新安装（证书有效期一年，过期 App 就打不开）。
**手机里一直留着 Shadowrocket 当备用**，万一 App 过期或者出问题，还有退路。

---

## 换服务器

服务器被封、重新部署后，打开 App → 节点卡片上的「更换」→ 粘贴新链接 → 保存 → 重新连接。不用重新编译。

## 不用数据线安装（可选）

Xcode 菜单 **Product → Archive** → **Distribute App** → **TestFlight Internal Only**，上传后在手机的 TestFlight App 里安装。
只给自己用不需要审核，但每个版本 90 天后过期，要重新上传。

---

## 常见问题

| 现象 | 处理 |
|---|---|
| `setup.sh` 说没找到 Xcode | 按第 2 步装 Xcode，并运行那条 `xcode-select` 命令 |
| 编译内核时报 Go 版本太旧 | 去 go.dev 装最新版 Go |
| Xcode 报 Bundle ID 被占用 | 换一个再生成：`BUNDLE_ID=com.你的名字.vpn TEAM_ID=… bash setup.sh` |
| Xcode 签名报错 / 没有 Network Extension 权限 | 确认用的是**付费**开发者账号，两个 target 都选了自己的 Team |
| 点了连接马上断开 | App 里会显示原因；也可以在 Mac 的「控制台」App 里选中 iPhone，搜索 `Tunnel` 看日志 |
| 连上一会儿就断，或者很卡 | 可能是 VPN 扩展内存超了（iOS 限制约 50MB）。把 `Tunnel/XrayConfig.swift` 里 DNS 的 `geosite:cn` 那一段删掉再试 |
| 国内某些网站打不开 | 服务器设置了屏蔽国内网站。这类网站如果没被识别成国内，就会走代理被挡；先断开 VPN 访问 |

---

## 文件说明

| 文件 | 作用 |
|---|---|
| `App/ContentView.swift` | 主界面：大开关、节点卡片、连通测试 |
| `App/ImportView.swift` | 粘贴链接的页面 |
| `App/TunnelManager.swift` | 保存 VPN 配置、连接 / 断开、显示状态 |
| `Tunnel/PacketTunnelProvider.swift` | VPN 扩展入口：设置网络、启动 Xray |
| `Tunnel/XrayConfig.swift` | 生成 Xray 配置（分流规则在这里改） |
| `Tunnel/XrayCore.swift` | 调用 Xray 内核 |
| `Shared/VLESSLink.swift` | 解析 `vless://` 链接 |
| `project.yml` | 工程描述，`setup.sh` 用它生成 Xcode 工程 |
| `setup.sh` | 一键准备：编译内核、下载数据、生成工程 |

用到的开源项目：[Xray-core](https://github.com/XTLS/Xray-core) 和 [libXray](https://github.com/XTLS/libXray)（MPL-2.0），分流数据来自 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) 和 [Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip)。

## 注意

- 这个 App 只装在自己手机上用，**不要把编译好的 App 分发给别人**，更不要拿来卖。
- 仓库里没有任何密钥，节点链接只存在手机的 VPN 配置里。**不要把 `vless://` 链接提交到仓库。**
