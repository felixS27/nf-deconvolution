# deconvolution/convert_to_tif

## Summary

Splits a bioio-readable image (OME-Zarr, TIFF, ...) into one 3D (ZYX) TIFF
per requested time point, for a single channel, and writes a manifest CSV
(`res_x,res_y,res_z,dim_z,channel_index,time_index,scene,filepath`)
listing every TIFF produced, for consumption by the `deconwolf` module and
the `deconvolution` subworkflow — `res_x/res_y/res_z` are the pixel sizes
in nm, `dim_z` is the number of z-planes (drives `deconwolf`'s PSF
`--nslice`), and `channel_index`/`time_index`/`scene` identify each row so
downstream steps can key on them without parsing the tif filename. Images
that are already a single-timepoint, single-channel, single-scene TIFF are
copied through unchanged rather than re-encoded. Raises an error if the
input image is 2D.

Only one channel is ever extracted per run, via the required
`meta.channel_index` — a multi-channel image needs one CSV row (and one
`CONVERT_TO_TIF` call) per channel, since each channel's emission
wavelength must stay paired with its own extracted data; fanning out
across all channels in a single call would silently mislabel every
channel but one with the wrong emission. Optional `meta` keys further
restrict which planes are processed: `scene` (default 0) and
`time_indices` (default: all present).

## Get started

Include this module in your Nextflow pipeline:

```nextflow
include { CONVERT_TO_TIF } from 'deconvolution/convert_to_tif'
```

## Dependencies

- `bioio` and `tifffile` (Python) inside the module's container — see `resources/usr/bin/convert_to_tif.py`.

## License

Apache-2.0
