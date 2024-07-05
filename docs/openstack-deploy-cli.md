# Openstack Deploying the Command Line Tools

Before we can get started we need to install a few things.

## Installing Python

While most operating systems have some form of Python already installed, you will need to ensure you have python available on your system to use the standard command line utilities. If you need to install python, consult your operating system documentation or the upstream python [documentation](https://www.python.org/downloads) to get started.

### Installing `pip`

Pip is the python package manager and can make installing libraries very simple; however, some build tools may be required. For more information on installing `pip`, consult the [upstream documentation](https://pip.pypa.io/en/stable/installation).

#### MacOS

``` shell
python -m ensurepip --upgrade
```

#### Microsoft Windows

Ensure that the C:\Python27\Scripts directory is defined in the PATH environment variable, and use the easy_install command from the setuptools package:

``` shell
C:> py -m ensurepip --upgrade
```

#### Linux

``` shell
python -m ensurepip --upgrade
```

### Installing the Openstack Client Using `pip`

Assuming you have `pip` installed, it can be used to install the openstack client utilities.

!!! tip

    Users may want to use a Virtual Environment so that they do not have any risk of hurting their default Python environment. For more information on seting up a venv please visit the python [documentation](https://packaging.python.org/en/latest/tutorials/installing-packages/#creating-and-using-virtual-environments) on working with virtual environments.

``` shell
pip install python-openstackclient
```

For further information on Openstack Command Line and Authentication please visit the [upstream docs](https://docs.openstack.org/python-openstackclient/latest/cli/man/openstack.html).

### Installing the OpenStack Client with packages

Package based client install is a great way to simplify the installation process, however, it does come with a greater possibility to lag behind a given release and may not be as featurefull.

#### MacOS

``` shell
brew install openstackclient
```

#### Ubuntu or Debian

``` shell
apt install python3-openstackclient
```

#### Enterprise Linux

``` shell
dnf install python3-openstackclient
```
