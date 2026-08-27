# deconvolution/convert_to_ome_zarr

## Summary

Inverts `convert_to_tif`'s per-channel/per-timepoint split: stacks every
deconvolved TIFF belonging to one `dataset_id`/`scene` into a single
OME-Zarr image — CZYX, or TCZYX when more than one time point is present.
Channel labels in the output's `omero` metadata are taken from each
channel's emission wavelength. Physical voxel size (`meta.physical_voxel_size_xy_nm`/
`_z_nm`, assumes square pixels) is written as the OME-Zarr scale transform,
in micrometers. Writes a single resolution level — no multiscale pyramid.

The `items`/`tifs` alignment (which entry in `items` describes which file
in `tifs`) is built by the `deconvolution` subworkflow's `groupTuple`; this
module's `script:` writes that into a manifest CSV
(`channel_index,time_index,emission,filepath`) for the python script to
read, rather than parsing it back out of TIFF filenames.

## Get started

Include this module in your Nextflow pipeline:

```nextflow
include { CONVERT_TO_OME_ZARR } from 'deconvolution/convert_to_ome_zarr'
```

## Dependencies

- `dask`, `bioio`, `bioio-ome-zarr` (Python) inside the module's container — see `resources/usr/bin/convert_to_ome_zarr.py`.

## License

Apache-2.0
