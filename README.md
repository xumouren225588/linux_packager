# Ubuntu 桌面 Ventoy vDisk 镜像 · diskimage-builder + GitHub Actions

一条完整的 GitHub Actions 流水线：用 OpenStack **diskimage-builder（DIB）** 构建带
GNOME 桌面的 Ubuntu 整盘镜像，后处理成 **Ventoy Linux vDisk 插件**要求的固定大小
`xxx.vhd.vtoy`，构建完成后**自动上传工件**（Actions artifact / GitHub Release / 分卷）。

产出物：

| 文件 | 说明 |
| --- | --- |
| `ubuntu-<release>-<flavor>-ventoy.vhd.vtoy` | 固定大小 VHD，直接拷进 Ventoy U 盘即可启动 |
| `*.vhd.vtoy.zst`（或 `.xz`） | 压缩工件，未使用区域是零，压缩比很高 |
| `*.sha256` | 校验和 |
| `*.part-*` + `RESTORE.txt` | 仅在开启分卷时产生 |

---

## 一、这份实现相对原始 AI 方案修正了什么

原始方案思路是对的，但有 7 处会直接导致构建失败或启动失败。下表每一条都经过本机
DIB 3.44 / qemu-img 实测验证。

| # | 原始写法 | 问题 | 本仓库的做法 |
| --- | --- | --- | --- |
| 1 | YAML 里 `image-type: vhd` | DIB 的 YAML 定义**没有** `image-type` 这个键，输出格式是 `types`（列表），写错直接被 `diskimage-builder` 判为非法定义 | 键名改成 `types`（本仓库取值是 `["raw"]`，原因见第 8 行），并用 `tools/check-definition.py` 白名单校验所有键 |
| 2 | `disk-image-create -c ubuntu-ventoy.yaml` | `disk-image-create` 没有 `-c/--config` 选项；YAML 定义要用包装命令 | `diskimage-builder ubuntu-ventoy.yaml` |
| 3 | 元素内假定能从 `/dib/<element>/` 取载荷 | DIB 3.x **没有**该机制。实测：`generate_hooks` 把元素的一级子目录复制进 hooks 目录，再由 `run_d_in_target` 只读 bind-mount 到 chroot 的 `/tmp/in_target.d` | 载荷目录 `ventoy-data/` → 镜像内 `/tmp/in_target.d/ventoy-data/`，构建期离线可用 |
| 4 | 用 `qemu-img info` 判断是否 fixed | 固定大小 VHD 只有尾部 footer、没有文件头，qemu-img 自动探测会报 `format: raw`，据此校验必然误判 | `tools/check-vhd.py` 直接解析 footer 的 `disk_type`（2=Fixed）与 `data_offset=0xFFFFFFFF` |
| 5 | 在 `finalise.d` 里直接跑 `vtoyboot.sh` 就算完 | vtoyboot 的前提是"运行在真实已启动的系统里"，在 DIB 的 chroot 中拿不到真实根设备，有可能判定失败并让整条 CI 挂掉 | 构建期试跑；失败则安装一次性 systemd 服务，在 Ventoy 上第一次真实启动时自动补齐钩子 |
| 6 | 在 `finalise.d` 里手写 `apt-get install` | 绕开了 DIB 的分层，包缓存与 `--no-install-recommends` 策略不可控 | 改用 `package-installs.yaml` 声明式安装，桌面变体用 `when:` 条件切换 |
| 7 | 账号密码明文写在 YAML | 密码进 git 历史 | 默认值仅为跑通，正式使用走 Repository Secrets（`VENTOY_USERNAME` / `VENTOY_PASSWORD`） |
| 8 | 直接用 `-t vhd` 产出镜像 | **DIB 的 vhd 输出类型要求系统里有 `vhd-util`**，Ubuntu/Debian 官方仓库不提供该包，托管 runner 上秒挂（`vhd output format specified but no vhd-util executable found`） | 默认改用 `types: ["raw"]`，由 `postprocess.sh` 用 qemu-img 一次转成固定大小 VHD；还省掉"动态 VHD 再固定化"的翻倍磁盘读写 |
| 9 | 在 `finalise.d` 里 `sudo -E` 保留环境 | GitHub runner 的 sudoers 禁止保留环境，日志出现 `sudo: preserving the entire environment is not supported, '-E' is ignored` | 统一改成 `sudo env "PATH=$PATH" "VAR=$VAR"` 显式传参，不依赖 `-E` |
| 11 | `qemu-img convert -o subformat=fixed`（不带 `force_size`） | **实测会被按 CHS 几何向上取整**：64 MiB 的 raw 变成 67125248 字节，导致整盘镜像的 GPT 备份头不再位于逻辑磁盘末尾，内核判定分区表损坏，Ventoy 上直接起不来 | 固定化统一用 `-o subformat=fixed,force_size`，`check-vhd.py` 额外校验 GPT 主/备头位置（自检里还带一个反向用例，确保漏写 force_size 会被拒绝） |
| 10 | `package-installs.yaml` 写 `linux-modules-extra-generic` | 该包名在 Ubuntu 24.04 里不存在（`modules-extra` 只有带内核版本号的实例包），apt 会直接 `Unable to locate package` | 换成 meta 包 `linux-generic` + `linux-headers-generic`，由依赖关系自动带上匹配版本的 modules 包 |

