# OCR

基于 PaddleOCR，整理《明日方舟》游戏文本生成数据集，用于微调与训练高精度的文本识别（Rec）模型。

本项目主要提供端到端的数据集生成脚本、语料处理工具、模型训练配置以及 ONNX 转换优化流水线。

支持两种模型训练方案：
- **单语言模型模式**：针对特定客户端语言或垂直场景（如纯数字、关卡代号、理智与掉落数量等 ASCII 字符）定向生成数据集并微调轻量端侧模型。
- **多语言统一模型模式**：将所有游戏客户端（cn/en/kr/jp/tw）数据合并为一份多语言数据集，微调单模型覆盖全语言。

## 支持的模型列表

| 模型名称 | 模型架构 | 目标语言与字符集 | 适用场景 | 配置文件 |
| :--- | :--- | :--- | :--- | :--- |
| **`en_PP-OCRv5_mobile_rec`** | 单语言轻量移动端模型 | 纯数字 / 关卡代号 / ASCII（95 字符） | MAA `PaddleCharOCR`：掉落物数量、理智计数、关卡编号、战局费用、公招计时 | `models/configs/en_PP-OCRv5_mobile_rec.yml` |

---

## 目录结构

```text
OCR/
├── datasets/
│   ├── custom/       # 手工裁剪并标注的补充数据
│   ├── generated/    # 生成的语料、图片、标签与字典（不提交）
│   ├── keys/         # 各语言基础字符字典 (en_US, zh_CN, zh_TW, ja_JP, ko_KR)
│   └── render.yaml   # 合成图片配置
├── game_data/        # 外部游戏数据、字体和 text_renderer（不提交）
├── models/
│   ├── configs/      # PaddleOCR 训练配置 (单语言 / 多语言)
│   ├── output/       # checkpoint 和导出模型（不提交）
│   └── pretrained/   # 下载或链接的预训练模型（不提交）
└── scripts/
    ├── data/         # 语料、标签、数据集合并等处理脚本
    ├── model/        # 模型转换与优化脚本 (pd2onnx, onnx_optimizer)
    └── generate_dataset.sh
```

---

## 依赖管理

数据集生成与模型转换脚本的 Python 依赖由 [uv](https://docs.astral.sh/uv/) 管理：

```bash
# 首次安装依赖（自动生成 .venv 与 uv.lock）
uv sync

# 模型优化（onnx / onnxoptimizer）需要
uv sync --extra model
```

> 注意：`paddle2onnx`（Paddle 静态图转 ONNX）无 Python 3.13+ 的 wheel，请放到 PaddleOCR 环境中安装（`pip install paddle2onnx`）后使用 `scripts/model/pd2onnx.sh`。

---

## 训练方法

> **重要提示**：以下所有脚本与训练命令均需在 **`common/OCR`** 目录下执行（配置中所有数据集与输出路径均以此为基准相对路径）。
> 如果 PaddleOCR 克隆在其他路径，可先设置环境变量 `export PADDLEOCR_DIR="/path/to/PaddleOCR"`。

### 1. 准备环境与代码

```bash
# 克隆 PaddleOCR（已克隆可跳过）
git clone https://github.com/PaddlePaddle/PaddleOCR.git
pip install -r PaddleOCR/requirements.txt
pip install paddle2onnx

# 设置 PaddleOCR 路径（示例指向同级或指定路径）
export PADDLEOCR_DIR="../PaddleOCR"
```

### 2. 生成数据集

`scripts/generate_dataset.sh` 能够同时支持单语言与多语言模式：

```bash
# 模式 A：单语言模式 (默认 en_US，纯数字 / ASCII / 关卡名，约 3 万张图片，生成仅需约 1 分钟)
bash ./scripts/generate_dataset.sh en_US

# 也可以针对其他单语言生成：
# bash ./scripts/generate_dataset.sh zh_CN
# bash ./scripts/generate_dataset.sh ja_JP
# bash ./scripts/generate_dataset.sh ko_KR

# 模式 B：多语言统一模式 (合并 cn/tw/jp/kr/en 5 种客户端数据，生成约 20 万张图片)
bash ./scripts/generate_dataset.sh all
```

> 小规模调试测试可用 `NUM_IMG=200 bash ./scripts/generate_dataset.sh en_US` 覆盖生成图片数量。  
> 如已在本地下载预训练权重，可通过 `LOCAL_PRETRAINED=/path/to/weights.pdparams bash ./scripts/generate_dataset.sh en_US` 指定。

### 3. 开始训练

根据所选目标模型，选择对应的配置文件启动训练：

```bash
# 训练单语言轻量模型 (en_PP-OCRv5_mobile_rec)
# 默认已开启 GPU（NVIDIA 显卡约 3~5 分钟收敛）：
python "$PADDLEOCR_DIR/tools/train.py" -c models/configs/en_PP-OCRv5_mobile_rec.yml

# 若在 CPU 机器上测试，可追加 -o Global.use_gpu=false：
# python "$PADDLEOCR_DIR/tools/train.py" -c models/configs/en_PP-OCRv5_mobile_rec.yml -o Global.use_gpu=false
```

### 4. 评估与导出

```bash
# 评估模型
python "$PADDLEOCR_DIR/tools/eval.py" \
    -c models/configs/en_PP-OCRv5_mobile_rec.yml \
    -o Global.pretrained_model=./models/output/en_PP-OCRv5_mobile_rec/best_accuracy.pdparams

# 导出静态图推理模型
python "$PADDLEOCR_DIR/tools/export_model.py" \
    -c models/configs/en_PP-OCRv5_mobile_rec.yml \
    -o Global.pretrained_model=./models/output/en_PP-OCRv5_mobile_rec/best_accuracy.pdparams \
       Global.save_inference_dir=./models/output/en_PP-OCRv5_mobile_rec/inference
```

---

## 模型转换与部署

```bash
# 1. Paddle 静态图导出为 ONNX（自动识别单语言/多语言导出目录）
bash ./scripts/model/pd2onnx.sh

# 也可显式传入参数指定目录：
# bash ./scripts/model/pd2onnx.sh models/output/en_PP-OCRv5_mobile_rec/inference

# 2. ONNX 算子优化与 Slim（自动识别对应模型并输出 _optimized.onnx）
uv run --extra model python ./scripts/model/onnx_optimizer.py
```

### 部署到 MAA
* **单语言模型**（如 `en_PP-OCRv5_mobile`）：将生成的 ONNX 模型及对应的 `datasets/keys/en_US.txt` 放置到 MAA 的 `resource/PaddleCharOCR/rec/` 目录下。
* **多语言模型**：将生成的 ONNX 模型及合并字典 `datasets/generated/keys.txt` 放置到 MAA 的 `resource/PaddleOCR/rec/` 目录下。
