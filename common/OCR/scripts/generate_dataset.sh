#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "国内用户请挂代理，或者自己想办法将以下 repo 及字体资源放到对应目录下"

# 依赖由 uv 管理（pyproject.toml + uv.lock）
if ! command -v uv > /dev/null 2>&1; then
    echo "未找到 uv，请先安装（如 brew install uv / 或参考 https://docs.astral.sh/uv/）"
    exit 1
fi
uv sync
# 用 uv run 代替 activate，避免依赖 venv 目录结构（Windows 为 Scripts/，类 Unix 为 bin/）
PY="uv run python"

# 目标设定：
# 1. 单语言模型模式：如 en_US (默认，用于纯数字/ASCII/关卡名)、zh_CN、zh_TW、ja_JP、ko_KR
#    示例：bash scripts/generate_dataset.sh en_US
# 2. 多语言统一模型模式：all 或 multi (全客户端数据合并为一份)
#    示例：bash scripts/generate_dataset.sh all
TARGET="${1:-${TARGET_LANG:-en_US}}"

case "$TARGET" in
    all|multi|multilingual)
        echo "=== 模式：多语言统一模型数据生成 ==="
        clients=(zh_CN:CN zh_TW:TW ja_JP:JP ko_KR:KR en_US:CN)
        font_subsets=(CN TW JP KR)
        num_img="${NUM_IMG:-200000}"
        ;;
    en_US|en)
        echo "=== 模式：单语言纯数字 / ASCII / 英文数据生成 (en_US) ==="
        clients=(en_US:CN)
        font_subsets=(CN)
        num_img="${NUM_IMG:-30000}"
        ;;
    zh_CN|cn)
        echo "=== 模式：单语言简体中文数据生成 (zh_CN) ==="
        clients=(zh_CN:CN)
        font_subsets=(CN)
        num_img="${NUM_IMG:-50000}"
        ;;
    zh_TW|tw)
        echo "=== 模式：单语言繁体中文数据生成 (zh_TW) ==="
        clients=(zh_TW:TW)
        font_subsets=(TW)
        num_img="${NUM_IMG:-50000}"
        ;;
    ja_JP|jp)
        echo "=== 模式：单语言日文数据生成 (ja_JP) ==="
        clients=(ja_JP:JP)
        font_subsets=(JP)
        num_img="${NUM_IMG:-50000}"
        ;;
    ko_KR|kr)
        echo "=== 模式：单语言韩文数据生成 (ko_KR) ==="
        clients=(ko_KR:KR)
        font_subsets=(KR)
        num_img="${NUM_IMG:-50000}"
        ;;
    *)
        echo "未知目标: $TARGET，可选值: en_US, zh_CN, zh_TW, ja_JP, ko_KR, all"
        exit 1
        ;;
esac

game_data_dir="game_data/ArknightsGamedata"
renderer_dir="game_data/text_renderer"
fonts_dir="game_data/fonts"
pretrained_model="models/pretrained"

mkdir -p "$game_data_dir" "$renderer_dir" "$fonts_dir" "$pretrained_model" "datasets/generated"

if [ ! -d "$game_data_dir/.git" ]; then
    git clone https://github.com/ArknightsAssets/ArknightsGamedata.git --depth=1 "$game_data_dir"
else
    git -C "$game_data_dir" pull --ff-only || true
fi

if [ ! -d "$renderer_dir/.git" ]; then
    git clone https://github.com/Sanster/text_renderer --depth=1 "$renderer_dir"
else
    git -C "$renderer_dir" pull --ff-only || true
fi
# text_renderer 依赖 Pillow 10+ 已移除的 API，打兼容补丁（幂等）
$PY ./scripts/data/patch_text_renderer.py

download_file() {
    local url="$1"
    local dest_dir="$2"
    local filename="${3:-$(basename "$url")}"
    local dest="$dest_dir/$filename"

    if [ -f "$dest" ]; then
        return 0
    fi
    mkdir -p "$dest_dir"
    if command -v curl > /dev/null 2>&1; then
        echo "下载 $filename ..."
        curl -fL "$url" -o "$dest"
    elif command -v wget > /dev/null 2>&1; then
        echo "下载 $filename ..."
        wget -nc "$url" -O "$dest"
    else
        echo "错误: 未找到 curl 或 wget，请先安装网络下载工具"
        exit 1
    fi
}

for fl in "${font_subsets[@]}"; do
    if [ ! -d "$fonts_dir/SubsetOTF/$fl" ]; then
        download_file \
            "https://github.com/adobe-fonts/source-han-sans/releases/download/2.004R/SourceHanSans${fl}.zip" \
            "$fonts_dir" \
            "SourceHanSans${fl}.zip"
        unzip -oq "$fonts_dir/SourceHanSans${fl}.zip" -d "$fonts_dir"
    fi
