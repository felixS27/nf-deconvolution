/*
 * Subworkflow: deconvolution
 *
 * Chains convert_to_tif -> deconwolf -> convert_to_ome_zarr. deconwolf runs
 * on GPU with CPU fallback when params.deconvolution_with_gpu is true
 * (default), or CPU-only otherwise.
 */

include { CONVERT_TO_TIF }             from '../../modules/deconvolution/convert_to_tif/main.nf'
include { DECONWOLF as DECONWOLF_GPU } from '../../modules/deconvolution/deconwolf/main.nf'
include { DECONWOLF as DECONWOLF_CPU } from '../../modules/deconvolution/deconwolf/main.nf'
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

    // One manifest CSV row per time point; derive a per-row internal_id
    // (dataset_id + whichever of channel/time/scene are available) from the
    // manifest's own channel_index/time_index/scene columns so retries and
    // joins below key on the individual tif, not the original per-channel
    // meta. Kept separate from meta.id (the dataset id) rather than
    // overwriting it, so the original dataset id survives downstream.
    ch_deconwolf_input = CONVERT_TO_TIF.out.deconvolution_input
        .flatMap { meta, manifest ->
            manifest.splitCsv(header: true).collect { row ->
                def id_parts = [meta.id, "C${row.channel_index}", "T${row.time_index}"]
                if (meta.containsKey('scene')) id_parts << "S${row.scene}"
                def row_meta = meta + [
                    internal_id: id_parts.join('_'),
                    time_index: row.time_index.toInteger(),
                    dim_z: row.dim_z.toInteger(),
                    physical_voxel_size_xy_nm: row.res_x.toFloat(),
                    physical_voxel_size_z_nm: row.res_z.toFloat(),
                ]
                tuple(row_meta, file(row.filepath))
            }
        }

    // .toString().toBoolean() guards against the CLI handing this through
    // as the String "false" (truthy in Groovy) when no params.config default
    // exists yet to tell Nextflow's CLI parser the param's type is boolean.
    if (params.deconvolution_with_gpu.toString().toBoolean()) {
        ch_gpu_input = ch_deconwolf_input.map { meta, tif -> tuple(meta, tif, true) }
        DECONWOLF_GPU(ch_gpu_input)

        // Items DECONWOLF_GPU ignored (see modules/deconvolution/deconwolf)
        // come through with no matching output — join with remainder to
        // find them and retry on CPU.
        ch_cpu_input = ch_gpu_input
            .join(DECONWOLF_GPU.out.deconvolved, remainder: true)
            .filter { _meta, _tif, _gpu, deconvolved -> deconvolved == null }
            .map { meta, tif, _gpu, _deconvolved -> tuple(meta, tif, false) }
        DECONWOLF_CPU(ch_cpu_input)

        ch_deconvolved = DECONWOLF_GPU.out.deconvolved.mix(DECONWOLF_CPU.out.deconvolved)
    } else {
        ch_cpu_input = ch_deconwolf_input.map { meta, tif -> tuple(meta, tif, false) }
        DECONWOLF_CPU(ch_cpu_input)
        ch_deconvolved = DECONWOLF_CPU.out.deconvolved
    }

    // Regroup by (dataset_id, scene) so every channel/time point belonging to
    // one scene lands in a single OME-Zarr — the inverse of convert_to_tif's
    // per-channel/per-timepoint fan-out. Voxel size is constant within a
    // group (all images in one run share microscope settings), so any one
    // member's meta carries it forward for the whole group.
    ch_ome_zarr_input = ch_deconvolved
        .map { meta, tif ->
            def group_key = [meta.id, meta.scene ?: 0]
            def item = [channel_index: meta.channel_index, time_index: meta.time_index, 
                        emission: meta.emission]
            tuple(group_key, meta, item, tif)
        }
        .groupTuple(by: 0)
        .map { group_key, metas, items, tifs ->
            def group_meta = [
                id: group_key[0],
                scene: group_key[1],
                physical_voxel_size_xy_nm: metas[0].physical_voxel_size_xy_nm,
                physical_voxel_size_z_nm: metas[0].physical_voxel_size_z_nm,
            ]
            tuple(group_meta, items, tifs)
        }
    CONVERT_TO_OME_ZARR(ch_ome_zarr_input)

    emit:
    ome_zarr = CONVERT_TO_OME_ZARR.out.ome_zarr
}
