/*
 * Subworkflow: deconvolution
 *
 * Chains convert_to_tif -> deconwolf -> convert_to_ome_zarr. deconwolf runs
 * on GPU with CPU fallback when params.deconvolution_with_gpu is true
 * (default), or CPU-only otherwise.
 */

include { CONVERT_TO_TIF }             from '../../modules/deconvolution/convert_to_tif/main.nf'
include { DECONWOLF as DECONWOLF_GPU ; DECONWOLF as DECONWOLF_CPU } from '../../modules/deconvolution/deconwolf/main.nf'
include { CONVERT_TO_OME_ZARR }        from '../../modules/deconvolution/convert_to_ome_zarr/main.nf'

workflow DECONVOLUTION {
    take:
    // tuple(meta, image) — meta: [id: dataset_id, emission: nm, channel_index: int,
    // time_indices: list<int> (optional), scene: int (optional)]. id/emission/channel_index
    // are required — id and emission pass through untouched to deconwolf, channel_index is
    // required by convert_to_tif; time_indices/scene are optional and default to "all/0".
    ch_input

    main:
    CONVERT_TO_TIF(ch_input)

    ch_deconwolf_input = CONVERT_TO_TIF.out.deconvolution_input
        .flatMap { meta, manifest ->
            manifest.splitCsv(header: true).collect { row ->
                def id_parts = [meta.id, "C${row.channel_index}", "T${row.time_index}",
                                "S${row.scene}"]
                def row_meta = meta + [
                    internal_id: id_parts.join('_'),
                    time_index: row.time_index.toInteger(),
                    dim_z: row.dim_z.toInteger(),
                    physical_voxel_size_xy_nm: row.res_x.toFloat(),
                    physical_voxel_size_z_nm: row.res_z.toFloat(),
                    orig_meta: meta,
                ]
                tuple(row_meta, file(row.filepath))
            }
        }

    if (params.deconvolution_with_gpu.toString().toBoolean()) {
        ch_gpu_input = ch_deconwolf_input.map { meta, tif -> tuple(meta, file(tif), true) }
        DECONWOLF_GPU(ch_gpu_input)

        ch_cpu_input = ch_gpu_input
            .join(DECONWOLF_GPU.out.deconvolved, remainder: true)
            .filter { _meta, _tif, _gpu, deconvolved -> deconvolved == null }
            .map { meta, tif, _gpu, _deconvolved -> tuple(meta, file(tif), false) }
        DECONWOLF_CPU(ch_cpu_input)

        ch_deconvolved = DECONWOLF_GPU.out.deconvolved.mix(DECONWOLF_CPU.out.deconvolved)
    } else {
        ch_cpu_input = ch_deconwolf_input.map { meta, tif -> tuple(meta, file(tif), false) }
        DECONWOLF_CPU(ch_cpu_input)
        ch_deconvolved = DECONWOLF_CPU.out.deconvolved
    }

    ch_ome_zarr_input = ch_deconvolved
        .map { meta, tif ->
            def group_key = [meta.id, meta.channel_index, meta.scene ?: 0]
            tuple(group_key, meta, tif)
        }
        .groupTuple(by: 0)
        .map { group_key, metas, tifs ->
            def task_meta = [
                id: group_key[0],
                channel_index: group_key[1],
                scene: group_key[2],
                physical_voxel_size_xy_nm: metas[0].physical_voxel_size_xy_nm,
                physical_voxel_size_z_nm: metas[0].physical_voxel_size_z_nm,
                orig_meta: metas[0].orig_meta,
            ]
            tuple(task_meta, tifs)
        }
    CONVERT_TO_OME_ZARR(ch_ome_zarr_input)

    emit:
    ome_zarr = CONVERT_TO_OME_ZARR.out.ome_zarr.map { meta, zarr -> tuple(meta.orig_meta, file(zarr)) }
}
