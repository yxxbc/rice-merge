# VM 走查：从 live ISO 到 niri 桌面

这份文档只讲**你要做什么、会看到什么**。真正的逻辑在 `live/` 和 `vm/live-autoinstall.sh`。

## 0. 宿主机准备

```bash
brew install qemu
# Arch ISO 放到 ~/Downloads，或下载：
# https://archlinux.org/download/
ls -lh ~/Downloads/archlinux-*.iso
```

磁盘镜像 `vm/arch-test.qcow2` 首次会自动创建（40G，稀疏文件）。
当前机器是 Apple Silicon，x86_64 完全走 TCG 模拟：能跑，但慢。

## 1. 启动 VM

```bash
bash vm/run.sh ~/Downloads/archlinux-x86_64.iso
```

会出现一个 QEMU 窗口。`vm/run.sh` 做了这些事：

- UEFI（OVMF）+ 40G virtio 磁盘 `/dev/vda`
- 把仓库目录通过 9p 共享给 guest，挂载标签为 `repo`
- 启动顺序 `disk,cdrom`：空盘时进 ISO，装完后重启自动从硬盘引导
- SSH 转发 `localhost:2222 -> 22`，QMP socket 在 `vm/qmp.sock`

## 2. live ISO 里（唯一的交互）

1. 等 GRUB/archiso 菜单出现，直接 **Enter**。
2. 等到 `root@archiso ~ #` 提示符（首次启动约 1–5 分钟，TCG 下更久）。
3. 字太小看不清时，先放大控制台字体：

```bash
setfont -d                    # 立刻放大一倍
ls /usr/share/kbd/consolefonts/ | grep -i '^ter' | head
setfont ter-132n              # 16x32，最清楚；没有就先 pacman -Sy terminus-font
```

QEMU 窗口也可以 `View → Zoom to Fit`（新版 `vm/run.sh` 已默认开 `zoom-to-fit`，分辨率 1024x768）。
4. 输入三条命令：

```bash
mkdir -p /repo
mount -t 9p -o trans=virtio,version=9p2000.L repo /repo
bash /repo/vm/live-autoinstall.sh full
```

- `full`：真的装包 + AUR，最后进 niri 桌面。
- `smoke`：只铺 dotfiles + 跑 04n，不装包，**没有桌面**；用来快速验证合并逻辑。

### 不想手打命令：两个办法

**A. 宿主机剪贴板直接打进 guest**（QMP send-key，只支持 ASCII）：

```bash
# 在 macOS 上复制命令，然后在仓库目录：
bash vm/paste.sh                 # 粘贴 + 回车
bash vm/paste.sh --no-enter      # 只粘贴
bash vm/paste.sh --text "setfont -d"
```

**B. 在线命令**（不需要 9p；仓库已推到 GitHub）：

```bash
curl -fsSL https://raw.githubusercontent.com/yxxbc/rice-merge/main/live/remote-install.sh \
  | bash -s -- full
```

它会 clone 到 `/tmp/rice-merge` 再调用同一个 `live-autoinstall.sh`。
真机上也可以用这条命令。

**C. 起 SSH**（能看中文日志，复制粘贴最自然）：

```bash
bash /repo/live/enable-ssh.sh
# 宿主机：
ssh -p 2222 root@localhost
```

脚本会自动：

1. 找到非 live 介质的整盘（VM 里是 `/dev/vda`）；
2. 写 `/tmp/rice-auto.env`（`ARCH` 用户密码 `arch`，`GRUB_REMOVABLE=1`）；
3. 显示配置并倒计时 5 秒（错了就 Ctrl+C）；
4. 用 `--yes` 跑 `live/install.sh`，中途**不再需要输入**。

如果 9p 挂载失败：

```bash
modprobe 9pnet_virtio
mount -t 9p -o trans=virtio,version=9p2000.L repo /repo
```

如果自动选盘不对：

```bash
lsblk -d -e 7,11 -o NAME,SIZE,MODEL
DISK=/dev/vda bash /repo/vm/live-autoinstall.sh full
```

## 3. 安装过程（会看到什么）

阶段和日志前缀：

| 阶段 | 你会看到 | 大致耗时（TCG / 原生 x86） |
|---|---|---|
| `10 partition` | `sgdisk`/`mkfs`/`mount` | 1–3 分钟 / 10 秒 |
| `20 bootstrap` | `pacstrap` 下载基础包 | 15–40 分钟 / 3–8 分钟 |
| `30 chroot` | locale、用户、GRUB、zram | 2–5 分钟 / 30 秒 |
| `40 deploy` | 拷仓库、clone Low-Spec | 1–3 分钟 / 20 秒 |
| `50 modules` | 00~05 + 04j + 04n | 1–4 小时 / 15–40 分钟 |

`50 modules` 里会跑 AUR 构建（`paru`），是主要耗时来源；中文进度在 live 控制台上会显示为方块，
日志在 `/tmp/rice-live.log`，装完会拷到 `~/Documents/rice-live.log`。

**想在看中文**：在 live 里另开一个终端（或安装前）执行 `bash /repo/live/enable-ssh.sh`，
起 sshd 并设置 root 密码，然后从宿主机：

```bash
ssh -p 2222 root@localhost
# 在 SSH 里重新跑：
bash /repo/vm/live-autoinstall.sh full
```

SSH 终端是 UTF-8，中文正常。

## 4. 重启后：ly 登录

安装完成后会自动重启。`vm/run.sh` 的启动顺序是 disk 优先，所以会从新系统引导。

- 看到 `ly` 登录界面：用户名 `arch`，密码 `arch`（在 `/tmp/rice-auto.env` 里）。
- ly 如果列出会话，选 **niri**；默认会话就是 niri。
- 如果登录后掉进 TTY shell，执行：

