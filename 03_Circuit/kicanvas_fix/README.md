# KiCad 网页端网络（NET）缺失修复说明

> 适用：电子森林 / 硬禾学堂（eetree.cn）项目报告页里的 **“KiCad文件”** 查看器
> 工程：`WeDesign8_ToF_FPGA/03_Circuit/`（嘉立创 EDA 专业版 → KiCad 10 导入的 PCB）
> 状态：已用 eetree 实际使用的查看器脚本在本地复现并验证通过

## 一、问题现象

把 KiCad 工程上传到电子森林后，报告页“KiCad文件”卡片里的 PCB：

- 右侧 **Nets（网络）面板是空的**，或所有走线无法按网络区分；
- 走线、过孔、焊盘、覆铜的“网络”全部识别不出来，看起来“所有走线都是同一种走线”。

## 二、根本原因（已确认）

由嘉立创 EDA 专业版导入后，用 KiCad 10 保存的 PCB 是 **KiCad 10 新格式**
（`(version 20260206)`），网络只以“名称”形式直接写在对象里：

```
(segment ... (net "GND"))
(pad "1" ... (net "GND"))
(zone (net "GND") ...)
```

文件里**没有顶层网络表** `(net N "NAME")`。

而电子森林网页端的 KiCad 查看器用的是旧版 **KiCanvas**（KiCad 6/7 时代的解析器），
它要求的是另一套写法：

| 对象 | 旧版 KiCanvas 需要的写法 |
| --- | --- |
| 顶层 | `(net 0 "")` `(net 1 "GND")` `(net 2 "3V3")` … |
| 走线 / 过孔 | `(net N)`（数字编号） |
| 焊盘 | `(net N "NAME")`（数字 + 名称） |
| 覆铜 | `(net N)` + `(net_name "NAME")` |

所以旧查看器解析出来的网络数量是 **0**，每个走线的 `net` 都是 `undefined`，
于是“全都被识别成同一种走线”。

另外还有一个会直接导致白屏的问题：KiCad 9/10 允许在 polygon 的
`(pts ...)` 里内嵌 `(arc ...)`（本工程有 12 处，来自 MX128L 连接器的封装），
旧版 KiCanvas 的 pts 解析器只认 `(xy x y)`，遇到 arc 会算出 NaN 并抛异常，
整页只显示纯色背景。**必须把圆弧展开成折线**。

## 三、解决办法

本目录的 `convert_kicad10_to_kicanvas.py` 做了两件事：

1. 把所有 `(pts ...)` 内的 `(arc (start ..) (mid ..) (end ..))` 按 12° 步长采样成折线点；
2. 按出现顺序给网络编号（1..46，0 保留给空网络），在 `(setup)` 之后插入顶层网络表，
   并把 pad / segment / via / zone 的 net 引用改成旧版格式。

其余内容（坐标、封装、走线、覆铜、图层、标题栏……）原样保留。
输出文件**仍能被 KiCad 10 正常打开**（已验证）。

### 本目录文件

| 文件 | 用途 |
| --- | --- |
| **`WeDesign8_ToF_FPGA_kicanvas_upload.zip`** | **上传到电子森林的就是这个 zip**（0.43 MB，内含 `.kicad_pcb` + `.kicad_sch`） |
| `WeDesign8_ToF_FPGA.kicad_pcb` | 修复后的 PCB（本地用 KiCad 10 查看也用这个） |
| `WeDesign8_ToF_FPGA.kicad_sch` | 原原理图，未改动（平台要求 zip 中必须同时含 sch 与 pcb） |
| `convert_kicad10_to_kicanvas.py` | 转换脚本，PCB 以后再改可以重新生成 |
| `网页端效果预览_Nets面板.png` | 用电子森林同款查看器加载修复后文件的截图：Nets 面板 47 个网络 |
| `网页端效果预览_PCB.png` | 同一查看器里的 PCB 渲染效果 |

### 验证结果

- **KiCad 10.0.8 打开**：`LoadBoard` 通过，47 nets / 219 tracks / 33 footprints / 4 zones / 175 pads，网络名正确（GND、3V3、LASER+3V3、VCC+5V ……）。
- **电子森林同款查看器**（本地用 eetree 的 kicanvas.js：805,256 字节，版本与网页端一致，无头 Edge 加载）：
  - 原文件：`board.nets.length === 0`（网络全部丢失）
  - 修复后：`board.nets.length === 47`，196 走线 / 23 过孔 / 4 覆铜 / 33 封装全部带网络；
    右侧 Nets 面板 47 项，点击任一网络会高亮对应走线；0 个渲染异常。

![Nets 面板](网页端效果预览_Nets面板.png)

## 四、上传步骤（电子森林）

1. 登录电子森林 → 我的主页 → 项目 → 编辑草稿 8571：
   <https://www.eetree.cn/user-center#project/edit/8571>
2. 在“设计资源”里找到 **“KiCad文件”**，上传
   `WeDesign8_ToF_FPGA_kicanvas_upload.zip`
   （平台要求：仅 1 个 zip、≤30 MB、里面必须含 `.kicad_sch` 与 `.kicad_pcb` —— 本 zip 已满足）。
3. 等待约 20 秒解析完成，然后点“保存”。
4. 打开预览 <https://www.eetree.cn/project-draft/8571>：
   “KiCad文件”卡片里应能看到 PCB；打开右侧 **Nets** 面板有 47 个网络，
   点某个网络会高亮对应走线（GND、3V3、LASER+3V3、VCC+5V、I2C_SDA ……）。
5. 确认无误后按原流程发布/提交（活动截止 2026-11-15）。

## 五、注意事项

- **原始文件没有被改动**：`ProPrj_基于FPGA的ToF激光测距数字系统_2026-11-10.kicad_pcb/.kicad_sch`
  保持原样，修复版是本目录下的副本。
- **不要用 KiCad 10 打开修复版再保存**：KiCad 10 会写回“只有网络名”的新格式，网页端又会丢网络。
  需要改 PCB 时请改原工程，改完重新转换：
  ```
  python convert_kicad10_to_kicanvas.py 原文件.kicad_pcb 新文件.kicad_pcb
  ```
- 原理图未做格式转换：旧查看器能正常解析（45 个符号 / 147 根导线），只是查看器默认显示 PCB 页；
  平台校验要求 zip 里同时有 sch，因此原样附带。
- 查看器只显示 PCB 页属于该网页端的正常行为，不影响 Nets 面板与网络高亮。
