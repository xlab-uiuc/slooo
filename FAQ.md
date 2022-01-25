# FAQ

If you have encountered confusions not answered in this FAQ board, please report them to us via GitHub issue.

1. **Q:** still reports `command 'xonsh' not found, but can be installed with: sudo apt install xonsh` even if I have followed the tutorial

   **A:** Please first check if "pip3 install 'xonsh[full]'" has been executed or not. If yes, please then check if the directory to Xonsh executable file has been appended to your PATH. Pip3 install packages inside `~/.local/` which is typically not in PATH. 

2. **Q:** error import python package?

   **A:** If `rethinkdb` cannot be imported, check if RethinkDB has been installed correctly. Please do follow each step in tutorial and check the execution results.

3. **Q:** error: `sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper`
   
   **A:** Please switch to sudoers before using slooo. Many tools used like cgroup requires sudo previleges. Manually type password would be exhaustive.

4. **Q:** error: `ycsb: error: argument database: invalid choice: 'rethinkdb'`. 
   
   **A:** Please rerun `git apply <path to rethink_ycsb_diff>` inside YCSB folder and make sure this succeed. The file can be found at [https://github.com/xlab-uiuc/slooo/blob/main/utils/rethink_ycsb_diff](https://github.com/xlab-uiuc/slooo/blob/main/utils/rethink_ycsb_diff)
