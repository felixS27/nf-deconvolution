/*
 * Module: deconvolution/convert_to_ome_zarr
 *
 * Inverts convert_to_tif's per-timepoint split: stacks every deconvolved
 * TIFF belonging to one dataset_id/channel_index/scene into a single ZYX
 * (or TZYX, when more than one time point is present) OME-Zarr image.
 * channel_index/emission are constant for the whole invocation (meta).
 * Time ordering is recovered by the python script directly from each
 * TIFF's filename (`_T<time>_C<channel>`, written by convert_to_tif and
 * preserved through dw's `dw_` prefix) — no separate per-tif metadata
 * needs to travel alongside the files.
 */

process CONVERT_TO_OME_ZARR {
    tag "${meta.id}_C${meta.channel_index}_S${meta.scene}"
    container 'ghcr.io/felixs27/bioio:3.5.0'

    input:
    tuple val(meta), path(tifs)

    output:
    tuple val(meta), path("*.ome.zarr"), emit: ome_zarr

    script:
    """
    convert_to_ome_zarr.py \\
        --dataset_id ${meta.id} \\
        --channel_index ${meta.channel_index} \\
        --scene ${meta.scene} \\
        --physical_voxel_size_xy_nm ${meta.physical_voxel_size_xy_nm} \\
        --physical_voxel_size_z_nm ${meta.physical_voxel_size_z_nm} \\
        --tifs ${tifs}
    """

    stub:
    """
    mkdir -p ${meta.id}_C${meta.channel_index}_S${meta.scene}_deconvolved.ome.zarr
    """
}
