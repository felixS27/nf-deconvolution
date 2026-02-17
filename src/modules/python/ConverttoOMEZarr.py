from bioio import BioImage
from bioio_ome_zarr.writers import OMEZarrWriter # pyright: ignore[reportMissingImports]
from pathlib import Path
import argparse

class Converter:
    """Class to convert tif to ome zarr.
    
    Attributes:
        file (str): absolute path to image.
        file_deconv (str): absolute path to deconvolved image.
        res_z (float): physical voxel size in z (nm)
        res_y (float): physical voxel size in y (nm)
        res_x (float): physical voxel size in x (nm)
        
    Methods:
        convert() -> None: 
            convert image from tif to ome zarr.
    """

    def __init__(self,
                 file:str,
                 file_deconv:str,
                 res_z:float,
                 res_y:float,
                 res_x:float):
        self.file = Path(file)
        self.deconv_file = Path(file_deconv)
        self.voxel_size = [res_z/1000, res_y/1000, res_x/1000]

    def convert(self) -> None:
        """Convert image from tif to ome zarr."""
        img = BioImage(self.deconv_file).dask_data.squeeze().rechunk('auto')
        file_name = f'{self.file.stem}'
        if file_name.endswith('.ome'):
            file_name = file_name[:-4]
        path_to_save = Path.cwd()/f'{Path(self.file).stem}_deconvolved.ome.zarr'
        omezarrwriter = OMEZarrWriter(store=path_to_save,level_shapes=img.shape,
                                      dtype=img.dtype,
                                      image_name=f'{Path(self.file).stem}_deconvolved',
                                      physical_pixel_size=self.voxel_size,
                                      axes_names=['z','y','x'],
                                      axes_types=['space','space','space'],
                                      axes_units=['micron','micron','micron'])
        omezarrwriter.write_full_volume(img)
        print(f'Converted image has been saved at {str(path_to_save)}',flush=True)
        files_to_delete = Path.cwd().glob("dw_*")
        for file in files_to_delete:
            print(f'Deleting temporary file {str(file)}',flush=True)
            if file.exists():
                file.unlink()
        files_to_delete = Path.cwd().glob("fftw_*")
        for file in files_to_delete:
            print(f'Deleting temporary file {str(file)}',flush=True)
            if file.exists():
                file.unlink()
        files_to_delete = Path.cwd().glob("PSF*")
        for file in files_to_delete:
            print(f'Deleting temporary file {str(file)}',flush=True)
            if file.exists():
                file.unlink()
        if self.deconv_file.exists():
            self.deconv_file.unlink()
            print(f'Deleted temporary deconvolved file {str(self.deconv_file)}',
                  flush=True)
        file_to_delete = Path.cwd()/'ConvertedTif.tif'
        if file_to_delete.exists():
            file_to_delete.unlink()
            print(f'Deleted temporary file {str(file_to_delete)}',flush=True)


if __name__ == "__main__":
    
    def parse_arguments():
        parser = argparse.ArgumentParser(description="Convert from tif to ome zarr")

        parser.add_argument("-f","--file", type=str,required=True,
                            help='Absolute path to original image file.')
        parser.add_argument("-fd","--file_deconvolved", type=str,required=True,
                            help='Absolute path to deconvolved image file.')
        parser.add_argument("--resz", type=float, required=True,
                            help='Voxel size in Z in nm')
        parser.add_argument("--resxy", type=float, required=True,
                            help='Voxel size in X/Y in nm.')
        args = parser.parse_args()
        return args
    
    args = parse_arguments()
    
    Converter(args.file,args.file_deconvolved,args.resz,args.resxy,args.resxy).convert()