```bash
niri-session
```

## 5. 第一次进桌面

正常应该看到：壁纸、waybar、无报错。

常用键位（来自 shorin 的 binds）：

| 键 | 作用 |
|---|---|
| `Mod+Return` | 终端 foot |
| `Mod+Z` | fuzzel 启动器 |
| `Mod+Y` | 壁纸选择 |
| `Mod+Ctrl+Y` | waybar 布局切换 |
| `Mod+Shift+E` | 退出 niri |
| `Mod+F1` | 开关 fcitx5 |
| `Ctrl+Space` | 切换中英文 |
| `Mod+Alt+O` | opencode（AI 助手） |
| `Mod+Shift+/` | 键位总览（如果当前 binds 提供） |

在终端里做首次检查：

```bash
# 中文
fc-list :lang=zh | head
# 输入法
systemctl --user status fcitx5 --no-pager
# 合成器
niri validate -c ~/.config/niri/config.kdl
# 网络 / 音频
nmcli device status
wpctl status | head -20
# 皮肤层落地情况
ls ~/.config/foot/rice-theme.ini ~/.config/mako/config ~/.config/fuzzel/fuzzel.ini
cat ~/.local/state/rice-merge/manifest.tsv | head
```

桌面没起来时，`Ctrl+Alt+F2` 切到 TTY，登录后看：

```bash
journalctl --user -b --no-pager | tail -50
systemctl status ly@tty1 --no-pager
```

## 6. 回滚

```bash
# 只撤 rice 皮肤层
sudo bash /opt/setup/rice/scripts/04n-lowspec-niri.sh undo

# 系统级回滚（shorin 自带）
sudo shorin-undochange
```

## 7. 常见问题

| 现象 | 处理 |
|---|---|
| 9p 挂载失败 | `modprobe 9pnet_virtio` 后重试；或重启 VM |
| 重启又进 ISO | 用 `VM_NO_ISO=1 bash vm/run.sh ...`（不挂 ISO，强制走硬盘） |
| ly 登录报 authentication error | 用 HMP/手动输入；确认密码 `arch`。QMP `input-send-event` 对 ly 不稳，`sendkey` 可用 |
| 登录后黑屏 / niri 停在 `niri_config: loaded config` | `systemctl status seatd`；`id arch` 应含 `seat` 组；`journalctl -u seatd -b`。新版 04n 会自动 enable seatd |
| `niri-session` 报 dinit 相关错误 | 04n 已把 `/usr/share/wayland-sessions/niri.desktop` 改成 `Exec=niri --session` |
| waybar 不出现 | `pkill waybar; waybar &`，看 stderr |
| 中文变方块 | `fc-list :lang=zh`；缺字体则 `sudo pacman -S noto-fonts-cjk` |
| 没有壁纸/不取色 | `matugen` 是否安装；`rice-wallpaper random` 手动跑 |
| AUR 构建失败 | 看 `/tmp/rice-live.log` 与 `~/Documents/log-shorin-arch-setup.txt` |

### VM 图形限制（已定位）

niri 官方 wiki 明确写了：**在 VM 里跑 niri 必须开启 3D 加速**。
本机 Homebrew QEMU **没有编译 OpenGL 支持**（`OpenGL support was not enabled in this build`），
virtio-gpu 只能提供 2D；niri 的 TTY 后端会拒绝软件 EGL：

```
failed to initialize renderer ... software EGL renderers are skipped
error adding primary node device ... no allocator available for device
```

所以这个 QEMU 里 niri 拿不到 output，不是安装问题。

无 3D 时的预览方案（已在本 VM 验证）：用 **headless sway（pixman 软件渲染）**托一个
**nested niri**，再用 grim 截图或 wayvnc 看。

```bash
# guest 内（SSH 或 TTY），用户 arch
systemd-run --user --unit=sway-headless \
  --setenv=XDG_RUNTIME_DIR=/run/user/1000 \
  --setenv=WLR_BACKENDS=headless --setenv=WLR_RENDERER=pixman \
  --setenv=WLR_LIBINPUT_NO_DEVICES=1 \
  /usr/bin/sway -c /dev/null

systemd-run --user --unit=niri-nested \
  --setenv=XDG_RUNTIME_DIR=/run/user/1000 --setenv=WAYLAND_DISPLAY=wayland-2 \
  /usr/bin/niri

# 截图（HEADLESS-1 是 sway 的虚拟输出）
XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-2 \
  grim -o HEADLESS-1 ~/desktop.png
```

实测截图：`vm/nested2.png`（niri 窗口内 waybar 正常：时钟/workspace/网络/蓝牙/电源）。

真正要 niri 直接上屏，选一个：
- 真机 Arch；
- Linux 主机 KVM + virtio-gpu-gl / virgl；
- macOS 上用支持 3D 加速的虚拟化（UTM/Parallels 的 arm64 来宾 + 对应 Arch ARM）。


- 本机是 Apple Silicon，x86_64 走 TCG；niri 在 `virtio-gpu`/TCG 下可能一直停在
  `niri_config: loaded config`，而 `seatd` 已打开 seat。这更像 QEMU/TCG 的图形后端问题，
  不代表真实硬件。
- QEMU 的 Cocoa 窗口在 niri 接手 DRM 后可能显示 `Display output is not active`；
  用 `VM_VNC=127.0.0.1:0` 启动，然后 macOS「屏幕共享」连 `vnc://localhost:5900` 查看。
- 最终桌面验证建议在真实 Arch 硬件（或带 GPU 加速的 UTM/virtio-gpu）上做。
