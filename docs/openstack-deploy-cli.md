# Openstack Deploying the Command Line Tools

Before we can get started we need to install a few things.

#### Installing Python

Installed by default on Mac OS X.

Many Linux distributions provide packages to make setuptools easy to install. Search your package manager for setuptools to find an installation package. If you cannot find one, download the setuptools package directly from https://pip.pypa.io/en/stable/installation.

The recommended way to install setuptools on Microsoft Windows is to follow the documentation provided on the setuptools website (https://pypi.python.org/pypi/setuptools).

#### Installing pip

MacOS

!!! note

    Users may want to use a Virtual Environment so that they do not have any risk of hurting their default Python environment. For more information on seting up a venv please visit (https://docs.python.org/3/library/venv.html).

``` shell
easy_install pip
```

Microsoft Windows

Ensure that the C:\Python27\Scripts directory is defined in the PATH environment variable, and use the easy_install command from the setuptools package:

``` shell
C:\>easy_install pip
```

Ubuntu or Debian

``` shell
apt-get install python-dev python-pip
```

#### Installing the Openstack Client Using Pip

``` shell
pip install python-openstackclient
```

!!! note

    You may want to set the PATH to you opesntack to more easily use the commands.


For further information on Openstack Command Line and Authentication please visit the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/man/openstack.html).
