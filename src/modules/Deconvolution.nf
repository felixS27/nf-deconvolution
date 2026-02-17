process DECONVOLUTION_GPU {

    tag "${meta.image_id}"

    label 'deconvolution_gpu'

    container 'registry.git.embl.org/felix.schneider1/podmanimages/deconwolf:0.4.6_py'

    input:
    tuple val(meta), path(image)

    output:
    tuple val(meta),path("*deconvolved.ome.zarr"),   emit: deconvolved, optional: true

    script:
    def tifconversion = "/project/src/modules/python/ConverttoTif.py"
    def omezarrconversion = "/project/src/modules/python/ConverttoOMEZarr.py"
    def args1 = task.ext.args1 ?: ''
    def args2 = task.ext.args2 ?: ''
    def args3 = task.ext.args3 ?: ''
    """
    # Ensure deconwolf cache directory is writable
    export XDG_CONFIG_HOME=\$PWD/.config
    mkdir -p \$XDG_CONFIG_HOME/deconwolf

    echo "Converting image to tif format..."
    python ${tifconversion} -f ${image} --channel_index ${meta.channel_index}

    echo "Running dw_bw to generate the PSF..."
    dw_bw $args1 $args3 --lambda ${meta.emission} --overwrite PSF.tif

    echo "Running dw to deconvolve image..."
    dw --gpu $args2 --float --overwrite --tempdir \$PWD --out \$PWD ConvertedTif.tif PSF.tif

    echo "Converting deconvolved image back to ome zarr format..."
    python ${omezarrconversion} -f ${image} -fd dw_ConvertedTif.tif $args3 

    rm -rf \$XDG_CONFIG_HOME

    echo "Deconvolution completed successfully!"
    """
}
process DECONVOLUTION_CPU {

    tag "${meta.image_id}"

    label 'deconvolution_cpu'

    container 'registry.git.embl.org/felix.schneider1/podmanimages/deconwolf:0.4.6_py'

    input:
    tuple val(meta), path(image)

    output:
    tuple val(meta),path("*deconvolved.ome.zarr"),   emit: deconvolved

    script:
    def tifconversion = "/project/src/modules/python/ConverttoTif.py"
    def omezarrconversion = "/project/src/modules/python/ConverttoOMEZarr.py"
    def args1 = task.ext.args1 ?: ''
    def args2 = task.ext.args2 ?: ''
    def args3 = task.ext.args3 ?: ''
    """
    # Ensure deconwolf cache directory is writable
    export XDG_CONFIG_HOME=\$PWD/.config
    mkdir -p \$XDG_CONFIG_HOME/deconwolf

    echo "Converting image to tif format..."
    python ${tifconversion} -f ${image} --channel_index ${meta.channel_index}

    echo "Running dw_bw to generate the PSF..."
    dw_bw $args1 $args3 --lambda ${meta.emission} --overwrite PSF.tif

    echo "Running dw to deconvolve image..."
    dw $args2 --float --overwrite --tempdir \$PWD --out \$PWD ConvertedTif.tif PSF.tif

    echo "Converting deconvolved image back to ome zarr format..."
    python ${omezarrconversion} -f ${image} -fd dw_ConvertedTif.tif $args3

    rm -rf \$XDG_CONFIG_HOME

    echo "Deconvolution completed successfully!"
    """
}