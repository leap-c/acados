# acados Pip Packaging — Implementation Handover

## Goal

Two pip packages from `leap-c/acados` fork:

| Package | PyPI name | Type | Contents |
|---------|-----------|------|----------|
| Runtime | `leap-c-acados-runtime` | Platform wheel (Linux x86_64) | Pre-compiled C shared libraries, headers, Tera renderer binary |
| Python | `leap-c-acados` | Noarch wheel | `acados_template` Python package (unchanged import style) |

```bash
pip install leap-c-acados
  → pulls in: leap-c-acados-runtime, casadi, numpy, scipy, matplotlib, cython, Deprecated

python -c "from acados_template import AcadosOcp"  # unchanged import style
```

## Branch & Commits

**Fork:** `leap-c/acados` (GitHub)  
**Branch:** `main`  
**Latest commit:** `b05bc94f4` (drop `-v` flag from auditwheel show)

```
b05bc94 Fix CI: auditwheel show -v removed
30f33f3 Add libgomp VERNEED + auditwheel show diagnostic
3d84b5f Add readelf -V diagnostic for version requirements
bb283e0 Fix diagnostic: show GLIBC version tags, add libgomp check
39ceefa Revert "Fix diagnostic: show GLIBC version tags, add libgomp check"
fe2cecc Add auditwheel diagnostic + disable non-wheel CI on push
aff31b4 Strip to Linux-only: remove macOS and Windows support
7e32509 Drop Windows, fix macOS RPATH, use manylinux_2_28
75107a8 Fix CI: auditwheel symbols, MSBuild -j4, macOS arch quotes
7a63256 Rename packages: acados -> leap-c-acados, acados-runtime -> leap-c-acados-runtime
4d7838c Fix wheel build: platform tag, Windows MSVC, macOS universal
58800aa Add pip packaging infrastructure
```

## Directory Structure

```
packages/
  leap_c_acados/
    pyproject.toml                              # name="leap-c-acados", deps include leap-c-acados-runtime==0.5.1
    acados_template/                            # → symlink to ../../interfaces/acados_template/acados_template
  leap_c_acados_runtime/
    pyproject.toml                              # cibuildwheel config, platform wheel meta
    setup.py                                    # PlatformDistribution override (force platform tag)
    leap_c_acados_runtime/
      __init__.py                               # env setup + shared lib preload
      lib/                                      # generated: libacados.so, libhpipm.so, libblasfeo.so*, link_libs.json, git_commit_hash
      include/                                  # generated: acados/, acados_c/, blasfeo/, hpipm/ headers
      bin/                                      # generated: t_renderer

scripts/
  build_acados_c.sh                             # cmake build + artifact copy + Tera download (Linux only now)
  sync_template.sh                              # creates symlink (no-op if exists)
  build_all.sh                                  # orchestrator: sync + build C + build wheels

.github/workflows/
  build-wheels.yml                              # cibuildwheel on ubuntu-24.04 + noarch Python wheel
```

## What Is Committed vs Generated

### Committed (tracked in git)

- All `pyproject.toml` files
- `packages/leap_c_acados_runtime/setup.py` (PlatformDistribution)
- `packages/leap_c_acados_runtime/leap_c_acados_runtime/__init__.py` (bootstrap)
- `packages/leap_c_acados/acados_template` → symlink (tracked as git symlink, mode 120000)
- `scripts/` (build scripts, CI workflow)
- `interfaces/acados_template/acados_template/` — source files with 4 backward-compatible patches

### Generated (git ignored by patterns: `lib/`, `include/`, `bin/`, `*.so`, `*.dll`, `*.o`, `packages/*/dist/`, `packages/*/build/`, `packages/*/*.egg-info/`)

- `packages/leap_c_acados_runtime/leap_c_acados_runtime/lib/`
- `packages/leap_c_acados_runtime/leap_c_acados_runtime/include/`
- `packages/leap_c_acados_runtime/leap_c_acados_runtime/bin/`
- All wheel files in `packages/*/dist/`

## Source Modifications (4 backward-compatible patches)

All in `interfaces/acados_template/acados_template/`:

