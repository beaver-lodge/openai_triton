# OpenAI Triton

The `openai_triton` Hex package installs Triton's native compiler core,
resolves its paired LLVM archive, and builds core libraries from a Triton
source checkout. It depends on the standalone `mlir` package.
Modules use `OpenAITriton`.

```elixir
{:openai_triton, "~> 0.1.0", runtime: false}
```

```sh
mix openai_triton.install --llvm-only --install-dir /path/to/llvm
mix openai_triton.install --install-dir /path/to/triton
mix openai_triton.build --source /path/to/triton-source --llvm /path/to/llvm --output /path/to/triton
```

Use `--resolve-only` to inspect either archive. `--triton-ref` selects the same
upstream commit for LLVM metadata and core artifacts. Core archives currently
cover Linux x86_64 and macOS arm64; LLVM-only selection also supports Linux
aarch64, macOS x86_64 and Windows amd64 when upstream provides an archive.
The LLVM selected by Triton can differ from the default `mlir` distribution.

`priv/toolchain.json` pins the default commit, repository ID and core SHA-256
digests. Core assets are hosted in this repository's releases; the stable ID
keeps default asset lookup valid across repository renames. `--repo`,
`--asset-url` and `--sha256` select an alternative release location.
No Triton Python module or GPU device is required to build the native core.

The install task prints `TRITON_PREBUILT_DIR`; consumers can pass that directory
to their linker. `--llvm-only` prints `LLVM_CONFIG_PATH`. The build task also
accepts `TRITON_SOURCE_DIR`, `LLVM_SYSPATH`, `TRITON_PREBUILT_OUTPUT_DIR`,
`TRITON_BUILD_WITH_CCACHE` and `TRITON_CACHE_PATH` for existing build drivers.
Building requires CMake, Ninja, a C/C++ toolchain, the paired LLVM distribution,
and ccache unless disabled with `--ccache OFF`. Only macOS/Linux core builds
are supported by the extracted recipe.

For local development before the first Hex release:

```sh
MLIR_TOOLCHAIN_PATH=/path/to/mlir mix deps.get
MLIR_TOOLCHAIN_PATH=/path/to/mlir mix test
mix hex.build
```

Build Hex archives without `MLIR_TOOLCHAIN_PATH` so their dependency metadata
records `mlir ~> 0.1.0`. Package builds do not publish or reserve a name.
The Hex name `triton` already belongs to a Cassandra ORM. Installer and builder
code is distributed under the MIT license; native Triton archives retain their
upstream licenses.
