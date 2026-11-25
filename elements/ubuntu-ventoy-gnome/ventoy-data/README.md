# ventoy-data/

构建用的离线载荷目录。`scripts/fetch-vtoyboot.sh` 会把 Ventoy 官方的
`vtoyboot-<ver>.tar.gz` 下载到这里并保存为 `vtoyboot.tar.gz`。

工作原理（diskimage-builder 3.x 实测行为）：

1. `generate_hooks`（lib/common-functions）把元素下的每个一级子目录内容复制到
   `$TMP_HOOKS_PATH/<目录名>/`，即 `ventoy-data/` → `$TMP_HOOKS_PATH/ventoy-data/`；
2. `run_d_in_target`（lib/img-functions）把 `$TMP_HOOKS_PATH` 只读 bind-mount 到
   chroot 的 `/tmp/in_target.d`；
3. 于是 `finalise.d/95-vtoyboot` 能在镜像内直接读到
   `/tmp/in_target.d/ventoy-data/vtoyboot.tar.gz`，构建期无需访问 GitHub。

目录名特意用 `ventoy-data` 而不是常见的 `data`：DIB 会按目录名合并各元素的 hook
目录，同名文件冲突会直接报 duplicated hook 并终止构建。

tar 包不入库（见仓库根 `.gitignore`）。
