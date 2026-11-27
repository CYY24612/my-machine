# tools/ —— 上位机工具

| 文件 | 作用 |
| --- | --- |
| `proto.py` | **统一帧协议参考实现**（可执行规范）：封包 / 解包 / 状态机 |
| `test_proto.py` | 协议测试向量（19 项，不依赖 pytest） |
| `load_prog.py` | 通过串口把机器码装进自制 CPU |
| `radar.py` | 极坐标雷达图（舵机扫描 + 超声测距） |
| `rx_test.py` | 接收通路走马灯自测 |
| `serial-log.ps1` | 串口日志（文本 / Hex） |

## 跑测试

```powershell
cd tools
python test_proto.py
python proto.py        # 打印协议文档 §5 的 7 条示例帧
```

## ⚠️ 本机（公司）特有陷阱：天锐绿盾透明加密

**node.exe / edit 工具写的 `.py` 文件会被绿盾包上 4096 字节密文，python 读到的是乱码。**

症状：
```
SyntaxError: Non-UTF-8 code starting with '\x88' in file ... on line 1
```
（文件在 PowerShell 里读是正常 UTF-8，在 python 里读是密文。）

修法：**用 PowerShell 把文件读出来再写回去**（白名单进程落盘成明文）：

```powershell
$f = 'tools\proto.py'
$t = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($f, $t, (New-Object System.Text.UTF8Encoding($false)))
```

**规则：本仓库里的 `.py` / `.ps1` 一律用 PowerShell 的 `WriteAllText` 修改，不要用 AI 的 `edit`/`write` 工具。**