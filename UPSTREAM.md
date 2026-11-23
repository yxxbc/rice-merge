# 上游来源与改动记录

本仓库是 [SHORiN-KiWATA/shorin-arch-setup](https://github.com/SHORiN-KiWATA/shorin-arch-setup)
的 fork，在其“中文底座 + Minimal Niri”基础上合并 Low-Spec 视觉层，并补上 live ISO 安装器。

- 上游 commit：`e442234bd56cea67d18e2190563b2fda04b35e1c`（2026-11-03）
- 上游许可：AGPL-3.0-or-later（见 `LICENSE`、`THIRD_PARTY_LICENSES.md`）

## 原样引入的文件

| 路径 | 说明 |
|---|---|
| `install.sh` | 上游主安装器（有本地改动，见下） |
| `scripts/*.sh` | 上游全部脚本（仅 `00-utils.sh` / `04n` 有本地改动） |
| `minimal-niri-dotfiles/` | Minimal Niri 的配置 payload |
| `resources/Minimal-Niri使用方法.txt` | 04j 会拷到家目录 |
| `resources/shorin-arch/` | 01b 可选模块的 keyring |
| `common-applist.txt`、`exclude-dotfiles.txt` | 99-apps / 工具脚本读取的清单 |
| `undochange.sh`、`scripts/de-undochange.sh` | 00-btrfs-init 部署的回滚工具 |
| `LICENSE`、`THIRD_PARTY_LICENSES.md` | 许可证与第三方声明 |

## 刻意没有引入的部分

| 路径 | 原因 |
|---|---|
| `gnome-dotfiles/`、`kde-dotfiles/`、`minimal-labwc-dotfiles/`、`quickshell-dotfiles/`、`noctalia-dotfiles/` | 本 fork 只做 Minimal Niri；保留脚本但菜单不再提供这些桌面 |
| `resources/Wallpapers/`（15M）、`resources/windows-sim-fonts/`（48M）、`resources/firefox/`、`resources/MangoHud/` | 仅 04-niri / 99-apps 使用，体积大；需要时自行从上游取 |
| `grub-themes/`、`grub-themes` 相关脚本的 payload | 与桌面无关，按需自取 |
| `strap.sh` | 上游的下载引导器会拉取上游 main，与本 fork 的固定 commit 冲突 |
| Low-Spec-Niri-Dotfiles | **无 LICENSE（保留所有权利）**，只能运行时 clone，不能再分发 |

## 本地改动

### `scripts/00-utils.sh`
- 删除文件末尾的顶层 `check_root` 调用。原实现导致“source 即要求 root”，
  使 `04n check|plan` 和端到端测试无法以普通用户运行。各入口脚本仍自行检查 root。
- `detect_target_user` 优先采用调用方显式设置的 `TARGET_USER`（且家目录存在）。
  `02a-user.sh` 会先删掉 `/tmp/shorin_install_user` 缓存再重新探测，无人值守安装
  因此会卡在选用户提示；设置 `TARGET_USER` 后直接返回。

### `install.sh`
- 新增 `--unattended`、`--desktop`、`--modules`、`--skip-reflector`、`--no-reboot`、
  `--file-manager`、`--gds-portal`；Minimal Niri 交互安装会提示选择 Thunar / GDS Files。
- 桌面菜单收敛为 `Minimal Niri + rice-merge` / `No Desktop`；`--desktop` 只接受
  `minimalniri`、`none`（其它桌面的 dotfiles 未打包）。
- `minimalniri` 的模块列表追加 `04n-lowspec-niri.sh`。
- 模块循环前按需 `git clone` Low-Spec 到 `low-spec-dotfiles/`。
- 结束时可跳过自动重启（`--no-reboot`），供 live/chroot 调用。

### 其它本地改动
- `minimal-niri-dotfiles/.config/fontconfig/fonts.conf`：`monospace` 的 prefer 列表加入
  `Noto Sans Mono CJK SC` / `Noto Sans CJK SC`，避免终端类应用（foot/fuzzel/waybar）
  在皮肤字体缺字时显示方块。
- `scripts/04n-lowspec-niri.sh` 的包列表加入 `noto-fonts-cjk`、`noto-fonts`、
  `noto-fonts-emoji`、`ttf-jetbrains-mono-nerd`：即使跳过 `01a`（smoke/独立运行），
  皮肤层也自带中文字形和皮肤字体。

### `scripts/04n-lowspec-niri.sh`（本仓库新增）
- 自包含 helper：`scripts/lib/common.sh`，没有 `00-utils.sh` 也能跑。
- 写盘前做契约预检（config.kdl 锚点、binds.kdl 结尾、皮肤层文件齐全）。
- 视觉层全量对齐 Low-Spec：`config/` 整棵树铺到 `~/.config`，唯一例外是
  `niri/config.kdl`（compositor 配置归 shorin）；matugen 的 foot/mako/fuzzel 模板保留，
  换壁纸时这些应用一起取色。
- 所有文本变换失败默认 fatal（`RICE_LENIENT=1` 可降级为告警）。
- 登记 `~/.local/state/rice-merge/manifest.tsv`，支持 `undo` 回滚。
- 支持 `check` / `plan` / `apply` / `undo` 四个子命令。
- 可选文件管理器 `RICE_FILE_MANAGER=gds`：从 GitHub Releases 下载 pin 版本
  `gds-files`（sha256 校验）并 `pacman -U`；改 `mimeapps.list`、`Mod+E`，
  可选 `RICE_GDS_PORTAL=1` 装 `xdg-desktop-portal-gds` 并接管 FileChooser。
  改动进 manifest，`undo` 会恢复配置并卸掉本工具装的包。
  GDS 为 Apache-2.0、独立二进制，不 vendor 进本仓库。

### `tools/niri_patch.py`
- binds 改为起止标记的整块替换（片段更新时会同步，而不是“见过 marker 就永不更新”）。
- 自动迁移旧版 `// ==== low-spec rice ====` 标记。
- `include` 改为整行匹配，避免命中注释里的 `include "layout.kdl"`。

### 新增
- `live/`：Arch live ISO 安装器（分区 → pacstrap → chroot → 部署 → 模块）。
- `vm/`：QEMU 验证环境（Arch ISO + virtio 磁盘 + 9p 共享仓库）。
- `tests/e2e/merge.sh`：真实 shorin 树 + 假 HOME 上验证合并/幂等/undo/契约。
- `resources/rice-merge/`：niri 键位片段与 fcitx5 environment.d（原 `overlay/`）。

## 与上游同步

```bash
git remote add upstream https://github.com/SHORiN-KiWATA/shorin-arch-setup.git
git fetch upstream
git log --oneline --no-merges upstream/main
git diff HEAD:. ...            # 按文件看差异
```

建议顺序：

1. 先看 `scripts/00-utils.sh`、`scripts/04j-minimal-niri.sh`、`minimal-niri-dotfiles/`
   是否有变化——这是 04n 的契约面。
2. 跑 `make check`（单元 + e2e）。e2e 用的是仓库里的真实树，契约面变化会直接失败。
3. 手工合并 `install.sh`：本地改动集中在参数解析、菜单、模块列表、Low-Spec clone 四处。
4. 更新本文件的“上游 commit”与改动列表。

## 许可与“授权”

- 代码层面：AGPL-3.0 允许 fork、修改、再分发，**不需要作者额外授权**；
  义务是保留许可证与声明、修改过的文件带显著改动说明、对外分发时提供源码。
  本仓库已满足，并保持 AGPL-3.0。
- 需要沟通的是**名称与背书**：如果公开使用 “shorin” 作为项目名/品牌，礼貌上应告知作者；
  但这不影响代码使用。
- 真正需要授权的是 **Low-Spec-Niri-Dotfiles**：仓库没有 LICENSE，默认保留所有权利。
  本仓库因此只在运行时 clone，不分发其配置。若将来想 vendor，必须先取得作者许可。
