from bioio import BioImage
from tifffile import imwrite
from pathlib import Path
import argparse

class Converter:
    """Class to convert ome zarr into tif.
    
    Attributes:
        file (str): absolute path to image.
        channel_index (int): zero-based channel index.
        
    Methods:
        convert() -> None: 
            convert image from ome zarr to tif.
    """

    def __init__(self,
                 file:str,
                 channel_index:int) -> None:
        self.file = Path(file)
        self.channel_index = channel_index


    def convert(self) -> None:
        """Convert image from ome zarr to tif."""
        img = BioImage(self.file)
        if img.dims.C>1:
            img = img.dask_data.squeeze()[self.channel_index]
        else:
            img = img.dask_data.squeeze()
        img = img.astype('float32')
        file_name = 'ConvertedTif'
        path_to_save = Path.cwd()/f'{file_name}.tif'
        imwrite(path_to_save,img.compute())
        print(f'Converted image has been saved at {str(path_to_save)}',flush=True)

if __name__ == "__main__":
    
    def parse_arguments():
        parser = argparse.ArgumentParser(description="Convert image from ome zarr to tif")

        parser.add_argument("-f","--file", type=str,required=True,
                            help='Absolute path to image file.')
        parser.add_argument("--channel_index",type=int,required=False,default=0,
                            help='Zero-based channel index.')
        args = parser.parse_args()
        return args
    
    args = parse_arguments()
    
    Converter(args.file,args.channel_index).convert()