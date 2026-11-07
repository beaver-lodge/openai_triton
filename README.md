# OpenAI Triton

The `openai_triton` Hex package installs Triton's native compiler core,
resolves its paired LLVM archive, and builds core libraries from a Triton
source checkout. It depends on the standalone `mlir` package and has no
Beaver or NIF dependency. Modules use `OpenAITriton`.

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

`priv/toolchain.json` pins the default commit and core SHA-256 digests. Existing
core assets are hosted in Beaver's releases; `--repo`, `--asset-url` and
`--sha256` allow an independent release location. The build recipe lives here.
No Triton Python module or GPU device is required to build the native core.
Beaver's NIF, dialect registration and pipeline APIs remain in Beaver.

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
The Hex name `triton` already belongs to a Cassandra ORM. Extracted installer
and builder code retains Beaver's MIT license; native Triton archives retain
their upstream licenses.
