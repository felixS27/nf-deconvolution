/*
 * Module: deconvolution/convert_to_tif
 *
 * Splits a bioio-readable image (OME-Zarr, TIFF, ...) into one 3D (ZYX)
 * TIFF per requested time point, for a single channel (meta.channel_index)
 * — the channel matching the emission wavelength already fixed for this
 * task's meta — and writes a manifest CSV
 * (res_x,res_y,res_z,dim_z,channel_index,time_index,scene,filepath)
 * listing every TIFF produced, for consumption by the deconwolf module
 * and the subworkflow (channel_index/time_index/scene let it key each
 * row without parsing the tif filename).
 */

process CONVERT_TO_TIF {
    tag "$meta.id"
    container 'ghcr.io/felixs27/bioio:3.5.0'

    input:
    tuple val(meta), path(image)

    output:
    tuple val(meta), path("*_deconvolution_input.csv"), emit: deconvolution_input

    script:
    def scene_arg = meta.scene != null ? "--scene ${meta.scene}" : ""
    def time_arg   = meta.time_indices ? "--time_indices ${meta.time_indices.join(' ')}" : ""
    """
    convert_to_tif.py \\
        --dataset_id ${meta.id} \\
        --filepath ${image} \\
        --channel_index ${meta.channel_index} \\
        ${scene_arg} \\
        ${time_arg}
    """

    stub:
    def stub_tif = "${meta.id}_T0_C${meta.channel_index}.tif"
    """
    touch ${stub_tif}
    echo "res_x,res_y,res_z,dim_z,channel_index,time_index,scene,filepath" > ${meta.id}_deconvolution_input.csv
    echo "0.0,0.0,0.0,2,${meta.channel_index},0,${meta.scene ?: 0},\$PWD/${stub_tif}" >> ${meta.id}_deconvolution_input.csv
    """
}
