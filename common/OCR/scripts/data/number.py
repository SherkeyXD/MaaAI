import os
import json
import random
import sys
from typing import Literal, Union, Tuple
import argparse as A
from pathlib import Path

ClientLang = Union[Literal['zh_CN'], Literal['en_US'], Literal['ja_JP'],
                   Literal['ko_KR'], Literal['zh_TW'], ]

# ArknightsGamedata 仓库中的语言目录名（小写）
CLIENT_DIR_MAP = {
    "zh_CN": "cn",
    "zh_TW": "tw",
    "ja_JP": "jp",
    "ko_KR": "kr",
    "en_US": "en",
}


def uniform_exponent_range(base: float, lo: float, hi: float, size: int):
    for _ in range(size):
        exponent = random.uniform(lo, hi)
        yield base**exponent


def generate_stages(stages: Union[dict, str]):
    # open stage json
    if isinstance(stages, (str, Path)):
        with open(stages, 'r', encoding="utf-8") as f:
            stages = json.loads(f.read())['stages']
    # Iterate through all the data with strict deduplication
    stage_codes = set()
    for stage in stages.values():
        code = stage.get('code')
        if not isinstance(code, str) or not code.isascii():
            continue
        code = code.strip()
        # 过滤非关卡代号（排除纯英文势力名/国家名/文件名，保留含数字或连字符的合法代号）
        if (any(c.isdigit() for c in code) or '-' in code) and len(code) <= 12 and not code.endswith(('.png', '.jpg')):
            stage_codes.add(code)
    return sorted(list(stage_codes))


def generate_numbers(lang: ClientLang, counts: Tuple = (1000, 20)):
    numbers = []

    UNITS_BY_LANG = {
        "zh_CN": "万亿",
        "zh_TW": "萬億",
        "ja_JP": "万億",
        "ko_KR": "만억",
        "en_US": "KM",
    }
    for i, count in enumerate(counts):
        unit = UNITS_BY_LANG[lang][i]
        rng = uniform_exponent_range(10, 1, 4, count)
        for v in rng:
            iv = int(v)
            if iv < 1:
                continue
            # 正常格式：12K, 350K，或带一位小数 1.5K, 2.5K（彻底杜绝科学计数法 e+）
            if random.random() < 0.15 and iv < 100:
                numbers.append(f"{v:.1f}{unit}")
            else:
                numbers.append(f"{iv}{unit}")

    # 常用整数 0..1000
    numbers += [str(x) for x in range(0, 1001)]
    return numbers