| File | Change | Why |
|------|--------|-----|
| `utils.py:get_shared_lib_dir()` | Added `if 'ACADOS_LIB_DIR' in os.environ: return os.environ['ACADOS_LIB_DIR']` at top | So Windows can use `lib/` instead of `bin/` in future. Set by runtime `__init__.py`. |
| `utils.py:get_python_interface_path()` | Fallback changed from `os.path.join(acados_path, 'interfaces', 'acados_template', 'acados_template')` to `os.path.dirname(os.path.abspath(__file__))` | The hardcoded repo layout path doesn't exist in pip-installed site-packages. `__file__`-relative works in both pip and source layouts. |
| `__init__.py` (line 30) | Added `try: import leap_c_acados_runtime; except ImportError: pass` before module imports | Side-effect import: sets `ACADOS_SOURCE_DIR`, `LD_LIBRARY_PATH`, preloads `libblasfeo.so`/`libhpipm.so`. |
| `acados_ocp_qp.py` (line 4) | `from acados_template.acados_ocp_iterate` → `from .acados_ocp_iterate` | Relative import works regardless of package directory name (needed for symlink). |
| `gnsf.py` (line 32) | `from acados_template import AcadosModel, AcadosOcpDims, AcadosSimDims` → `from .acados_model import AcadosModel; from .acados_dims import AcadosOcpDims, AcadosSimDims` | Same reason — relative imports. |

## How It Works At Runtime

```
User code: from acados_template import AcadosOcp
  → pip install leap-c-acados
      → pulls in leap-c-acados-runtime
  → acados_template/__init__.py executes:
      → try: import leap_c_acados_runtime (side-effect bootstrap)
          → leap_c_acados_runtime/__init__.py:
              1. ACADOS_SOURCE_DIR = /path/to/leap_c_acados_runtime/   (force set)
              2. ACADOS_INSTALL_DIR = same
              3. ACADOS_LIB_DIR = 'lib'                               (so Windows doesn't use 'bin')
              4. LD_LIBRARY_PATH += .../lib                           (dynamic linker finds .so)
              5. PATH += .../bin                                      (t_renderer found)
              6. CDLL(libblasfeo.so, RTLD_GLOBAL)                    (preload dep chain)
              7. CDLL(libhpipm.so, RTLD_GLOBAL)                      (preload dep chain)
      → get_acados_path() picks up ACADOS_SOURCE_DIR
      → CodeGenOptions sets acados_include_path and acados_lib_path from there
      → AcadosOcpSolver: JIT renders templates, compiles against wheel headers, links against wheel libs
```

## CI/CD

**Workflow:** `.github/workflows/build-wheels.yml`

**Two jobs:**

| Job | Runner | Triggers | Produces |
|-----|--------|----------|----------|
| `build-runtime` | `ubuntu-24.04` | cibuildwheel via `before-build` runs inside manylinux2014 container | 3 wheels: `cp311`, `cp312`, `cp313` |
| `build-acados-noarch` | `ubuntu-latest` | `pip install build && python -m build` | 1 noarch wheel |

**Other workflows temporarily disabled** (changed `push: branches-ignore` to `'**'`) to reduce cost during development:
- `full_build.yml`, `full_build_windows.yml`, `ext_dep_off.yml`, `c_test_blasfeo_reference.yml`, `deploy_docs.yml`
- `core_build.yml` is reusable only (workflow_call), no push trigger
- `codeql.yml` is PRs only

**No PyPI publish configured** — deferred for now.

## Platform Support

| Platform | Status |
|----------|--------|
| Linux x86_64 | Development (not yet passing auditwheel) |
| Linux aarch64 | Deferred |
| macOS x86_64 / arm64 | Removed from CI (simplified) |
| Windows x86_64 / arm64 | Removed (MSVC OpenMP incompatibility, no Tera binary) |

## Problems Encountered & Resolved

### 1. `py3-none-any` tag instead of platform-specific

**Symptom:** cibuildwheel rejected wheel because setuptools tagged it as pure Python.

**Root cause:** `.so` files are package data, not compiled C extensions. `has_ext_modules()` returns False.

**Fix:** Added `packages/leap_c_acados_runtime/setup.py` with `PlatformDistribution(Distribution)` override: `has_ext_modules() → True`. This forces `cp311-cp311-linux_x86_64` tags.

### 2. `libhpipm.so` / `libacados.so` symbol not found at load time

**Symptom:** `OSError: undefined symbol: d_dense_qp_set_m_all`

**Root cause:** `libacados.so` depends on `libhpipm.so` which depends on `libblasfeo.so.0`. CMake clears RPATH on install. On Linux, `dlopen()` with a full path does NOT search the file's directory for dependencies.

**Fix:** `leap_c_acados_runtime/__init__.py` preloads `libblasfeo.so` and `libhpipm.so` with `RTLD_GLOBAL` before anything else loads `libacados.so`. This populates the symbol table so subsequent `dlopen()` calls find all needed symbols.

### 3. `setdefault` didn't override existing env vars

**Symptom:** Wheel used old `ACADOS_SOURCE_DIR` from host environment, pointed to wrong paths.

