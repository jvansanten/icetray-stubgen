FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# https://software.icecube.wisc.edu/icetray/main/projects/cmake/supported_platforms/ubuntu.html#full-install-recommended
# explicitly install nvcc; we only need to detect and link against CUDA, not actually run anything
RUN apt-get update -y && \
    apt-get install -y wget && \
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    apt-get update && \
    apt-get install -y build-essential cmake ninja-build libbz2-dev libgsl0-dev \
      libcfitsio-dev libboost-all-dev libstarlink-pal-dev libhdf5-dev \
      libzstd-dev libsuitesparse-dev libsprng2-dev liblapack-dev libhealpix-cxx-dev \
      python3-numpy libfftw3-dev libqt5opengl5-dev libcdk5-dev libncurses-dev \
      python3-sphinx doxygen python3-mysqldb python3-zmq python3-h5py \
      python3-pandas python3-seaborn libnlopt-dev \
      libzmq5-dev python3-zmq opencl-dev \
      libxpm-dev libxft-dev libxext-dev \
      cuda-nvcc-12-4 \
      python3-pip 

ARG BOOST_PYTHON_PACKAGE=boost_python_1.74.0_amd64.deb

# libboost-dev includes _all_ headers, including those for boost::python, which we need to overwrite
# two-step install: first deps with default behavior, then package itself, ignoring file overwrites
RUN wget -q https://github.com/jvansanten/boost-python/releases/download/better-docstrings-1.74.0/${BOOST_PYTHON_PACKAGE} && \
    apt-get install -y ./${BOOST_PYTHON_PACKAGE} -o Dpkg::Options::="--force-overwrite" && \
    rm ${BOOST_PYTHON_PACKAGE}

FROM builder as geant4

ARG GEANT4_RELEASE=v11.2.1

RUN wget --progress=dot:giga https://gitlab.cern.ch/geant4/geant4/-/archive/$GEANT4_RELEASE/geant4-${GEANT4_RELEASE}.tar.gz
RUN tar xzf geant4-${GEANT4_RELEASE}.tar.gz
RUN mkdir build && cd build && \
    cmake ../geant4-${GEANT4_RELEASE} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local/geant4 \
    -DGEANT4_INSTALL_DATA=OFF \
    -DGEANT4_BUILD_MULTITHREADED=OFF \
    -DGEANT4_USE_SYSTEM_CLHEP=OFF \
    -DGEANT4_USE_SYSTEM_EXPAT=ON \
    -DGEANT4_USE_SYSTEM_ZLIB=ON \
    && cmake --build . --target install

FROM builder as root

ARG ROOT_RELEASE=6.30.06

RUN cd /usr/local && wget --progress=dot:giga -O - https://root.cern/download/root_v${ROOT_RELEASE}.Linux-ubuntu22.04-x86_64-gcc11.4.tar.gz | tar xzf -

FROM builder

# install photospline at top level so the Python module can be found
ARG PHOTOSPLINE_VERSION=2.3.0
RUN wget --progress=dot:giga https://github.com/icecube/photospline/archive/refs/tags/v${PHOTOSPLINE_VERSION}.tar.gz -O - | tar xzf - && \
   mkdir build && \
   cmake -S photospline-${PHOTOSPLINE_VERSION} -B build \
     -DCMAKE_INSTALL_PREFIX=/usr/ \
   && cmake --build build --target install \
   && rm -r photospline-${PHOTOSPLINE_VERSION} \
   && rm -r build

COPY --from=geant4 /usr/local/geant4 /usr/local/geant4
COPY --from=root /usr/local/root /usr/local/root

ARG MYPY_VERSION=1.8
RUN pip3 install mypy==${MYPY_VERSION}

ARG RUFF_VERSION=0.1.5
RUN pip3 install ruff==${RUFF_VERSION}

ARG PYBIND11_STUBGEN_VERSION=5adb2fa9bda99c76d7e5b67a7d5db3e5d9c2b987
RUN pip3 install https://github.com/jvansanten/pybind11-stubgen/archive/${PYBIND11_STUBGEN_VERSION}.tar.gz
RUN pip3 install pyparsing>=3 --force-reinstall

COPY icetray-stubgen icetray-build /usr/local/bin/
