# Choose hardware and a model

## What you need

- Linux x86-64 with Docker and Compose v2.
- A GPU with a Strata engine:
  - NVIDIA RTX 20-50 series with driver 580 or newer, plus the
    [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
    Older cards or drivers 575-579 use the `cuda12` image.
  - AMD RX 7000, RX 9000, Radeon AI PRO R9700 or Strix Halo with the `amdgpu`
    kernel driver. **Untested by this project**; reports welcome.
- Enough **system RAM** for the experts (table below). This, not VRAM, decides
  which sizes run.
- About 105 GB free on an **NVMe** drive per model size
  ([ADR 5](../adr/0005-keep-model-data-on-nvme.md)).
- A CPU with AVX2.

## Pick the image

Set `STRATA_IMAGE` and `GPU_VENDOR` in `.env`:

| Card | `STRATA_IMAGE` tag | `GPU_VENDOR` |
| --- | --- | --- |
| NVIDIA RTX 20-50, driver 580+ | `0.2.7-cuda13` | `nvidia` |
| NVIDIA Pascal/Volta, or driver 575-579 | `0.2.7-cuda12` | `nvidia` |
| AMD RX 9000, Radeon AI PRO R9700 | `0.2.7-rocm-gfx120x` | `amd` |
| AMD RX 7000 | `0.2.7-rocm-gfx110x` | `amd` |
| AMD Ryzen AI Max (Strix Halo) | `0.2.7-rocm-gfx1151` | `amd` |

A wrong pick does no harm: the container says the engine does not fit the card
and stops.

## Pick the model size

Strata keeps one shard's experts in RAM. A size fits when RAM is at least its
experts plus about 10 GB for the system (figures from Strata's model guide):

| `MODEL` | Experts in RAM | RAM to plan for | Notes |
| --- | ---: | ---: | --- |
| `Q2_0` | 34 GB | 44 GB+ | Default. Fastest; 100/100 on the hard canary. |
| `IQ2_XS` | 35.5 GB | 46 GB+ | |
| `IQ3_XXS` | 43 GB | 53 GB+ | |
| `IQ3_S` | 50 GB | 60 GB+ | Closest to the full model; tight on 64 GB. |
| `IQ1_M` with `FAMILY=coder` | 23 GB | 33 GB+ | Half the experts, chosen for code; weaker elsewhere. |

A bigger graphics card makes a size faster; it does not reduce the RAM needed.
Run `make plan` after changing `MODEL` to see the download before committing
to it.

## Measured reference points

Decode speed in tokens per second on cold prompts, Q2_0 unless noted:

| Hardware | Decode | Source |
| --- | ---: | --- |
| RTX 5090 32 GB, Basalt engine | 377-400 | Akita |
| RTX 5090 32 GB, Strata | 245-270 | Akita |
| **RTX 4080 16 GB, 60 GB RAM, this repo** | **113-131** | [benchmarks](benchmarks.md) |
| RTX 5060 Ti 16 GB, 64 GB RAM (abliterated Q2_0) | 68-73 | Strata community results |
| Strix Halo, 64 GB GPU memory | 55-65 | Akita |

Basalt is a Strata fork for RTX 50-series (Blackwell) cards only.
