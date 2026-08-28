# deconvolution/convert_to_ome_zarr

## Summary

Inverts `convert_to_tif`'s per-timepoint split: stacks every deconvolved
TIFF belonging to one `dataset_id`/`channel_index`/`scene` into a single
OME-Zarr image — ZYX, or TZYX when more than one time point is present.
Physical voxel size (`meta.physical_voxel_size_xy_nm`/`_z_nm`, assumes
square pixels) is written as the OME-Zarr scale transform, in micrometers.
Writes a single resolution level — no multiscale pyramid.

Grouping into one `(dataset_id, channel_index, scene)` set is done by the
`deconvolution` subworkflow's `groupTuple`; this module then recovers each
TIFF's time index directly from its filename (`_T<time>_C<channel>`,
written by `convert_to_tif` and preserved through `dw`'s `dw_` prefix)
rather than from separate per-tif metadata.

## Get started

Include this module in your Nextflow pipeline:

```nextflow
include { CONVERT_TO_OME_ZARR } from 'deconvolution/convert_to_ome_zarr'
```

## Dependencies

- `dask`, `bioio`, `bioio-ome-zarr` (Python) inside the module's container — see `resources/usr/bin/convert_to_ome_zarr.py`.

## License

Apache-2.0
