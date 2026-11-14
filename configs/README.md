# 启动配置（configs）

这里的文件会在编译时**嵌入固件**，交换机第一次启动就会使用它。

## 命名规则

```
configs/<MACHINE>.txt
```

`<MACHINE>` 必须和 `machine/<MACHINE>.h` 的文件名完全一致（区分大小写），例如：

```
configs/KEEPLINK_KP_9000_6XHML_X2.txt
```

编译时按以下顺序选择配置：

1. Workflow 参数 `config_file` 指定的文件；
2. `configs/<MACHINE>.txt`（存在就自动使用）；
3. 固件源码自带的 `config.txt`。

一次编译多个机型（本地脚本，`MACHINES="A B"`）时，每个机型会分别匹配自己的
`configs/<MACHINE>.txt`；如果显式传了 `config_file`，则所有机型共用这一份。

## 语法

每行一条命令，参数用空格分隔。为避免不同版本解析差异，**只写命令，不要写注释**。

| 命令 | 说明 | 示例 |
| --- | --- | --- |
| `ip <地址>` | 交换机管理地址 | `ip 192.168.10.247` |
| `netmask <掩码>` | 子网掩码 | `netmask 255.255.255.0` |
| `gw <地址>` | 默认网关 | `gw 192.168.10.1` |
| `port <端口> name <名称>` | 端口别名 | `port 1 name uplink` |
| `port <端口> 1g` | 强制该端口为 1G | `port 5 1g` |
| `igmp on\|off` | IGMP 组播 | `igmp on` |
| `session <秒>` | Web 会话超时 | `session 3600` |

完整示例见 [`KEEPLINK_KP_9000_6XHML_X2.txt`](KEEPLINK_KP_9000_6XHML_X2.txt)。

## 注意

- 配置是编译进镜像的，改完必须重新编译、重新刷机；已经刷好的设备也可以直接在
  网页 **System → Startup Configuration** 里改，不必重新编译。
- 设备默认地址是 `192.168.10.247`，默认密码 `1234`。
- 改 IP 前先确认新地址和电脑在同一网段，避免刷完后找不到设备。
