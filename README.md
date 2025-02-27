# Image data deconvolution as nextflow subworkflow

## Project description
The aim of this repo is to create a subworkflow with Nextflow for deconvoluting 3D imaging data (with DeconWolf, maybe more methods are added further along).
The idea is the following:
This subworkflow should be usable for everyone and every pipeline wishing to do deconvolution on 3D imaging data. This subworkflow should in the end be an easy plugin to every pipeline as well as a standalone tool.

## Anticipated workflow
- Module 1:
    - Reading different imaging formats ((ome-)tif(f),ome-zarr,lif,czi,nd2)
    - Converting to tif
    - split into single channels (if necessary)
- Module 2:
    - Deconvolution
- Module 3:
    - save deconvolved images as ome-zarr/ome-tif(f)

# Considerations / issues
- keep it modular (possible future exchange of the deconvolution module or addition/choice of several different ones)
- royjac/deconwolf as docker image to use -> check for gpu availability
- how to parse arguments?
    - single parameter?
    - as file? csv vs json vs txt?
- how to deal with image metadata?
- what parameter should be flexible, which should be prerequisite?
- what are sensible default?
- what should be the input format for PSF if supplied?
- how can we check it for functionality/compatibility? would it be then possible to correct it? -> nslice parameter?
- should we allow for different PSF?


# Parameter
## needed
- input image
- number of iterations

## optional
### if no PSF is given
- resolution in xy
- resolution in z
- numerical aperture
- refraction index
- wavelength

### other
- PSF (from https://bigwww.epfl.ch/algorithms/psfgenerator/)
- tilesize (for internal tiling for processing)
- threads (number of threads to use for processing)
- bq (boundary quality)
- float ( to switch between uint16 or float32 output)
- scale (to scale the output intensity)
- gpu (option to enable gpu)
- cldevice (for number of gpus>1)

### pre/post deconvolution
- split imae into channels
- save as ome-tif(f)/ome-zarr
