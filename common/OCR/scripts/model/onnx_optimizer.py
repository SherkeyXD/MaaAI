import argparse
from pathlib import Path
import onnx
import onnxoptimizer

default_input = None
for candidate in [
    Path("models/output/en_PP-OCRv5_mobile_rec/inference.onnx"),
    Path("models/output/PP-OCRv6_medium_rec/inference.onnx"),
]:
    if candidate.exists():
        default_input = str(candidate)
        break
if not default_input:
    default_input = "models/output/en_PP-OCRv5_mobile_rec/inference.onnx"

parser = argparse.ArgumentParser()
parser.add_argument("input", nargs="?", default=default_input, help="Input ONNX model path")
parser.add_argument("output", nargs="?", help="Output optimized ONNX model path")
args = parser.parse_args()

input_path = Path(args.input)
output_path = Path(args.output) if args.output else input_path.with_name(f"{input_path.stem}_optimized{input_path.suffix}")

print(f"Optimizing ONNX: {input_path} -> {output_path}")
model = onnx.load(str(input_path))
new_model = onnxoptimizer.optimize(model)
onnx.save(new_model, str(output_path))
print("Optimization complete!")
