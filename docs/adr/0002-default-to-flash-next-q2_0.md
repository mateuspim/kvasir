# 2. Default to Qwen3.8 Flash-Next Q2_0

- Status: Accepted
- Date: 2026-10-29 (documented from the code)

## Context

Strata offers Flash-Next at Q2_0, IQ2_XS, IQ3_XXS and IQ3_S from ISTA-DASLab,
and larger Unsloth files. Lower bits use less RAM and run faster; the question
is what they cost in coding quality.

In Akita's runs on an RTX 5090, Q2_0 and IQ3_S both scored 100 on the hard
canary in three of three runs each, and Q2_0 finished sooner. UD-Q4_K_XL was
killed for running out of memory. Strata's documentation says a size fits when
RAM is at least its experts plus about 10 GB: 34 GB of experts for Q2_0, 43 GB
for IQ3_XXS, 50 GB for IQ3_S.

## Decision

`.env.example` sets `FAMILY=qwen`, `MODEL=Q2_0`, `CONTEXT=128k`, `KV=int8`:
the ISTA-DASLab original that fits a 48 GB machine, at the context and KV
format Akita measured.

## Consequences

- Fits more machines than any other full-expert size, and is the fastest.
- Akita reports Basalt's measurement of top-token agreement with Q8_0 at 78%
  for Q2_0 against 87% for IQ3_S. Users with RAM to spare can move to IQ3_XXS
  or IQ3_S by changing `MODEL`.
- Coding tests so far cover small Python projects up to about 113K tokens of
  context. Behaviour on large codebases is untested.
- Abliterated derivatives exist on Hugging Face but are not the default: none
  has a published coding-quality result.
