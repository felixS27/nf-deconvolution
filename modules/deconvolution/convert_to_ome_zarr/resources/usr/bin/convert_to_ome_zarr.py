#!/usr/bin/env python3
"""Reassembles per-channel/per-timepoint deconvolved 3D TIFFs into one OME-Zarr image.

Used within the `convert_to_ome_zarr` Nextflow process to invert
`convert_to_tif`'s per-channel/per-timepoint split: stacks every
deconvolved TIFF belonging to one dataset_id/scene into a single CZYX
(or TCZYX, when more than one time point is present) array and writes
it as OME-Zarr.
"""

import csv
from pathlib import Path

import dask.array as da
from bioio import BioImage
from bioio_ome_zarr.writers import Channel, OMEZarrWriter

CHANNEL_COLOR = "FFFFFF"


class Assembler:
    """Stacks per-channel/per-timepoint deconvolved TIFFs into one OME-Zarr image.

    Attributes:
        dataset_id (str): identifier embedded in the output directory name.
        manifest (Path): CSV (channel_index,time_index,emission,filepath)
            listing every deconvolved TIFF belonging to this dataset_id/scene.
        scene (int): zero-based scene index, embedded in the output directory name.
        physical_voxel_size_xy_nm (float): lateral pixel size in nm (assumes square pixels).
        physical_voxel_size_z_nm (float): z pixel size in nm.

    Methods:
        assemble() -> None:
            Stack every TIFF in the manifest into one OME-Zarr image.
    """

    def __init__(self,
                 dataset_id: str,
                 manifest: str,
                 scene: int,
                 physical_voxel_size_xy_nm: float,
                 physical_voxel_size_z_nm: float) -> None:
        self.dataset_id = dataset_id
        self.manifest = Path(manifest)
        self.scene = scene
        self.physical_voxel_size_xy_nm = physical_voxel_size_xy_nm
        self.physical_voxel_size_z_nm = physical_voxel_size_z_nm

    def assemble(self) -> None:
        """Stack every TIFF in the manifest into one OME-Zarr image."""
        rows = self._read_manifest()
        time_indices = sorted({row["time_index"] for row in rows})
        channel_indices = sorted({row["channel_index"] for row in rows})

        if len(rows) != len(time_indices) * len(channel_indices):
            raise ValueError(
                f"Expected one TIFF per (time_index, channel_index) pair "
                f"({len(time_indices)} time point(s) x {len(channel_indices)} channel(s)), "
                f"got {len(rows)} in {self.manifest}."
            )

        by_index = {(row["time_index"], row["channel_index"]): row["filepath"] for row in rows}
        emission_by_channel = {row["channel_index"]: row["emission"] for row in rows}

        image, axes = self._stack(by_index, time_indices, channel_indices)
        out_path = Path.cwd() / f"{self.dataset_id}_S{self.scene}_deconvolved.ome.zarr"
        self._write(image, axes, channel_indices, emission_by_channel, out_path)
        print(f"OME-Zarr written to {out_path}", flush=True)

    def _read_manifest(self) -> list[dict]:
        with open(self.manifest, newline="") as manifest_file:
            return [
                {
                    "time_index": int(row["time_index"]),
                    "channel_index": int(row["channel_index"]),
                    "emission": row["emission"],
                    "filepath": row["filepath"],
                }
                for row in csv.DictReader(manifest_file)
            ]

    @staticmethod
    def _stack(by_index: dict, time_indices: list, channel_indices: list) -> tuple:
        """Stacks planes as (t)czyx, dropping the t axis when there's a single time point."""
        def plane(t: int, c: int) -> da.Array:
            return BioImage(by_index[(t, c)]).get_image_dask_data("ZYX")

        if len(time_indices) > 1:
            image = da.stack([da.stack([plane(t, c) for c in channel_indices], axis=0) for t in time_indices], axis=0)
            return image, ["t", "c", "z", "y", "x"]
        image = da.stack([plane(time_indices[0], c) for c in channel_indices], axis=0)
        return image, ["c", "z", "y", "x"]

    def _write(self, image: da.Array, axes: list, channel_indices: list, emission_by_channel: dict,
               out_path: Path) -> None:
        space_um = {
            "z": self.physical_voxel_size_z_nm / 1000,
            "y": self.physical_voxel_size_xy_nm / 1000,
            "x": self.physical_voxel_size_xy_nm / 1000,
        }
        physical_pixel_size = [1.0 if axis in ("t", "c") else space_um[axis] for axis in axes]
        axes_units = [None if axis in ("t", "c") else "micrometer" for axis in axes]
        channels = [
            Channel(label=f"{emission_by_channel[c]}nm", color=CHANNEL_COLOR)
            for c in channel_indices
        ]

        writer = OMEZarrWriter(
            store=str(out_path),
            level_shapes=image.shape,
            dtype=image.dtype,
            channels=channels,
            axes_units=axes_units,
            physical_pixel_size=physical_pixel_size,
        )
        writer.write_full_volume(image)


if __name__ == "__main__":

    import argparse

    def parse_arguments():
        parser = argparse.ArgumentParser(
            description="Stack per-channel/per-timepoint deconvolved TIFFs into one OME-Zarr image."
        )

        parser.add_argument("--dataset_id", type=str, required=True,
                             help="Identifier embedded in the output directory name.")
        parser.add_argument("--manifest", type=str, required=True,
                             help="Manifest CSV (channel_index,time_index,emission,filepath).")
        parser.add_argument("--scene", type=int, required=False, default=0,
                             help="Zero-based scene index (default: 0).")
        parser.add_argument("--physical_voxel_size_xy_nm", type=float, required=True,
                             help="Lateral pixel size in nm (assumes square pixels).")
        parser.add_argument("--physical_voxel_size_z_nm", type=float, required=True,
                             help="Z pixel size in nm.")
        return parser.parse_args()

    args = parse_arguments()

    Assembler(
        args.dataset_id,
        args.manifest,
        args.scene,
        args.physical_voxel_size_xy_nm,
        args.physical_voxel_size_z_nm,
    ).assemble()
