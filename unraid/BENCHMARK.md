# Dense GEMM benchmark on Unraid

This tests PyTorch/cuBLAS matrix multiplication, not Strata or end-to-end LLM
performance. It requests FP32 accumulation (FP16 accumulation and FP16/BF16
reduced-precision reductions disabled). FP16/BF16 outputs still round to their
output dtype. TF32 uses float32 tensors with cuBLAS TF32 enabled. Kernel dispatch
remains up to cuBLAS; profiling is needed to establish exact machine instructions.
The finite-output check is not a full numerical-correctness test.

Defaults: dense 8192 x 8192 x 8192 GEMM; 10 warmups; five timed samples of 20
multiplies; CUDA event timing; TFLOPS = 2*N^3 / elapsed seconds / 10^12.
Allocation, CPU transfers, and initialization are outside the timed regions.
This is comparable in shape and precision intent to reports using torch 2.9,
but is not claimed to reproduce another report's exact harness or results.

Use the official, verified-existing image
`pytorch/pytorch:2.9.0-cuda13.0-cudnn9-runtime` with an appropriate host NVIDIA
driver. No PyTorch installation on the Unraid host is needed.

1. Stop Strata and other workloads using the target GPU. Let any array rebuild
   finish before the reboot-based A/B. Keep the badblocks test and other host
   loads consistent or pause them cleanly; don't reboot during the destructive
   disk test. Stop LACT temporarily or ensure it applies identical limits,
   clock offsets and voltage settings in both arms.
2. Confirm GPU index/identity and set the same power limit for both arms:

```bash
nvidia-smi --query-gpu=index,name,uuid,power.limit --format=csv
nvidia-smi -i 0 -pl 250
```

3. From the fork checkout, test the unlocked arm (replace index 0 if necessary):

```bash
mkdir -p bench-results
docker run --rm --gpus device=0 \
  --mount "type=bind,src=$PWD/unraid/benchmark.py,dst=/bench.py,readonly" \
  pytorch/pytorch:2.9.0-cuda13.0-cudnn9-runtime \
  python /bench.py --label unlocked-250W \
  > bench-results/unlocked-250W.json
```

The script refuses to run if more than one GPU is visible. The second card is
not benchmarked. Progress/summary goes to stderr and the complete JSON goes to
the results file. Pull the image once beforehand if you want the measured run
to start without waiting for its download.

4. Save host context alongside each arm:

```bash
nvidia-smi -q -i 0 > bench-results/unlocked-gpu.txt
dmesg | grep -Ei 'gpu.unlock|NVRM: loading' > bench-results/unlocked-boot.txt
```

5. Disable the unlock using the marker that matches your installation:

```bash
# Fork's generalized scripts:
touch /boot/config/gpu-unlock-unraid/disabled
# Earlier interactive setup instead:
# touch /boot/config/gpu-unlock.disable
```

Reboot cleanly, restore the same 250 W limit/settings, confirm the unlock did
not run, and repeat with `--label locked-250W`, saving to a different file.
To re-enable, remove the applicable marker and reboot. Do not unload/reload or
unbind NVIDIA to change arms. Keep the same image; record its image ID/digest.

Repeat each arm, preferably alternating boot states. Keep thermal conditions
and background loads comparable. Report all five samples and medians, the
driver, exact image, matrix shape, precision flags and power/clock settings.
A higher GEMM rate does not establish a Strata speedup; benchmark Strata
separately with identical model, prompt, context, vision and cache settings.

References: [PyTorch 2.9 CUDA backend flags](https://github.com/pytorch/pytorch/blob/v2.9.0/torch/backends/cuda/__init__.py),
[upstream benchmark report](https://github.com/Zagitta/gpu-unlock/issues/1).
