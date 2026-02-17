#!/usr/bin/env nextflow
nextflow.enable.dsl=2

// Load modules
include { DECONVOLUTION_GPU; DECONVOLUTION_CPU } from './modules/Deconvolution.nf'



workflow {

        channel.fromPath(params.input, checkIfExists:true)
                .splitCsv(header:true)
                .map { row -> tuple(['image_id': row.image_id,'emission':row.emission,
                                'channel_index':row.channel_index], 
                                file(row.path,checkIfExists:true)) }
                .set { input_files }

        // Deconvolution
        // GPU
        deconvolution_gpu = DECONVOLUTION_GPU(input_files)

        // Catch failed GPU deconvolutions and rerun on CPU
        input_files.join(deconvolution_gpu.deconvolved,remainder:true)
                .filter { item -> item[2] == null }
                .map { it -> tuple(it[0],it[1]) }
                .set { failed_deconvolution }

        // CPU
        deconvolution_cpu = DECONVOLUTION_CPU(failed_deconvolution)

        // combine results
        deconvolution_gpu.deconvolved.mix(deconvolution_cpu.deconvolved)
                .set { deconvolved_images } 
                        
}