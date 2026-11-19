# VPS 一键部署（Xray VLESS + Reality）

在一台全新的境外 Linux 服务器（Debian 12 / Ubuntu）上运行一条命令，几分钟内得到一条 `vless://` 链接，复制到 Shadowrocket 就能用。

脚本不含任何密钥：每次运行都会在服务器上生成全新的密钥和链接。

---

## 一键部署

登录服务器（root 身份）后运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Zeyu-0210/vps-setup/main/install.sh)
```

运行结束会打印一条 `vless://...` 链接，同时保存在服务器的 `/root/vless-link.txt`。

---

## 应急流程：节点被封 / 连不上了

> 适用场景：人在国内，Shadowrocket 突然连不上，Claude 也用不了。整个过程大约 10 分钟。

### 1. 先确认是不是 IP 被封

打开 <https://www.itdog.cn/tcping/>，输入 `服务器IP:443` 测试。
- 国内大部分地区都不通 → IP 被封了，继续下一步。
- 都是通的 → 不是被封，看最后的「排查」一节。

### 2. 在 Vultr 开一台新服务器

1. 打开 <https://my.vultr.com> 登录（国内一般能直接打开，慢的话多等一会）。
2. 点 **Deploy** → **Cloud Compute**。
3. 地区选 **Sydney** 或 **Melbourne**（或者东京、新加坡，国内连起来更快）。
4. 系统选 **Debian 12**，配置选最便宜的一档。
5. **SSH Keys 一栏勾选之前添加的 Mac 公钥**（很重要，否则下一步登录不了）。
6. 点 Deploy，等状态变成 **Running**，记下新的 IP。

### 3. 用 Mac 登录新服务器并部署

打开 Mac 的「终端」，运行（把 `新IP` 换成实际 IP）：

```bash
ssh root@新IP
```

第一次连接会问 `Are you sure you want to continue connecting`，输入 `yes` 回车。登录成功后运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Zeyu-0210/vps-setup/main/install.sh)
```

> 如果 ssh 提示 `REMOTE HOST IDENTIFICATION HAS CHANGED`，先运行 `ssh-keygen -R 新IP` 再重新 ssh。
>
> 如果 ssh 也连不上：在 Vultr 后台点进这台服务器，右上角打开 **View Console**（网页控制台），用 root 和后台显示的密码登录，再输入上面那条命令。

### 4. 换到新节点

1. 复制脚本最后打印的 `vless://...` 链接。
2. 打开 Shadowrocket，添加新节点，选中它，打开开关。
3. 终端运行 `curl -s ipinfo.io`，确认显示的是新 IP。

### 5. 删掉旧服务器

回 Vultr 后台，把旧的那台 **Destroy** 掉，否则会一直计费。

---

## 常用命令（在服务器上运行）

| 用途 | 命令 |
|---|---|
| 再次查看节点链接 | `cat /root/vless-link.txt` |
| 查看运行状态 | `systemctl status xray` |
| 查看最近日志 | `journalctl -u xray -n 50 --no-pager` |
| 重启服务 | `systemctl restart xray` |
| 重新生成密钥和链接 | 再运行一次一键部署命令 |

自定义端口或伪装网站（可选）：

```bash
PORT=8443 SNI=www.apple.com bash <(curl -fsSL https://raw.githubusercontent.com/Zeyu-0210/vps-setup/main/install.sh)
```

---

## 排查：IP 没被封但连不上

1. 服务器上运行 `systemctl status xray`，看是不是 `active (running)`。
2. Vultr 后台的 **Firewall**（防火墙组）里是否放行了 TCP 443。
3. Shadowrocket 里的节点是不是最新的链接（重新部署后旧链接会失效）。
4. 以上都没问题，直接重新运行一键部署命令，用新链接。

---

## 自己的 iPhone App（以后再做）

[`ios-app/`](./ios-app) 里是一个只给自己用的 iPhone VPN App 的代码和完整操作步骤：导入 `vless://` 链接，一键连接，国内网站直连。
需要 Xcode 和付费的 Apple 开发者账号（约 A$149/年），现在用 Shadowrocket 就够了。

---

## 注意

- **不要把 `vless://` 链接发到这个仓库、群聊或任何公开的地方**，拿到链接的人都能用你的服务器。
- **不要把 Mac 上的 `~/.ssh/id_ed25519`（私钥）发给任何人。**
- 节点只给自己用，用的人多了 IP 更容易被封。
