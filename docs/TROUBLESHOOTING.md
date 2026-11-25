# 排障手册

按症状查。左侧是你会看到的报错/现象，右侧是原因与处理。

## 1. 构建阶段

### `diskimage-builder` 报定义里有不认识的键
输出格式写成了 `image-type: vhd`。DIB 的 YAML 只认 `types`（列表）：

```yaml
types: ["vhd"]
```

`python3 tools/check-definition.py .build/ubuntu-ventoy.yaml` 会把所有非法键列出来。

### `disk-image-create: error: unrecognized arguments: -c`
`disk-image-create` 没有 `-c/--config`。YAML 定义要用包装命令：

```bash
diskimage-builder .build/ubuntu-ventoy.yaml
```

### `Element not found: ubuntu-ventoy-gnome`
`ELEMENTS_PATH` 没指到本仓库的 `elements/`。检查渲染结果：

```bash
grep ELEMENTS_PATH .build/ubuntu-ventoy.yaml
```

正确值是 `<仓库绝对路径>/elements`。脚本外手工调 DIB 时先
`export ELEMENTS_PATH=$PWD/elements`。

### package-installs 报变量未定义（`when:` 相关）
`package-installs.yaml` 里 `when: DIB_VENTOY_DESKTOP = gnome` 引用的变量必须存在于镜像
定义的 `environment` 中，否则 DIB 直接抛异常。模板里已经固定注入该变量；自己加
`when:` 条件时记得同时加变量默认值。

### `could not find an unused loop device` / `losetup: ... failed`
构建机 loop 设备不够或没权限：

```bash
sudo modprobe loop max_loop=64
cat /sys/module/loop/parameters/max_loop
```

容器内构建还要放行 `/dev/loop-control` 与 `CAP_SYS_ADMIN`，否则换 runner。

### `No space left on device`
动态 VHD → 固定 VHD 的转换期同时存在两份镜像（`IMAGE_SIZE=20` ≈ 需要 40 GB）。处理：

- 托管 runner 上确认 `scripts/free-disk-space.sh` 跑过（看日志里的 df 对比）；
- `IMAGE_SIZE` 调小，或改用自建 runner；
- `TMPDIR` / `BUILD_DIR` 指到大盘（`build-image.sh` 支持环境变量覆盖）。

### 构建期内存不足被 OOM kill
`no-tmpfs: true` 已在定义里（不让 DIB 把构建目录搬到 tmpfs）。若仍 OOM，说明构建机
内存不足 8 GB，加内存或换 `desktop: none` 先验证链路。

### apt 装不到 `ubuntu-desktop-minimal`
`DIB_DEBIAN_COMPONENTS` 少了 `universe`。模板已带
`main,restricted,universe,multiverse`；换镜像源时注意目标源是否同步了 universe。

### vtoyboot 载荷下载失败
GitHub 匿名 API 有速率限制。两条办法：

- CI 里已用 `gh api` + `GITHUB_TOKEN`（认证请求，限额高得多）；
- 钉版本并把 tar 包预先放进 `elements/ubuntu-ventoy-gnome/ventoy-data/vtoyboot.tar.gz`，
  构建期完全离线。

## 2. 后处理 / 工件阶段

### 提示 `这是动态扩展 VHD ... 需要转成固定大小`
说明 `qemu-img convert -o subformat=fixed` 没生效，多半是 qemu-utils 版本过老
（`subformat` 选项要求 qemu ≥ 2.x）。`qemu-img --version` 确认。

### 为什么不能用 `qemu-img info` 判断是不是固定大小
固定大小 VHD 没有文件头，只有文件末尾 512 字节 footer，qemu-img 自动探测会把它报成
`format: raw`（实测）。本仓库用 `tools/check-vhd.py` 读 footer 的 `disk_type`
（2=Fixed）并核对 `data_offset=0xFFFFFFFF`、文件大小 = 虚拟大小 + 512。

### 分卷还原后 sha256 不匹配
- Linux/macOS：`cat xxx.zst.part-* > xxx.zst`，分卷名是 `-d -a 3` 生成的数字后缀，
  shell 展开顺序即正确顺序；
- Windows：`copy /b xxx.zst.part-000+xxx.zst.part-001+... merged.zst`，顺序必须手工保证；
- 别用文本模式传输分卷（会改行尾），用二进制方式下载。

### artifact 上传报配额/大小问题
压缩后仍超限就换策略：`split_size_mb` 分卷、`upload_target: release`（单附件 5 GB 上限）、
或 `upload_target: none` 自行投递到对象存储。artifact 与仓库存储配额挂钩，
把 `retention_days` 调小能少占一些。

## 3. Ventoy 启动阶段

### 菜单里根本看不到这个文件
- 后缀必须是 `.vhd.vtoy`（不是 `vtoy.vhd`，也不是 `.VTOY`，全小写）；
- 要放在存放镜像的那个分区，别放进 32 MB 的 `VTOYEFI` 分区；
- 目录位置随意，大小写敏感的旧固件建议放根目录。

### 选中后黑屏 / `Unable to find root filesystem`
最常见是 vtoyboot 钩子没生效。在能进的系统里（或该 vDisk 挂到别的 Linux 上挂载后 chroot）：

```bash
bash /usr/local/share/vtoyboot/vtoyboot.sh
```

然后重启。本仓库已内置首启动自动执行逻辑，正常情况会自己重启一次后就好了。
若是全新镜像里连载荷都缺失，就重新下载 vtoyboot 再跑。

### UEFI 机器上起不来，Legacy 可以（或反之）
- BIOS 里把 Secure Boot 设为 Off / Other OS；Ventoy 安装时若勾了 Secure Boot 支持，
  重装时取消该选项；
- 确认 vDisk 内 initramfs 有 virtio 驱动：
  `lsinitramfs /boot/initrd.img-$(uname -r) | grep virtio_blk`。
  缺了就补 `/etc/initramfs-tools/modules` 后 `sudo update-initramfs -u`。

### 起来了但是进不了图形界面
```bash
systemctl get-default                       # 应为 graphical.target
systemctl status gdm3
journalctl -b -p err | tail -50
```
`multi-user.target` 说明 `90-desktop-default` 没匹配到 graphical target（例如选了
`desktop: none`），手工 `sudo systemctl set-default graphical.target`。

### 每次换机器都要重新配置网卡
`dhcp-all-interfaces` 已让所有接口走 DHCP；若某机型需要专有驱动，在
`package-installs.yaml` 里加 `linux-modules-extra-<内核版本>` 或 `firmware-*` 包。

### 想验证 vDisk 里的东西但不想真机启动
在任意 Linux 上挂载 vDisk 文件：

```bash
sudo modprobe nbd max_part=8
qemu-nbd -c /dev/nbd0 ubuntu-noble-gnome-ventoy.vhd.vtoy
lsblk /dev/nbd0
sudo mount /dev/nbd0p3 /mnt        # 分区号以 lsblk 为准
```
用完 `sudo qemu-nbd -d /dev/nbd0`。

## 4. 复现同一份镜像

钉住三个变量即可：`dib_version`（如 `3.32.0`）、`vtoyboot_version`（如 `1.0.42`）、
`ubuntu_release`。内核与桌面包仍随 apt 源滚动，要严格一致需自建 apt 快照仓库。
