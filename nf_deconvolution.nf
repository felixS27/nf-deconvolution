process Deconvolve {
    
    label 'deconvolution'
    container 'royjac/deconwolf:latest'

    input:
    tuple val(image_id),path(image_path)
    val resolution_xy
    val resolution_z
    val lambda
    val NA
    val ni
    val iter
    val tilesize

    output:
    tuple val(image_id), path("dw*.tif"), emit: deconvolved_image

    script:
    """
    echo "Running dw_bw to generate the PSF..."
    dw_bw --resxy ${resolution_xy} --resz ${resolution_z} --lambda ${lambda} --NA ${NA} --ni ${ni} PSF.tif

    echo "Running dw with the generated PSF..."
    if [[ "${tilesize}" == "whole" ]]; then
        echo "Running whole image processing"
        dw --iter ${iter} ${image_path} PSF.tif
    elif [[ "${tilesize}" =~ ^[0-9]+$ ]] && [[ "${tilesize}" -gt 0 ]]; then
        echo "Running tiled processing with size $tilesize"
        dw --iter ${iter} --tilesize ${tilesize} ${image_path} PSF.tif
    else
        echo "Invalid tilesize: ${tilesize}. Must be 'whole' or a positive integer." >&2
        exit 1
    fi

    echo "Deconvolution completed successfully!"
    """
}
