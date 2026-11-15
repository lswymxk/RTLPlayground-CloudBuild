# RTLPlayground 云编译

用 GitHub Actions 给 [RTLPlayground](https://github.com/logicog/RTLPlayground)（RTL8372 / RTL8373 的 2.5G 交换机固件）做云端编译：

> 先选**设备型号**，再选 **PCB 版本** → 点 Run workflow → 只编译对应的机型 → 下载 `.bin`。

本仓库只包含**编译脚本和 GitHub Actions workflow**，不保存固件源码。每次运行时按 `source_repo` + `source_ref` 现场 checkout 指定版本，所以既能编上游，也能编你自己的 fork、分支或某个 commit。

---

## 功能

- 🖱️ **纯手动触发**：没有定时任务，只有你在 Actions 页面点运行时才会编译
- 🎯 **按型号 + PCB 精确选择**：同一型号有多个 PCB 时选具体版本；只编译选中的 machine，未选中的不会编译
- 🧰 **自动准备工具链**：下载 SDCC 4.6.0、打上项目自带的 4 个补丁、编译成 `toolchain/`，并缓存复用
- 📦 **两种镜像一起出**：直接刷 Flash / RTLPlayground 网页升级的普通镜像，以及原厂 OEM 网页升级专用镜像
- 🏷️ **可选发布 Release**：填一个 tag，产物自动上传到 Release，附 `SHA256SUMS`
- 🔁 **可复现**：`source_ref` 可以填 commit SHA，配合 `SOURCE_DATE_EPOCH` 得到稳定的构建结果

## 工作流程

```
工作流手动触发（选型号 + PCB / 选版本 / 选配置）
        │
        ├─ checkout 本仓库            → scripts/build.sh + machines.tsv + configs/
        ├─ checkout 固件源码          → src/（source_repo @ source_ref）
        ├─ 型号 + PCB → machine 映射   → 查 machines.tsv，查不到立刻失败
        ├─ apt 安装编译依赖
        ├─ 恢复 SDCC 工具链缓存 ──未命中──→ 下载 SDCC 4.6.0、打补丁、编译（几分钟）
        ├─ make CI=1 MACHINE=<映射出的 machine> [CONFIG=<配置>]
        ├─ make -C installer          → OEM 网页升级包
        └─ dist/  →  Artifact（30 天） / Release（永久）
```

---

## 快速开始

### 1. 新建仓库

在 GitHub 上新建一个仓库，例如 `RTLPlayground-CloudBuild`，**Public** 即可（公开仓库的 Actions 分钟数免费）。

### 2. 把本项目文件传上去

把本目录下的**所有内容**（包括隐藏目录 `.github/`）上传到仓库根目录：

```
.github/workflows/build.yml
machines.tsv
scripts/build.sh
configs/...
Dockerfile
README.md
...
```

两种方式任选：

**A. 网页上传（不需要 git）**

1. 打开新仓库 → **Add file → Upload files**；
2. 在文件资源管理器里打开本项目文件夹，全选里面的**内容**（不是外层文件夹）拖进网页；
3. Windows 默认隐藏 `.github`，需要先在资源管理器 **查看 → 显示 → 隐藏的项目** 打开；
4. 如果 `.github` 实在传不上去，用 **Add file → Create new file**，文件名填 `.github/workflows/build.yml`，把内容粘进去即可。

**B. git 命令行**

```bash
cd RTLPlayground-CloudBuild
git init
git add .
git commit -m "RTLPlayground cloud build"
git branch -M main
git remote add origin https://github.com/<你的用户名>/RTLPlayground-CloudBuild.git
git push -u origin main
```

### 3. 打开 Actions 写权限（发布 Release 需要）

仓库 **Settings → Actions → General → Workflow permissions** → 选 **Read and write permissions** → **Save**。

只下载 Artifact 不发布 Release 的话，这一步可以跳过。

### 4. 运行

仓库顶部 **Actions** → 左侧 **Build firmware** → 右侧 **Run workflow**：

| 参数 | 填什么 |
| --- | --- |
| `source_repo` | `logicog/RTLPlayground`（或你自己的 fork） |
| `source_ref` | `main`、分支名、tag 或 commit SHA |
| `model` | **必选**，下拉选择设备型号（如 `keepLiNK KP-9000-6XHML-X2`） |
| `pcb` | **必选**，选择 PCB 版本；该型号只有一种 PCB 时选 `AUTO`，有多个时必须选具体版本 |
| `custom_machine` | 一般留空；高级用法：直接填 machine 文件名，会忽略上面的型号/PCB |
| `config_file` | 一般留空；见下面「启动配置」 |
| `build_oem` | 默认勾选，会多出一个 OEM 升级包 |
| `release_tag` | 想发布 Release 就填如 `v0.1.0`，否则留空 |

**一次运行只编译“型号 + PCB”映射出的那一个 machine。** 想编另一个型号/PCB，再运行一次即可。

首次运行会从 SourceForge 下载 SDCC 并编译工具链，大约 **8–15 分钟**；之后命中缓存，通常 **2–5 分钟**。

### 5. 下载固件

打开这次运行的页面，拉到底部 **Artifacts**，下载 `rtlplayground-<run号>.zip`，解压即得 `.bin`。

---

## 选择型号与 PCB（重要）

同一个型号在不同批次可能使用不同 PCB，**PCB 版本决定硬件布局**。请按板上的 PCB 丝印选择，
不要只看外壳标签。项目里的 `machines.tsv` 记录了每个 machine 对应的型号和 PCB：

```
# machine	model	pcb
KEEPLINK_KP_9000_6XHML_X2_2M_PCB43_V2_1	keepLiNK KP-9000-6XHML-X2	2M_PCB43_V2_1
```

当前共 **58 个型号、65 个 machine**，其中 4 个型号有多个 PCB：

| 型号 | 可选 PCB |
| --- | --- |
| keepLiNK KP-9000-6XHML-X2 | `2M_PCB43_V1_1`、`2M_PCB43_V1_2`、`2M_PCB43_V2_1` |
| keepLiNK KP-9000-6XH-X2 | `2M_PCB43_V1_1`、`2M_PCB43_V1_2`、`2M_PCB43_V2_1` |
| keepLiNK KP-9000-9XHML-X | `2M_PCB23_V2_2`、`2M_PCB23_V3_1`、`2M_PCB23_V3_2` |
| Hisource Hi-K0402WS | `PCB_K0402W_V2_0`、`PCB_K0402W_V3_0` |

- `pcb` 选 `AUTO`：型号只有一种 PCB 时自动使用；有多种时会报错并列出可选版本。
- 默认型号 `keepLiNK KP-9000-6XHML-X2` 有 3 种 PCB，默认的 `AUTO` 会提示你选择；这是故意的，避免刷错。
- 下拉框里用的是源码里的 PCB 文件名（下划线），丝印通常写作 `2M-PCB43-V2.1` 这种形式，对应关系看下面的文档。
- 只有一种 PCB 的型号，`pcb` 保持 `AUTO` 即可；如果选了不匹配的值，会提示并忽略。
- PCB 丝印和文档的对应关系见固件项目的 [`doc/supported_devices.md`](https://github.com/logicog/RTLPlayground/blob/main/doc/supported_devices.md)
  以及 `doc/devices/*.md` 里的 “Machine target” 表。
- 上游新增型号或 PCB 后，更新 `machines.tsv` 和 workflow 里的 `model` / `pcb` 下拉选项；
  临时编译也可以直接在 `custom_machine` 里填 machine 文件名。
- 下拉列表按 `logicog/RTLPlayground` 生成；换成别的 fork 时如果型号对不上，用 `custom_machine`。

常见的两个例子（固件项目 CI 一直在编的）：

| 型号 | PCB | 编译目标 | 硬件 |
| --- | --- | --- | --- |
| `keepLiNK KP-9000-6XHML-X2` | `2M_PCB43_V1_1` | `KEEPLINK_KP_9000_6XHML_X2_2M_PCB43_V1_1` | 4 × 2.5G + 2 × SFP+ |
| `keepLiNK KP-9000-9XHML-X` | `2M_PCB23_V3_1` | `KEEPLINK_KP_9000_9XHML_X_2M_PCB23_V3_1` | 8 × 2.5G + 1 × SFP+ |

---

## 启动配置（IP / 网关 / 端口名…）

编译时可以把一份启动配置嵌进固件，设备第一次启动就生效。

**自动匹配**：创建 `configs/<machine>.txt`，其中 `<machine>` 是运行摘要/日志里“编译目标”的值（例如 `KEEPLINK_KP_9000_6XHML_X2_2M_PCB43_V1_1`），编译对应机型时会自动使用。如果不想猜文件名，直接用下面的 `config_file` 指定更省事。

**手动指定**：把 `config_file` 填成仓库里的路径（如 `configs/my-lab.txt`）。

**都不提供**：使用固件源码自带的 `config.txt`（默认 `192.168.10.247` / `255.255.255.0`）。

示例：

```
ip 192.168.10.247
gw 192.168.10.1
netmask 255.255.255.0
port 1 name uplink
igmp on
session 3600
```

完整语法见 [`configs/README.md`](configs/README.md)。

> 配置是**编译进镜像**的，改完要重新编译再刷机；已经刷好的设备也可以直接在网页 **System → Startup Configuration** 修改，不必重编。

---

## 产物说明（很重要，别刷错）

一次成功的手动构建，`dist/` 里会有：

| 文件 | 用途 |
| --- | --- |
| `rtlplayground-<机型>.bin` | **512 KiB 主镜像**。用编程器直接刷 Flash；设备已经在跑 RTLPlayground 时，也可用它网页升级 |
| `rtlplayground_oem_upgrade-<机型>.bin` | **只用于原厂 OEM 网页界面升级**，而且通常只需用一次；之后升级都用上面的主镜像 |
| `rtlplayground-<机型>.map` / `.mem` | 链接 map 和内存占用，调试用，不用刷 |
| `SHA256SUMS` | 校验和 |
| `build-info.txt` | 源码仓库、commit、构建时间、文件大小 |

> ⚠️ 已经在跑 RTLPlayground 的设备，**不要**再刷 `oem_upgrade` 包；原厂设备也**不要**刷普通 `.bin`（除非用编程器直接写 Flash）。

---

## 发布 Release

`release_tag` 填一个 tag（如 `v0.1.0` 或 `v0.1.0-20261102`），构建成功后会：

- tag 不存在 → 创建 Release 并上传 `dist/` 全部文件；
- tag 已存在 → 覆盖上传同名文件（`--clobber`）。

Release 标题会带上机型，方便区分。这样固件就有固定下载地址，不会像 Artifact 那样 30 天后过期。

---

## 本地编译（可选）

`scripts/build.sh` 本身支持一次传多个机型（CI 里只传选中的那一个）。有 Docker 的话：

```bash
git clone --depth 1 https://github.com/logicog/RTLPlayground.git src
docker build -t rtlplayground-builder .
docker run --rm -v "$PWD:/work" -w /work rtlplayground-builder \
  env MACHINES="KEEPLINK_KP_9000_6XHML_X2_2M_PCB43_V1_1" bash scripts/build.sh
```

产物在 `dist/`。容器以 root 运行，`src/toolchain`、`src/output`、`dist` 的属主会是 root，需要的话 `sudo chown -R "$USER" src dist`。

或者直接在 Debian/Ubuntu 上装依赖：

```bash
sudo apt install make gcc g++ pkg-config bison flex libboost-dev patch bzip2 curl \
  xxd python3 libjson-c-dev zlib1g-dev git
git clone --depth 1 https://github.com/logicog/RTLPlayground.git src
MACHINES="KEEPLINK_KP_9000_6XHML_X2_2M_PCB43_V1_1" bash scripts/build.sh
```

---

## ⚠️ 安全警告

- 刷错型号/PCB 可能**变砖**。刷之前务必确认设备型号、PCB 丝印与 machine 定义一致。
- 强烈建议先用 SOIC-8 夹子备份原厂 Flash，确认能救回来再动手。
- 具体刷写步骤见固件项目 README 的第 (4)（网页升级）和 (5)（编程器直刷）节。
- 本项目只是把固件项目的编译流程搬到 Actions，**不对固件本身和刷机后果负责**。
- 固件项目的提醒同样适用：不熟悉 Spanning Tree 等特性时不要在生产网络上启用。

---

## 常见问题

**Q：第一次运行为什么这么慢？**
A：要下载并编译打了补丁的 SDCC 4.6.0，约 5–10 分钟；之后 `src/toolchain` 命中缓存，只剩固件本身的编译。

**Q：卡在下载 SDCC / `curl` 失败？**
A：SourceForge 偶尔不稳定，重新运行一次即可；缓存命中后不会再下载。缓存 key 与 `sdcc/` 下内容的哈希绑定，补丁变了会自动重建。

**Q：报 `MACHINE='xxx' has no definition` 或 “源码里没有 machine”？**
A：`custom_machine` 里的 machine 名写错，或这个 commit 里还没有该 machine。用 `ls src/machine/*.h` 核对，注意大小写和下划线。

**Q：为什么不能一次选多个机型？**
A：GitHub Actions 的下拉框（choice）只能单选。需要多个机型就分别运行；本地用 `scripts/build.sh` 时可以一次传多个（`MACHINES="A B"`）。

**Q：选了型号，但提示“有多个 PCB”？**
A：该型号有多个 PCB 版本，`pcb` 不能选 `AUTO`。按板上 PCB 丝印从下拉框里选对应版本（见上面“选择型号与 PCB”）。

**Q：发布 Release 报 `Resource not accessible by integration`？**
A：仓库没有给 workflow 写权限。按「快速开始第 3 步」打开 **Read and write permissions**。

**Q：能编译别人的私有仓库吗？**
A：默认的 `GITHUB_TOKEN` 只能读当前仓库。私有源码需要在 workflow 里换成有 `repo` 权限的 PAT（`actions/checkout` 的 `token` 参数），并注意不要泄露。

**Q：Artifact 会一直保留吗？**
A：30 天；要长期保存请发 Release。

**Q：这个和固件仓库里自带的 CI 有什么区别？**
A：自带的 `build.yml` 只做 CI 检查（编两个机型、跑单测、检查所有 machine 定义），**不上传固件**。本项目专注出可刷写的镜像，并且在页面上选型号/PCB、版本、配置。

**Q：Fork 过来 / 新仓库里 Actions 是灰的，没有 Run workflow 按钮？**
A：新仓库一般默认启用；fork 的仓库需要先在 **Actions** 页点 “I understand my workflows, go ahead and enable them”。还要确认 workflow 文件在**默认分支**的 `.github/workflows/` 目录下。

**Q：镜像大小不是 512 KiB 怎么办？**
A：`scripts/build.sh` 默认校验 `524288` 字节。如果以后固件项目调整了 `IMAGESIZE`，把环境变量 `EXPECTED_SIZE` 改成新值，或设为 `0` 关闭校验。

**Q：会消耗 Actions 额度吗？**
A：公开仓库免费；私有仓库按分钟计费（免费账户每月 2000 分钟）。

---

## 目录结构

```
.
├── .github/workflows/
│   └── build.yml            # 手动选型号 + PCB → Artifact / Release
├── machines.tsv             # 型号 / PCB → machine 映射
├── configs/
│   ├── README.md            # 启动配置语法
│   └── KEEPLINK_KP_9000_6XHML_X2_2M_PCB43_V1_1.txt
├── scripts/
│   └── build.sh             # 真正的编译逻辑（CI 和本地共用）
├── Dockerfile               # 本地复现用的编译环境
└── README.md
```

## 许可

本仓库的脚本与 workflow 使用 MIT 许可；RTLPlayground 固件本身也是 MIT（Copyright © 2025 The RTLPlayground Contributors）。