def generate_other():
    # 1. 单字符与两位补零纯数字
    numbers = ['0' + str(x) for x in range(10)]
    numbers += [str(x) for x in range(10, 100)]

    # 2. 掉落物数量（重点强化高频 x1..x10，兼顾全区间 x1..x99 与大掉落）
    for x in range(1, 11):
        numbers.extend([f"x{x}"] * 8)
    for x in range(11, 100):
        numbers.append(f"x{x}")
    for x in (120, 150, 200, 250, 300, 500, 999):
        numbers.append(f"x{x}")

    # 3. 理智分数与关卡进度（聚焦真实常见上限，彻底杜绝极端荒谬溢出）
    # 常见理智上限：120、125、128、130、135、180、210（及少量萌新低上限 80、100）
    common_sanity_caps = [120, 125, 128, 130, 135, 180, 210]
    low_sanity_caps = [80, 100]
    fractions = []

    for tot in common_sanity_caps:
        # 常规消耗与恢复点位
        cur_values = [
            0, 1, 5, 10, 12, 15, 18, 20, 21, 24, 30, 36, 40, 50, 60, 80,
            100, 120, 125, 128, 130, 135, tot - 10, tot - 5, tot - 1, tot
        ]
        for cur in set(cur_values):
            if cur <= tot:
                fractions.append(f"{cur}/{tot}")
        # 合理轻度溢出（理智药/升级回满）
        for cur in (tot + 1, tot + 10, tot + 60, tot + 100, tot + 120):
            fractions.append(f"{cur}/{tot}")
        # 高上限的大额溢出（如碎石/大体力瓶）
        if tot in (135, 180, 210):
            for cur in (250, 300, 500, 999):
                fractions.append(f"{cur}/{tot}")

    for tot in low_sanity_caps:
        for cur in (0, 1, 10, 20, 36, 50, tot - 1, tot, tot + 10, tot + 60):
            if cur <= tot or cur in (tot + 10, tot + 60):
                fractions.append(f"{cur}/{tot}")

    # 战斗杀敌数 / 任务进度分数
    for tot in (10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 75, 80, 100):
        for cur in (0, 1, 5, 10, tot // 2, tot - 5, tot - 1, tot):
            if 0 <= cur <= tot:
                fractions.append(f"{cur}/{tot}")

    numbers += sorted(list(set(fractions)))

    # 4. 百分比与折扣
    numbers += [f"{x}%" for x in (0, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 99, 100)]

    # 5. 公招计时与日常倒计时（核心业务强化）
    timers = []
    # 公招最常见预设，权重加倍
    recruit_presets = [
        "09:00", "08:00", "07:40", "06:00", "05:00",
        "04:00", "03:00", "02:00", "01:00", "00:00"
    ]
    for p in recruit_presets:
        timers.extend([p] * 5)
    # 0~9 小时全常见分钟
    for h in range(10):
        for m in (0, 10, 20, 30, 40, 50, 58):
            timers.append(f"0{h}:{m:02d}")
    # 带秒倒计时
    timers += [
        "09:00:00", "08:00:00", "07:40:00", "00:00:00",
        "00:01", "00:15", "01:58", "02:30", "03:45", "05:20", "12:00", "18:30", "23:59:59"
    ]
    numbers += timers

    # 6. 战局费用增减、等级与阶段
    numbers += [f"-{x}" for x in range(1, 31)]
    numbers += [f"+{x}" for x in range(1, 31)]
    numbers += [f"Lv.{x}" for x in (1, 10, 20, 30, 40, 50, 60, 70, 80, 90)]
    numbers += ["E0", "E1", "E2", "SLv.1", "SLv.7", "M1", "M2", "M3", "Pot.1", "Pot.6"]

    # 7. 常用基建/关卡常数与大额货币整数
    numbers += [12, 18, 24, 30, 36, 48, 60, 72, 84, 96, 120, 150, 180, 200, 210, 240, 300, 360, 400, 500, 600, 800]
    numbers += [
        1000, 1200, 1500, 2000, 2400, 3000, 3600, 4000, 5000, 6000, 8000,
        10000, 12000, 15000, 20000, 24000, 30000, 50000, 100000, 150000,
        200000, 250000, 300000, 500000, 600000, 1000000
    ]
    numbers = [str(x) for x in numbers]

    # 8. 游戏 UI 关键标语
    numbers += [
        "MISSION", "RESULTS", "EXP", "COMPLETE", "FAILED", "AUTO",
        "SANITY", "DROP", "COST", "STAGE", "PRTS", "PAUSE", "START",
        "DEFEAT", "VICTORY", "LEVEL", "TOTAL", "CLEAR", "RECRUIT"
    ]

    # 9. 保证所有单个 ASCII 字符均出现
    numbers += [chr(x) for x in range(33, 127)]
    return numbers


def main(args):
    output_dir = Path(args.output_dir) / args.lang / "number"
    os.makedirs(output_dir, exist_ok=True)
    f = open(output_dir / 'numbers.txt', 'w', encoding="utf-8")
    # Write stages
    stages = generate_stages(args.game_data / CLIENT_DIR_MAP[args.lang] /
                             "gamedata" / "excel" / "stage_table.json")
    f.write('\n'.join(stages) + '\n')

    # write others
    others = generate_other()
    f.write('\n'.join(others) + '\n')
    # generate numbers
    numbers_size = (args.total, int(args.total * args.ratio_100m))
    numbers = generate_numbers(args.lang, numbers_size)
    f.write('\n'.join(numbers) + '\n')

    f.close()


def parse_args():
    parser = A.ArgumentParser()
    parser.add_argument("--lang",
                        "-l",
                        choices=("zh_CN", "zh_TW", "ja_JP", "ko_KR", "en_US"),
                        help="target language, default to \"zh_CN\"",
                        default="zh_CN")
    parser.add_argument(
        "--game_data",
        "-g",
        default="game_data/ArknightsGamedata",
        type=Path,
        help="path to game data, default to game_data/ArknightsGamedata")
    parser.add_argument("--output_dir", "-o", default="datasets/generated", type=Path)
    parser.add_argument(
        "--ratio_100m",
        "-r",
        default=2 / 100,
        type=float,
        help="proportation for numbers >= 100m, default to 2/1000")
    parser.add_argument("--total",
                        "-t",
                        default=1000,
                        type=int,
                        help="total numbers to be generated, default to 10000")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    main(args)
