# fish-vol
Keyboard- or command-driven ALSA volume control with OSD display.

# After cloning:
git submodule init
git submodule update --remote --recursive
cd libmain/fish-lib-asound
git submodule init
cd ../..
git submodule update --remote --recursive

# To keep updated:
git pull
git submodule update --remote --recursive
