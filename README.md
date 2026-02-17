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
- additional parameter
    - image dimension in z
    - physical voxel size in nanometer for z,y,x
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
Create a command separated (csv) file with the following columns:
- image_id: an image/experiment id
- emission: emission of fluorophore used (in nm)
- channel_index: zero-based index of channel to use. If image is only 3D, then you can enter an arbitrary number.
- path: absolute path to the image. The image should bei either 3D with dimension oder ZYX or 4D with order 
channel x ZYX
Each image you want to process goes into a separate row.

### Prepare your params.config file
Open the params.config and change the following values according to your experimental setup.
**Note**: The current setup allows only to simultaneously process images, which where recorded with the same microscope
settings.
- input: absolute path to the above prepared input data
- image_dim_z: dimension of the image in z in pixel units
- physical_voxel_size_xy_nm: physical voxel size in xy in nanometers (assumes that the image is isotropic in xy)
- physical_voxel_size_z_nm: physical voxel size in z in nanometers
- microscope_ni: refractive index of the immersion medium
- microscope_NA: numerical aperture of the used microscope objective
- deconvolution_iter: number of iterations to run for deconvolution
- deconvolution_tile_size: size of tile for performing tiled deconvolution

### Prepare your nextflow.config file
Please adjust the nextflow.config file according to your HPC configurations/settings. The provided nextflow.config file
is merely a guideline on what to expect. Obvisouly these values can be finetuned to you own needs in terms of ressources
needed or used. If you plan to run this on the EMBL HD HPC, then you can leave it like this, as it should cover most 
cases.

### main.nf
The main.nf is designed in a way that if the GPU fails, it will run with CPU instead, which will always be slower, but
maybe also more reliable.
Nothing needs to be changed here, except you want to run it on purely GPU or CPU.

### Run the module
The following steps written for EMBL HD HPC, but can be similarly adapted for other HPCs or put in a single SLURM script.

1. Make directory for downloading apptainer

``` bash
cd /scratch/$USER
mkdir -p .apptainer_cache
export APPTAINER_CACHEDIR=/scratch/$USER/nf-deconvolution/.apptainer_cache
```

2. Load nextflow (this maybe different on each system)

``` bash
module load Nextflow/24.10.0
```

3. Run the module with this command

``` bash
nextflow run main.nf -c params.config
```
The main.nf has to be started from within the directory of this module, but the params.config file can be loaded from 
somewhere different. You then only have to provide the absolute path ```nextflow run main.nf -c path/to/params/config```