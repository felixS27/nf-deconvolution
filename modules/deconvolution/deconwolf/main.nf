/*
 * Module: deconvolution/deconwolf
 *
 * Generates a PSF with dw_bw (Born & Wolf model) from per-run optical
 * parameters, then deconvolves the input TIFF with dw (Richardson-Lucy).
 * Emission wavelength (meta.emission), z-plane count (meta.dim_z), and
 * pixel size (meta.physical_voxel_size_xy_nm/_z_nm) all stay per-image —
 * sourced from the convert_to_tif manifest (xy assumes square pixels,
 * so the manifest's res_y is not used). NA, ni, iterations, tile size,
 * and boundary quality are shared across the run and come from params.
 * GPU/CPU mode is a third tuple input
 * (gpu), not a meta key or global param, so the subworkflow can retry a
 * failed GPU attempt on CPU by re-invoking with gpu = false — the retry
 * branching itself lives at the subworkflow level, not here.
 * XDG_CONFIG_HOME is isolated per task so concurrent SLURM tasks don't
 * race on deconwolf's cache directory.
 */

process DECONWOLF {
    tag "$meta.id"
    label 'process_high'
    container 'TODO: add container image address'

    input:
    tuple val(meta), path(image), val(gpu)

    output:
    tuple val(meta), path("dw_*.tif"), emit: deconvolved

    script:
    def min_tile_size = 128 // safety floor: tiles smaller than this produce severe boundary artifacts
    if (params.deconvolution_tile_size && params.deconvolution_tile_size < min_tile_size) {
        error "deconvolution_tile_size (${params.deconvolution_tile_size}) is below the minimum safe tile size (${min_tile_size})"
    }
    def gpu_diagnostics = gpu ?
        'echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"\nnvidia-smi || echo "nvidia-smi unavailable"' : ""
    def gpu_args  = gpu ? "--gpu" : "--threads ${task.cpus}"
    def tile_args = params.deconvolution_tile_size ? "--tilesize ${params.deconvolution_tile_size}" : ""
    def nslice    = meta.dim_z
    """
    ${gpu_diagnostics}

    export XDG_CONFIG_HOME=\$PWD/.config
    mkdir -p \$XDG_CONFIG_HOME/deconwolf
    trap 'rm -f PSF* fftw_*; rm -rf "\$XDG_CONFIG_HOME"' EXIT

    dw_bw \\
        --resxy ${meta.physical_voxel_size_xy_nm} \\
        --resz ${meta.physical_voxel_size_z_nm} \\
        --NA ${params.microscope_NA} \\
        --ni ${params.microscope_ni} \\
        --lambda ${meta.emission} \\
        --nslice ${nslice} \\
        --overwrite \\
        PSF.tif

    dw \\
        --iter ${params.deconvolution_iter} \\
        ${gpu_args} \\
        ${tile_args} \\
        --bq ${params.deconvolution_bq} \\
        --overwrite \\
        --tempdir \$PWD \\
        --out \$PWD \\
        ${image} \\
        PSF.tif
    """

    stub:
    """
    touch dw_${image}
    """
}