另外两点属于体验修正：镜像内做清理 + 压缩（20 GB 固定 VHD 的零区能被压掉一大半）、
以及提供分卷以绕开单文件大小限制。

---

## 二、仓库结构

```
.
├── .github/workflows/
│   ├── build-ventoy-image.yml      # 主流程：构建 → 固定化 → 压缩 → 上传
│   └── validate.yml                # 秒级静态校验，抓配置层错误
├── config/
│   └── ubuntu-ventoy.yaml.in       # DIB 镜像定义模板（envsubst 渲染）
├── elements/ubuntu-ventoy-gnome/   # 自定义元素
│   ├── element-deps
│   ├── package-installs.yaml       # 桌面与内核包（when 条件切换 gnome/xfce/none）
│   ├── ventoy-data/                # vtoyboot.tar.gz 离线载荷（不入库）
│   └── finalise.d/
│       ├── 90-desktop-default      # 默认进图形界面
│       ├── 92-initramfs-virtio     # initramfs 内置 virtio_blk/pci
│       ├── 95-vtoyboot             # vtoyboot 注入 + 首启动兜底
│       └── 99-ventoy-cleanup       # 清理与抹指纹
├── scripts/
│   ├── install-deps.sh             # DIB + qemu-utils + gdisk 等
│   ├── free-disk-space.sh          # 清理托管 runner 预装软件
│   ├── fetch-vtoyboot.sh           # 下载 vtoyboot 载荷
│   ├── render-config.sh            # 渲染镜像定义
│   ├── build-image.sh              # 调 DIB 构建（需 root）
│   ├── postprocess.sh              # 动态 VHD → 固定大小 VHD + .vtoy
│   ├── pack-artifact.sh            # 压缩 + sha256 + 分卷
│   ├── build-all.sh                # 本地一键全流程
│   └── validate-config.sh          # 本地/CI 共用的自检
├── tools/
│   ├── check-definition.py         # 校验镜像定义的键、元素、类型
│   └── check-vhd.py                # 解析 VHD footer，判定是否满足 Ventoy 要求
└── docs/TROUBLESHOOTING.md
```

---

## 三、快速开始

### A. 用 GitHub Actions（推荐）

1. 新建仓库并把本目录推到 `main`。
2. **Actions → Build Ventoy vDisk image → Run workflow**，按需调参数。
3. 构建完在 run 页面 Download artifact；`upload_target` 选 `release` 时产物挂在 Release 上。

也可以用 tag 触发（全默认参数：noble / gnome / 20 GB / zstd / artifact）：

```bash
git tag v1.0.0 && git push origin v1.0.0
```

推送前建议先跑 `validate.yml`，它几秒就能抓出元素名写错、`when:` 变量缺失这类问题：

```bash
bash scripts/validate-config.sh
```

