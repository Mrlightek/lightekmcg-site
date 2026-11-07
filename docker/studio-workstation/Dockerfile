FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends blender python3-numpy ffmpeg xvfb openbox x11vnc novnc websockify xdotool ca-certificates fonts-dejavu-core libgl1-mesa-dri libegl-mesa0 libglx-mesa0 tini && rm -rf /var/lib/apt/lists/*
COPY start.sh /usr/local/bin/lightek-workstation
COPY socket_proxy.py /usr/local/bin/lightek-desktop-socket.py
ENV HOME=/tmp DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /work
USER 65532:65532
ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/lightek-workstation"]
