import os
import platform
import sys
from ctypes import CDLL, RTLD_GLOBAL

_root = os.path.dirname(os.path.abspath(__file__))

os.environ['ACADOS_SOURCE_DIR'] = _root
os.environ['ACADOS_INSTALL_DIR'] = _root
os.environ['ACADOS_LIB_DIR'] = 'lib'

_system = platform.system()
_lib_dir = os.path.join(_root, 'lib')
_bin_dir = os.path.join(_root, 'bin')

if _system == 'Windows':
    os.add_dll_directory(_lib_dir)
else:
    _var = 'LD_LIBRARY_PATH' if _system == 'Linux' else 'DYLD_LIBRARY_PATH'
    _existing = os.environ.get(_var, '')
    os.environ[_var] = os.pathsep.join([_lib_dir, _existing]) if _existing else _lib_dir

os.environ['PATH'] = os.pathsep.join([_bin_dir, os.environ.get('PATH', '')])

if _system == 'Linux':
    _blasfeo_so = os.path.join(_lib_dir, 'libblasfeo.so')
    if os.path.exists(_blasfeo_so):
        CDLL(_blasfeo_so, RTLD_GLOBAL)
    _hpipm_so = os.path.join(_lib_dir, 'libhpipm.so')
    if os.path.exists(_hpipm_so):
        CDLL(_hpipm_so, RTLD_GLOBAL)
elif _system == 'Darwin':
    _blasfeo_dylib = os.path.join(_lib_dir, 'libblasfeo.dylib')
    if os.path.exists(_blasfeo_dylib):
        CDLL(_blasfeo_dylib, RTLD_GLOBAL)
    _hpipm_dylib = os.path.join(_lib_dir, 'libhpipm.dylib')
    if os.path.exists(_hpipm_dylib):
        CDLL(_hpipm_dylib, RTLD_GLOBAL)
