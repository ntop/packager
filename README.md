## Introduction

This project contains some scripts that run some basic tests on binary packages built on ntop code. While each ntop project has its package/ directory that contains scripts for building each individual project (example https://github.com/ntop/PF_RING/tree/dev/package and https://github.com/ntop/ntopng/tree/dev/packages), the idea is to extend the travis concept to packages, trying to spot incompatibilies, platform-specific packaging issues etc. In order to achieve this we rely on docker to create various containers, one per platform for which we build packages for.

[ntop_logo]: https://camo.githubusercontent.com/58e2a1ecfff62d8ecc9d74633bd1013f26e06cba/687474703a2f2f7777772e6e746f702e6f72672f77702d636f6e74656e742f75706c6f6164732f323031352f30352f6e746f702e706e67
