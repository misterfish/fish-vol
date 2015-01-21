# fish-vol
Keyboard- or command-driven ALSA volume control with OSD display.

# After cloning:
git submodule init
cd libmain/fish-lib-asound
git submodule init
cd ../..

# Once after submodule init. Also in the future if submodules change.
git submodule update --remote --recursive