done

# 预训练权重配置
if [ "$TARGET" = "en_US" ] || [ "$TARGET" = "en" ]; then
    TARGET_PRETRAINED="$pretrained_model/en_PP-OCRv5_mobile_rec_pretrained.pdparams"
    LOCAL_PRETRAINED="${LOCAL_PRETRAINED:-}"
    if [ -n "$LOCAL_PRETRAINED" ] && [ -f "$LOCAL_PRETRAINED" ] && [ ! -f "$TARGET_PRETRAINED" ]; then
        echo "发现指定的本地预训练模型，复制到项目目录: $LOCAL_PRETRAINED"
        cp "$LOCAL_PRETRAINED" "$TARGET_PRETRAINED"
    elif [ ! -f "$TARGET_PRETRAINED" ]; then
        echo "下载 en_PP-OCRv5_mobile 预训练模型..."
        download_file \
            "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_pretrained_model/en_PP-OCRv5_mobile_rec_pretrained.pdparams" \
            "$pretrained_model" \
            "en_PP-OCRv5_mobile_rec_pretrained.pdparams"
    fi
elif [ "$TARGET" = "all" ] || [ "$TARGET" = "multi" ]; then
    if [ ! -f "$pretrained_model/PP-OCRv6_medium_rec_pretrained.pdparams" ]; then
        download_file \
            "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_pretrained_model/PP-OCRv6_medium_rec_pretrained.pdparams" \
            "$pretrained_model" \
            "PP-OCRv6_medium_rec_pretrained.pdparams"
    fi
fi

###### 以下是离线操作了 ######

for item in "${clients[@]}"; do
    client="${item%%:*}"
    font_lang="${item##*:}"
    echo "=== 生成 $client 数据 ==="
    ls "$fonts_dir/SubsetOTF/$font_lang"/* > "$fonts_dir/fonts_${client}.txt"

    $PY ./scripts/data/wording.py "$client"
    $PY ./scripts/data/number.py -l "$client"

    num_img_fraction=$((num_img / 100))
    if [ "$client" = "en_US" ]; then
        # en_US / ASCII 场景重点强化数字、关卡代号、DP、公招时间与简短文本
        num_short_img=$((num_img_fraction * 35))
        num_long_img=$((num_img_fraction * 15))
        num_number_img=$((num_img_fraction * 50))
    else
        num_short_img=$((num_img_fraction * 30))
        num_long_img=$((num_img_fraction * 60))
        num_number_img=$((num_img_fraction * 10))
    fi
    output="datasets/generated/render"
    fonts_list="$fonts_dir/fonts_${client}.txt"

    $PY "$renderer_dir/main.py" --fonts_list "$fonts_list" --config_file datasets/render.yaml --img_width=0 --corpus_dir "datasets/generated/$client/short/" --corpus_mode=list --num_img "$num_short_img" --chars_file="datasets/generated/$client/keys_render.txt" --strict --output_dir="$output/$client/short"
    $PY "$renderer_dir/main.py" --fonts_list "$fonts_list" --config_file datasets/render.yaml --img_width=0 --corpus_dir "datasets/generated/$client/long/" --corpus_mode=chn --length=7 --num_img "$num_long_img" --chars_file="datasets/generated/$client/keys_render.txt" --strict --output_dir="$output/$client/long"
    $PY "$renderer_dir/main.py" --fonts_list "$fonts_list" --config_file datasets/render.yaml --img_width=0 --corpus_dir "datasets/generated/$client/number/" --corpus_mode=list --num_img "$num_number_img" --chars_file="datasets/generated/$client/keys_render.txt" --strict --output_dir="$output/$client/number"

    $PY ./scripts/data/train_test_split.py "$output/$client/short/default/tmp_labels.txt" -o "$output/$client/short/default"
    $PY ./scripts/data/train_test_split.py "$output/$client/long/default/tmp_labels.txt" -o "$output/$client/long/default"
    $PY ./scripts/data/train_test_split.py "$output/$client/number/default/tmp_labels.txt" -o "$output/$client/number/default"

    $PY ./scripts/data/build_ppocr_labels.py "$output/$client" "datasets/generated/$client" "$client"
done

# 整理合并字典与数据集（写入 datasets/generated/keys.txt, rec_gt_train.txt, rec_gt_test.txt）
langs=()
for item in "${clients[@]}"; do langs+=("${item%%:*}"); done
$PY ./scripts/data/merge_dataset.py --langs "${langs[@]}"
echo "=== 数据集生成完成 (目标: $TARGET) ==="
