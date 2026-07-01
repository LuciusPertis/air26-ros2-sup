# AIR26 — Offline Downloadables Inventory

Every heavy artifact the workshop needs **beyond the ROS 2 Humble base install**. ROS 2 Humble
itself (`ros-humble-desktop`) is the workshop baseline and is covered by the separate
*Software Prerequisites Guide* PDF in this repo — it is **not** re-downloaded here.

**Target platform (hard requirement for every artifact below):**
Ubuntu **22.04 LTS (Jammy)**, **amd64**, Python **3.10**, ROS 2 **Humble**.
The `.deb`s, wheels and model blobs are platform-specific and will not work on any other
arch / Ubuntu / Python combination.

All artifacts land in **one cache folder** (default `~/air26-offline/`, override with
`AIR26_CACHE`). That folder is what you copy to the pendrive.

```
air26-offline/
  apt/            # local apt repo: *.deb + Packages.gz  (ROS/Gazebo/Webots-ros2/MoveIt/Nav2/py-trees/xvfb + deps)
  webots/         # webots_2025a_amd64.deb
  ollama/         # ollama-linux-amd64-<ver>.tgz + models/ (blobs+manifests) + ollama.service
  pip/system/     # wheels for the system python (project 04/06)
  pip/vla-venv/   # wheels for the SmolVLA venv (project 07)
  hf/             # Hugging Face cache (smolvla_base + VLM backbone)  (project 07)
  MANIFEST.sha256 # checksums of every file (written by download.sh, checked by verify.sh)
  VERSIONS.txt    # exact versions captured at download time
```

---

## 1. APT packages (`apt/`)

Downloaded **with all transitive dependencies** and turned into a local apt repo
(`Packages.gz`), so a target installs them with **zero internet**. Top-level package list lives
in `manifest/apt-packages.txt`.

| Package(s) | Project | Why |
|---|---|---|
| `ros-humble-webots-ros2` (2025.0.0) | 03, 05 | Webots↔ROS bridge — must match the Webots R2025a `.deb` |
| `ros-humble-ros-gz` (0.244.24, Fortress) | 02, 05, 07-arch | Gazebo Fortress bridge **← the doc-gap dependency** |
| `ros-humble-moveit` + 7 companion pkgs | 04 | MoveIt2 motion planning (no Stretch config on Humble → hand-generated) |
| `ros-humble-navigation2`, `nav2-bringup`, `slam-toolbox` | 04 | Nav2 mapping + navigation |
| `ros-humble-cv-bridge`, `vision-msgs`, `image-transport`, `compressed-image-transport` | 05 | camera/perception pipeline |
| `ros-humble-py-trees`, `py-trees-ros`, `py-trees-ros-interfaces` | 03 | behaviour trees |
| `xvfb` | all sims | headless GL for verification on machines with no display |

> **Transitive-deps caveat (read this):** `.deb` dependency capture is the one fragile part of
> the whole plan. `download.sh` uses `apt-cache depends --recurse` so it grabs deps **even if
> they are already installed** on the staging box. For maximum safety, run the apt step on a
> **fresh Ubuntu 22.04** box/VM that already has ROS Humble + the ROS apt repo configured but
> nothing else, so nothing is silently assumed-present. See `OFFLINE-SETUP.md`.

## 2. Webots R2025a (`webots/`)

| Artifact | Size | Source |
|---|---|---|
| `webots_2025a_amd64.deb` | ~2 GB | `github.com/cyberbotics/webots/releases/download/R2025a/` |

Installs to `/usr/local/webots`. **Version must match `ros-humble-webots-ros2` 2025.0.0.**

## 3. Ollama runtime + model (`ollama/`) — project 06

| Artifact | Size | Source |
|---|---|---|
| `ollama-linux-amd64-<ver>.tgz` (v0.30.11) | ~1.5 GB | `github.com/ollama/ollama/releases` |
| `models/` (`qwen3:1.7b` default + `qwen3:4b` opt-in) | ~1.4 GB + ~2.4 GB | `ollama pull` → `blobs/` + `manifests/` |
| `ollama.service` | tiny | generated systemd unit (the official `install.sh` makes this) |

We ship the **binary tarball**, not the `install.sh` curl, so install is fully offline. Model
tag list: `manifest/ollama-models.txt`.

## 4. pip — system python (`pip/system/`) — projects 04 & 06

Wheelhouse for the **system** interpreter (Python 3.10). List: `manifest/pip-system.txt`.

| Package | Pin | Project |
|---|---|---|
| `mujoco` | 3.2.6 | 04 (Stretch sim) |
| `numpy` | 1.24.2 | 04 (rclpy/Humble pin) |
| `opencv-python` | 4.10.0.84 | 04/05 |
| `ollama` (python client) | latest | 06 |
| `pyquaternion`, `termcolor` | latest | 04 (not auto-pulled by hello_helpers) |

> `stretch_mujoco` / `stretch_ros2` are **vendored into the ws repo** (`src/04_.../upstream/`),
> so they are not downloaded here — they ship with the workshop code.

## 5. pip — SmolVLA venv (`pip/vla-venv/`) — project 07

Wheelhouse for the **isolated venv** (`/home/lsp/vla_venv`, `--system-site-packages`). It keeps
torch/numpy≥2 out of the system python. List: `manifest/pip-vla-venv.txt`.

| Package | Source / note |
|---|---|
| `torch`, `torchvision` | **CPU** wheels from `download.pytorch.org/whl/cpu` (no GPU in workshop) |
| `lerobot[smolvla]` | PyPI (pulls transformers, etc.) |
| `numpy<2` | re-pinned last so rclpy still works (ends ~1.26.4) |

## 6. Hugging Face models (`hf/`) — project 07

| Repo | Size | Note |
|---|---|---|
| `lerobot/smolvla_base` | ~0.9 GB | the VLA policy |
| VLM backbone (`SmolVLM2-500M…`) | ~1 GB | auto-referenced by the policy at load time |

Captured as a **HF cache tree** (`hf/`). On the target, point `HF_HOME` at it and set
`HF_HUB_OFFLINE=1`. `download.sh` populates this by **loading the policy once** (in the existing
`vla_venv` if present), which pulls the backbone automatically — so we don't have to hard-code
the backbone repo id. List/fallback: `manifest/hf-models.txt`.

---

## Size budget

| Bucket | Approx |
|---|---|
| apt (ROS/Gazebo/Webots-ros2/MoveIt/Nav2 + deps) | 2–4 GB |
| Webots `.deb` | 2 GB |
| Ollama bin + qwen3:4b | ~4 GB |
| pip system + venv (torch CPU ≈ 200 MB + lerobot deps) | 1–2 GB |
| HF models | ~2 GB |
| **Total** | **~12–16 GB** |

Use a **≥32 GB exFAT** pendrive (some single blobs approach the FAT32 4 GB file limit).

## Not included here (separate plans)

- **ESP32 / micro-ROS firmware toolchain** (PlatformIO `penv` + ESP-IDF) — projects 02/05
  firmware is a separate *hardware* plan; its downloads are large and board-specific. Add later
  if you want to provision flashing laptops offline too.
- **Robocasa / robosuite kitchens** (project 04) — deliberately skipped; GPU-hungry, asset
  downloads, and the plain scene is enough.