### 参数说明（workflow_dispatch）

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `ubuntu_release` | `noble` | `noble`=24.04 LTS，`jammy`=22.04 LTS |
| `desktop` | `gnome` | `gnome` / `xfce` / `none`（纯命令行） |
| `image_size` | `20` | 整盘 GB。**最终是固定大小 VHD，这个数直接决定工件体积** |
| `output_format` | `raw` | DIB 输出格式。`raw` 无外部依赖（推荐）；`vhd` 需要系统装有 `vhd-util`，缺失时自动降级回 raw |
| `vtoyboot_version` | `latest` | 可钉具体版本（如 `1.0.42`）保证可复现 |
| `compression` | `zstd` | `zstd` / `xz` / `none` |
| `split_size_mb` | `0` | 非 0 时按 MiB 分卷，绕开单文件大小限制 |
| `upload_target` | `artifact` | `artifact` / `release` / `none` |
| `release_tag` | 空 | 投 Release 时的目标 tag，留空用触发 ref |
| `runner` | `ubuntu-24.04` | 自建 runner 填其 label |
| `dib_version` | 空 | 钉 DIB 版本（如 `3.32.0`）复现构建 |

### B. 本地或自建 runner 一键构建

```bash
# Ubuntu 22.04 / 24.04，需要 root（DIB 要用 loop 设备与 chroot），建议 ≥40GB 空闲磁盘
UBUNTU_RELEASE=noble DESKTOP=gnome IMAGE_SIZE=20 OUTPUT_FORMAT=raw \
  sudo env "PATH=$PATH" "BUILD_DIR=$PWD/.build" bash scripts/build-all.sh
```

产物在 `.build/out/dist/`。

### C. 镜像内账号

默认 `user` / `1234`，带免密 sudo。**在真实机器上启动后请立即改密**：

```bash
passwd
```

想从一开始就用强密码，在仓库 Settings → Secrets and variables → Actions 里建
`VENTOY_USERNAME` 与 `VENTOY_PASSWORD`，流水线会自动取用。

---

## 四、拿到 vtoy 文件之后

1. U 盘装好 Ventoy（**建议在 Ventoy2Disk 的 Options 里关闭 Secure Boot 支持**，
   或在目标机 BIOS 里把 Secure Boot 设为 Off / Other OS）。
2. 把 `xxx.vhd.vtoy` 拷到 U 盘存放镜像的那个分区根目录。
   后缀必须是 `.vhd.vtoy`：`.vtoy` 告诉 Ventoy 走 Linux vDisk 插件，
   只写 `.vhd` 会被当成 Windows VHD 处理。
3. 开机选 Ventoy 菜单里的这个文件。
4. 若构建期 vtoyboot 未能执行，系统会在第一次启动时自动运行钩子并**自动重启一次**，
   第二次启动即正常。手工补跑：

   ```bash
   sudo bash /usr/local/share/vtoyboot/vtoyboot.sh && sudo reboot
   ```

5. 换机器启动如果网络起不来，检查该机型网卡驱动；`dhcp-all-interfaces` 已保证
   所有接口默认 DHCP。

---

## 五、工件体积与 GitHub 配额（务必先看）

固定大小 VHD 会按整盘大小占满磁盘，但没写入过的区域全是零，压缩后通常只剩实际数据量：
本机实测 64 MiB 镜像（其中 56 MiB 为零）压成 8.1 MiB。桌面镜像经验上 20 GB 盘能压到
1~3 GB 量级。

上传方式怎么选：

- **`artifact`**：最省事。但 Actions artifact 占的是仓库**存储配额**（与套餐挂钩，
  免费额度很小，见 Settings → Billing），几十 GB 的原盘镜像根本放不下 —— 所以
  这里默认先 zstd 压缩再传，并把 `retention-days` 设为 7。
- **`release`**：适合当发行版发布。注意 GitHub 对单个 Release 附件有 5 GB 上限，
  超了就得配合 `split_size_mb` 分卷。
- **`none`**：只要镜像、不上传（自己从 runner 拉走或换对象存储）。

分卷还原（`RESTORE.txt` 里也有同样说明）：

```bash
cat xxx.vhd.vtoy.zst.part-* > xxx.vhd.vtoy.zst
sha256sum -c xxx.vhd.vtoy.zst.sha256
zstd -d xxx.vhd.vtoy.zst -o xxx.vhd.vtoy
python3 tools/check-vhd.py --expect-fixed xxx.vhd.vtoy   # 确认仍是 fixed VHD
```

