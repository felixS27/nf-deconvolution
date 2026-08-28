# deconvolution/deconwolf

## Summary

Generates a PSF with `dw_bw` (Born & Wolf model) from per-run optical
parameters, then deconvolves the input 3D TIFF with `dw`
(Richardson-Lucy). Emission wavelength (`meta.emission`), z-plane count
(`meta.dim_z`, from the `convert_to_tif` manifest — drives `dw_bw`'s
`--nslice`), and pixel size (`meta.physical_voxel_size_xy_nm` /
`meta.physical_voxel_size_z_nm`, also from the manifest — lateral size
assumes square pixels, so the manifest's `res_y` is not used) are all
per-image; NA, refractive index, iterations, and tile size are shared
across the run and come from params. GPU/CPU mode is
a third input tuple element (`gpu`), not a `meta` key or a global param,
so the subworkflow can retry a failed GPU attempt on CPU by re-invoking
with `gpu = false` — that retry branching lives at the subworkflow
level, not in this module.

On `gpu = true`, a failure whose exit status looks like an OOM kill or a
scheduler timeout (`130..145`, or `104`) is retried up to `maxRetries`
(3), with memory/time scaled per `task.attempt` via the
`withName: 'DECONWOLF_GPU'` block in `nextflow.config`, then ignored so
the subworkflow-level fallback can retry on CPU; any other GPU failure is
ignored immediately. On `gpu = false` (the CPU fallback itself) errors
terminate the run as usual — there's no further fallback.

A process-local safety floor (`min_tile_size`, 128px) rejects
`deconvolution_tile_size` values that would produce degenerate tiles.
`XDG_CONFIG_HOME` is isolated per task so concurrent SLURM tasks don't
race on deconwolf's cache directory; intermediates (`PSF*`, `fftw_*`,
the isolated config dir) are cleaned up on exit, but the `dw_*` output
is left in place.

## Get started

Include this module in your Nextflow pipeline:

```nextflow
include { DECONWOLF } from 'deconvolution/deconwolf'
```

## Optional flags

`--float`, `--bq`, and `--scale` aren't per-image/validated inputs, so
they're set via `task.ext` (the `withName: 'DECONWOLF_GPU'` /
`'DECONWOLF_CPU'` config blocks — this process is included twice under
those aliases) rather than `params`:

```nextflow
process {
    withName: 'DECONWOLF_GPU' {
        ext.float = true   // write float32 output instead of the dw default
        ext.bq    = 2      // boundary quality; defaults to 2 if unset
        ext.scale = 1.5    // must be > 0, otherwise omitted
    }
}
```

## Dependencies

- `deconwolf` (`dw`, `dw_bw`) inside the module's container.
- Optional GPU support requires an OpenCL-capable device and driver;
  `nvidia-smi`/`$CUDA_VISIBLE_DEVICES` are logged when `gpu` is true.

## License

Apache-2.0
