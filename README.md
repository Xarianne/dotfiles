# My Fedora Setup

## Bootstrap
Run these commands on a fresh installation.

### 1. Install Yadm

Clone Yadm into a hidden project folder
```bash
git clone https://github.com/yadm-dev/yadm.git ~/.yadm-project
```
Link it to your local bin (ensure ~/.local/bin is in your PATH)
```bash
mkdir -p ~/.local/bin
ln -s ~/.yadm-project/yadm ~/.local/bin/yadm
```

Verify it works
```bash
yadm version
```
