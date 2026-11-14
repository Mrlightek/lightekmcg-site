FROM ubuntu:24.04 AS blender
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils unzip && rm -rf /var/lib/apt/lists/*
RUN curl --fail --location --retry 2 https://download.blender.org/release/Blender4.5/blender-4.5.16-linux-x64.tar.xz -o /tmp/blender.tar.xz \
 && echo '23432b064977908beb1ab4b7f32f024e7331105c875c187dce002aff84b10c11  /tmp/blender.tar.xz' | sha256sum --check - \
 && mkdir -p /opt/blender && tar -xJf /tmp/blender.tar.xz --strip-components=1 -C /opt/blender && rm /tmp/blender.tar.xz

RUN curl --fail --location --retry 2 https://github.com/DanielSWolf/rhubarb-lip-sync/releases/download/v1.14.0/Rhubarb-Lip-Sync-1.14.0-Linux.zip -o /tmp/rhubarb.zip \
 && echo 'a9a9074862cff47b2d59b8bf399a678a3b0b74f9452ad6ad94cb292913dd8667  /tmp/rhubarb.zip' | sha256sum --check - \
 && unzip -q /tmp/rhubarb.zip -d /opt && mv /opt/Rhubarb-Lip-Sync-1.14.0-Linux /opt/rhubarb \
 && chmod 755 /opt/rhubarb/rhubarb && rm /tmp/rhubarb.zip

FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-numpy libx11-6 libxi6 libxxf86vm1 libxfixes3 libxrender1 libxkbcommon0 libsm6 libice6 libgl1 libegl1 libxext6 libtbb12 libgomp1 libfreetype6 libpulse0 libxrandr2 libxcursor1 libxinerama1 libdbus-1-3 ffmpeg fonts-dejavu-core ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=blender /opt/blender /opt/blender
COPY --from=blender /opt/rhubarb /opt/rhubarb
RUN ln -s /opt/blender/blender /usr/local/bin/blender
ENV HOME=/tmp
USER root
RUN apt-get update && apt-get install -y --no-install-recommends nodejs && rm -rf /var/lib/apt/lists/*
COPY movie-render.cjs /opt/lightek-editors/movie-render.cjs
WORKDIR /work
USER 65532:65532
CMD ["ffmpeg", "-version"]
