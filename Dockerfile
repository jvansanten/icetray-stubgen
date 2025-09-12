FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

ARG TARGETPLATFORM

# https://software.icecube.wisc.edu/icetray/main/projects/cmake/supported_platforms/ubuntu.html#full-install-recommended
# explicitly install nvcc; we only need to detect and link against CUDA, not actually run anything
# multi-arch support inspired by https://nielscautaerts.xyz/making-dockerfiles-architecture-independent.html
RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCHITECTURE=arm64; else ARCHITECTURE=x86_64; fi; \
    apt-get update -y && \
    apt-get install -y wget && \
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/${ARCHITECTURE}/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && rm cuda-keyring_1.1-1_all.deb && \
    apt-get update && \
    apt-get install -y build-essential cmake ninja-build libbz2-dev libgsl0-dev \
      libcfitsio-dev libboost-all-dev libstarlink-pal-dev libhdf5-dev \
      libzstd-dev libsuitesparse-dev libsprng2-dev liblapack-dev libhealpix-cxx-dev \
      python3-numpy libfftw3-dev libqt5opengl5-dev libcdk5-dev libncurses-dev \
      python3-sphinx doxygen python3-mysqldb python3-zmq python3-h5py \
      python3-pandas python3-seaborn libnlopt-cxx-dev \
      libzmq5-dev python3-zmq opencl-dev \
      libxpm-dev libxft-dev libxext-dev \
      cuda-nvcc-12-4 ccache \
      python3-pip

ARG BOOST_PYTHON_VERSION=1.74.0

# libboost-dev includes _all_ headers, including those for boost::python, which we need to overwrite
# two-step install: first deps with default behavior, then package itself, ignoring file overwrites
RUN if [ "$TARGETPLATFORM" = "linux/arm64" ]; then ARCHITECTURE=arm64; else ARCHITECTURE=amd64; fi; \
    PACKAGE_FILE=boost_python_${BOOST_PYTHON_VERSION}_${ARCHITECTURE}.deb; \
    wget -q https://github.com/jvansanten/boost-python/releases/download/better-docstrings-${BOOST_PYTHON_VERSION}/${PACKAGE_FILE} && \
    apt-get install -y ./${PACKAGE_FILE} -o Dpkg::Options::="--force-overwrite" && \
    rm ${PACKAGE_FILE}

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
    && cmake --build . -j$(nproc) --target install

FROM builder as root

ARG ROOT_VERSION=6.30.06
ARG TARGETPLATFORM

# use binary distribution on x86_64, otherwise build from source
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
      (wget --progress=dot:giga -O - https://root.cern/download/root_v${ROOT_VERSION}.Linux-ubuntu22.04-x86_64-gcc11.4.tar.gz | tar xzf - -C /usr/local); \
    else \
      (wget --progress=dot:giga -O - https://root.cern/download/root_v${ROOT_VERSION}.source.tar.gz | tar xzf - -C /) && \
       apt-get install -y git && \
       mkdir /build && cd /build && \
       cmake /root-${ROOT_VERSION} \
         -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_INSTALL_PREFIX=/usr/local/root \
         -Dminimal=ON \
       && cmake --build . --target install; \
    fi

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

RUN apt-get install -y libsqlite3-dev

ARG MYPY_VERSION=1.8
RUN pip3 install mypy==${MYPY_VERSION}

ARG RUFF_VERSION=0.1.5
RUN pip3 install ruff==${RUFF_VERSION}

ARG PYBIND11_STUBGEN_VERSION=312c45ee3b8c5f899f964f0a81c491135bf7b220
RUN mkdir /pybind11-stubgen && \
    wget -O - https://github.com/jvansanten/pybind11-stubgen/archive/${PYBIND11_STUBGEN_VERSION}.tar.gz | tar xzf - -C /pybind11-stubgen --strip-components=1 && \
    pip3 install -e /pybind11-stubgen
RUN pip3 install 'pyparsing>=3' --force-reinstall

ENV CC=gcc CXX=g++ CCACHE_DIR=/ccache PATH=/usr/lib/ccache:${PATH}
RUN ccache -M0

COPY icetray-stubgen icetray-build /usr/local/bin/