**Root cause:** `os.environ.setdefault()` doesn't override already-set variables. The user's shell had `ACADOS_SOURCE_DIR` pointing to leap-c's old source tree.

**Fix:** Changed to `os.environ['KEY'] = value` (force-set).

### 4. Windows: MSVC can't compile BLASFEO `X64_AUTOMATIC`

**Symptom:** `CMake Error: MSVC compiler only supported for TARGET=GENERIC`

**Root cause:** BLASFEO's `X64_AUTOMATIC` target uses x86 assembly/intrinsics that only GCC/Clang can compile.

**Fix:** Platform dropped. If re-added: pass `-DBLASFEO_TARGET=GENERIC` to cmake on Windows.

### 5. Windows: MSBuild can't parse `-j4`

**Symptom:** `MSBUILD: error MSB1001: Unknown switch: -j4`

**Root cause:** MSBuild uses `/m` for parallel builds, not `-j`. We passed `-j$(nproc)` from a Linux-centric script.

**Fix:** Platform dropped. If re-added: use `--config Release` instead of `-j` on Windows.

### 6. macOS: `delocate` can't find `@rpath` dependencies

**Symptom:** `@rpath/libblasfeo.0.dylib not found`

**Root cause:** CMake clears RPATH on install. `delocate` can't resolve `@rpath` references to bundle libraries.

**Fix:** Platform dropped. If re-added: add `-DCMAKE_INSTALL_RPATH=@loader_path` to macOS cmake flags.

### 7. macOS: Universal arch escaping

**Symptom:** `clang: error: invalid arch name '-arch x86_64 -arch arm64'`

**Root cause:** Shell quotes around `"x86_64;arm64"` passed literal `"` into cmake, creating malformed `-arch` flag.

**Fix:** Use CMake's native semicolon separator: `-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64` (no inner quotes).

### 8. Linux: GCC 10 C++ ABI (`_GLIBCXX_USE_CXX11_ABI=0`)

acados CMakeLists.txt (line 121) sets `-D_GLIBCXX_USE_CXX11_ABI=0` for CasADi compatibility. This is correct — CasADi PyPI wheels use the old C++ ABI. No action needed.

### 9. **UNRESOLVED: auditwheel rejects wheel with too-recent symbols**

**Symptom:** `auditwheel: error: cannot repair ... to "manylinux2014_x86_64" ABI because of the presence of too-recent versioned symbols`

**Diagnostic findings (3 rounds):**

