# Kvasir brand assets

Kvasir is the wisest being in Norse myth, made when the gods pooled their
knowledge into one. The name fits a mixture-of-experts model: one answer
drawn from 512 experts per layer.

The mark is three stacked layers with a terminal prompt on the top one. The
layers stand for where the model lives while it serves: VRAM, system RAM and
NVMe ([architecture](architecture.md#where-the-model-lives-while-serving)).
The prompt says it is a tool for terminal agents. At 32 px the prompt fades
and the mark reads as a plain stack.

Colours: accent violet `#b48cff` (top layer, wordmark tail, outline), middle
layer `#8f6ae6`, bottom layer `#6a4bb8`, tile `#171328`. On light surfaces the
outline and wordmark tail use `#7a52d6` and the wordmark text `#1a1530`.
Violet was chosen because no sibling repo uses it.

| Asset | Use |
| --- | --- |
| [`icon.svg`](../icon.svg) | Square app icon and README heading. |
| [`logo.svg`](brand/logo.svg) | Horizontal wordmark on a dark surface. |
| [`logo-light.svg`](brand/logo-light.svg) | Horizontal wordmark on a light surface. |
| [`preview.svg`](brand/preview.svg) | Editable README hero layout. |
| [`preview.png`](../preview.png) | Rendered README hero at 3840 × 2160. |

The logo SVGs and the preview inline the mark so they render standalone; keep
the paths in sync when changing the icon. Wordmarks use live SVG text in
JetBrainsMono Nerd Font, so the font can vary where it is not installed.

Keep clear space around the mark, and the wordmark as one word with a capital
K: **Kvasir**, set entirely in the accent colour. This project has no UI to capture: the hero's terminal
cards are drawn from real command output. The
[development runbook](runbooks/development.md#refresh-the-preview) explains
how to update and re-render them.
