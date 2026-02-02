# Task Manager

A simple CLI task manager for those who like working in the terminal.

- Features
    - Add, remove, and update tasks
    - Organize tasks within different categories

## Getting Started

Install the Odin compiler if it is not installed already: https://odin-lang.org/docs/install/.

Begin by git cloning the repository.
```bash
git clone https://github.com/calvintran1478/task-manager.git
```
Open the main.odin file and change DATA_FILE to an absolute path where you want the data to be stored. If there is no particular preference, the standard choice is to write:
```
DATA_FILE :: "<$HOME>/.local/share/tm/data.bin"
```
where `<$HOME>` is replaced with your home directory. Create an empty file at the chosen path if there is not one already.

Finally, compile the source code into a globally executable binary.
```bash
sudo odin build ./task-manager -out:/usr/local/bin/tm -o:speed -no-bounds-check
```
You can now start the application by running
```bash
tm
```
This will start an interactive session where you can run commands. The supported list of commands are: `show`, `add`, `update`, `delete`, `start`, `check`, `save`, and `quit`.

At this point you can freely delete the source file. To quickly display tasks without starting a session you can run
```bash
tm show
```

## Uninstalling

To uninstall the application simply delete the executable and data file.
