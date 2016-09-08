## Introduction

This project contains some scripts that run some basic tests on binary packages built on ntop code. While each ntop project has its package/ directory that contains scripts for building each individual project (example https://github.com/ntop/PF_RING/tree/dev/package and https://github.com/ntop/ntopng/tree/dev/packages), the idea is to extend the travis concept to packages, trying to spot incompatibilies, platform-specific packaging issues etc. In order to achieve this we rely on docker to create various containers, one per platform for which we build packages for.

Tests are logically divided into installation tests and functional tests.

# Installation tests
During these tests a docker image is created for each supported architecture (presently ubuntu 12/14/16, debian jessie and wheezy, cento 6/7) and for each package (or group of packages) that is meant to be tested.

The bash scripts under the entrypoint/ directory are used to specify the packages to be tested. Each script can be thought of as a unit test. Inside each script there is the list of packages and the test logic that have to be executed.

# Functional tests
Functional tests are run by instantiating containers out of the docker images. Each container is then run via `docker run` that passes the string test as command line argument. This string is handled by the bash scripts above that can figure out they are carrying the tests.

# Entering the containers
For additional desting, debugging purposes, etc it is possible to enter the containers. Indeed, the bash scripts under entrypoints/ are generic and can handle also other command. For example to launch an interactive bash shell on a container, one may run:

```
docker run -it centos7.n2disk /bin/bash
```

[ntop_logo]: https://camo.githubusercontent.com/58e2a1ecfff62d8ecc9d74633bd1013f26e06cba/687474703a2f2f7777772e6e746f702e6f72672f77702d636f6e74656e742f75706c6f6164732f323031352f30352f6e746f702e706e67
