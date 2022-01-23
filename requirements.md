# Requirements

The slooo tool is relies on a Python3.6+ installation and the following Python3 packages to function.

- json
- yaml
- argparse
- xonsh

To install those packages, you need to have python3.6+ and pip3 installed on your machine.
Then you can copy the code below to install xonsh.

```shell
pip3 install 'xonsh[full]'
```
Note that `json`, `yaml` and `argparse` are built-in packages of Python3, which should eliminate the need to install them. *But please install them as well if you encountered any trouble.*

---
## Installation Verification
Type `xonsh` in terminal to see if you have successfully installed it. If not, please add xonsh executable file to PATH.

```shell
echo 'export PATH="$USER/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```


For more information on how to install xonsh and use xonsh, please go to [xonsh](https://xon.sh).

---
## IDE Support for Xonsh

Visual Studio Code
```
ext install jnoortheen.xonsh
```

Emacs
```
(require 'xonsh-mode)
```

Vim
```
git clone --depth 1 https://github.com/linkinpark342/xonsh-vim ~/.vim
```
