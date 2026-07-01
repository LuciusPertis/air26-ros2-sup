# AIR26 — Offline Setup (installing from the distributed folder)

How to install every heavy workshop dependency on a **target box** using only the
`air26-offline/` folder from the pendrive — **no internet required**.

**Prerequisites on the target (already done via the *Software Prerequisites Guide* PDF):**
Ubuntu 22.04 LTS (amd64) + ROS 2 Humble (`ros-humble-desktop`) installed and sourced.

**Before you start:** copy the folder off the pendrive to local disk (installing across USB is
slow and flaky), then verify it survived the copy:

```bash
cp -r /media/$USER/AIR26/air26-offline ~/air26-offline
cd ~/air26-ros2-sup            # this repo (also on the stick)
AIR26_CACHE=~/air26-offline scripts/verify.sh      # must say VERIFY PASSED
```

All commands below assume `CACHE=~/air26-offline`.

```bash
CACHE=~/air26-offline
```

---

## 1. APT packages (local repo) — Webots-ros2, Gazebo, MoveIt2, Nav2, py-trees, xvfb

Register the offline `.deb` folder as a **trusted local apt source**, then install normally.

```bash
# tell apt to read the pendrive folder as a repo (trusted = no GPG signing needed)
echo "deb [trusted=yes] file://$CACHE/apt ./" | sudo tee /etc/apt/sources.list.d/air26-offline.list

# IMPORTANT: do this update OFFLINE so apt doesn't try to reach the internet mirrors.
#   -o Dir::Etc::sourcelist limits the refresh to just our local repo.
sudo apt-get update -o Dir::Etc::sourcelist="sources.list.d/air26-offline.list" \
                    -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"

# now install the top-level packages (deps resolve from the local repo)
sudo apt-get install -y --no-install-recommends \
  ros-humble-webots-ros2 ros-humble-ros-gz \
  ros-humble-moveit ros-humble-moveit-setup-assistant \
  ros-humble-moveit-simple-controller-manager ros-humble-moveit-planners-ompl \
  ros-humble-moveit-ros-move-group ros-humble-moveit-configs-utils \
  ros-humble-moveit-kinematics ros-humble-moveit-ros-visualization \
  ros-humble-navigation2 ros-humble-nav2-bringup ros-humble-slam-toolbox \
  ros-humble-cv-bridge ros-humble-vision-msgs \
  ros-humble-image-transport ros-humble-compressed-image-transport \
  ros-humble-py-trees ros-humble-py-trees-ros ros-humble-py-trees-ros-interfaces \
  xvfb
```

When finished (optional), remove the source so future online `apt update`s aren't slowed:
```bash
sudo rm /etc/apt/sources.list.d/air26-offline.list
```

> **If apt reports an unmet dependency:** the cache was built on a staging box that already had
> that dep installed, so it never got downloaded. Rebuild the apt cache on a clean 22.04 box
> (ROS repo configured, nothing else) — see `DOWNLOADABLES.md` §1.

## 2. Webots R2025a

```bash
sudo apt-get install -y "$CACHE"/webots/webots_2025a_amd64.deb   # installs to /usr/local/webots
# if apt complains about deps, they are in the local repo from step 1 (do step 1 first)
```
Set `WEBOTS_HOME=/usr/local/webots` if a launch can't find the binary.

## 3. Ollama runtime + models (project 06)

```bash
# 3a. binary
sudo tar -C /usr -xzf "$CACHE"/ollama/ollama-linux-amd64-*.tgz    # -> /usr/bin/ollama or /usr/local/bin

# 3b. service user + models (the models dir is owned by the 'ollama' user)
sudo useradd -r -s /bin/false -m -d /usr/share/ollama ollama 2>/dev/null || true
sudo mkdir -p /usr/share/ollama/.ollama/models
sudo cp -r "$CACHE"/ollama/models/* /usr/share/ollama/.ollama/models/
sudo chown -R ollama:ollama /usr/share/ollama

# 3c. systemd service
sudo cp "$CACHE"/ollama/ollama.service /etc/systemd/system/ollama.service
sudo systemctl daemon-reload && sudo systemctl enable --now ollama

# 3d. verify (no network)
systemctl status ollama --no-pager
ollama list                       # should show qwen3:1.7b (+ qwen3:4b)
```

## 4. pip — system python (projects 04 & 06)

Install from the wheelhouse with the network disabled (`--no-index`):

```bash
pip3 install --no-index --find-links "$CACHE"/pip/system \
     -r ~/air26-ros2-sup/manifest/pip-system.txt
```

## 5. pip — SmolVLA venv (project 07)

Create the isolated venv, then install the venv wheelhouse offline:

```bash
python3 -m venv --system-site-packages /home/lsp/vla_venv
source /home/lsp/vla_venv/bin/activate
pip install --no-index --find-links "$CACHE"/pip/vla-venv \
    -r ~/air26-ros2-sup/manifest/pip-vla-venv.txt
deactivate
```

## 6. Hugging Face models (project 07)

Point the venv at the offline HF cache and lock it to offline mode:

```bash
mkdir -p ~/.cache/huggingface
cp -r "$CACHE"/hf/* ~/.cache/huggingface/         # or set HF_HOME=$CACHE/hf instead of copying
# make the SmolVLA node run fully offline (add to the launch env / ~/.bashrc):
echo 'export HF_HUB_OFFLINE=1' >> ~/.bashrc
echo 'export TRANSFORMERS_OFFLINE=1' >> ~/.bashrc
```

Sanity (offline):
```bash
HF_HUB_OFFLINE=1 /home/lsp/vla_venv/bin/python -c \
  "from lerobot.policies.smolvla.modeling_smolvla import SmolVLAPolicy; \
   SmolVLAPolicy.from_pretrained('lerobot/smolvla_base'); print('offline load ok')"
```

---

## Post-install: build & smoke-test the workshop

```bash
cd ~/air26-ros2-ws && source /opt/ros/humble/setup.bash
colcon build       # or --packages-select per project
source install/setup.bash
```

Then follow each project's own `TUTORIAL.md`. Per-project entry points:

| Project | Needs (from this cache) | Launch |
|---|---|---|
| 02 micro_ros | pip system (mujoco) | `ros2 launch microbot_sim mujoco.launch.py` |
| 03 multi_bot | apt (webots-ros2, py-trees) + Webots | `ros2 launch multibot_sim patrol.launch.py` |
| 04 stretch | apt (moveit/nav2) + pip system | `ros2 launch stretch_se3_bringup sim.launch.py` |
| 05 perception | apt (webots-ros2, ros-gz, cv-bridge) + Webots | `ros2 launch perceptbot_sim webots.launch.py` |
| 06 llm | ollama + qwen3 + pip (ollama client) | `ros2 launch llm_integration micro.launch.py` |
| 07 vla | pip venv + HF models | `ros2 launch vla_so101_demo vla.launch.py` |

## Troubleshooting

- **`apt` tries to hit the internet / is slow:** you ran a plain `apt update`. Use the scoped
  `update` in step 1 (`-o Dir::Etc::sourcelist=...`), or unplug networking during install.
- **Webots version mismatch errors:** `ros-humble-webots-ros2` (2025.0.0) and the Webots
  `.deb` (R2025a) must both come from this cache — don't mix with an online-installed Webots.
- **Ollama model not found:** confirm `models/` was copied *and* `chown ollama:ollama`'d, and
  that `OLLAMA_MODELS` in the unit points where you copied them.
- **SmolVLA tries to download:** `HF_HUB_OFFLINE=1` isn't set in the node's environment; export
  it before launching (or put it in the launch file's env).
