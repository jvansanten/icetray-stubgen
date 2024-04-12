# icetray-stubgen

This container provides an environment that can be used to generate type stubs
for IceTray python bindings. In addition to a [all the dependencies under the
sun](https://software.icecube.wisc.edu/icetray/main/projects/cmake/supported_platforms/ubuntu.html#full-install-recommended),
it includes:

- A [fork of boost-python](https://github.com/jvansanten/boost-python/tree/packaging) that emits complete type information into the generated docstrings
- A [fork of pybind11-stubgen](https://github.com/jvansanten/pybind11-stubgen/tree/boostmode) that can interpret boost-python's signature format
- ruff for consistent stub formatting
- mypy for type checking
