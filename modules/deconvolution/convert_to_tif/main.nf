/*
 * Module: deconvolution/convert_to_tif
 *
 * Splits a bioio-readable image (OME-Zarr, TIFF, ...) into one 3D (ZYX)
 * TIFF per requested time point, for a single channel (meta.channel_index)
 * — the channel matching the emission wavelength already fixed for this
 * task's meta — and writes a manifest CSV
 * (res_x,res_y,res_z,dim_z,filepath) listing every TIFF produced, for
 * consumption by the deconwolf module.
 */

process CONVERT_TO_TIF {
    tag "$meta.id"
    label 'process_low'
    container 'TODO: add container image address'

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
    """
    touch ${meta.id}_T0_C0.tif
    echo "res_x,res_y,res_z,dim_z,filepath" > ${meta.id}_deconvolution_input.csv
    echo "0.0,0.0,0.0,2,\$PWD/${meta.id}_T0_C0.tif" >> ${meta.id}_deconvolution_input.csv
    """
}
