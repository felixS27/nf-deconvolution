/*
 * Module: deconvolution/deconwolf
 *
 * Generates a PSF with dw_bw (Born & Wolf model) from per-run optical
 * parameters, then deconvolves the input TIFF with dw (Richardson-Lucy).
 * Emission wavelength (meta.emission), z-plane count (meta.dim_z), and
 * pixel size (meta.physical_voxel_size_xy_nm/_z_nm) all stay per-image —
 * sourced from the convert_to_tif manifest (xy assumes square pixels,
 * so the manifest's res_y is not used). NA, ni, iterations, and tile
 * size are shared across the run and come from params.
 * GPU/CPU mode is a third tuple input
 * (gpu), not a meta key or global param, so the subworkflow can retry a
 * failed GPU attempt on CPU by re-invoking with gpu = false — the retry
 * branching itself lives at the subworkflow level, not here.
 * XDG_CONFIG_HOME is isolated per task so concurrent SLURM tasks don't
 * race on deconwolf's cache directory. meta.internal_id (set by the
 * subworkflow to distinguish per-channel/time/scene rows sharing one
 * meta.id) is used for tag when present, falling back to meta.id.
 * --float, --bq, and --scale are flat, run-level dw output-shaping
 * flags rather than per-image/validated inputs, so they're sourced from
 * task.ext (set per-process via the withName: 'DECONWOLF_GPU' /
 * 'DECONWOLF_CPU' config blocks — this process is included twice under
 * those aliases), not params: ext.float defaults to false (flag
 * omitted), ext.bq defaults to 2, and ext.scale is only passed through
 * when > 0 (0/negative/unset all omit --scale silently).
 * On gpu=true, a failure with an OOM/timeout-shaped exit status is
 * retried up to maxRetries, with memory/time scaled per task.attempt via
 * the withName: 'DECONWOLF_GPU' block in nextflow.config, then ignored
 * so the subworkflow-level fallback can retry on CPU. Any other GPU
 * failure is ignored immediately. gpu=false (the CPU fallback itself)
 * uses default error handling — there's no further fallback.
 */

process DECONWOLF {
    tag "${meta.internal_id ?: meta.id}"
    container 'TODO: add container image address'

    errorStrategy {
        if (!gpu) return 'terminate'
        def resource_failure = (task.exitStatus in 130..145) || task.exitStatus == 104
        (resource_failure && task.attempt <= task.maxRetries) ? 'retry' : 'ignore'
    }
    maxRetries 3

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
    def nslice    = "--nslice ${meta.dim_z}"
    def float_flag = task.ext.float ? '--float' : ''
    def bq         = task.ext.bq != null ? "--bq ${task.ext.bq}" : "--bq 2"
    def scale_flag = (task.ext.scale && task.ext.scale > 0) ? "--scale ${task.ext.scale}" : ''
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
        ${nslice} \\
        --overwrite \\
        PSF.tif

    dw \\
        --iter ${params.deconvolution_iter} \\
        ${gpu_args} \\
        ${tile_args} \\
        ${bq} \\
        ${float_flag} \\
        ${scale_flag} \\
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
