#!/usr/bin/env python3
"""Splits a bioio-readable image into per-timepoint 3D (ZYX) TIFFs for one channel.

Used within the `convert_to_tif` Nextflow process to normalize arbitrary
bioio-readable input (OME-Zarr, TIFF, ...) into per-timepoint 3D TIFFs
before running `dw`/`dw_bw`, which require 3D TIFF input. Only a single
channel is extracted per run, since the channel's emission wavelength
(tracked separately in the CSV input contract) must match the extracted
data one-to-one.
"""

import csv
import shutil
from pathlib import Path
from typing import Optional

from bioio import BioImage
from tifffile import imwrite


class Converter:
    """Splits a bioio-readable image into per-timepoint 3D TIFFs for one channel.

    Attributes:
        dataset_id (str): identifier embedded in each output filename.
        filepath (Path): absolute path to the input image.
        channel_index (int): zero-based channel index to extract.
        scene (int): zero-based scene index to read.
        time_indices (Optional[list[int]]): time indices to extract; None means all present.

    Methods:
        convert() -> None:
            Write one 3D TIFF per requested time point, for a single channel.
    """

    BIGTIFF_THRESHOLD_GB = 4.0

    def __init__(self,
                 dataset_id: str,
                 filepath: str,
                 channel_index: int = 0,
                 scene: int = 0,
                 time_indices: Optional[list[int]] = None) -> None:
        self.dataset_id = dataset_id
        self.filepath = Path(filepath)
        self.channel_index = channel_index
        self.scene = scene
        self.time_indices = time_indices

    def convert(self) -> None:
        """Write one 3D TIFF per requested time point, for a single channel."""
        img = BioImage(self.filepath)
        img.set_scene(self.scene)

        if img.dims.Z <= 1:
            raise ValueError(
                f"Image at {self.filepath} is 2D (Z={img.dims.Z}); only 3D images are supported."
            )

        multi_scene = len(img.scenes) > 1
        already_tif = self.filepath.suffix.lower() in {".tif", ".tiff"}

        time_indices = self.time_indices if self.time_indices is not None else list(range(img.dims.T))
        pixel_sizes = img.physical_pixel_sizes

        rows = []
        if already_tif and len(time_indices) == 1 and img.dims.C == 1 and not multi_scene:
            rows.append(self._copy_through(time_indices[0], pixel_sizes, img.dims.Z))
        else:
            for t in time_indices:
                rows.append(self._write_tif(img, t, multi_scene, pixel_sizes))

        self._write_manifest(rows)

    def _output_path(self, t: int, multi_scene: bool) -> Path:
        parts = [self.dataset_id, f"T{t}", f"C{self.channel_index}"]
        if multi_scene:
            parts.append(f"S{self.scene}")
        return Path.cwd() / f"{'_'.join(parts)}.tif"

    def _copy_through(self, t: int, pixel_sizes, dim_z: int) -> dict:
        out_path = self._output_path(t, multi_scene=False)
        shutil.copy(self.filepath, out_path)
        print(f"Copied already-3D TIFF to {out_path}", flush=True)
        return self._manifest_row(out_path, pixel_sizes, dim_z, t)

    def _write_tif(self, img: BioImage, t: int, multi_scene: bool, pixel_sizes) -> dict:
        data = img.get_image_dask_data("ZYX", T=t, C=self.channel_index).astype("float32").compute()
        use_bigtiff = data.nbytes / (1024**3) >= self.BIGTIFF_THRESHOLD_GB

        resolution = None
        metadata = {"axes": "ZYX"}
        if pixel_sizes.X and pixel_sizes.Y:
            resolution = (1 / pixel_sizes.X, 1 / pixel_sizes.Y)
            metadata["unit"] = "um"
        if pixel_sizes.Z:
            metadata["spacing"] = pixel_sizes.Z

        out_path = self._output_path(t, multi_scene)
        imwrite(out_path, data, imagej=False, resolution=resolution, metadata=metadata, bigtiff=use_bigtiff)
        print(f"Converted image has been saved at {out_path}", flush=True)
        return self._manifest_row(out_path, pixel_sizes, img.dims.Z, t)

    def _manifest_row(self, out_path: Path, pixel_sizes, dim_z: int, t: int) -> dict:
        return {
            "res_x": pixel_sizes.X*1000,  # convert from um to nm
            "res_y": pixel_sizes.Y*1000,  # convert from um to nm
            "res_z": pixel_sizes.Z*1000,  # convert from um to nm
            "dim_z": dim_z,
            "channel_index": self.channel_index,
            "time_index": t,
            "scene": self.scene,
            "filepath": str(out_path),
        }

    def _write_manifest(self, rows: list) -> None:
        manifest_path = Path.cwd() / f"{self.dataset_id}_deconvolution_input.csv"
        with open(manifest_path, "w", newline="") as manifest_file:
            writer = csv.DictWriter(manifest_file, fieldnames=[
                "res_x", "res_y", "res_z", "dim_z",
                "channel_index", "time_index", "scene", "filepath",
            ])
            writer.writeheader()
            writer.writerows(rows)
        print(f"Manifest written to {manifest_path}", flush=True)


if __name__ == "__main__":

    import argparse

    def parse_arguments():
        parser = argparse.ArgumentParser(
            description="Split a bioio-readable image into per-timepoint 3D TIFFs for one channel."
        )

        parser.add_argument("--dataset_id", type=str, required=True,
                             help="Identifier embedded in each output filename.")
        parser.add_argument("-f", "--filepath", type=str, required=True,
                             help="Absolute path to the input image (OME-Zarr, TIFF, or any bioio-readable format).")
        parser.add_argument("--channel_index", type=int, required=False, default=0,
                             help="Zero-based channel index to extract (default: 0).")
        parser.add_argument("--scene", type=int, required=False, default=0,
                             help="Zero-based scene index to read (default: 0).")
        parser.add_argument("--time_indices", type=int, nargs="+", required=False, default=None,
                             help="Zero-based time indices to extract (default: all present).")
        return parser.parse_args()

    args = parse_arguments()

    Converter(
        args.dataset_id,
        args.filepath,
        args.channel_index,
        args.scene,
        args.time_indices,
    ).convert()
