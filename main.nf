/*
 * main.nf
 *
 * Top-level entry point: reads the input manifest CSV (params.input),
 * builds the DECONVOLUTION subworkflow's input channel, and publishes
 * the resulting OME-Zarr images to params.outdir.
 *
 * Input CSV columns: image_id, emission, channel_index, path — see
 * README for the full contract — plus optional time_indices
 * (semicolon-separated 0-based ints, e.g. "0;1;2"; default: all time
 * points) and scene (0-based int; default: 0).
 */

include { DECONVOLUTION } from './subworkflows/deconvolution/main.nf'

workflow {
    main:
    if (!params.input) {
        error "params.input is required — path to the input manifest CSV (see README)"
    }

    ch_input = channel.fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            def meta = [
                id: row.image_id,
                emission: row.emission.toInteger(),
                channel_index: row.channel_index.toInteger(),
            ]
            if (row.scene)         meta.scene = row.scene.toInteger()
            if (row.time_indices)  meta.time_indices = row.time_indices.split(';').collect { it -> it.toInteger() }
            tuple(meta, file(row.path))
        }

    DECONVOLUTION(ch_input)

    publish:
    ome_zarr = DECONVOLUTION.out.ome_zarr
}

output {
    ome_zarr {
        path { meta, _zarr -> "${meta.id}" }
    }
}
