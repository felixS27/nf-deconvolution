# deconvolution

## Summary

Chains the three deconvolution stages: `convert_to_tif` → `deconwolf` →
`convert_to_ome_zarr`.

Each `convert_to_tif` manifest row (one per time point) is split into its
own `deconwolf` call, with a per-row `meta.internal_id` built from
dataset id + whichever of channel/time/scene are available (kept separate
from `meta.id`, which stays the plain dataset id), plus
`dim_z`/`physical_voxel_size_*_nm`/`time_index` pulled from the manifest.

`params.deconvolution_with_gpu` (default `true`) selects the branch:
- **GPU (default):** every row runs on GPU (`gpu = true`); rows where
  `DECONWOLF_GPU` exhausted its retries or hit a non-resource failure (see
  `modules/deconvolution/deconwolf`) are detected via a join-with-remainder
  against the original input and re-run through `DECONWOLF_CPU` with
  `gpu = false`.
- **CPU-only:** every row runs directly through `DECONWOLF_CPU`
  (`gpu = false`), no GPU attempt, no fallback.

Deconvolved tifs are then regrouped by `(meta.id, meta.scene ?: 0)` — the
inverse of `convert_to_tif`'s per-channel/per-timepoint fan-out — so every
channel/time point belonging to one scene is combined by
`convert_to_ome_zarr` into a single CZYX (or TCZYX) OME-Zarr image.

**Status:** all three stages are wired in, including the GPU/CPU branch,
the GPU→CPU fallback, and the channel/scene regrouping ahead of
`convert_to_ome_zarr`. `params.deconvolution_with_gpu` is defined in
`nextflow.config` (default `true`).

## Get started

Include this subworkflow in your Nextflow pipeline:

```nextflow
include { DECONVOLUTION } from './subworkflows/deconvolution/main.nf'

workflow {
    ch_input = Channel.of([[id: 'sample1', emission: 525, channel_index: 0], file('sample1.zarr')])
    DECONVOLUTION(ch_input)
}
```

`meta` required keys: `id` (dataset id), `emission` (nm), `channel_index` (int).
Optional: `time_indices` (list of int, default all present), `scene` (int, default 0).

## Dependencies

- `modules/deconvolution/convert_to_tif`
- `modules/deconvolution/deconwolf`
- `modules/deconvolution/convert_to_ome_zarr`
