#!/usr/bin/env python3
"""Reassembles per-timepoint deconvolved 3D TIFFs into one OME-Zarr image.

Used within the `convert_to_ome_zarr` Nextflow process to invert
`convert_to_tif`'s per-timepoint split: stacks every deconvolved TIFF
belonging to one dataset_id/channel_index/scene into a single ZYX (or
TZYX, when more than one time point is present) array and writes it as
OME-Zarr. Time index is parsed from each TIFF's filename
(`_T<time>_C<channel>`, written by convert_to_tif and preserved through
dw's `dw_` prefix) rather than carried alongside as separate metadata.
"""

import re
from pathlib import Path

import dask.array as da
import numpy as np
from bioio import BioImage
import bioio_tifffile
from bioio_ome_zarr.writers import Channel, OMEZarrWriter

TIME_INDEX_PATTERN = re.compile(r"_T(\d+)_C\d+")

# Target (z, y, x) chunk shape per dtype dw can emit (uint16 by default,
# float32 via task.ext.float), each sized to ~32 MiB so the two dtypes land
# on comparable on-disk chunk sizes despite the itemsize difference. Kept
# well under 128 MiB so writing has enough independent chunks to actually
# parallelize across cores rather than a few oversized ones. Clamped
# per-axis against the actual image size in _chunk_shape.
TARGET_CHUNK_SHAPE_ZYX = {
    np.dtype("uint16"): (16, 1024, 1024),
    np.dtype("float32"): (8, 1024, 1024),
}


class Assembler:
    """Stacks per-timepoint deconvolved TIFFs into one OME-Zarr image.

    Attributes:
        dataset_id (str): identifier embedded in the output directory name.
        channel_index (int): zero-based channel index, embedded in the output directory name.
        scene (int): zero-based scene index, embedded in the output directory name.
        physical_voxel_size_xy_nm (float): lateral pixel size in nm (assumes square pixels).
        physical_voxel_size_z_nm (float): z pixel size in nm.
        tifs (list[Path]): deconvolved TIFFs belonging to this dataset_id/channel_index/scene.

    Methods:
        assemble() -> None:
            Stack every TIFF into one OME-Zarr image, ordered by time index.
    """

    def __init__(self,
                 dataset_id: str,
                 channel_index: int,
                 scene: int,
                 physical_voxel_size_xy_nm: float,
                 physical_voxel_size_z_nm: float,
                 tifs: list[str]) -> None:
        self.dataset_id = dataset_id
        self.channel_index = channel_index
        self.scene = scene
        self.physical_voxel_size_xy_nm = physical_voxel_size_xy_nm
        self.physical_voxel_size_z_nm = physical_voxel_size_z_nm
        self.tifs = [Path(t) for t in tifs]

    def assemble(self) -> None:
        """Stack every TIFF into one OME-Zarr image, ordered by time index."""
        ordered = sorted(self.tifs, key=self._time_index)

        image, axes = self._stack(ordered)
        out_path = Path.cwd() / f"{self.dataset_id}_C{self.channel_index}_S{self.scene}_deconvolved.ome.zarr"
        self._write(image, axes, out_path)
        print(f"OME-Zarr written to {out_path}", flush=True)

    @staticmethod
    def _time_index(tif: Path) -> int:
        match = TIME_INDEX_PATTERN.search(tif.name)
        if not match:
            raise ValueError(f"Could not parse time index from filename: {tif.name}")
        return int(match.group(1))

    @staticmethod
    def _stack(tifs: list) -> tuple:
        """Stacks time points as tzyx, dropping the t axis when there's a single time point."""
        if len(tifs) == 1:
            return BioImage(tifs[0],reader=bioio_tifffile.Reader).get_image_dask_data("ZYX"), ["z", "y", "x"]
        time_points = [BioImage(tif,reader=bioio_tifffile.Reader).get_image_dask_data("ZYX") for tif in tifs]
        return da.stack(time_points, axis=0), ["t", "z", "y", "x"]

    @staticmethod
    def _chunk_shape(image: da.Array, axes: list) -> tuple:
        """Looks up the target (z, y, x) chunk shape for this image's dtype,
        clamped per-axis to the actual image size, with one time point per
        chunk."""
        dtype = np.dtype(image.dtype)
        if dtype not in TARGET_CHUNK_SHAPE_ZYX:
            raise ValueError(f"No target chunk shape defined for dtype {dtype} (expected uint16 or float32)")
        target = dict(zip("zyx", TARGET_CHUNK_SHAPE_ZYX[dtype]))
        shape = dict(zip(axes, image.shape))
        return tuple(1 if axis == "t" else min(target[axis], shape[axis]) for axis in axes)

    def _write(self, image: da.Array, axes: list, out_path: Path) -> None:
        space_um = {
            "z": self.physical_voxel_size_z_nm / 1000,
            "y": self.physical_voxel_size_xy_nm / 1000,
            "x": self.physical_voxel_size_xy_nm / 1000,
        }
        physical_pixel_size = [1.0 if axis == "t" else space_um[axis] for axis in axes]
        axes_units = [None if axis == "t" else "micrometer" for axis in axes]
        axes_types = ["time" if axis == "t" else "space" for axis in axes]
        chunk_shape = self._chunk_shape(image, axes)

        writer = OMEZarrWriter(
            store=str(out_path),
            level_shapes=image.shape,
            dtype=image.dtype,
            axes_units=axes_units,
            axes_types=axes_types,
            axes_names=axes,
            physical_pixel_size=physical_pixel_size,
            chunk_shape=chunk_shape,
        )
        writer.write_full_volume(image.rechunk(chunk_shape))


if __name__ == "__main__":

    import argparse

    def parse_arguments():
        parser = argparse.ArgumentParser(
            description="Stack per-timepoint deconvolved TIFFs into one OME-Zarr image."
        )

        parser.add_argument("--dataset_id", type=str, required=True,
                             help="Identifier embedded in the output directory name.")
        parser.add_argument("--channel_index", type=int, required=True,
                             help="Zero-based channel index, embedded in the output directory name.")
        parser.add_argument("--scene", type=int, required=False, default=0,
                             help="Zero-based scene index (default: 0).")
        parser.add_argument("--physical_voxel_size_xy_nm", type=float, required=True,
                             help="Lateral pixel size in nm (assumes square pixels).")
        parser.add_argument("--physical_voxel_size_z_nm", type=float, required=True,
                             help="Z pixel size in nm.")
        parser.add_argument("--tifs", type=str, nargs="+", required=True,
                             help="Deconvolved TIFFs belonging to this dataset_id/channel_index/scene.")
        return parser.parse_args()

    args = parse_arguments()

    Assembler(
        args.dataset_id,
        args.channel_index,
        args.scene,
        args.physical_voxel_size_xy_nm,
        args.physical_voxel_size_z_nm,
        args.tifs,
    ).assemble()
