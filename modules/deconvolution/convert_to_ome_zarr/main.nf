/*
 * Module: deconvolution/convert_to_ome_zarr
 *
 * Inverts convert_to_tif's per-channel/per-timepoint split: stacks every
 * deconvolved TIFF belonging to one dataset_id/scene into a single CZYX
 * (or TCZYX, when more than one time point is present) OME-Zarr image.
 * The channel_index/time_index/emission alignment between items and tifs
 * is built in the subworkflow's groupTuple — this process just writes a
 * manifest CSV from those parallel lists for the python script to read.
 */

process CONVERT_TO_OME_ZARR {
    tag "${meta.id}_S${meta.scene}"
    container 'TODO: add container image address'

    input:
    tuple val(meta), val(items), path(tifs)

    output:
    tuple val(meta), path("*.ome.zarr"), emit: ome_zarr

    script:
    def manifest_lines = ["channel_index,time_index,emission,filepath"]
    items.eachWithIndex { item, i ->
        manifest_lines << "${item.channel_index},${item.time_index},${item.emission},${tifs[i]}"
    }
    def manifest_csv = manifest_lines.join('\n')
    """
    cat <<'MANIFEST' > manifest.csv
${manifest_csv}
MANIFEST

    convert_to_ome_zarr.py \\
        --dataset_id ${meta.id} \\
        --manifest manifest.csv \\
        --scene ${meta.scene} \\
        --physical_voxel_size_xy_nm ${meta.physical_voxel_size_xy_nm} \\
        --physical_voxel_size_z_nm ${meta.physical_voxel_size_z_nm}
    """

    stub:
    """
    mkdir -p ${meta.id}_S${meta.scene}_deconvolved.ome.zarr
    """
}
