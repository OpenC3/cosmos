# MINIO

Minio has stopped building their own containers. To build the latest Minio release you need to copy the source code from the latest [release](https://github.com/minio/minio/releases) and put it in this directory. Then update the `Dockerfile`, `scripts/linux/openc3_build_ubi.sh`, and `scripts/release/build_multi_arch.sh` and change the `OPENC3_MINIO_RELEASE` to the released version.

Make sure that the IronBank [minio](https://ironbank.dso.mil/repomap/details;registry1Path=opensource%252Fminio%252Fminio) has a valid release as they can be different.
