# rice-merge

[shorin-arch-setup](https://github.com/SHORiN-KiWATA/shorin-arch-setup) 的 fork：
中文底座（系统管线 / fcitx5 + rime / niri 配置）+ [Low-Spec-Niri-Dotfiles](https://github.com/okyashgajjar/Low-Spec-Niri-Dotfiles)
的整套皮肤层（waybar 15 套布局 / foot / fuzzel / mako / gtk / matugen 取色 / `rice-*` 命令），
再加一个可以在 Arch live ISO 里直接跑的安装器。

上游脚本已经 vendor 进本仓库并做了本地修改，不再需要 `make deploy` 到另一份 shorin 副本。
来源、改动与同步方式见 [UPSTREAM.md](UPSTREAM.md)。

## 组成

| 层 | 来源 | 提供什么 |
|---|---|---|
| 底座 | shorin（AGPL-3.0，已 fork 进本仓库） | 00~03 系统管线、locales/中文输入、niri 主配置、xwayland-satellite |
| 视觉层 | Low-Spec（**无 LICENSE**，运行时 clone） | waybar、foot、fuzzel、mako、gtk、matugen 模板、`rice-*` 命令、壁纸池 |
| 胶水 | 本仓库新增 | `04n` 合并模块、契约检查、undo、live 安装器、QEMU 验证 |

## 目录

```
.
├── install.sh                  # 上游主安装器（+ --unattended 等参数）
├── scripts/                    # 上游全部脚本 + 本仓库的 04n
│   ├── 04j-minimal-niri.sh     # shorin 的 Minimal Niri
│   ├── 04n-lowspec-niri.sh     # 合并视觉层（apply/check/plan/undo）
│   └── lib/common.sh           # 04n 的回退 helper + manifest/undo
├── minimal-niri-dotfiles/      # 底座 dotfiles
├── resources/rice-merge/       # 键位片段、fcitx5 environment.d
├── tools/niri_patch.py         # 唯一的文本变换入口（幂等、有测试）
├── live/                       # Arch live ISO 安装器
│   ├── install.sh
│   ├── install.env.example
│   ├── enable-ssh.sh           # live 里起 sshd，用普通终端看 UTF-8 输出
│   ├── remote-install.sh       # 一条 curl 命令完成 clone + 安装
│   └── steps/                  # 10 分区 / 20 pacstrap / 30 chroot / 40 部署 / 50 模块
├── vm/
│   ├── run.sh                  # QEMU + 9p 共享本仓库
│   ├── live-autoinstall.sh     # live 里自动选盘 + 无人值守安装
│   ├── paste.sh / paste.py     # 把宿主机剪贴板打进 guest（QMP send-key）
│   └── WALKTHROUGH.md          # 从 ISO 到 niri 桌面的交互步骤
├── tests/                      # 单元测试 + 端到端合并测试
├── Makefile                    # test / lint / e2e / check / live-dry-run / vm
└── UPSTREAM.md                 # 来源、改动、同步流程、许可说明
```

## 快速开始

### A. 已经能启动的 Arch

`install.sh` 沿用上游模型：它是“装完系统之后”的编排器，假设已经有可启动的 Arch
（archinstall 的最小系统即可）。

```bash
git clone <本仓库> ~/rice-merge
cd ~/rice-merge

sudo bash install.sh --unattended --desktop minimalniri
# 可选：--modules 01b-shorin-arch.sh,03b-gpu-driver.sh
# 可选：--file-manager gds（GDS Files，实验；见下文）
# 可选：--skip-reflector / --no-reboot
```

它会依次跑：`00-btrfs-init` → `01a-base` → `02a-user` → `02b-musthave` →
`03c-snapshot` → `04j-minimal-niri` → **`04n-lowspec-niri`** → `05-verify`。
`04n` 需要 `low-spec-dotfiles/`，`install.sh` 会在模块循环前自动 clone。

### B. 从 Arch live ISO 全自动装

**真机前置条件**：UEFI 启动、有线网络（Wi-Fi 先在 live 里跑 `iwctl`）、**目标盘会被整盘清空**。
安装器只接受整盘设备（`/dev/nvme0n1`、`/dev/sda`），并且会拒绝“live U 盘自己”。

```bash
# 1. 先看盘
lsblk -d -e 7,11 -o NAME,SIZE,MODEL
# 或
bash live/install.sh --list-disks

# 2. 写配置
cp live/install.env.example live/install.env
chmod 600 live/install.env
$EDITOR live/install.env      # DISK=整盘、USER_PASSWORD、GRUB_REMOVABLE=0、PROFILE=full

# 3. 先 dry-run 看命令，再实跑
sudo bash live/install.sh --config live/install.env --dry-run
sudo bash live/install.sh --config live/install.env
```

- `ALLOW_WIPE=yes` 是第二道保险；实跑还会要求你输入磁盘路径确认（`--yes` 可跳过）。
- 双系统/多盘：本安装器是“整盘安装”，不会保留盘上已有系统；`GRUB_REMOVABLE` 在真机保持 `0`。
- 没有 `DISK` 且 stdin 是 TTY 时，会列出磁盘并提示输入；否则直接报错。
- `--from deploy` 可以在分区/引导完成后跳过前面步骤。
- 文件管理器：`install.env` 里 `FILE_MANAGER=thunar|gds|gds-portal`，留空则在 TTY 上询问
  （`--yes` 非交互时默认 thunar）。
- GPU：默认装 `mesa`（Intel/AMD/软件渲染）。NVIDIA 需要在首次启动后装
  `nvidia-open`/`nvidia-utils` 并配置 modeset，或跑可选的 `03b-gpu-driver.sh`。
- 仓库来源：真机先把本仓库 `git clone` 到 live（或挂 U 盘），再让 `--config` 指向里面的 `install.env`。
- 不支持：Secure Boot 签名、LUKS 全盘加密、保留盘上已有系统。

`PROFILE`：

| 值 | 内容 | 用途 |
|---|---|---|
| `full` | 基础系统 + 04j + 04n + 05 verify（含 AUR 包） | 真机 |
| `smoke` | 基础系统 + dotfiles + 04n（`RICE_SKIP_PACKAGES=1`） | VM 里几分钟验证合并逻辑 |
| `base` | 只装基础系统 | 分步调试 |

安装器做的事：GPT（1G ESP + btrfs `@`/`@home`）→ `pacstrap` → chroot 里
时区/locale/用户/GRUB/zram → 把本仓库拷到 `/opt/setup/rice` → 在 chroot 里跑模块。

**中文显示**：Arch live 的控制台没有 CJK 字形，所以安装器本身只说英文（中文在这里一定会变方块）；
shorin 模块自己的中文进度在控制台上也可能显示为方块，但日志是 UTF-8。两种看中文日志的方式：

1. 装好后看 `~/Documents/rice-live.log`（UTF-8）；
2. 想在安装过程中看：`bash live/enable-ssh.sh` 在 live 里起 sshd，然后从普通终端
   `ssh root@<live-ip>` 跑安装器（VM 用 `-p 2222`），中文输出就正常了。

### C. 本地 QEMU 验证

```bash
brew install qemu
bash vm/run.sh ~/Downloads/archlinux-x86_64.iso
```

进入 live ISO 后，三条命令就能全自动装完（交互细节见 [vm/WALKTHROUGH.md](vm/WALKTHROUGH.md)）：

```bash
mkdir -p /repo
mount -t 9p -o trans=virtio,version=9p2000.L repo /repo
bash /repo/vm/live-autoinstall.sh full   # 真装到 niri 桌面；smoke = 只验证合并、无桌面
```

宿主机复制了命令后，可以直接打进 guest 的控制台（QMP send-key，ASCII）：

```bash
bash vm/paste.sh                 # 剪贴板内容 + 回车
bash vm/paste.sh --no-enter      # 只粘贴不回车
bash vm/paste.sh --text "setfont -d"
```

**在线命令**（不需要 9p，live 和真机都适用）：

```bash
curl -fsSL https://raw.githubusercontent.com/yxxbc/rice-merge/main/live/remote-install.sh \
  | bash -s -- full
```

它会 clone 仓库到 `/tmp/rice-merge`，然后走同一套 `live-autoinstall.sh`。
真机同样会先列盘/倒计时，Ctrl+C 可中止。

`live-autoinstall.sh` 会自动识别 `/dev/vda`、写临时配置、`--yes` 跑完整流程。
磁盘是 `vm/arch-test.qcow2`（40G，首次自动创建），启动顺序 disk→cdrom，装完自动从硬盘引导，
SSH 转发 `localhost:2222`。Apple Silicon 上 x86_64 走 TCG，`full` 可能数小时；
想先看中文输出，可在 live 里 `bash /repo/live/enable-ssh.sh` 后从宿主机 SSH 进去跑。

## 04n：合并、检查、回滚

```bash
sudo bash scripts/04n-lowspec-niri.sh apply    # 默认
bash scripts/04n-lowspec-niri.sh check        # 只做契约预检，不写盘
bash scripts/04n-lowspec-niri.sh plan         # 预检 + 打印目标
sudo bash scripts/04n-lowspec-niri.sh undo    # 按 manifest 回滚
```

- **契约预检**（写盘前）：`config.kdl` 必须有 `include "layout.kdl"`（或 `binds.kdl`）、
  `binds.kdl` 最后一个非空行必须是 `}`、Low-Spec/overlay 所需文件齐全。
  失败会直接退出，不会留下半合并状态。
- **备份**：被覆盖的文件保留 `<file>.rice.bak`；由本工具新建的文件没有备份。
- **manifest**：`~/.local/state/rice-merge/manifest.tsv`，`undo` 逆序恢复/删除。
  注意 `undo` 会用 `.rice.bak` 覆盖安装后的改动；只想撤销部分文件时，先看一眼 manifest。
- **校验**：合并后断言 include 只出现一次、binds 花括号平衡、waybar 没有 `/home/yg`；
  同时检查 foot/fuzzel/mako/gtk/waybar 与 matugen 模板都已落地，
  并用 `fc-list :lang=zh` 确认中文字形可用；
  装了 `niri` 时再跑一次 `niri validate`。

### 视觉层边界

`04n` 会把 Low-Spec 的 `config/` **整棵**铺到 `~/.config`，只跳过一个文件：
`niri/config.kdl`。原因是它属于 compositor 配置（硬编码 `/home/yg`、不带 shorin 的
中文输入/输出/多屏设置）；皮肤对 niri 的视觉影响通过 `niri/rice-colors.kdl` + rice 键位生效。
其余 foot / fuzzel / mako / gtk-3.0 / gtk-4.0 / environment.d / waybar / matugen 全部以皮肤为准，
matugen 也不再裁掉 foot/mako/fuzzel 模板——换壁纸时这些应用一起跟色。

常用环境变量：`RICE_SKIP_PACKAGES=1`（只合并不装包）、`RICE_NO_DM=1`（不动显示管理器）、
`RICE_DRY_RUN=1`、`RICE_LENIENT=1`（patch 失败降级为告警）。

## 文件管理器：Thunar 或 GDS Files

Minimal Niri 安装时可以选文件管理器（交互安装会弹菜单；`--unattended` 默认 Thunar）：

| 选项 | 效果 |
|---|---|
| `thunar`（默认） | Low-Spec 原样：Thunar + tumbler，缺失时回退 Nautilus |
| `gds` | 安装 pinned 的 `gds-files`，`inode/directory` 与 `Mod+E` 指向 GDS Files |
| `gds-portal` | 在 `gds` 基础上装 `xdg-desktop-portal-gds`，并让 FileChooser 走 GDS |

```bash
sudo bash install.sh --unattended --desktop minimalniri --file-manager gds
sudo bash install.sh --file-manager gds-portal      # 或 --gds-portal
```

GDS 细节：

- 只发布 **x86_64** 预编译包，没有 Arch 仓库；04n 从 GitHub Releases 下载后校验 sha256
  再 `pacman -U`（默认 pin `0.0.5`）。离线安装用
  `RICE_GDS_PKG=/path/gds-files-*.pkg.tar.zst`、`RICE_GDS_PORTAL_PKG=...`。
- 会改：`~/.config/mimeapps.list` 的 `inode/directory`、niri `Mod+E`、
  （可选）`~/.config/xdg-desktop-portal/niri-portals.conf` 的 `FileChooser`。
  这些改动都进 manifest，`04n undo` 会恢复；本工具装的 GDS 包也会被卸掉。
- **不跟 matugen 取色**：GDS 是 GPUI 应用，只跟随 Noctalia/DMS/KDE/GNOME 的系统配色，
  niri + matugen 不在支持列表里，视觉层会多一个不随壁纸变色的窗口。
- GDS 仍是早期版本：归档、卷管理、gvfs-mtp 等功能少于 Thunar；
  04j 装的 Thunar / Nautilus 会保留作回退（04n 只是不把它们设为默认）。
- 若想临时切回 Thunar：重跑安装器选 Thunar，或先把 `mimeapps.list` / `Mod+E` 改回；
  `gds-files` 包可以手动 `pacman -R gds-files`。

## 应用裁剪

后续要删应用时，改这几处（都在本仓库内）：

| 文件 | 内容 |
|---|---|
| `scripts/04j-minimal-niri.sh` | `NIRI_PKGS` / `TERMINAL_PKGS` / `FM_PKGS1,2` / `TOOLS_PKGS` |
| `scripts/04n-lowspec-niri.sh` | `pac_pkgs` / `aur_pkgs`（视觉层依赖；`thunar` 只在默认文件管理器下安装，04j 仍装一份作回退） |
| `scripts/02b-musthave.sh` | 音频、蓝牙、电源、常用工具 |
| `scripts/99-apps.sh` + `common-applist.txt` | 可选 Common Apps 清单 |
| `live/steps/20-bootstrap.sh` | 基础系统包（目前只有 base/base-devel/linux/...） |

注意：`05-verify-desktop.sh` 会用各模块写进 `/tmp/shorin_install_verify.list` 的清单对账，
删包时同一文件里的 `echo ... >> "$VERIFY_LIST"` 也要一起删，否则最后验证会失败。

当前已按需求移除：`linuxqq` / `linuxqq-wayland-fix`；`common-applist.txt` 里的
`visual-studio-code-bin` 已换成官方仓库的 `zed`。

## 上游维护

本 fork 固定在上游 `e442234`（2026-11-03）。同步流程、哪些文件是原样引入、哪些改了，
都记在 [UPSTREAM.md](UPSTREAM.md)。核心原则：

- **契约面**：`scripts/00-utils.sh`、`scripts/04j-minimal-niri.sh`、`minimal-niri-dotfiles/`
  是 04n 的依赖；它们变了，`make e2e` 会直接失败，而不是装到一半才炸。
- **升级是主动的**：`git fetch upstream` 后按文件 review，不自动 merge `install.sh`。
- **回滚**：`04n undo` 只撤本工具的改动；系统级回滚仍用 shorin 的
  `shorin-undochange` / snapper 快照。

## 开发

```bash
make test          # 单元测试（niri_patch）
make lint          # bash -n + py_compile + shellcheck -S error
make e2e           # 真实树 + 假 HOME：合并 / 幂等 / undo / 契约检查
make check         # lint + test + e2e（CI）
make live-dry-run  # 打印 live 安装器将执行的命令
```

CI 在 `.github/workflows/ci.yml`，push 即跑 `make check`。

## 许可

- 本仓库（含 fork 的上游脚本）以 **AGPL-3.0-or-later** 发布，见 `LICENSE`。
  修改过的上游文件已在文件头标注来源与改动；再分发时请保留许可证与源码。
- Low-Spec-Niri-Dotfiles **没有 LICENSE**（默认保留所有权利），因此不 vendor，
  只在安装时 clone。自己的机器上使用无碍，但不要再分发它的配置；
  若将来要打包，需要先取得作者许可。
- 使用 “shorin” 作为公开项目名/品牌前，建议先和上游作者打个招呼（不是代码许可要求）。
