# rice-merge

shorin-arch-setup 的中文底座 + Low-Spec-Niri-Dotfiles 的视觉层，拼成一套 niri 桌面安装步骤。

- **底座**：[SHORiN-KiWATA/shorin-arch-setup](https://github.com/SHORiN-KiWATA/shorin-arch-setup)（AGPL-3.0）
  提供 00~03 的系统管线、fcitx5 + rime 中文输入、niri 主配置、Xwayland satellite。
- **皮肤**：[okyashgajjar/Low-Spec-Niri-Dotfiles](https://github.com/okyashgajjar/Low-Spec-Niri-Dotfiles)（无 LICENSE）
  提供 waybar 15 套布局、matugen 壁纸取色、`rice-*` 命令与壁纸池。

两个上游都**不 vendor 进仓库**：`make deploy` 只把本仓库的产物装进你的 shorin 副本，
低配视觉层由你自己 `git clone`，这样升级上游不冲突、也不再分发没有许可证的配置。

## 结构

```
rice-merge/
├── install/04n-lowspec-niri.sh        # 装进 <shorin>/scripts/ 的桌面步骤
├── overlay/
│   ├── niri/rice-binds.kdl            # 合并进 binds.kdl 的 rice 键位
│   └── environment.d/91-low-spec-fcitx.conf
├── tools/niri_patch.py                # 所有文本变换（幂等、可测）
├── tests/test_niri_patch.py           # 单元测试
├── Makefile                           # test / lint / check / deploy
└── .github/workflows/ci.yml           # push 即跑 make check
```

## 用法

```bash
git clone <本仓库> rice-merge && cd rice-merge

# 1. 部署到你的 shorin 副本
make deploy SHORIN=~/projects/shorin-arch-setup

# 2. 拉低配视觉层
git clone --depth=1 https://github.com/okyashgajjar/Low-Spec-Niri-Dotfiles.git \
  ~/projects/shorin-arch-setup/low-spec-dotfiles

# 3. 在新装的 Arch 上，跑完 shorin 的 00~03 后：
sudo bash ~/projects/shorin-arch-setup/scripts/04n-lowspec-niri.sh
```

## 文件归属（冲突判据）

| 配置 | 归属 | 原因 |
|---|---|---|
| `niri/config.kdl`、`layout.kdl`、`output.kdl` | shorin | 中文 locale、输出与多屏配置 |
| `niri/binds.kdl` | shorin + 追加 | 保留 `Mod+F1` 切输入法，追加 rice 键位 |
| `niri/rice-colors.kdl` | Low-Spec | matugen 生成，被 config 引用 |
| `waybar/*` | Low-Spec | 15 套布局；shorin 原件存为 `*.shorin.bak` |
| `fcitx5`、rime、`foot`、`fuzzel` | shorin | 中文与字体已调好 |
| `mako` | shorin | matugen 的 mako 模板会被裁掉 |
| `matugen/config.toml` | Low-Spec（裁剪） | 只保留 waybar / niri / gtk3 / gtk4 |
| 锁屏、电源菜单 | shorin（hyprlock） | Low-Spec 的 `rice-lock` 指向 swaylock |

## 开发

```bash
make check     # bash -n + py_compile + shellcheck(-S error) + 单元测试
make test      # 只跑测试
make clean
```

`tools/niri_patch.py` 是唯一的文本变换入口，四个子命令（`binds` / `include` / `matugen` / `sub`）
全部幂等；安装脚本只调用它，不在 shell 里写内联 Python。

## 已知上游问题（已在合并时绕开）

- `Low-Spec-Niri-Dotfiles/config/niri/config.kdl` 硬编码 `/home/yg`，安装脚本用 `sub` 修正。
- Low-Spec 声明不使用 Xwayland；本仓库保留 shorin 的 `xwayland-satellite`，老应用可跑。
- matugen 的 foot/mako/fuzzel 模板会覆盖中文配置，`matugen` 子命令负责裁掉。

## 许可

本仓库代码以 **AGPL-3.0** 发布（见 LICENSE），因为安装步骤派生自 AGPL 的 shorin-arch-setup。

上游 Low-Spec-Niri-Dotfiles 仓库**没有 LICENSE 文件**，默认保留所有权利：
自己的机器上使用无碍，但不要把它的配置文件再分发（本仓库也因此不 vendor 它）。

## 状态

- 已验证：`bash -n`、`py_compile`、`make test`（8 个用例）、对 shorin 真实 `binds.kdl`（371 行）与 `config.kdl`（211 行）的干跑。
- 未验证：真机 Arch + niri 的 kdl 解析、matugen 对 shorin 字体的实际影响、hyprlock 依赖。
