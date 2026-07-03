from setuptools import setup
from setuptools.dist import Distribution


class PlatformDistribution(Distribution):
    def has_ext_modules(self):
        return True


setup(distclass=PlatformDistribution)
