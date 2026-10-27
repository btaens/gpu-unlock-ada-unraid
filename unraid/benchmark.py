#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""PyTorch/cuBLAS dense GEMM microbenchmark; run in the documented CUDA container."""
import argparse
import json
import platform
import statistics
import sys


def main():
    import torch

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, default=8192)
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--label", required=True, help="e.g. unlocked-250W or locked-250W")
    args = parser.parse_args()
    if min(args.size, args.samples, args.iterations, args.warmup) < 1:
        parser.error("sizes and counts must be positive")
    if not torch.cuda.is_available():
        parser.error("CUDA is unavailable")
    if torch.cuda.device_count() != 1:
        parser.error("Expose only the target GPU with docker --gpus device=INDEX")
    # Pin cuBLAS rather than silently using the cuBLASLt preference.
    torch.backends.cuda.preferred_blas_library("cublas")
    torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction = False
    torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction = False
    torch.backends.cuda.matmul.allow_fp16_accumulation = False
    torch.manual_seed(1234)
    report = {
        "label": args.label,
        "torch": torch.__version__,
        "cuda_runtime": torch.version.cuda,
        "kernel": platform.release(),
        "gpu": torch.cuda.get_device_name(0),
        "compute_capability": torch.cuda.get_device_capability(0),
        "blas_preference": str(torch.backends.cuda.preferred_blas_library()),
        "matrix_size": args.size,
        "samples": args.samples,
        "iterations_per_sample": args.iterations,
        "warmup_iterations": args.warmup,
        "fp16_accumulation_allowed": torch.backends.cuda.matmul.allow_fp16_accumulation,
        "fp16_reduced_precision_reduction": torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction,
        "bf16_reduced_precision_reduction": torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction,
        "results": [],
    }
    with torch.inference_mode():
        for name, dtype in [("FP16", torch.float16), ("BF16", torch.bfloat16), ("TF32", torch.float32)]:
            torch.backends.cuda.matmul.allow_tf32 = name == "TF32"
            a = torch.randn(args.size, args.size, device="cuda", dtype=dtype)
            b = torch.randn_like(a)
            out = torch.empty_like(a)
            for _ in range(args.warmup):
                torch.mm(a, b, out=out)
            torch.cuda.synchronize()
            times = []
            for _ in range(args.samples):
                start = torch.cuda.Event(enable_timing=True)
                end = torch.cuda.Event(enable_timing=True)
                start.record()
                for _ in range(args.iterations):
                    torch.mm(a, b, out=out)
                end.record()
                end.synchronize()
                times.append(start.elapsed_time(end) / args.iterations)
            if not torch.isfinite(out).all().item():
                raise RuntimeError(f"{name}: non-finite output; result rejected")
            rates = [2 * args.size**3 / (ms * 1e9) for ms in times]
            row = {"input": name, "milliseconds": times, "tflops": rates,
                   "median_tflops": statistics.median(rates),
                   "output_dtype": str(out.dtype), "finite_output": True}
            report["results"].append(row)
            print(f"{name}: {row['median_tflops']:.2f} TFLOPS (median of {args.samples})", file=sys.stderr, flush=True)
            del a, b, out
            torch.cuda.empty_cache()
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
