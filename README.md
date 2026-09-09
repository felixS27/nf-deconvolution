# Nextflow module of deconwolf to deconvolve 3D fluorescence microscopy data
This is a repo packing the software [deconwolf](https://github.com/elgw/deconwolf) into a nextflow module as well as 
supplying a dockerfile to create your own docker image.
Furthermore it is providing a guideline on how to use the module with some exemplary condig files.
For further information on the general usage of deconwolf, 
please have a look at the official [documentation](https://elgw.github.io/deconwolf/).

## Module overview
The module is capable of performing three tasks:
1. Convert an OME Zarr image into a tif image
2. Deconvolve the tif image
3. Convert the deconvolved image into an OME Zarr image
The designed workflow is thought to accept either an OME Zarr image or a tif image and returns an deconvolved OME Zarr
image. The image has to be a 3D image with dimension order ZYX. If it is a 4D image, then the dimension order has to be 
channel x ZYX.

## Requisites
### Software
- nextflow >= 24.0
- docker/apptainer

### Data
- Minimum input table (comma separated)
    - column for image/experiment/file id
    - column for emission
    - column for channel_index (for 3D data input any number)
    - path to image file
    - optional column for time_indices (which timepoints to process; default: all)
    - optional column for scene (which scene to read; default: 0)
- Image dimension in z and physical voxel size (z, y, x) are read automatically
  from each image's own metadata — the image must carry calibrated pixel size
  metadata, or the pipeline will error.
- Additional parameters (set once per run in `nextflow.config`, shared across
  all images — see the note under "Prepare your params" below)
    - refraction index of immersion medium
    - numerical aperture of the objective
    - number of iterations
    - tile size for tiled deconvolution

## How to use
This guide is designed to run this module on an HPC and the current configs can be used to run it at EMBL HD HPC.

### Download repo
Log onto your HPC and download this repo (preferrably on /scratch directory)

```bash
cd /scratch/$USER
git clone https://github.com/felixS27/nf-deconvolution.git
```

### Prepare your data
Create a comma separated (csv) file with the following columns:
- image_id: an image/experiment id
- emission: emission of fluorophore used (in nm)
- channel_index: zero-based index of channel to use. If image is only 3D, then you can enter an arbitrary number.
- path: absolute path to the image. The image should be either 3D with dimension order ZYX or 4D with order 
channel x ZYX
- time_indices (optional): semicolon-separated, zero-based time indices to process, e.g. `"0;1;2"`. Leave empty to
process all time points present in the image.
- scene (optional): zero-based scene index to read. Leave empty to default to scene 0.

Each channel of a multi-channel image goes into its own row (never a list of channels in one row) — see
`data/test_input.csv` for a worked example, including a multi-channel/multi-timepoint case.

### Prepare your params
Open `nextflow.config` and change the `params` block's values according to your experimental setup — there is no
separate `params.config` file, all params live directly in `nextflow.config`.
**Note**: The current setup allows only to simultaneously process images, which where recorded with the same microscope
settings.
- input: path to the above prepared input data
- microscope_ni: refractive index of the immersion medium
- microscope_NA: numerical aperture of the used microscope objective
- deconvolution_iter: number of iterations to run for deconvolution
- deconvolution_tile_size: size of tile for performing tiled deconvolution
- deconvolution_with_gpu: `true` (default) to deconvolve on GPU with automatic CPU fallback on failure, `false` to
skip GPU entirely and always run on CPU
- outdir: directory where the deconvolved OME-Zarr results are published (default: `results`)

### Prepare your nextflow.config file
Please adjust the rest of the nextflow.config file (process resources, container engine, execution profiles) according
to your HPC configurations/settings. The provided nextflow.config file is merely a guideline on what to expect.
Obvisouly these values can be finetuned to you own needs in terms of ressources needed or used. If you plan to run this
on the EMBL HD HPC, then you can leave it like this, as it should cover most cases.

### main.nf
`main.nf` is the top-level entry point: it reads `params.input`, runs the three deconvolution stages, and publishes
the deconvolved OME-Zarr images to `params.outdir` (one subdirectory per `image_id`; each channel of a multi-channel
dataset is published as its own OME-Zarr image, not combined into one multi-channel file).
By default it deconvolves on GPU and automatically falls back to CPU if the GPU attempt fails, which will always be
slower, but maybe also more reliable. Nothing needs to be changed here, except if you want to force purely GPU or CPU
via `deconvolution_with_gpu`.

### Run the module
The following steps written for EMBL HD HPC, but can be similarly adapted for other HPCs or put in a single SLURM script.

1. Make directory for downloading apptainer images (the cache location itself is set in `nextflow.config`'s `apptainer.cacheDir`, no need to `export APPTAINER_CACHEDIR` manually)

``` bash
mkdir -p /scratch/$USER/apptainer_cache
```

2. Load nextflow (this maybe different on each system)

``` bash
module load Nextflow/24.10.0
```

3. Run the module with this command

``` bash
nextflow run main.nf
```
`main.nf` has to be started from within the directory of this module, so that its `nextflow.config` (with your params
already set, see above) is picked up automatically. To override individual params without editing the file, pass them
on the command line, e.g. ```nextflow run main.nf --input path/to/other_input.csv```, or load a separate override file
with ```nextflow run main.nf -c path/to/extra.config```.

For a quick local smoke test without a real container or SLURM, run
```nextflow run main.nf -profile stub -stub-run``` — this uses the bundled `data/test_input.csv` and fixture images
under `data/` by default.