---

## 六、环境变量总表（脚本共用）

| 变量 | 默认 | 作用 |
| --- | --- | --- |
| `UBUNTU_RELEASE` | `noble` | DIB_RELEASE |
| `DESKTOP` | `gnome` | `gnome` / `xfce` / `none` |
| `IMAGE_SIZE` | `20` | 整盘 GB |
| `OUTPUT_FORMAT` | `raw` | DIB 输出格式（`raw` / `qcow2` / `vhd`，vhd 缺 vhd-util 时降级） |
| `DEV_USERNAME` / `DEV_PASSWORD` | `user` / `1234` | 镜像内账号 |
| `VTOYBOOT_VERSION` | `latest` | vtoyboot 版本 |
| `DIB_VERSION` | 空 | 钉 diskimage-builder 版本 |
| `COMPRESSION` / `COMPRESSION_LEVEL` | `zstd` / `19` | 压缩方式与等级 |
| `SPLIT_MB` | `0` | 分卷 MiB |
| `KEEP_SOURCE` | `0` | 1=保留 DIB 原始动态 VHD |
| `SKIP_DISK_FREE` | `0` | 1=不清理磁盘（自建 runner 建议设 1） |
| `BUILD_DIR` / `DIB_VENV` | `.build` / `.venv-dib` | 构建目录 |
| `DRY_RUN` | `0` | 1=只做 DIB dry-run |

---

## 七、已知限制与风险（不藏着）

- **托管 runner 磁盘吃紧**：动态→固定的转换期间会同时存在两份镜像
  （20 GB 参数 ≈ 需要 40 GB 空闲）。`free-disk-space.sh` 能腾出空间，但
  更大的镜像建议用自建 runner（`runs-on` 填自己的 label）或调小 `IMAGE_SIZE`。
- **vtoyboot 与发行版支持范围**：vtoyboot 官方测试列表覆盖 Ubuntu Desktop/Server 等，
  24.04 属于较新目标；若某台机器上起不来，先按第四节手工补跑钩子再判断。
- **首次启动可能多一次自动重启**（构建期钩子没跑成时的兜底路径），这是设计行为。
- **本仓库处理的是 Linux vDisk 插件**，不是 Windows VHD 启动插件
  （后者是 `ventoy_vhdboot.img`，两者不要混）。
- **镜像内默认密码是弱口令**，仅用于跑通流水线。
- 构建出的镜像里带 cloud-init（继承自 DIB 的 `vm` 元素），裸机首启动会多花几秒探测
  数据源。想彻底去掉，在 `package-installs.yaml` 里把 `cloud-init` 标成 `uninstall: true`。

---

## 八、二次开发

- **换桌面**：编辑 `elements/ubuntu-ventoy-gnome/package-installs.yaml`，
  新增一个 `when: DIB_VENTOY_DESKTOP = kde` 分支，并在
  `scripts/render-config.sh` 的 `case` 里加一个分支、workflow 的 `options` 里加一项。
- **加预装软件**：直接往 `package-installs.yaml` 里加包名（构建更快、缓存更友好），
  比在 `finalise.d` 里写 apt 更好。
- **改分区布局**：`block-device-gpt` 里的 `block-device-default.yaml` 是默认布局，
  需要定制时设 `DIB_BLOCK_DEVICE_CONFIG` 覆盖（支持 BIOS Boot + ESP + root 的任意组合）。
- **换发行版**：把元素依赖 `ubuntu-minimal` 换成 `debian` / `fedora` 等，
  vtoyboot 钩子部分对使用 dracut / initramfs-tools / mkinitcpio 的发行版通用。

---

## 九、本地自检

任何改动后跑这一条即可（CI 的 `validate.yml` 跑的是同一套检查）：

```bash
bash scripts/validate-config.sh
```

它会依次检查：shell 语法 → 元素脚本可执行位 → YAML 合法性 → 渲染定义 →
定义语义白名单 → VHD footer 解析工具 → DIB dry-run（元素解析与依赖）。

## 许可

MIT