- `objdump -T` on all 3 `.so` files: **Clean.** `libacados.so` max `GLIBC_2.14`, `libhpipm.so` max `GLIBC_2.2.5`, `libblasfeo.so` max `GLIBC_2.14`. No `GLIBCXX` or `CXXABI` symbols.
- `readelf -V` (VERNEED): **Clean.** Only requires `GLIBC_2.14`, `GLIBC_2.7`, `GLIBC_2.2.5`, `GOMP_4.0`, `OMP_1.0`.
- `objdump -T` on `libgomp.so.1` (from container): **Clean.** Max `GLIBC_2.17`.
- `readelf -V` on `libgomp.so.1`: **(pending — added but CI hasn't run yet, next commit needed)**
- `auditwheel show {wheel}`: Reports wheel requires `GLIBC_2.34` in `libc.so.6` — this is coming from `libgomp.so.1`'s transitive dependency on the container's libc. The wheel bundles `libgomp.so.1`, and that lib requires a newer libc version than manylinux2014 allows.

**Root cause:** The `manylinux2014` container (CentOS 7, glibc 2.17) uses GCC 10 via devtoolset-10. Even though we compile our `.so` files against the container's glibc 2.17, when `auditwheel repair` bundles `libgomp.so.1` into the wheel, it inspects `libgomp.so.1`'s dependencies — specifically a transitive `libc.so.6` requirement at `GLIBC_2.34`. This triggers rejection.

**Why `manylinux_2_28` also fails:** The earlier `manylinux_2_28` failure was from **host build contamination** — we had a "Build C libraries" step running on the host (ubuntu-24.04, glibc 2.39) before the containerized build. This contaminated the CMake cache. This step has been removed — the diagnostic output now comes purely from the container build, showing clean symbols. `manylinux_2_28` has NOT been retried since the host build step was removed.

### 10. **UNRESOLVED: Temporary CI workflow disabling**

Other workflows (`full_build.yml`, etc.) have their push triggers set to ignore all branches (`branches-ignore: '**'`) to reduce CI costs during wheel development. These should be reverted before any upstream PR.

## Next Agent To-Do List

### Blocking

- [ ] **Fix auditwheel rejection.** The planned approach (not yet implemented):
  - Option A (recommended): Skip auditwheel repair (`repair-wheel-command = ""` in pyproject.toml) + rename wheel tag from `linux_x86_64` to `manylinux2014_x86_64` in CI.
  - Option B: Retry `manylinux_2_28` container now that host build contamination is fixed.
- [ ] Once wheels build cleanly, smoke-test with `pip install` + pendulum OCP in a clean venv.
- [ ] Revert CI workflow disabling (`branches-ignore: '**'` → original triggers).

### Nice-to-Have

- [ ] Add `libgomp` VERNEED diagnostic (already committed, need to check CI output).
- [ ] Clean up diagnostic blocks from `build_acados_c.sh` after auditwheel issue is resolved.
- [ ] Configure PyPI publish (api token, trusted publisher) + tag-trigger release.
- [ ] Add Linux aarch64 support.
- [ ] Re-evaluate macOS support.
- [ ] Verify `manylinux_2_28` approach works post-contamination-fix and compare with Option A.
- [ ] Remove unused `[tool.cibuildwheel.macos]` section from pyproject.toml if macOS not planned.

### Key Files to Know About

| File | Role |
|------|------|
| `packages/leap_c_acados_runtime/pyproject.toml` | cibuildwheel config. The critical section is `[tool.cibuildwheel.linux]` with `before-build`, `repair-wheel-command` |
| `packages/leap_c_acados_runtime/leap_c_acados_runtime/__init__.py` | Runtime bootstrap. Sets env vars, preloads libs with `RTLD_GLOBAL`. |
| `packages/leap_c_acados_runtime/setup.py` | Forces platform-specific wheel tag via `has_ext_modules() = True`. |
| `scripts/build_acados_c.sh` | Builds acados C libs inside manylinux container. Output goes to `$OUTPUT_DIR`. Contains diagnostic blocks that should be cleaned up eventually. |
| `scripts/sync_template.sh` | Creates symlink from packages to source. |
| `.github/workflows/build-wheels.yml` | Two jobs: `build-runtime` (cibuildwheel) + `build-acados-noarch` (setuptools). |
| `interfaces/acados_template/acados_template/__init__.py` | Has `try: import leap_c_acados_runtime` at top. Critical for bootstrap. |
| `interfaces/acados_template/acados_template/utils.py` | `get_shared_lib_dir()` and `get_python_interface_path()` were patched. |

## Local Testing Commands

```bash
# Full build from current repo
rm -rf packages/leap_c_acados_runtime/leap_c_acados_runtime/{lib,include,bin}
SOURCE_DIR="$PWD" bash scripts/build_acados_c.sh

# Build both wheels
python3 -m build --wheel packages/leap_c_acados_runtime
python3 -m build --wheel packages/leap_c_acados

# Test in fresh venv
python3 -m venv /tmp/leap-test && source /tmp/leap-test/bin/activate
pip install packages/leap_c_acados_runtime/dist/*.whl packages/leap_c_acados/dist/*.whl

# Smoke test (pendulum OCP — uses unchanged from acados_template import style)
python3 -c "
from acados_template import AcadosOcp, AcadosModel, AcadosOcpSolver
import casadi as ca
import numpy as np

model = AcadosModel()
model.name = 'pendulum'
x = ca.SX.sym('x'); theta = ca.SX.sym('theta')
xdot = ca.SX.sym('xdot'); thetadot = ca.SX.sym('thetadot')
model.x = ca.vertcat(x, theta, xdot, thetadot)
model.u = ca.SX.sym('F')
model.xdot = ca.SX.sym('xdot', 4)
model.f_expl_expr = ca.vertcat(xdot, thetadot, -ca.sin(theta) + model.u, 0.0)
model.f_impl_expr = model.f_expl_expr - model.xdot

ocp = AcadosOcp()
ocp.model = model
ocp.solver_options.N_horizon = 10
ocp.solver_options.tf = 1.0
ocp.solver_options.nlp_solver_type = 'SQP'
ocp.solver_options.qp_solver = 'PARTIAL_CONDENSING_HPIPM'
ocp.cost.cost_type = 'NONLINEAR_LS'
ocp.cost.W = np.eye(4)
ocp.model.cost_y_expr = model.x
ocp.cost.yref = np.zeros(4)

solver = AcadosOcpSolver(ocp, json_file='pendulum.json')
for i in range(ocp.solver_options.N_horizon+1):
    solver.set(i, 'x', np.zeros(4))
status = solver.solve()
assert status == 0, f'solve failed with status {status}'
print('Pendulum OCP solved successfully.')
print(f'Status: {status}')
"
