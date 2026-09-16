#!/usr/bin/env bash
set -euo pipefail

if ! command -v paddle2onnx > /dev/null 2>&1; then
    echo "未找到 paddle2onnx，请先在 PaddleOCR 环境中安装：pip install paddle2onnx"
    exit 1
fi

MODEL_DIR="${1:-./models/output/en_PP-OCRv5_mobile_rec/inference}"
SAVE_FILE="${2:-./models/output/en_PP-OCRv5_mobile_rec/inference.onnx}"

if [ -f "$MODEL_DIR/inference.json" ]; then
    MODEL_FILE="inference.json"
else
    MODEL_FILE="inference.pdmodel"
fi

echo "正在将 $MODEL_DIR ($MODEL_FILE) 转换为 ONNX: $SAVE_FILE ..."

paddle2onnx \
    --model_dir "$MODEL_DIR" \
    --model_filename "$MODEL_FILE" \
    --params_filename inference.pdiparams \
    --save_file "$SAVE_FILE" \
    --opset_version 11 \
    --enable_dev_version True

echo "转换完成: $SAVE_FILE"
