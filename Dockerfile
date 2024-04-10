FROM ubuntu:22.04 AS builder

ADD boost_python_1.74.0_arm64.deb /mnt

# libboost-dev includes _all_ headers, including those for boost::python, which we need to overwrite
# two-step install: first deps with default behavior, then package itself, ignoring file overwrites

# https://software.icecube.wisc.edu/icetray/main/projects/cmake/supported_platforms/ubuntu.html#full-install-recommended

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get install -y build-essential cmake libbz2-dev libgsl0-dev \
      libcfitsio-dev libboost-all-dev libstarlink-pal-dev libhdf5-dev \
      libzstd-dev libsuitesparse-dev libsprng2-dev liblapack-dev libhealpix-cxx-dev \
      python3-numpy libfftw3-dev libqt5opengl5-dev libcdk5-dev libncurses-dev \
      python3-sphinx doxygen python3-mysqldb python3-zmq python3-h5py \
      python3-pandas python3-seaborn libnlopt-dev \
      libzmq5-dev python3-zmq opencl-dev && \
    apt-get install -y /mnt/boost_python_*.deb -o Dpkg::Options::="--force-overwrite"

FROM builder as geant4

# NB: geant4 provide binary packages for x86_64 only, and also only on alma9
# e.g. https://cern.ch/geant4-data/releases/lib4.11.2.p01/Linux-g++11.4.1-Alma9.tar.gz

ARG GEANT4_RELEASE=v11.2.1

RUN apt-get install -y wget
RUN wget https://gitlab.cern.ch/geant4/geant4/-/archive/$GEANT4_RELEASE/geant4-${GEANT4_RELEASE}.tar.gz
RUN tar xzf geant4-${GEANT4_RELEASE}.tar.gz
RUN mkdir build && cd build && \
    cmake ../geant4-${GEANT4_RELEASE} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local/geant4 \
    -DGEANT4_INSTALL_DATA=OFF \
    -DGEANT4_USE_SYSTEM_CLHEP=OFF \
    -DGEANT4_USE_SYSTEM_EXPAT=OFF && \
    cmake --build . --target install

FROM builder as root

# NB: root provides binary releases for x86_64 only
# e.g. https://root.cern/download/root_v6.30.06.Linux-ubuntu22.04-x86_64-gcc11.4.tar.gz

ARG ROOT_RELEASE=6.30.06

RUN apt-get install -y wget
RUN wget --progress=dot:giga -O - https://root.cern/download/root_v${ROOT_RELEASE}.source.tar.gz | tar xzf -
RUN apt-get install -y libxpm-dev libxft-dev libxext-dev git
RUN mkdir build && cd build && \
    cmake ../root-${ROOT_RELEASE} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local/root && \
    cmake --build . --target install

FROM builder

COPY --from=geant4 /usr/local/geant4 /usr/local/geant4
COPY --from=root /usr/local/root /usr/local/root

RUN apt-get install -y ninja-build python3-pip

ARG MYPY_VERSION=1.8
RUN pip3 install mypy==${MYPY_VERSION}

ARG RUFF_VERSION=0.1.5
RUN pip3 install ruff==${RUFF_VERSION}

ARG PYBIND11_STUBGEN_VERSION=5adb2fa9bda99c76d7e5b67a7d5db3e5d9c2b987
RUN pip3 install https://github.com/jvansanten/pybind11-stubgen/archive/${PYBIND11_STUBGEN_VERSION}.tar.gz
RUN pip3 install pyparsing>=3 --force-reinstall

# explicitly install nvcc; we only need to detect and link against CUDA, not actually run anything
RUN apt-get install -y wget
# FIXME: adjust architecture
# RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb && \
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/cuda-keyring_1.1-1_all.deb && \
  dpkg -i cuda-keyring_1.1-1_all.deb
RUN apt-get update
RUN apt-get install -y cuda-nvcc-12-4