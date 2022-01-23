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


---
### Sudo Privileges 
It makes it easier to run Slooo using sudo privleges

To run SSH without authentication each time :
1. ssh-keygen -t rsa (ignore this step if you have the key present already)
Press enter for each line

2. cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

And also assign root prevligies to your user using following commands:

1. Open the /etc/sudoers file (as root) by running:
    `sudo visudo`

2. At the end of the /etc/sudoers file add this line:	
    `username     ALL=(ALL) NOPASSWD:ALL`
   Replace username with your account username Save the file and exit.

3. Now you can run sudo commands without password (which is required for Slooo).

Note: Please revert back after testing
